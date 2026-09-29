package com.hsin.data.state

import org.json.JSONArray

/**
 * Presenter Log A12 (murni, tanpa Android).
 *
 * Kontrak §3.6: `logs [type] [lines]` → array JSON 1 baris berisi N baris
 * terakhir; file hilang → `[]`. `type` = nama file di `$HSIN_DATA/logs/`
 * (`boot.log`, `apply.log`, ...).
 *
 * Aturan:
 * - Hanya N baris terakhir yang disimpan (batas memori; default 200).
 * - Baris rusak (JSON pecah, elemen bukan string, baris tanpa level)
 *   tidak boleh membuat crash — dilewati/di-fallback, bukan throw.
 */
object LogPresenter {

    /** Jumlah baris maksimum per tab (batas memori). */
    const val MAX_LINES = 200

    /**
     * Parse keluaran `logs`: coba sebagai array JSON dulu; kalau gagal,
     * fallback ke baris teks biasa. Tidak pernah throw.
     */
    fun parseLogOutput(output: String, maxLines: Int = MAX_LINES): List<String> {
        if (output.isBlank()) return emptyList()
        val fromJson = tryParseJsonArray(output)
        val lines = fromJson ?: output.lines().filter { it.isNotBlank() }
        if (lines.size <= maxLines) return lines
        return lines.takeLast(maxLines)
    }

    private fun tryParseJsonArray(output: String): List<String>? {
        val trimmed = output.trim()
        if (!trimmed.startsWith("[")) return null
        return try {
            val arr = JSONArray(trimmed)
            val out = ArrayList<String>(arr.length())
            for (i in 0 until arr.length()) {
                val s = arr.optString(i, "")
                if (s.isNotBlank()) out.add(s)
            }
            out
        } catch (_: Exception) {
            null
        }
    }

    /**
     * Level baris untuk badge: isi tag `[...]` pertama (uppercase),
     * atau kata kunci ERROR/WARN bila tanpa tag. Baris tanpa info level
     * → "INFO" (bukan crash, bukan kosong).
     */
    fun levelOf(line: String): String {
        val tag = Regex("\\[([^\\]]{1,24})\\]").find(line)?.groupValues?.get(1)
            ?.trim()?.uppercase()
        if (!tag.isNullOrBlank()) return tag
        val up = line.uppercase()
        return when {
            "ERROR" in up || "FAILED" in up || "GAGAL" in up -> "ERROR"
            "WARN" in up -> "WARN"
            else -> "INFO"
        }
    }

    /**
     * Ringkasan laporan bug untuk tombol "Salin": status boot guard,
     * ringkasan capability, dan baris log terakhir. Murni string —
     * penyalinan ke clipboard dilakukan layar Compose.
     */
    fun buildBugReport(
        guard: GuardState?,
        capability: KnobCapability?,
        bootTail: List<String>,
        applyTail: List<String>,
        maxLogLines: Int = 20,
    ): String {
        val sb = StringBuilder()
        sb.appendLine("HSIN bug report (beta)")
        val g = guard
        sb.appendLine(
            if (g == null) "boot guard: tidak diketahui"
            else "boot guard: active=${g.active} fail=${g.failCount}/${g.threshold} cooldown=${g.cooldownRemainingSec}s reason=${g.lastReason}"
        )
        val c = capability
        sb.appendLine(
            if (c == null) "capability: belum diperiksa"
            else "capability: ${c.supportedKeys.size} knob"
        )
        sb.appendLine("--- boot.log (terakhir $maxLogLines) ---")
        for (l in bootTail.takeLast(maxLogLines)) sb.appendLine(l)
        sb.appendLine("--- apply.log (terakhir $maxLogLines) ---")
        for (l in applyTail.takeLast(maxLogLines)) sb.appendLine(l)
        return sb.toString().trimEnd()
    }
}
