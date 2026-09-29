package com.hsin.data.state

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * A12 — Log. Semua test memanggil KODE PRODUKSI ([LogPresenter]);
 * tidak ada logika yang disalin ke dalam test.
 */
class LogPresenterTest {

    @Test
    fun jsonArrayParsedAndTailed() {
        val out = """["a","b","c"]"""
        assertEquals(listOf("b", "c"), LogPresenter.parseLogOutput(out, maxLines = 2))
    }

    @Test
    fun emptyArrayIsEmpty() {
        assertEquals(emptyList<String>(), LogPresenter.parseLogOutput("[]"))
    }

    @Test
    fun brokenJsonFallsBackWithoutCrash() {
        val out = "[\"a\",\nbaris rusak tanpa json"
        val lines = LogPresenter.parseLogOutput(out)
        assertTrue("fallback harus menghasilkan baris", lines.isNotEmpty())
    }

    @Test
    fun nonArrayFallsBackToLines() {
        val out = "baris satu\nbaris dua\n"
        assertEquals(listOf("baris satu", "baris dua"), LogPresenter.parseLogOutput(out))
    }

    @Test
    fun tailLimitRespected() {
        val out = (1..250).joinToString("\n") { "baris $it" }
        val lines = LogPresenter.parseLogOutput(out, maxLines = 200)
        assertEquals(200, lines.size)
        assertEquals("baris 51", lines.first())
        assertEquals("baris 250", lines.last())
    }

    @Test
    fun blankIsEmpty() {
        assertEquals(emptyList<String>(), LogPresenter.parseLogOutput("  \n "))
    }

    @Test
    fun levelFromTag() {
        assertEquals("SCAN", LogPresenter.levelOf("2026-09-28 12:38:36 [scan] gpu detect"))
        assertEquals("ENGINE", LogPresenter.levelOf("[ENGINE] Profile applied"))
    }

    @Test
    fun levelFromKeywordWithoutTag() {
        assertEquals("ERROR", LogPresenter.levelOf("ERROR: sesuatu gagal"))
        assertEquals("WARN", LogPresenter.levelOf("peringatan warn di sini"))
        assertEquals("INFO", LogPresenter.levelOf("baris biasa tanpa info level"))
    }

    @Test
    fun bugReportContainsGuardCapabilityAndLogs() {
        val guard = GuardState(1, 2, 2, 86400, "boot gagal 2 x berturut-turut")
        val cap = KnobCapability(
            supportedKeys = listOf("a", "b", "c"),
            allowedValues = emptyMap(),
            allowExtreme = false,
        )
        val report = LogPresenter.buildBugReport(
            guard, cap,
            listOf("boot baris 1"), listOf("apply baris 1"),
        )
        assertTrue(report.contains("active=1"))
        assertTrue(report.contains("3 knob"))
        assertTrue(report.contains("boot baris 1"))
        assertTrue(report.contains("apply baris 1"))
    }

    @Test
    fun bugReportWithoutStateIsHonest() {
        val report = LogPresenter.buildBugReport(null, null, emptyList(), emptyList())
        assertTrue(report.contains("tidak diketahui"))
        assertTrue(report.contains("belum diperiksa"))
    }
}
