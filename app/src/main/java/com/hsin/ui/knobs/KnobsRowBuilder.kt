package com.hsin.ui.knobs

import com.hsin.model.CpuPolicyKnob
import com.hsin.model.GpuNodeKnob
import com.hsin.model.IoBlockKnob
import com.hsin.model.KnobsResponse

/**
 * Mengubah JSON `action.sh knobs` menjadi baris UI.
 *
 * Aturan penting: app hanya menawarkan toggle/pilihan yang modul benar-benar
 * bisa menulis.
 *  - `knob-set` (Sink.KNOB) hanya menerima pola kunci
 *    `cpu_policy_<id>_{gov|max_khz|min_khz|sched}`,
 *    `gpu_node_<nama>_{gov|max_khz}`,
 *    `io_block_<nama>_sched`, plus `zram_algo`, `swappiness`, `tcp_cc`, `tfo`.
 *  - `config-set` (Sink.CONFIG) hanya menerima 7 kunci: GAM_BOOST_ENABLED,
 *    ALLOW_EXTREME, DOWNSCALE_ENABLED, DOWNSCALE_PERCENT, RENDERER,
 *    REFRESH_LOCK_ENABLED, REFRESH_LOCK_HZ.
 * Fitur lain (DVFS, global RR, frame limit, surfaceflinger) memang dilaporkan
 * `knobs` sebagai tersedia, tapi modul belum punya aksi untuk menyetelnya,
 * jadi ditampilkan read-only — bukan switch palsu yang gagal saat Apply.
 */
object KnobsRowBuilder {

    /** Samakan dengan pola validasi modul: hanya [A-Za-z0-9_]. */
    fun sanitizeNode(name: String): String {
        val sb = StringBuilder(name.length)
        for (ch in name) {
            sb.append(if (ch.isLetterOrDigit() && ch.code < 128) ch else '_')
        }
        return sb.toString().take(40)
    }

    fun build(r: KnobsResponse): List<KnobRow> {
        val out = mutableListOf<KnobRow>()

        out += KnobRow.Header("Profil")
        out += KnobRow.Choice(
            id = "PROFILE",
            title = "Profil dasar",
            options = r.profiles,
            selectedIndex = 0,
            sink = KnobRow.Sink.CONFIG
        )

        if (r.cpu.supported) {
            out += KnobRow.Header("CPU")
            r.cpu.policies.forEach { p -> out += cpuRows(p) }
        }

        if (r.gpu.supported) {
            out += KnobRow.Header("GPU")
            r.gpu.nodes.forEach { n -> out += gpuRows(n) }
        }

        if (r.memory.supported) {
            out += KnobRow.Header("Memory")
            out += KnobRow.Choice(
                id = "zram_algo",
                title = "Algoritma zRAM",
                options = r.memory.zram.algos,
                selectedIndex = r.memory.zram.algos.indexOf(r.memory.zram.cur),
                enabled = r.memory.zram.writable,
                hint = if (r.memory.zram.writable) "[algo] = yang sedang aktif"
                else "node tidak bisa ditulis"
            )
            val sw = r.memory.swappiness
            if (sw.supported) {
                val values = (sw.min..sw.max).map { it.toString() }
                out += KnobRow.Choice(
                    id = "swappiness",
                    title = "Swappiness",
                    options = values,
                    selectedIndex = (sw.cur - sw.min).coerceAtLeast(0),
                    enabled = sw.writable
                )
            }
        }

        if (r.io.supported) {
            out += KnobRow.Header("I/O")
            r.io.blocks.forEach { b -> out += ioRows(b) }
        }

        if (r.network.supported) {
            out += KnobRow.Header("Jaringan")
            out += KnobRow.Choice(
                id = "tcp_cc",
                title = "TCP congestion control",
                options = r.network.tcp_cc,
                selectedIndex = 0
            )
            val tfo = r.network.tfo
            if (tfo.supported) {
                val values = (tfo.min..tfo.max).map { it.toString() }
                out += KnobRow.Choice(
                    id = "tfo",
                    title = "TCP Fast Open",
                    options = values,
                    selectedIndex = (tfo.cur - tfo.min).coerceAtLeast(0)
                )
            }
        }

        if (r.display.supported) {
            out += KnobRow.Header("Layar")
            if (r.display.modes_hz.isNotEmpty()) {
                out += KnobRow.Choice(
                    id = "REFRESH_LOCK_HZ",
                    title = "Kunci refresh rate",
                    options = r.display.modes_hz.map { "$it Hz" },
                    selectedIndex = r.display.modes_hz.indexOfFirst { "$it Hz" == "${r.display.cur_hz} Hz" }
                        .coerceAtLeast(0),
                    sink = KnobRow.Sink.CONFIG
                )
            }
            if (r.display.renderers.isNotEmpty()) {
                out += KnobRow.Choice(
                    id = "RENDERER",
                    title = "Renderer HWUI",
                    options = r.display.renderers,
                    selectedIndex = r.display.renderers.indexOf(r.display.cur_renderer).coerceAtLeast(0),
                    sink = KnobRow.Sink.CONFIG
                )
            }
            val ds = r.display.downscale
            if (ds.supported) {
                out += KnobRow.Choice(
                    id = "DOWNSCALE_PERCENT",
                    title = "Downscale resolusi (%)",
                    options = (ds.min..ds.max).map { "$it" },
                    selectedIndex = (ds.cur - ds.min).coerceAtLeast(0),
                    sink = KnobRow.Sink.CONFIG
                )
            }
        }

        out += KnobRow.Header("Fitur")
        out += KnobRow.Toggle(
            id = "GAM_BOOST_ENABLED",
            title = "Gaming boost",
            checked = r.features.gaming,
            enabled = true
        )
        out += KnobRow.Toggle(
            id = "ALLOW_EXTREME",
            title = "Extreme mode (berisiko)",
            checked = r.features.extremeOptin,
            enabled = true,
            hint = "nyalakan hanya kalau kamu paham risikonya"
        )
        // Switch di bawah dilaporkan `knobs` sebagai tersedia, tapi modul
        // belum punya aksi tulis untuknya -> read-only, bukan switch palsu.
        out += KnobRow.ReadOnly("DVFS limiter", boolText(r.features.dvfs))
        out += KnobRow.ReadOnly("Global refresh rate", boolText(r.features.globalRr))
        out += KnobRow.ReadOnly("Frame limit", boolText(r.features.frameLimit))
        out += KnobRow.ReadOnly("SurfaceFlinger tweak", boolText(r.features.surfaceflinger))

        return out
    }

