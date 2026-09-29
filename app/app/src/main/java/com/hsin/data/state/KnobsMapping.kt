package com.hsin.data.state

import com.hsin.data.cache.CapabilityCachePolicy
import org.json.JSONArray
import org.json.JSONObject

/**
 * Pemetaan keluaran `knobs` (kontrak §3.2) ke [KnobCapability] + peta base
 * untuk dirty tracking. Bersifat murni, teruji di JVM biasa.
 *
 * `knobs` memberi daftar knob yang VALID untuk device ini, termasuk nilai
 * yang boleh dipakai (governor, scheduler, TCP CC, dsb). Ini satu-satunya
 * sumber pilihan valid di app — `capabilities` tidak dipakai sama sekali
 * (kontrak §3.9 dan keputusan D3).
 */
object KnobsMapping {

    /** Profil yang boleh di-app; `manual` selalu ada sebagai default M1. */
    private val KNOWN_PROFILES = setOf("manual", "battery", "balanced", "performance", "extreme")

    /**
     * Kunci yang bisa diedit user. Mengikuti pola §4 kontrak. Sengaja TIDAK
     * memuat `*_opp_khz`/`*_max_khz` yang nilainya daftar panjang — untuk
     * OPP aplikasi menSHIP slider terpisah nanti (A9).
     */
    private val EDITABLE = Regex(
        "^(cpu_policy_\\d+_(gov|sched|rate_limit_us)|" +
            "gpu_node_[A-Za-z0-9_]+_(gov|polling_interval|up_threshold|down_differential)|" +
            "io_block_[A-Za-z0-9_]+_(sched|readahead|add_random|iostats|nomerges)|" +
            "zram_algo|swappiness|vfs_cache_pressure|dirty_ratio|dirty_background_ratio|" +
            "page_cluster|stat_interval|backlog|tcp_cc|tfo|sched_child_runs_first|" +
            "sched_latency_pct|sched_min_granularity_pct|sched_wakeup_granularity_pct|" +
            "uclamp_min|uclamp_max|mali_boost_level2|mali_pollingtime|mali_upthreshold)$"
    )

    /** Hasil parsing: capability + peta base (key -> nilai sistem saat ini). */
    data class Parsed(
        val capability: KnobCapability,
        val baseValues: Map<String, String>,
    )

