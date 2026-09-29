package com.hsin.ui

import com.hsin.data.state.Metric
import com.hsin.data.state.RealtimeMetrics
import org.json.JSONObject
import com.hsin.data.state.StatusMapping
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * A11 — Monitor. Semua test memanggil KODE PRODUKSI ([MonitorPresenter]
 * + [StatusMapping]); tidak ada logika yang disalin ke dalam test.
 * Polling lifecycle (LaunchedEffect + repeatOnLifecycle) hanya ada di
 * Compose dan dibuktikan lewat CI/review — yang diuji di sini adalah
 * aturan tampilannya: tersedia = angka, hilang = "N/A" (bukan 0).
 */
class MonitorPresenterTest {

    private fun metricsFromStatus(json: String): RealtimeMetrics {
        val obj = JSONObject(json)
        return StatusMapping.toMetrics(obj)
    }

    @Test
    fun allMissingShowsNA() {
        val m = RealtimeMetrics.unknown()
        val lines = MonitorPresenter.lines(m)
        assertEquals(10, lines.size)
        for (l in lines) {
            assertEquals("N/A", l.display)
            assertEquals(false, l.readable)
        }
    }

    @Test
    fun readableMetricsShowValues() {
        val m = RealtimeMetrics.unknown().copy(
            cpuTempC = Metric(45, "°C"),
            batteryPct = Metric(80, "%"),
        )
        val byLabel = MonitorPresenter.lines(m).associateBy { it.label }
        assertEquals("45 °C", byLabel.getValue("Suhu CPU").display)
        assertEquals(true, byLabel.getValue("Suhu CPU").readable)
        assertEquals("80 %", byLabel.getValue("Baterai").display)
        assertEquals("N/A", byLabel.getValue("Suhu GPU").display)
    }

    @Test
    fun sentinelFromRealStatusBecomesNA() {
        // Kontrak §3.1: battery_pct=-1, refresh_hz=0, game_fps=0 = sentinel.
        val m = metricsFromStatus(
            """{"cpu_temp":45000,"gpu_temp":0,"cpu_freq":1488500,"gpu_freq":0,"ram_used_kb":3000000,"ram_total_kb":8000000,"battery_pct":-1,"refresh_hz":0,"cpu_load_x100":235,"zram_pct":0}"""
        )
        val byLabel = MonitorPresenter.lines(m).associateBy { it.label }
        assertEquals("45 °C", byLabel.getValue("Suhu CPU").display)
        assertEquals("N/A", byLabel.getValue("Suhu GPU").display)
        assertEquals("N/A", byLabel.getValue("Baterai").display)
        assertEquals("N/A", byLabel.getValue("Refresh").display)
        assertTrue("beban 2.35 → 2 harus terbaca", byLabel.getValue("Beban").readable)
    }

    @Test
    fun zeroIsNeverShownAsNumber() {
        val m = RealtimeMetrics.unknown()
        for (l in MonitorPresenter.lines(m)) {
            assertTrue("tidak boleh tampil 0 untuk '${l.label}': ${l.display}", l.display != "0" && !l.display.startsWith("0 "))
        }
    }
}
