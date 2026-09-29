package com.hsin.data.root

import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * A6 — RootClient. Semua test memanggil KODE PRODUKSI via [CommandRunner] fake;
 * tidak ada logika yang diduplikasi di dalam test.
 * Tidak memanggil `su` nyata (runner CI tidak punya root).
 */
class RootClientTest {

    private class FakeRunner(
        private val rc: Int,
        private val outText: String = "",
        private val throwMsg: String? = null,
    ) : CommandRunner {
        var calls = 0
        var lastCmd: String? = null
        override fun run(cmd: String, timeoutMs: Long, out: StringBuilder, onTimeout: () -> Unit): Int {
            calls++
            lastCmd = cmd
            throwMsg?.let { throw RuntimeException(it) }
            out.append(outText)
            return rc
        }
    }

    private fun client(runner: CommandRunner, timeoutMs: Long = 500L) =
        RootClient(runner = runner, timeoutMs = timeoutMs, modulePath = EXISTING_MODULE_PATH)

    @Test
    fun allowlist_rejects_foreign_command_before_runner() = runTest {
        val fake = FakeRunner(rc = 0)
        val res = client(fake).execute("delete", listOf("/data"))
        assertTrue(res is RootResult.Error)
        assertEquals(RootError.COMMAND_FAILED, (res as RootResult.Error).type)
        assertEquals("runner tak boleh dipanggil", 0, fake.calls)
    }

    @Test
    fun allowlist_accepts_knob_commands_used_by_app() = runTest {
        // knob-set WAJIB ada: A10 butuh mengatur override lewat app.
        val fake = FakeRunner(rc = 0, outText = "OK cpu_policy_0_gov=performance\n")
        val res = client(fake).execute("knob-set", listOf("cpu_policy_0_gov", "performance"))
        assertTrue("knob-set harus diterima: $res", res is RootResult.Success)
        assertEquals(1, fake.calls)
    }

    @Test
    fun allowlist_accepts_config_and_knob_read_commands() = runTest {
        for (cmd in listOf("knobs", "knob-list", "knob-reset", "config-get", "config-set", "guard-status")) {
            val fake = FakeRunner(rc = 0, outText = "{}\n")
            val res = client(fake).execute(cmd)
            assertTrue("$cmd harus di-allowlist", res is RootResult.Success)
        }
    }

    @Test
    fun unsafe_args_rejected_before_runner() = runTest {
        val dangerous = listOf(
            "; rm -rf /",
            "\$(rm -rf /)",
            "\`id\`",
            "a && b",
            "a | b",
            "perf'ormance",
            "a\nb",
        )
        for (bad in dangerous) {
            val fake = FakeRunner(rc = 0)
            val res = client(fake).execute("knob-set", listOf("cpu_policy_0_gov", bad))
            assertTrue("arg '$bad' harus ditolak, dapat: $res", res is RootResult.Error)
            assertEquals(RootError.COMMAND_FAILED, (res as RootResult.Error).type)
            assertEquals("runner tak boleh dipanggil untuk '$bad'", 0, fake.calls)
        }
    }

    @Test
    fun knob_key_must_match_pattern() = runTest {
        val badKeys = listOf("CPU_GOV", "cpu-gov", "a.b", "\$(id)", "1")
        for (k in badKeys) {
            val fake = FakeRunner(rc = 0)
            val res = client(fake).execute("knob-set", listOf(k, "performance"))
            assertTrue("key '$k' harus ditolak, dapat: $res", res is RootResult.Error)
            assertEquals(0, fake.calls)
        }
    }

    @Test
    fun non_numeric_knob_value_allowed() = runTest {
        // Governor adalah nilai non-numerik yang sah (kontrak §4).
        val fake = FakeRunner(rc = 0, outText = "OK io_block_sda_sched=bfq\n")
        val res = client(fake).execute("knob-set", listOf("io_block_sda_sched", "bfq"))
        assertTrue("nilai non-numerik harus boleh: $res", res is RootResult.Success)
    }

    @Test
    fun apply_profile_must_be_known() = runTest {
        val fake = FakeRunner(rc = 0)
        val res = client(fake).execute("apply", listOf("turbo"))
        assertTrue(res is RootResult.Error)
        assertEquals(RootError.COMMAND_FAILED, (res as RootResult.Error).type)
        assertEquals(0, fake.calls)
    }

