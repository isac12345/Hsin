package com.hsin

import kotlinx.serialization.Serializable

@Serializable
data class RootResult(
    val stdout: String,
    val exitCode: Int,
    val success: Boolean
)

class RootExec {
    companion object {
        private const val DEFAULT_TIMEOUT_MS = 20000L
        private const val TAG = "RootExec"

        /**
         * Quote a single argument for POSIX shell safety.
         * Alphanumeric + ._/@:=- pass through; everything else wrapped in single quotes with embedded quotes escaped.
         */
        fun quoteArg(arg: String): String {
            if (arg.matches("^[a-zA-Z0-9._/@:=-]+\$".toRegex())) {
                return arg
            }
            return "'${arg.replace("'", "'\\\\''")}'"
        }

        /**
         * Build a shell command from pre-quoted tokens.
         */
        fun buildCommand(vararg tokens: String): String {
            return tokens.joinToString(" ") { quoteArg(it) }
        }

        /**
         * Execute a shell command via `su -c` with timeout and stdout capture.
         */
        fun exec(command: String, timeoutMs: Long = DEFAULT_TIMEOUT_MS): RootResult {
            return try {
                val process = Runtime.getRuntime().exec(arrayOf("su", "-c", command))
                var stdout = ""
                var stderr = ""
                val stdoutThread = Thread {
                    process.inputStream.bufferedReader().use { reader ->
                        stdout = reader.readText()
                    }
                }
                val stderrThread = Thread {
                    process.errorStream.bufferedReader().use { reader ->
                        stderr = reader.readText()
                    }
                }
                stdoutThread.start()
                stderrThread.start()
                val finished = process.waitFor(timeoutMs, java.util.concurrent.TimeUnit.MILLISECONDS)
                stdoutThread.join(1000)
                stderrThread.join(1000)
                if (!finished) {
                    process.destroy()
                    try { process.destroyForcibly() } catch (e: Throwable) {}
                    return RootResult(
                        stdout = "timeout ${timeoutMs}ms: $command",
                        exitCode = -1,
                        success = false
                    )
                }
                val exitCode = process.exitValue()
                if (exitCode != 0) {
                    return RootResult(
                        stdout = "exit $exitCode: $command\nstdout: $stdout\nstderr: $stderr",
                        exitCode = exitCode,
                        success = false
                    )
                }
                RootResult(stdout = stdout.trim(), exitCode = exitCode, success = true)
            } catch (e: Exception) {
                RootResult(stdout = "${e.javaClass.simpleName}: $command - ${e.message}", exitCode = -1, success = false)
            }
        }

        /**
         * Execute with pre-quoted tokens (safe for user input).
         */
        fun execTokens(vararg tokens: String, timeoutMs: Long = DEFAULT_TIMEOUT_MS): RootResult {
            return exec(buildCommand(*tokens), timeoutMs)
        }
    }
}