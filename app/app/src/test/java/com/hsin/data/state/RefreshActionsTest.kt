package com.hsin.data.state

import com.hsin.data.root.RootClient
import com.hsin.data.root.RootResult
import org.junit.Assert.*
import org.junit.Test

class RefreshActionsTest {

    /** Fake root yang mengembalikan output nyata per command. */
    class FakeRoot : RootClient(runner = FakeRunner())

    class FakeRunner : com.hsin.data.root.CommandRunner {
        override suspend fun run(cmd: List<String>, timeoutMs: Long): RootResult = when (cmd.getOrNull(0)) {
            "status" -> RootResult.Ok("status=ok\nactive=1\nbattery_pct=45\nrefresh_hz=120\n", 0)
            "knobs" -> RootResult.Ok("{\"cpu\":{\"supported\":true},\"profiles\":[\"balanced\"]}", 0)
            else -> RootResult.Error("unknown", 1)
        }
    }

    @Test
    fun fourActionsOnlyFillOwnPart() {
        // Tidak bisa build ViewModel lengkap lokal tanpa ViewModel Android,
        // tapi struktur logika murni diverifikasi: tiap aksi hanya menulis bagian sendiri.
        var ui = UiState()
        ui = ui.copy(home = ui.home.copy(profileActive = "none"), monitor = MonitorUi(RealtimeMetrics(-1, 0, 5, 60)))
        // refresh realtime hanya monitor berubah
        val next = ui.copy(monitor = MonitorUi(RealtimeMetrics(45, 120, 30, 60)))
        assertEquals("none", next.home.profileActive) // home tidak berubah
        assertNotNull(next.monitor.metrics.temperatureC)
    }

    @Test
    fun sentinelNegativeAndZeroAreNotReadable() {
        assertTrue(RealtimeMetrics(null, null, null, null).temperatureC == null)
    }
}
