package com.hsin.data.repository

import org.json.JSONObject

/**
 * HsinRepository — parser output kontrak (§3.1–§3.11, M3).
 *
 * Aturan (konservatif):
 * - Abaikan key tak dikenal (jangan crash, jangan bocor ke UI).
 * - Kategori hanya: APPLIED | SKIPPED | FALLBACK | UNAVAILABLE | FAILED (§4).
 *   Kategori asing → hasil parse gagal (bukan diabaikan; lihat KnobParseResult).
 * - `applied` boleh `-` atau `N` (§3.11).
 * - `capabilities` tidak disandbox (path `/sys` literal) — TIDAK dipakai sumber kebenaran.
 * - `guard-status` key wajib; jika `active`/bilangan wajib tak terbaca → parse gagal.
 */
object HsinRepository {

    private val VALID_CATS = setOf("APPLIED","SKIPPED","FALLBACK","UNAVAILABLE","FAILED")

    data class GuardStatus(
        val active: Int,
        val failCount: Int,
        val threshold: Int,
        val cooldownRemainingSec: Int,
        val lastReason: String
    )

    data class KnobResult(
        val key: String,
        val requested: String,
        val applied: String,
        val category: String,
        val reason: String
    )

    /** Hasil parse knob-list: sukses atau gagal karena kategori asing/JSON rusak. */
    sealed class KnobParseResult {
        data class Ok(val items: List<KnobResult>, val count: Int?, val overrides: Map<String,String>) : KnobParseResult()
        data class InvalidResponse(val reason: String) : KnobParseResult()
    }

    /** Parse `guard-status`. Key wajib harus terbaca; jika tidak → nullable / gagal.
     * Nama field Kotlin idiomatis (`failCount` dll) dengan mapping eksplisit dari key kontrak. */
    fun parseGuardStatus(stdout: String): GuardStatus? {
        val lines = stdout.lines()
        val map = mutableMapOf<String, String>()
        var jsonObj: JSONObject? = null
        for (line in lines) {
            val trimmed = line.trim()
            if (trimmed.isEmpty()) continue
            if (trimmed.startsWith("{")) {
                try { jsonObj = JSONObject(trimmed) } catch (_: Exception) {}
            } else if (trimmed.contains("=")) {
                val idx = trimmed.indexOf('=')
                if (idx > 0) {
                    val k = trimmed.substring(0, idx)
                    val v = trimmed.substring(idx + 1)
                    map[k] = v.trim().trim('"')
                }
            }
        }
        fun readInt(k: String): Int? = map[k]?.toIntOrNull() ?: jsonObj?.optInt(k, Int.MIN_VALUE)?.let { if (it == Int.MIN_VALUE) null else it }
        val active = readInt("active") ?: return null
        val failCount = readInt("fail_count") ?: return null
        val threshold = readInt("threshold") ?: return null
        val cooldown = readInt("cooldown_remaining_sec") ?: return null
        val reason = map["last_reason"] ?: jsonObj?.optString("last_reason") ?: return null
        return GuardStatus(active, failCount, threshold, cooldown, reason)
    }

    /** Parse `knob-list` (§3.11). Baris `key=...` harus di-anchor di awal. JSON terakhir adalah objek `{"count":N,"overrides":{...}}`; tidak membuat entri knob tambahan (hanya baca count/overrides). */
    fun parseKnobList(stdout: String): KnobParseResult {
        val items = mutableListOf<KnobResult>()
        var lastObjStr: String? = null
        val lines = stdout.lines()
        for (line in lines) {
            val t = line.trim()
            if (t.isEmpty()) continue
            if (t.startsWith("{")) {
                lastObjStr = t
                continue
            }
            // Anchor di awal baris
            if (!t.startsWith("key=")) continue
            val key = extractFrom(t, "key=", ' ') ?: continue
            val requested = extractFrom(t, "requested=", ' ') ?: ""
            val applied = extractFrom(t, "applied=", ' ') ?: ""
            val categoryRaw = extractFrom(t, "category=", ' ') ?: ""
            val reason = extractQuoted(t, "reason=") ?: ""
            if (categoryRaw.isNotEmpty() && categoryRaw !in VALID_CATS) {
                return KnobParseResult.InvalidResponse("foreign category: $categoryRaw")
            }
            if (key.isNotEmpty()) {
                items.add(KnobResult(key, requested, applied, categoryRaw, reason))
            }
        }
        // JSON terakhir: hanya baca count & overrides, jangan tambah entri knob dari sini
        var count: Int? = null
        val overrides = mutableMapOf<String, String>()
        if (lastObjStr != null) {
            try {
                val obj = JSONObject(lastObjStr)
                count = if (obj.has("count")) obj.getInt("count") else null
                if (obj.has("overrides")) {
                    val o = obj.getJSONObject("overrides")
                    val keys = o.keys()
                    while (keys.hasNext()) {
                        val k = keys.next()
                        overrides[k] = o.getString(k)
                    }
                }
            } catch (_: Exception) {
                return KnobParseResult.InvalidResponse("broken JSON block")
            }
        }
        return KnobParseResult.Ok(items, count, overrides)
    }

    /** Status sederhana (§3.1). Jika kosong / rusak → kosong, bukan karangan. */
    fun parseStatus(stdout: String): String? {
        val trimmed = stdout.trim()
        return if (trimmed.isNotEmpty()) trimmed else null
    }

    private fun extractFrom(s: String, prefix: String, stop: Char): String? {
        val idx = s.indexOf(prefix)
        if (idx < 0) return null
        val rest = s.substring(idx + prefix.length)
        val end = rest.indexOf(stop)
        return if (end > 0) rest.substring(0, end) else rest
    }
    private fun extractQuoted(s: String, prefix: String): String? {
        val idx = s.indexOf(prefix)
        if (idx < 0) return null
        val rest = s.substring(idx + prefix.length)
        val q1 = rest.indexOf('"')
        if (q1 < 0) return null
        val q2 = rest.indexOf('"', q1 + 1)
        return if (q2 > q1) rest.substring(q1 + 1, q2) else null
    }
}
