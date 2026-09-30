package com.hsin.data.state

import com.hsin.data.repository.HsinRepository
import com.hsin.data.root.CommandRunner
import com.hsin.data.root.RootClient
import com.hsin.data.root.RootError
import com.hsin.data.root.RootResult
import com.hsin.data.root.SudoCommandRunner
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * A10 — Alur Terapkan. Semua test memanggil KODE PRODUKSI
 * ([ApplyFlow], [DirtyTracker], [HsinRepository], [RootClient]);
 * tidak ada logika produksi yang disalin ke dalam test.
 *
 * Fake hanya mengganti transport [CommandRunner] (signature dicek silang
 * ke `CommandRunner.kt`: `run(cmd, timeoutMs, out, onTimeout): Int`).
 * Respons tiap command meniru kontrak (kontrak §2/§3.11): `knob-set`
 * `OK ...`, `apply` `OK: Applying ... (running in background...)`,
 * `knob-list` baris hasil + JSON terakhir.
 */
class ApplyFlowTest {

    private val modulePath: String =
        java.io.File(System.getProperty("java.io.tmpdir") ?: "/tmp", "hsin-test-action.sh")
            .apply { writeText("#!/system/bin/sh\n# stub untuk test\n") }
            .absolutePath

    /** Fake yang menjawab per command (dipetakan dari argumen, bukan hardcode global). */
    private class ScriptRunner(
        private val answers: Map<String, Pair<Int, String>>,
        private val timeoutCmds: Set<String> = emptySet(),
    ) : CommandRunner {
        val seen = mutableListOf<String>()
        override fun run(cmd: String, timeoutMs: Long, out: StringBuilder, onTimeout: () -> Unit): Int {
            // cmd = "sh '<path>' '<command>' '<arg>' ..." — ambil command ke-2 yang di-quote.
            // Probe modul ("[ -f '<path>' ]") hanya punya 1 token quoted -> catat "<probe>".
            val quoted = Regex("'([^']*)'").findAll(cmd).map { it.groupValues[1] }.toList()
            val sub = quoted.getOrNull(1) ?: "<probe>"
            seen.add(sub)
            if (sub in timeoutCmds) {
                onTimeout()
                return SudoCommandRunner.TIMEOUT_EXIT
            }
            val (rc, text) = answers[sub] ?: (0 to "OK\n")
            out.append(text)
            return rc
        }
    }

    private fun client(runner: CommandRunner) =
        RootClient(runner = runner, timeoutMs = 500L, modulePath = modulePath)

    private fun dirtyOf(vararg pairs: Pair<String, String>): DirtyMap {
        var m: DirtyMap = mapOf(
            "cpu_policy_0_gov" to DirtyEntry("schedutil", "schedutil"),
            "vfs_cache_pressure" to DirtyEntry("100", "100"),
        )
        for ((k, v) in pairs) m = DirtyTracker.setOverride(m, k, v)
        return m
    }

    private val knobListOk =
        "key=cpu_policy_0_gov requested=performance applied=performance category=APPLIED reason=\"dipakai sesuai permintaan\"\n" +
            "key=vfs_cache_pressure requested=250 applied=250 category=APPLIED reason=\"dipakai sesuai permintaan\"\n" +
            "{\"count\":2,\"overrides\":{\"cpu_policy_0_gov\":\"performance\",\"vfs_cache_pressure\":\"250\"}}\n"

    private val knobListPartial =
        "key=cpu_policy_0_gov requested=performance applied=performance category=APPLIED reason=\"dipakai sesuai permintaan\"\n" +
            "key=vfs_cache_pressure requested=9999 applied=- category=FAILED reason=\"nilai di luar rentang\"\n" +
            "{\"count\":2,\"overrides\":{\"cpu_policy_0_gov\":\"performance\",\"vfs_cache_pressure\":\"9999\"}}\n"

    @Test
    fun emptyDirtyDoesNoRootCalls() = runTest {
        val runner = ScriptRunner(emptyMap())
        val out = ApplyFlow.apply(client(runner), emptyMap())
        assertTrue(out is ApplyFlow.Outcome.Empty)
        assertEquals(0, runner.seen.size)
    }

