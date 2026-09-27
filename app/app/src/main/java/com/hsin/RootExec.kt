package com.hsin

import android.util.Log
import kotlin.concurrent.thread

/**
 * Eksekusi root lewat `su -c` dengan stdout capture, timeout, dan quoting
 * POSIX-aman.
 *
 * Diwarisi dari RootExecutor Alpha (timeout + exit code + quoting), ditambah
 * stdout karena HSIN selalu menjawab dengan teks/JSON yang harus dibaca app.
 */
object RootExec {

    private const val TAG = "RootExec"
    const val DEFAULT_TIMEOUT_MS = 20_000L

    data class Result(
        val stdout: String,
        val exitCode: Int,
        val success: Boolean
    )

    /** Token aman dilewati; sisanya dibungkus '...' dengan ' di-escape. */
    private val SAFE_TOKEN = Regex("^[A-Za-z0-9._/@:=+-]+$")

    fun quoteArg(arg: String): String {
        if (arg.isEmpty()) return "''"
        if (SAFE_TOKEN.matches(arg)) return arg
        return "'" + arg.replace("'", "'\\''") + "'"
    }

    fun buildCommand(vararg tokens: String): String =
        tokens.joinToString(" ") { quoteArg(it) }

    fun exec(command: String, timeoutMs: Long = DEFAULT_TIMEOUT_MS): Result {
        if (command.isEmpty()) return Result("", -1, false)
        val to = if (timeoutMs > 0) timeoutMs else DEFAULT_TIMEOUT_MS
        return try {
            val process = Runtime.getRuntime().exec(arrayOf("su", "-c", command))

            // stdout & stderr HARUS dua thread terpisah; kalau keduanya
            // ditunggu setelah waitFor(), pipe penuh -> deadlock.
            val out = StringBuilder()
            val err = StringBuilder()
            val outThread = thread { process.inputStream.bufferedReader().use { out.append(it.readText()) } }
            val errThread = thread { process.errorStream.bufferedReader().use { err.append(it.readText()) } }

            val finished = process.waitFor(to, java.util.concurrent.TimeUnit.MILLISECONDS)
            if (!finished) {
                process.destroy()
                runCatching { process.destroyForcibly() }
                Log.w(TAG, "timeout ${to}ms: $command")
                outThread.join(500)
                errThread.join(500)
                return Result("timeout ${to}ms", -1, false)
            }
            outThread.join(2_000)
            errThread.join(2_000)

            val code = process.exitValue()
            if (code != 0) {
                Log.w(TAG, "exit=$code cmd=$command err=${err.take(200)}")
                return Result(out.toString().trim(), code, false)
            }
            Result(out.toString().trim(), 0, true)
        } catch (t: Throwable) {
            Log.w(TAG, "gagal: $command", t)
            Result("${t.javaClass.simpleName}: ${t.message}", -1, false)
        }
    }

    fun execTokens(vararg tokens: String, timeoutMs: Long = DEFAULT_TIMEOUT_MS): Result =
        exec(buildCommand(*tokens), timeoutMs)
}
