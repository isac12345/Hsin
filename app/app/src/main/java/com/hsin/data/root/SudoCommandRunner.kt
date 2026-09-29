package com.hsin.data.root

import java.io.ByteArrayOutputStream

/**
 * Implementasi nyata [`CommandRunner`] via su -c.
 * Path modul TIDAK bisa diubah dari luar (konstanta `/data/adb/modules/hsin/action.sh`).
 */
object SudoCommandRunner : CommandRunner {
    override fun run(cmd: String, timeoutMs: Long, out: StringBuilder, onTimeout: () -> Unit): Int {
        val pb = ProcessBuilder("su", "-c", cmd)
        pb.redirectErrorStream(true)
        val proc = pb.start()
        val ba = ByteArrayOutputStream()
        val reader = proc.inputStream.bufferedReader()
        val writer = ba.outputStream()
        val t = Thread {
            try { reader.copyTo(writer) } catch (_: Exception) {}
        }
        t.start()
        t.join(timeoutMs)
        if (t.isAlive) {
            proc.destroyForcibly()
            t.interrupt()
            onTimeout()
            // Setelah timeout, baca sisa jika ada
            try { reader.copyTo(writer) } catch (_: Exception) {}
            out.append(ba.toString("UTF-8"))
            return -1 // tanda timeout
        }
        val stdout = ba.toString("UTF-8")
        out.append(stdout)
        return proc.waitFor()
    }
}