    @Test
    fun apply_known_profile_reaches_runner() = runTest {
        val fake = FakeRunner(rc = 0, outText = "OK: Applying manual\n")
        val res = client(fake).execute("apply", listOf("manual"))
        assertTrue(res is RootResult.Success)
        assertEquals(1, fake.calls)
    }

    @Test
    fun command_string_is_quoted_and_module_path_pinned() = runTest {
        val fake = FakeRunner(rc = 0, outText = "OK\n")
        client(fake).execute("status")
        val cmd = fake.lastCmd!!
        assertTrue("path modul harus quoted: $cmd", cmd.contains("'/data/adb/modules/hsin/action.sh'"))
        assertTrue("command quoted: $cmd", cmd.contains("'status'"))
    }

    @Test
    fun module_not_found_when_path_missing() = runTest {
        val fake = FakeRunner(rc = 0)
        val c = RootClient(
            runner = fake, timeoutMs = 500L,
            modulePath = "/data/adb/modules/tidak-ada-xyz/action.sh"
        )
        val res = c.execute("status")
        assertTrue(res is RootResult.Error)
        assertEquals(RootError.MODULE_NOT_FOUND, (res as RootResult.Error).type)
        assertEquals("runner tak boleh dipanggil", 0, fake.calls)
    }

    @Test
    fun usage_despite_rc0_maps_to_command_failed() = runTest {
        // Jebakan kontrak §3.9: rc=0 tapi isinya teks Usage:.
        val usage = javaClass.getResourceAsStream("/fixtures/usage_rc0.txt")
            ?.bufferedReader()?.use { it.readText() } ?: error("fixture usage_rc0.txt hilang")
        val fake = FakeRunner(rc = 0, outText = usage)
        val res = client(fake).execute("status")
        assertTrue("Usage: harus jadi COMMAND_FAILED, dapat: $res", res is RootResult.Error)
        assertEquals(RootError.COMMAND_FAILED, (res as RootResult.Error).type)
    }

    @Test
    fun rc_nonzero_maps_to_command_failed() = runTest {
        val fake = FakeRunner(rc = 1, outText = "ERROR: key knob tidak dikenal (pola: ...)\n")
        val res = client(fake).execute("knob-set", listOf("bogus_key", "1"))
        assertTrue(res is RootResult.Error)
        assertEquals(RootError.COMMAND_FAILED, (res as RootResult.Error).type)
    }

    @Test
    fun rc_zero_without_usage_is_success() = runTest {
        val fake = FakeRunner(rc = 0, outText = "OK: info\n")
        val res = client(fake).execute("info")
        assertTrue(res is RootResult.Success)
        assertEquals("OK: info", (res as RootResult.Success).output)
        assertEquals(0, res.rc)
    }

    @Test
    fun timeout_maps_to_timeout() = runTest {
        val slow = object : CommandRunner {
            override fun run(cmd: String, timeoutMs: Long, out: StringBuilder, onTimeout: () -> Unit): Int {
                onTimeout()
                return SudoCommandRunner.TIMEOUT_EXIT
            }
        }
        val res = client(slow, timeoutMs = 50L).execute("status")
        assertTrue(res is RootResult.Error)
        assertEquals(RootError.TIMEOUT, (res as RootResult.Error).type)
    }

    @Test
    fun transport_exception_maps_to_root_unavailable() = runTest {
        val fake = FakeRunner(rc = 0, throwMsg = "Cannot run program \"su\"")
        val res = client(fake).execute("info")
        assertTrue(res is RootResult.Error)
        assertEquals(RootError.ROOT_UNAVAILABLE, (res as RootResult.Error).type)
    }

    @Test
    fun error_enum_has_exactly_six_members() {
        assertEquals(6, RootError.values().size)
        assertEquals(
            setOf(
                "ROOT_UNAVAILABLE", "MODULE_NOT_FOUND", "FEATURE_UNSUPPORTED",
                "COMMAND_FAILED", "TIMEOUT", "INVALID_RESPONSE"
            ),
            RootError.values().map { it.name }.toSet()
        )
    }

    companion object {
        /** Path yang pasti ada di environment test JVM mana pun. */
        private const val EXISTING_MODULE_PATH = "/data/adb/modules/hsin/action.sh"
    }
}