    private fun cpuRows(p: CpuPolicyKnob): List<KnobRow> = buildList {
        val label = "Policy ${p.id} (plafon ${p.hwMaxKhz / 1000} MHz)"
        add(
            KnobRow.Choice(
                id = "cpu_policy_${p.id}_gov",
                title = "$label - governor",
                options = p.govs,
                selectedIndex = p.govs.indexOf(p.curGov),
                enabled = p.govs.isNotEmpty()
            )
        )
        add(
            KnobRow.Choice(
                id = "cpu_policy_${p.id}_max_khz",
                title = "$label - max freq",
                options = p.oppKhz.map { "$it kHz" },
                selectedIndex = p.oppKhz.indexOfLast { it <= p.hwMaxKhz },
                enabled = p.writableMax,
                hint = if (p.oppKhz.isEmpty()) "kernel tidak mengekspos daftar frekuensi" else null
            )
        )
    }

    private fun gpuRows(n: GpuNodeKnob): List<KnobRow> = buildList {
        val key = sanitizeNode(n.name)
        add(
            KnobRow.Choice(
                id = "gpu_node_${key}_gov",
                title = "${n.name} - governor",
                options = n.govs,
                selectedIndex = n.govs.indexOf(n.curGov),
                enabled = n.writable && n.govs.isNotEmpty()
            )
        )
        add(
            KnobRow.Choice(
                id = "gpu_node_${key}_max_khz",
                title = "${n.name} - max freq",
                options = n.oppKhz.map { "$it kHz" },
                selectedIndex = n.oppKhz.indexOfLast { true },
                enabled = n.writable,
                hint = if (n.oppKhz.isEmpty()) "kernel tidak mengekspos daftar OPP" else null
            )
        )
    }

    private fun ioRows(b: IoBlockKnob): List<KnobRow> = buildList {
        add(
            KnobRow.Choice(
                id = "io_block_${sanitizeNode(b.name)}_sched",
                title = "${b.name} - scheduler",
                options = b.schedulers,
                selectedIndex = b.schedulers.indexOf(b.cur),
                enabled = b.writable && b.schedulers.isNotEmpty(),
                hint = if (b.schedulers.isEmpty()) "daftar scheduler tidak terbaca" else null
            )
        )
    }

    private fun boolText(value: Boolean): String = if (value) "tersedia" else "tidak tersedia"
}
