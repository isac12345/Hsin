package com.hsin

/**
 * Jembatan native (NDK/JNI) untuk path panas HSIN.
 *
 * Penentuan: native dipakai hanya bila [available] == true, yaitu setelah
 * [System.loadLibrary("hsin_native")] berhasil dan JNI symbol ditemukan.
 * Bila .so hilang / tidak cocok ABI / gagal load, [available] = false dan
 * semua pemanggilan otomatis fallback ke implementasi Kotlin murni — TIDAK
 * force-close. Javadoc ini berlaku untuk semua fungsi publik.
 */
object HsinNative {

    @JvmStatic
    val available: Boolean = try {
        System.loadLibrary("hsin_native")
        true
    } catch (e: Throwable) {
        false
    }

    /**
     * Jalankan native [lastJsonLine] bila [available]; jika tidak,
     * fallback Kotlin murni (identik perilakunya: scan baris akhir,
     * trim, mulai `{`, null bila tidak ada).
     */
    @JvmStatic
    fun lastJsonLineOrNull(output: String): String? =
        if (available) nativeLastJsonLine(output) else fallbackLastJsonLine(output)

    /**
     * Jalankan native [sanitizeNode] bila [available]; jika tidak,
     * fallback Kotlin murni (hanya [A-Za-z0-9] dipertahankan, lain `_`,
     * potong 40 char per codepoint).
     */
    @JvmStatic
    fun sanitizeNode(node: String): String =
        if (available) nativeSanitizeNode(node) else fallbackSanitizeNode(node)

    // --- JNI vai native ---

    private external fun nativeLastJsonLine(output: String): String?
    private external fun nativeSanitizeNode(node: String): String

    // --- Fallback Kotlin murni (identik dengan implementasi asli) ---

    private fun fallbackLastJsonLine(stdout: String): String? =
        stdout.lineSequence()
            .map { it.trim() }
            .lastOrNull { it.startsWith("{") }

    private fun fallbackSanitizeNode(name: String): String {
        val sb = StringBuilder(name.length)
        for (ch in name) {
            sb.append(if (ch.isLetterOrDigit() && ch.code < 128) ch else '_')
        }
        return sb.toString().take(40)
    }
}