    @Test
    fun successSendsOnlyDirtyAndReadsPerKnobResults() = runTest {
        val runner = ScriptRunner(
            mapOf(
                "knob-set" to (0 to "OK cpu_policy_0_gov=performance\n"),
                "apply" to (0 to "OK: Applying manual (running in background...)\n"),
                "knob-list" to (0 to knobListOk),
            )
        )
        val dirty = dirtyOf("cpu_policy_0_gov" to "performance", "vfs_cache_pressure" to "250")
        val out = ApplyFlow.apply(client(runner), dirty)
        assertTrue("harus Completed, dapat $out", out is ApplyFlow.Outcome.Completed)
        val results = (out as ApplyFlow.Outcome.Completed).results
        // Hasil PER KNOB dari modul — bukan karangan dari rc.
        assertEquals(2, results.size)
        assertEquals("APPLIED", results.first { it.key == "cpu_policy_0_gov" }.category)
        assertEquals("performance", results.first { it.key == "cpu_policy_0_gov" }.applied)
        // Hanya dirty yang dikirim: 2× knob-set + apply + knob-list, masing-masing
        // didahului probe modul `[ -f ]` via root -> 8 panggilan total.
        assertEquals(8, runner.seen.size)
        assertEquals(
            listOf("knob-set", "knob-set", "apply", "knob-list"),
            runner.seen.filter { it != "<probe>" })
        assertEquals("tiap command nyata didahului probe", 4, runner.seen.count { it == "<probe>" })
        assertTrue(
            "urutan probe-dulu: ${runner.seen}",
            runner.seen.chunked(2).all { it == listOf("<probe>", it[1]) })
    }

    @Test
    fun partialSuccessKeepsBothCategories() = runTest {
        val runner = ScriptRunner(
            mapOf(
                "knob-set" to (0 to "OK\n"),
                "apply" to (0 to "OK: Applying manual (running in background...)\n"),
                "knob-list" to (0 to knobListPartial),
            )
        )
        val dirty = dirtyOf("cpu_policy_0_gov" to "performance", "vfs_cache_pressure" to "9999")
        val out = ApplyFlow.apply(client(runner), dirty)
        assertTrue(out is ApplyFlow.Outcome.Completed)
        val results = (out as ApplyFlow.Outcome.Completed).results
        assertEquals("APPLIED", results.first { it.key == "cpu_policy_0_gov" }.category)
        assertEquals("FAILED", results.first { it.key == "vfs_cache_pressure" }.category)
    }

    @Test
    fun knobSetRejectedBecomesFailedPerKnob() = runTest {
        // knob-set pertama OK, kedua ditolak modul (rc=1). Fake per-command
        // tunggal tidak bisa bedakan key — simulasikan via runner kustom.
        val runner = object : CommandRunner {
            val seen = mutableListOf<String>()
            override fun run(cmd: String, timeoutMs: Long, out: StringBuilder, onTimeout: () -> Unit): Int {
                val quoted = Regex("'([^']*)'").findAll(cmd).map { it.groupValues[1] }.toList()
                val sub = quoted.getOrNull(1) ?: ""
                seen.add(sub)
                return when (sub) {
                    "knob-set" -> {
                        if (cmd.contains("vfs_cache_pressure")) {
                            out.append("ERROR: vfs_cache_pressure: nilai harus 0-1000\n")
                            1
                        } else {
                            out.append("OK cpu_policy_0_gov=performance\n")
                            0
                        }
                    }
                    "apply" -> {
                        out.append("OK: Applying manual (running in background...)\n")
                        0
                    }
                    "knob-list" -> {
                        out.append(knobListOk)
                        0
                    }
                    else -> {
                        out.append("OK\n")
                        0
                    }
                }
            }
        }
        val dirty = dirtyOf("cpu_policy_0_gov" to "performance", "vfs_cache_pressure" to "9999")
        val out = ApplyFlow.apply(client(runner), dirty)
        assertTrue(out is ApplyFlow.Outcome.Completed)
        val results = (out as ApplyFlow.Outcome.Completed).results
        // Key yang ditolak knob-set tetap FAILED (synthetic menimpa baris modul).
        assertEquals("FAILED", results.first { it.key == "vfs_cache_pressure" }.category)
        assertEquals("APPLIED", results.first { it.key == "cpu_policy_0_gov" }.category)
    }