    fun parse(knobsJson: JSONObject, allowExtreme: Boolean = false): Parsed {
        val profiles = readStringList(knobsJson.optJSONArray("profiles"))
            .filter { it in KNOWN_PROFILES }
            .let { if (it.contains("manual")) it else listOf("manual") + it }

        val cpu = knobsJson.optJSONObject("cpu")
        val gpu = knobsJson.optJSONObject("gpu")
        val memory = knobsJson.optJSONObject("memory")
        val io = knobsJson.optJSONObject("io")
        val net = knobsJson.optJSONObject("network")
        val vm = knobsJson.optJSONObject("vm")

        val allowed = linkedMapOf<String, List<String>>()
        val base = linkedMapOf<String, String>()

        // --- CPU: satu key per policy yang gpio ---
        val policies = cpu?.optJSONArray("policies")
        if (policies != null) {
            for (i in 0 until policies.length()) {
                val p = policies.optJSONObject(i) ?: continue
                val id = p.optString("id")
                if (id.isBlank()) continue
                val govs = readStringList(p.optJSONArray("govs"))
                allowed["cpu_policy_${id}_gov"] = govs
                base["cpu_policy_${id}_gov"] = p.optString("cur_gov")

                val schedFlags = p.optJSONObject("sched")?.optJSONArray("cs_flags")
                if (schedFlags != null) {
                    val scheds = readStringList(schedFlags)
                    if (scheds.isNotEmpty()) {
                        allowed["cpu_policy_${id}_sched"] = scheds
                        base["cpu_policy_${id}_sched"] = p.optString("cur_sched")
                    }
                }
            }
        }

        // --- GPU: satu key per node devfreq ---
        val nodes = gpu?.optJSONArray("nodes")
        if (nodes != null) {
            for (i in 0 until nodes.length()) {
                val n = nodes.optJSONObject(i) ?: continue
                val raw = n.optString("name")
                if (raw.isBlank()) continue
                val key = sanitize(raw)
                val govs = readStringList(n.optJSONArray("govs"))
                allowed["gpu_node_${key}_gov"] = govs
                base["gpu_node_${key}_gov"] = n.optString("cur_gov")
            }
        }

        // --- memory: skalar + zram ---
        val sw = memory?.optJSONObject("swappiness")
        if (sw != null && sw.optBoolean("supported", false)) {
            base["swappiness"] = sw.optInt("cur", 0).toString()
        }
        val zram = memory?.optJSONObject("zram")
        if (zram != null && zram.optBoolean("supported", false)) {
            val algos = readStringList(zram.optJSONArray("algos"))
            if (algos.isNotEmpty()) {
                allowed["zram_algo"] = algos
                base["zram_algo"] = zram.optString("cur")
            }
        }

        // --- vm: node global dengan min/max/cur/writable ---
        copyScalar(vm, "vfs_cache_pressure", base)
        copyScalar(vm, "dirty_ratio", base)
        copyScalar(vm, "dirty_background_ratio", base)
        copyScalar(vm, "page_cluster", base)
        copyScalar(vm, "stat_interval", base)

        // --- io: per block ---
        val blocks = io?.optJSONArray("blocks")
        if (blocks != null) {
            for (i in 0 until blocks.length()) {
                val b = blocks.optJSONObject(i) ?: continue
                val name = sanitize(b.optString("name"))
                if (name.isBlank()) continue
                val scheds = readStringList(b.optJSONArray("schedulers"))
                if (scheds.isNotEmpty()) {
                    allowed["io_block_${name}_sched"] = scheds
                    base["io_block_${name}_sched"] = b.optString("cur")
                }
            }
        }

        // --- network ---
        val cc = readStringList(net?.optJSONArray("tcp_cc"))
        if (cc.isNotEmpty()) {
            allowed["tcp_cc"] = cc
            base["tcp_cc"] = net?.optString("cur_cc")?.takeIf { it.isNotBlank() } ?: cc.first()
        }

        val cap = KnobCapability(
            supportedKeys = allowed.keys.filter { it.matches(EDITABLE) }.sorted(),
            allowedValues = allowed.filterKeys { it.matches(EDITABLE) },
            allowExtreme = allowExtreme,
        )
        return Parsed(cap, base.filterKeys { it.matches(EDITABLE) })
    }

    /**
     * Sanitasi nama node, PERSIS sama dengan modul (`core/user_knobs.sh`):
     * karakter selain alfanumerik diganti `_`, panjang dibatasi 40.
     */
    fun sanitize(name: String): String {
        val sb = StringBuilder(name.length)
        for (c in name) sb.append(if (c.isLetterOrDigit()) c else '_')
        return sb.toString().take(40)
    }

    private fun copyScalar(vm: JSONObject?, key: String, out: MutableMap<String, String>) {
        val node = vm?.optJSONObject(key) ?: return
        if (!node.optBoolean("supported", false)) return
        out[key] = node.optInt("cur", 0).toString()
    }

    private fun readStringList(arr: JSONArray?): List<String> {
        if (arr == null) return emptyList()
        val out = ArrayList<String>(arr.length())
        for (i in 0 until arr.length()) {
            val s = arr.optString(i)
            if (s.isNotBlank()) out.add(s)
        }
        return out
    }

    /** Ambil capability dari cache tanpa memanggil root lagi. */
    fun fromCacheHit(knobs: JSONObject, allowExtreme: Boolean): KnobCapability =
        parse(knobs, allowExtreme).capability
}

/** Dipakai ViewModel untuk membedakan HIT/MISS tanpa Android. */
typealias CacheDecision = CapabilityCachePolicy.Decision
