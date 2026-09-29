package com.hsin.data.root

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * RootClient — eksekusi `su` di Dispatchers.IO dengan timeout.
 *
 * Pemetaan error (kontrak §5 butir 5; juga §3.9 jebakan Usage: rc=0):
 * - ROOT_UNAVAILABLE: su tidak bisa dijalankan (transport)
 * - MODULE_NOT_FOUND: path modul hilang / modul tidak terpasang
 * - FEATURE_UNSUPPORTED: `writable:false` / `supported:false` (bukan rc)
 * - COMMAND_FAILED: rc=1 + `ERROR:`; atau `Usage:` meski rc=0 (§3.9)
 * - TIMEOUT: proses melebihi timeoutMs (default 15000 ms)
 * - INVALID_RESPONSE: output tidak mengandung blok JSON yang diharapkan
 *
 * Jebakan §3.9 (WAJIB): perintah tak dikenal → teks Usage dengan rc=0.
 * Jadi rc=0 ≠ sukses jika baris pertama berawal `Usage:`.
 *
 * Jebakan §3.9: `capabilities` tidak bisa disandbox (path `/sys` literal)
 * — CATAT di KDoc, TIDAK dipakai sumber kebenaran oleh parser.
 */
sealed class RootResult {
    data class Success(val stdout: String, val stderr: String, val rc: Int) : RootResult()
    data class Error(val type: RootError, val message: String) : RootResult()
}

enum class RootError { ROOT_UNAVAILABLE, MODULE_NOT_FOUND, FEATURE_UNSUPPORTED, COMMAND_FAILED, TIMEOUT, INVALID_RESPONSE }

class RootClient(private val timeoutMs: Long = 15000L) {

    /** Allowlist persis `action.sh:1406`. */
    private val ALLOWLIST = setOf(
        "info","device","capabilities","status","guard-status","logs","apply",
        "backup","rollback","conflicts","export","renderer-apply","renderer-state",
        "downscale-enable","downscale-disable","downscale-status",
        "refresh-lock-enable","refresh-lock-disable","refresh-lock-status",
        "export-debug","list-apps","game-list","game-add","game-remove"
    )

    private val PROFILES = setOf("manual","battery","balanced","performance","extreme")
    private val KEY_PAT = Regex("^[a-z0-9_]+$")

    /** Escape argumen untuk `sh -c` (quote single, hapus `'` dalam nilai). */
    private fun String.quoteShell(): String = "'" + this.replace("'", "'\\''") + "'"

    suspend fun execute(cmd: String, args: List<String> = emptyList()): RootResult = withContext(Dispatchers.IO) {
        if (cmd !in ALLOWLIST) return@withContext RootResult.Error(
            RootError.COMMAND_FAILED, "command not allowed: $cmd")

        for (a in args) {
            if (a.contains(";") || a.contains("|") || a.contains("&") || a.contains("`") ||
                a.contains("$") || a.contains("(") || a.contains(")") || a.contains("<") ||
                a.contains(">") || a.contains("\n") || a.contains("\r")) {
                return@withContext RootResult.Error(
                    RootError.COMMAND_FAILED, "unsafe arg: $a")
            }
        }

        if (cmd == "apply" && args.isNotEmpty()) {
            val p = args[0]
            if (p !in PROFILES) return@withContext RootResult.Error(
                RootError.COMMAND_FAILED, "invalid profile: $p")
        }

        val cmdStr = buildString {
            append("sh /data/adb/modules/hsin/action.sh ")
            append(cmd.quoteShell())
            for (a in args) append(" ").append(a.quoteShell())
        }

        try {
            val pb = ProcessBuilder("su", "-c", cmdStr)
            pb.redirectErrorStream(true)
            val proc = pb.start()

            val stdoutBa = java.io.ByteArrayOutputStream()
            val reader = proc.inputStream.bufferedReader()
            val writer = stdoutBa.outputStream()

            val t = Thread {
                try { reader.copyTo(writer) } catch (_: Exception) {}
            }
            t.start()
            t.join(timeoutMs)
            if (t.isAlive) {
                proc.destroyForcibly()
                t.interrupt()
                return@withContext RootResult.Error(
                    RootError.TIMEOUT, "timeout after ${timeoutMs}ms")
            }

            val stdout = stdoutBa.toString("UTF-8")
            val rc = proc.waitFor()

            val firstLine = stdout.lineSequence().map { it.trim() }.filter { it.isNotEmpty() }.firstOrNull() ?: ""
            if (firstLine.startsWith("Usage:")) {
                return@withContext RootResult.Error(
                    RootError.COMMAND_FAILED, "unknown command returned Usage (rc=$rc): $firstLine")
            }

            if (rc != 0) {
                val msg = stdout.trim()
                if (msg.contains("MODULE_NOT_FOUND")) return@withContext RootResult.Error(
                    RootError.MODULE_NOT_FOUND, msg)
                if (msg.contains("FEATURE_UNSUPPORTED") || msg.contains("not supported")) return@withContext RootResult.Error(
                    RootError.FEATURE_UNSUPPORTED, msg)
                return@withContext RootResult.Error(
                    RootError.COMMAND_FAILED, "rc=$rc: $msg")
            }

            RootResult.Success(stdout.trim(), "", rc)
        } catch (e: Exception) {
            val msg = e.message ?: e.toString()
            when {
                msg.contains("su") || msg.contains("Permission") || msg.contains("not found") ->
                    RootResult.Error(RootError.ROOT_UNAVAILABLE, msg)
                else -> RootResult.Error(RootError.COMMAND_FAILED, msg)
            }
        }
    }
}
