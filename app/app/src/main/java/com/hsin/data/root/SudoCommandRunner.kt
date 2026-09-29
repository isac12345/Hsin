package com.hsin.data.root

/**
 * Implementasi nyata [CommandRunner] via `su -c`.
 *
 * Catatan: `redirectErrorStream(true)` — output yang dikembalikan adalah
 * stdout+stderr GABUNGAN, bukan stdout murni. Tidak ada pemisahan di sini
 * karena kontrak modul tidak menjamin stderr terisi pada rc=0.
 */
object SudoCommandRunner : CommandRunner {
    override fun run(cmd: String, timeoutMs: Long, out: StringBuilder, onTimeout: () -> Unit): Int {
        val pb = ProcessBuilder("su", "-c", cmd)
        pb.redirectErrorStream(true)
        val proc = pb.start()
        val reader = proc.inputStream.bufferedReader()
        val sb = StringBuilder()

        val readerThread = Thread {
            try {
                reader.readText { chunk -> sb.append(chunk) }
            } catch (_: Exception) {
                // stream ditutup paksa saat timeout; output parsial tetap dipakai
            }
        }
        readerThread.isDaemon = true
        readerThread.start()
        readerThread.join(timeoutMs)

        if (readerThread.isAlive) {
            // Timeout: matikan proses (dan anak-anaknya) sebelum membaca sisa.
            proc.destroyForcibly()
            readerThread.join(READBACK_GRACE_MS)
            readerThread.interrupt()
            onTimeout()
            out.append(sb.toString())
            return TIMEOUT_EXIT
        }

        val exit = try {
            proc.waitFor()
        } catch (e: InterruptedException) {
            Thread.currentThread().interrupt()
            proc.destroyForcibly()
            onTimeout()
            out.append(sb.toString())
            return TIMEOUT_EXIT
        }
        out.append(sb.toString())
        return exit
    }

    /** Nilai kembalian khusus agar [RootClient] tidak salah baca sebagai exit code asli. */
    const val TIMEOUT_EXIT = -1

    /** Waktu tambahan untuk reader menutup stream setelah proses dibunuh. */
    private const val READBACK_GRACE_MS = 250L
}
