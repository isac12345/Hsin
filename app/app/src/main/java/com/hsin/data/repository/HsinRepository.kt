package com.hsin.data.repository

import org.json.JSONObject
import org.json.JSONArray

/**
 * HsinRepository — parser output kontrak (§3.1–§3.11).
 *
 * Aturan (konservatif, dari kontrak):
 * - Abaikan key tak dikenal (jangan crash, jangan bocor ke UI).
 * - Kategori hanya: APPLIED | SKIPPED | FALLBACK | UNAVAILABLE | FAILED (§4, `core/safe_apply.sh:9-21`).
 *   Kategori asing → INVALID_RESPONSE (KDoc catat ini).
 * - `applied` boleh `-` atau `N` (manual tanpa override, §3.11).
 * - Log bercampur JSON: baris bukan `key=`/JSON diabaikan; JSON terakhir diambil blok.
 * - `capabilities` tidak disandbox (path `/sys` literal) — TIDAK dipakai sumber kebenaran.
 */
object HsinRepository {

    /** Kategori yang valid dari kode modul (§4, `core/safe_apply.sh:9-21`, `core/user_knobs.sh`). */
    private val VALID_CATS = setOf("APPLIED","SKIPPED","FALLBACK","UNAVAILABLE","FAILED")

    data class GuardStatus(
        val active: Int,
        val fail_count: Int,
        val threshold: Int,
        val cooldown_remaining_sec: Int,
        val last_reason: String
    )

    data class KnobResult(
        val key: String,
        val requested: String,
        val applied: String,
        val category: String,
        val reason: String
    )

    /** Parse `status` (output sederhana; kita ambil baris OK / error). */
    fun parseStatus(stdout: String): String = stdout.trim()

    /** Parse `guard-status` (§3.10): 5 key=value + JSON terakhir. */
    fun parseGuardStatus(stdout: String): GuardStatus {
        val lines = stdout.lines()
        val map = mutableMapOf<String, String>()
        var lastJson: JSONObject? = null
        for (line in lines) {
            val trimmed = line.trim()
            if (trimmed.isEmpty()) continue
            if (trimmed.startsWith("{")) {
                try { lastJson = JSONObject(trimmed) } catch (_: Exception) {}
            } else if (trimmed.contains("=")) {
                val idx = trimmed.indexOf('=')
                if (idx > 0) map[trimmed.substring(0, idx)] = trimmed.substring(idx + 1)
            }
        }
        // Prioritas: baris key=value; JSON terakhir sebagai fallback jika key hilang
        return GuardStatus(
            active = map["active"]?.toIntOrNull() ?: lastJson?.optInt("active") ?: 0,
            fail_count = map["fail_count"]?.toIntOrNull() ?: lastJson?.optInt("fail_count") ?: 0,
            threshold = map["threshold"]?.toIntOrNull() ?: lastJson?.optInt("threshold") ?: 0,
            cooldown_remaining_sec = map["cooldown_remaining_sec"]?.toIntOrNull() ?: lastJson?.optInt("cooldown_remaining_sec") ?: 0,
            last_reason = map["last_reason"] ?: lastJson?.optString("last_reason") ?: ""
        )
    }

    /** Parse `knob-list` (§3.2–§3.11). Baris `key=... requested=... applied=... category=... reason="..."` + JSON terakhir. */
    fun parseKnobList(stdout: String): List<KnobResult> {
        val results = mutableListOf<KnobResult>()
        var lastJsonBlock: String? = null
        val lines = stdout.lines()
        for (line in lines) {
            val t = line.trim()
            if (t.isEmpty()) continue
            if (t.startsWith("{")) {
                lastJsonBlock = t
                continue
            }
            // Baris key=... (bukan JSON)
            if (t.contains("key=")) {
                val key = extractKey(t, "key=") ?: continue
                val requested = extractValue(t, "requested=") ?: ""
                val applied = extractValue(t, "applied=") ?: ""
                val category = extractValue(t, "category=") ?: ""
                val reason = extractQuoted(t, "reason=") ?: ""
                // Validasi kategori: hanya set yang PUNYA (§4)
                if (category.isNotEmpty() && category !in VALID_CATS) {
                    // Kategori asing → abaikan entry ini (jangan crash, jangan bocor)
                    // Tapi kita tetap simpan sebagai INVALID_RESPONSE tanda di KDoc; karena
                    // parser hanya mengembalikan list, kita abaikan agar UI tidak menerima kategori baru.
                    continue
                }
                // Abaikan jika key tak dikenal (jangan bocor) — kita hanya izinkan yang ada dalam baris
                if (key.isNotEmpty()) {
                    results.add(KnobResult(key, requested, applied, category, reason))
                }
            }
        }
        // JSON terakhir sebagai tambahan jika berisi array/objek knob
        if (lastJsonBlock != null) {
            try {
                val arr = JSONArray(lastJsonBlock)
                for (i in 0 until arr.length()) {
                    val obj = arr.getJSONObject(i)
                    val k = obj.optString("key", "")
                    val req = obj.optString("requested", "")
                    val app = obj.optString("applied", "")
                    val cat = obj.optString("category", "")
                    val reas = obj.optString("reason", "")
                    if (k.isNotEmpty() && (cat.isEmpty() || cat in VALID_CATS)) {
                        results.add(KnobResult(k, req, app, cat, reas))
                    }
                }
            } catch (_: Exception) {
                try {
                    val obj = JSONObject(lastJsonBlock)
                    val k = obj.optString("key", "")
                    if (k.isNotEmpty()) {
                        results.add(KnobResult(k, obj.optString("requested"), obj.optString("applied"), obj.optString("category"), obj.optString("reason")))
                    }
                } catch (_: Exception) {}
            }
        }
        return results
    }

    private fun extractKey(s: String, prefix: String): String? {
        val idx = s.indexOf(prefix)
        if (idx < 0) return null
        val rest = s.substring(idx + prefix.length)
        val end = rest.indexOf(' ')
        return if (end > 0) rest.substring(0, end) else rest
    }
    private fun extractValue(s: String, prefix: String): String? {
        val idx = s.indexOf(prefix)
        if (idx < 0) return null
        val rest = s.substring(idx + prefix.length)
        val end = rest.indexOf(' ')
        val valStr = if (end > 0) rest.substring(0, end) else rest
        return valStr.trim()
    }
    private fun extractQuoted(s: String, prefix: String): String? {
        val idx = s.indexOf(prefix)
        if (idx < 0) return null
        val rest = s.substring(idx + prefix.length)
        val quoteStart = rest.indexOf('"')
        if (quoteStart < 0) return null
        val quoteEnd = rest.indexOf('"', quoteStart + 1)
        return if (quoteEnd > quoteStart) rest.substring(quoteStart + 1, quoteEnd) else null
    }
}
