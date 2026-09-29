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
 * Validasi argumen: allowlist karakter `^[A-Za-z0-9_.:@%+=,-]+$` per argumen;
 * key knob `^[a-z0-9_]{1,64}$`; nilai knob cukup aman karakter + panjang maks
 * (nilai bisa non-numerik, mis. governor `performance` — validasi semantic
 * dilakukan modul yang balas rc=1 `ERROR: <key>: nilai harus ...`, kontrak §2);
 * profil hanya `manual|battery|balanced|performance|extreme`.
 *
 * CATATAN allowlist: string `Usage:` di `action.sh:1406` TIDAK lengkap —
 * ia tidak menyebut `knobs`, `knob-set`, `knob-list`, `knob-reset`,
 * `config-get`, `config-set`, `warn`, padahal ketujuhnya subcommand nyata
 * di dispatch. Allowlist di bawah = hasil pembandingan terhadap dispatch
 * `action.sh`, bukan hasil menyalin string Usage.
 */
sealed class RootResult {
    /** [output] adalah stdout+stderr GABUNGAN (runner memakai redirectErrorStream). */
    data class Success(val output: String, val rc: Int) : RootResult()
    data class Error(val type: RootError, val message: String) : RootResult()
}

enum class RootError { ROOT_UNAVAILABLE, MODULE_NOT_FOUND, FEATURE_UNSUPPORTED, COMMAND_FAILED, TIMEOUT, INVALID_RESPONSE }

class RootClient(
    private val runner: CommandRunner = SudoCommandRunner,
    private val timeoutMs: Long = 15000L,
    /** Path modul; di-set default. Dapat di-override test untuk menguji MODULE_NOT_FOUND. */
    private val modulePath: String = "/data/adb/modules/hsin/action.sh"
) {

    private val ALLOWLIST = setOf(
        "info","device","capabilities","status","guard-status","warn","logs","apply",
        "backup","rollback","conflicts","export","renderer-apply","renderer-state",
        "downscale-enable","downscale-disable","downscale-status",
        "refresh-lock-enable","refresh-lock-disable","refresh-lock-status",
        "export-debug","list-apps","game-list","game-add","game-remove",
        "knobs","knob-set","knob-list","knob-reset","config-get","config-set"
    )

    private val PROFILES = setOf("manual","battery","balanced","performance","extreme")
    private val SAFE_ARG = Regex("^[A-Za-z0-9_.:@%+=,-]+$")
    private val KEY_PAT = Regex("^[a-z0-9_]{1,64}$")

    /** Panjang maksimum satu argumen (nilai knob terpanjang di kontrak §4 < 64). */
    private const val MAX_ARG_LEN = 64

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
            if (a.length > MAX_ARG_LEN) {
                return@withContext RootResult.Error(
                    RootError.COMMAND_FAILED, "arg too long: ${a.length} chars")
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

        // knob-set <key> <value>: key wajib pola key, value cukup karakter aman
        // (bisa non-numerik, mis. governor "performance"). Nilai semantic
        // ditolak modul sendiri dengan rc=1 (kontrak §2 baris knob-set).
        if (cmd == "knob-set" && args.isNotEmpty()) {
            if (!KEY_PAT.matches(args[0])) {
                return@withContext RootResult.Error(
                    RootError.COMMAND_FAILED, "invalid knob key: ${args[0]}")
            }
        }
        if (cmd == "knob-reset" && args.isNotEmpty()) {
            if (!KEY_PAT.matches(args[0])) {
                return@withContext RootResult.Error(
                    RootError.COMMAND_FAILED, "invalid knob key: ${args[0]}")
            }
        }
        // config-set <key> <value>: key likewise pola sederhana
        if (cmd == "config-set" && args.isNotEmpty()) {
            if (!KEY_PAT.matches(args[0])) {
                return@withContext RootResult.Error(
                    RootError.COMMAND_FAILED, "invalid config key: ${args[0]}")
            }
        }

        // Pemeriksaan path modul sebelum menjalankan → MODULE_NOT_FOUND
        val moduleFile = java.io.File(modulePath)
        if (!moduleFile.exists()) {
            return@withContext RootResult.Error(
                RootError.MODULE_NOT_FOUND, "module path missing: $modulePath")
        }

        val cmdStr = buildString {
            append("sh ")
            append(modulePath.quoteShell())
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
        if (timeoutCalled || rc == SudoCommandRunner.TIMEOUT_EXIT) {
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
        RootResult.Success(stdout.trim(), rc)
    }
}
