package com.hsin

import java.util.concurrent.TimeUnit

/** Semua akses root lewat sini. Satu proses `su` per panggilan, dengan timeout. */
object Shell {
    private const val ACTION = "/data/adb/modules/hsin/action.sh"

    fun run(cmd: String, timeoutSec: Long = 20): Pair<Int, String> {
        return try {
            val p = ProcessBuilder("su", "-c", cmd).redirectErrorStream(true).start()
            val sb = StringBuilder()
            val reader = Thread {
                try {
                    p.inputStream.bufferedReader().use { r ->
                        val buf = CharArray(4096)
                        while (true) {
                            val n = r.read(buf)
                            if (n < 0) break
                            sb.append(buf, 0, n)
                        }
                    }
                } catch (e: Exception) {
                    // proses dimatikan / stream ditutup
                }
            }
            reader.start()
            val done = p.waitFor(timeoutSec, TimeUnit.SECONDS)
            if (!done) p.destroyForcibly()
            reader.join(1500)
            Pair(if (done) p.exitValue() else -2, sb.toString().trim())
        } catch (e: Exception) {
            Pair(-1, "")
        }
    }

    fun hasRoot(): Boolean {
        val r = run("id", 12)
        return r.first == 0 && r.second.contains("uid=0")
    }

    /** Argumen dibersihkan: hanya huruf, angka, dan _ . = : - + */
    fun action(vararg args: String): Pair<Int, String> {
        val clean = args.map { a -> a.filter { it.isLetterOrDigit() || it in "_.=:-+" } }
        return run("sh $ACTION " + clean.joinToString(" "))
    }
}