    @Test
    fun applyTimeoutReturnsFailed() = runTest {
        val runner = ScriptRunner(
            mapOf("knob-set" to (0 to "OK\n")),
            timeoutCmds = setOf("apply"),
        )
        val dirty = dirtyOf("cpu_policy_0_gov" to "performance")
        val out = ApplyFlow.apply(client(runner), dirty)
        assertTrue(out is ApplyFlow.Outcome.Failed)
        assertEquals(RootError.TIMEOUT, (out as ApplyFlow.Outcome.Failed).error)
    }

    @Test
    fun brokenKnobListIsInvalidResponse() = runTest {
        val runner = ScriptRunner(
            mapOf(
                "knob-set" to (0 to "OK\n"),
                "apply" to (0 to "OK: Applying manual (running in background...)\n"),
                // Kategori asing → parser menolak (bukan diabaikan).
                "knob-list" to (0 to "key=x requested=1 applied=1 category=SUKSES reason=\"x\"\n{}\n"),
            )
        )
        val dirty = dirtyOf("cpu_policy_0_gov" to "performance")
        val out = ApplyFlow.apply(client(runner), dirty)
        assertTrue(out is ApplyFlow.Outcome.Failed)
        assertEquals(RootError.INVALID_RESPONSE, (out as ApplyFlow.Outcome.Failed).error)
    }

    // --- DirtyTracker.confirmApplied (dipanggil ViewModel sesudah apply) ---

    @Test
    fun confirmAppliedResetsOnlyApplied() {
        val dirty = dirtyOf("cpu_policy_0_gov" to "performance", "vfs_cache_pressure" to "9999")
        val results = listOf(
            HsinRepository.KnobResult("cpu_policy_0_gov", "performance", "performance", "APPLIED", "ok"),
            HsinRepository.KnobResult("vfs_cache_pressure", "9999", "-", "FAILED", "di luar rentang"),
        )
        val after = DirtyTracker.confirmApplied(dirty, results)
        assertFalse("APPLIED tidak dirty lagi", after.getValue("cpu_policy_0_gov").dirty)
        assertEquals("performance", after.getValue("cpu_policy_0_gov").base)
        assertTrue("FAILED tetap dirty (nilai lama acuan)", after.getValue("vfs_cache_pressure").dirty)
        assertEquals("100", after.getValue("vfs_cache_pressure").base)
    }

    @Test
    fun confirmAppliedSkippedKeepsOldBase() {
        val dirty = dirtyOf("cpu_policy_0_gov" to "performance")
        val results = listOf(
            HsinRepository.KnobResult(
                "cpu_policy_0_gov", "(manual)", "-", "SKIPPED", "tidak diatur (mode manual)"
            ),
        )
        val after = DirtyTracker.confirmApplied(dirty, results)
        assertTrue("SKIPPED tetap dirty", after.getValue("cpu_policy_0_gov").dirty)
        assertEquals("schedutil", after.getValue("cpu_policy_0_gov").base)
    }

    @Test
    fun confirmAppliedFallbackUpdatesBaseButKeepsDirty() {
        val dirty = dirtyOf("cpu_policy_0_gov" to "performance")
        val results = listOf(
            HsinRepository.KnobResult("cpu_policy_0_gov", "performance", "schedutil", "FALLBACK", "governor tak tersedia"),
        )
        val after = DirtyTracker.confirmApplied(dirty, results)
        assertEquals("base = nilai sistem kini", "schedutil", after.getValue("cpu_policy_0_gov").base)
        assertTrue("masih dirty (belum sesuai permintaan)", after.getValue("cpu_policy_0_gov").dirty)
    }

    @Test
    fun resultIsFromModuleNotFromRc() = runTest {
        // rc apply = 0 TAPI modul melaporkan FAILED per knob — UI wajib
        // menampilkan FAILED, bukan sukses dari rc.
        val runner = ScriptRunner(
            mapOf(
                "knob-set" to (0 to "OK\n"),
                "apply" to (0 to "OK: Applying manual (running in background...)\n"),
                "knob-list" to (0 to knobListPartial),
            )
        )
        val dirty = dirtyOf("cpu_policy_0_gov" to "performance", "vfs_cache_pressure" to "9999")
        val out = ApplyFlow.apply(client(runner), dirty) as ApplyFlow.Outcome.Completed
        val failed = out.results.first { it.key == "vfs_cache_pressure" }
        assertEquals("FAILED", failed.category)
        assertTrue("alasan dari modul", failed.reason.isNotBlank())
    }
}
