package com.hsin.data.root

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * RootClient — eksekusi `su` di Dispatchers.IO dengan timeout.
 *
 * Pemetaan error (kontrak §5 butir 5; §3.9 jebakan Usage rc=0):
 * - ROOT_UNAVAILABLE: su tidak bisa dijalankan / exception transport
 * - MODULE_NOT_FOUND: path `/data/adb/modules/hsin/action.sh` tidak ada (diperiksa sebelum run)
 * - FEATURE_UNSUPPORTED: TIDAK dari rc; berasal dari payload `knobs` (writable:false) di Repository
 * - COMMAND_FAILED: rc!=0 + `ERROR:`; atau `Usage:` meski rc=0 (§3.9)
 * - TIMEOUT: proses tidak selesai dalam timeoutMs
 * - INVALID_RESPONSE: parser Repository menemui kategori asing atau JSON rusak
 *
 * Jebakan §3.9: `Usage:` dengan rc=0 → COMMAND_FAILED.
 * `capabilities` tidak disandbox (path `/sys` literal) — catat di KDoc, TIDAK dipakai parser.
 *
 * Validasi argumen: allowlist character `^[A-Za-z0-9_.:@%+=,-]+$` per argumen; key knob `^[a-z0-9_]{1,64}$`; nilai numerik `^-?\d{1,12}$`; profil hanya `manual|battery|balanced|performance|extreme`.
 */
sealed class RootResult {
    data class Success(val stdout: String, val stderr: String, val rc: Int) : RootResult() {
        init {
            require(stderr.isNotEmpty() || stdout.isNotEmpty()) { "output tidak boleh kosong bersama" }
        }
    }
    data class Error(val type: RootError, val message: String) : RootResult()
}

enum class RootError { ROOT_UNAVAILABLE, MODULE_NOT_FOUND, FEATURE_UNSUPPORTED, COMMAND_FAILED, TIMEOUT, INVALID_RESPONSE }

class RootClient(
    private val runner: CommandRunner = SudoCommandRunner,
    private val timeoutMs: Long = 15000L
) {

    private val ALLOWLIST = setOf(
        "info","device","capabilities","status","guard-status","logs","apply",
        "backup","rollback","conflicts","export","renderer-apply","renderer-state",
        "downscale-enable","downscale-disable","downscale-status",
        "refresh-lock-enable","refresh-lock-disable","refresh-lock-status",
        "export-debug","list-apps","game-list","game-add","game-remove"
    )

    private val PROFILES = setOf("manual","battery","balanced","performance","extreme")
    private val SAFE_ARG = Regex("^[A-Za-z0-9_.:@%+=,-]+$")
    private val KEY_PAT = Regex("^[a-z0-9_]{1,64}$")
    private val NUM_PAT = Regex("^-?\\d{1,12}$")
    private val MODULE_PATH = "/data/adb/modules/hsin/action.sh"

    /** Escape argumen dengan single-quote (`'...'`) dan sanitasi `'` → `'\''`. */
    private fun String.quoteShell(): String = "'" + this.replace("'", "'\\''") + "'"

    suspend fun execute(cmd: String, args: List<String> = emptyList()): RootResult = withContext(Dispatchers.IO) {
        // Allowlist sebelum apa pun
        if (cmd !in ALLOWLIST) {
            return@withContext RootResult.Error(
                RootError.COMMAND_FAILED, "command not allowed: $cmd")
        }

        // Validasi tiap argumen via allowlist karakter (bukan blacklist)
        for (a in args) {
            if (a.isEmpty()) {
                return@withContext RootResult.Error(RootError.COMMAND_FAILED, "empty arg")
            }
            if (!SAFE_ARG.matches(a)) {
                return@withContext RootResult.Error(
                    RootError.COMMAND_FAILED, "unsafe arg char: $a")
            }
        }

        // Profil valid jika apply
        if (cmd == "apply" && args.isNotEmpty()) {
            if (args[0] !in PROFILES) {
                return@withContext RootResult.Error(
                    RootError.COMMAND_FAILED, "invalid profile: ${args[0]}")
            }
        }

        // Validasi key/pattern jika argumen mengandung key (konservatif; tidak semua command)
        // Untuk knob-set / knob-get / knob-reset jika dipakai oleh Repository
        if (args.size >= 2 && (cmd.contains("knob") || cmd.contains("set") || cmd.contains("get") || cmd.contains("reset"))) {
            val key = args[0]
            if (!KEY_PAT.matches(key)) {
                return@withContext RootResult.Error(
                    RootError.COMMAND_FAILED, "invalid knob key: $key")
            }
            val value = args[1]
            if (!NUM_PAT.matches(value) && value != "manual" && value != "auto") {
                return@withContext RootResult.Error(
                    RootError.COMMAND_FAILED, "invalid knob value: $value")
            }
        }

        // Pemeriksaan path modul sebelum menjalankan → MODULE_NOT_FOUND
        val moduleFile = java.io.File(MODULE_PATH)
        if (!moduleFile.exists()) {
            return@withContext RootResult.Error(
                RootError.MODULE_NOT_FOUND, "module path missing: $MODULE_PATH")
        }

        val cmdStr = buildString {
            append("sh ")
            append(MODULE_PATH.quoteShell())
            append(" ")
            append(cmd.quoteShell())
            for (a in args) append(" ").append(a.quoteShell())
        }

        val out = StringBuilder()
        var timeoutCalled = false
        val rc = try {
            runner.run(cmdStr, timeoutMs, out) {
                timeoutCalled = true
            }
        } catch (e: Exception) {
            val msg = e.message ?: e.toString()
            return@withContext RootResult.Error(
                RootError.ROOT_UNAVAILABLE, "transport error: $msg")
        }

        val stdout = out.toString()
        if (timeoutCalled || rc == -1) {
            return@withContext RootResult.Error(
                RootError.TIMEOUT, "timeout after ${timeoutMs}ms")
        }

        // Jebakan §3.9: Usage: meski rc=0 → COMMAND_FAILED
        val firstLine = stdout.lineSequence()
            .map { it.trim() }
            .filter { it.isNotEmpty() }
            .firstOrNull() ?: ""
        if (firstLine.startsWith("Usage:")) {
            return@withContext RootResult.Error(
                RootError.COMMAND_FAILED, "unknown command returned Usage (rc=$rc): $firstLine")
        }

        if (rc != 0) {
            val msg = stdout.trim()
            return@withContext RootResult.Error(
                RootError.COMMAND_FAILED, "rc=$rc: $msg")
        }

        // Output sudah digabung (redirectErrorStream=true)
        RootResult.Success(stdout.trim(), "(combined via redirectErrorStream)", rc)
    }
}
