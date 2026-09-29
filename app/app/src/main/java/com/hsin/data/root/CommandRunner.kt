package com.hsin.data.root

/**
 * Injeksi untuk RootClient agar bisa diuji tanpa root nyata.
 * Implementasi default [`SudoCommandRunner`] menggunakan ProcessBuilder("su","-c",...).
 */
fun interface CommandRunner {
    /**
     * Jalankan command. Isi [out] dengan output gabungan stdout+stderr.
     * Kembalikan exit code. Panggil [onTimeout] jika belum selesai dalam [timeoutMs].
     */
    fun run(cmd: String, timeoutMs: Long, out: StringBuilder, onTimeout: () -> Unit): Int
}
