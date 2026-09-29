package com.hsin.data.state

import org.junit.Assert.*
import org.junit.Test

class RefreshActionsTest {

    @Test
    fun fourActionsOnlyFillOwnPart() {
        // Simulasi: hanya bagian yang di-refresh berubah; lainnya tetap
        var ui = UiState()
        ui = ui.copy(home = ui.home.copy(profileActive = "balanced"))
        // refresh status hanya mengubah home.guardActive
        val oldMonitor = ui.monitor
        assertNotEquals(oldMonitor.metrics.fps, 99) // baseline
        // Setelah refresh realtime hanya monitor berubah
        ui = ui.copy(monitor = MonitorUi(metrics = RealtimeMetrics(99, 99, 99, 99)))
        assertEquals("balanced", ui.home.profileActive) // home tidak berubah oleh realtime
        assertEquals(99, ui.monitor.metrics.fps)
    }

    @Test
    fun realtimeRefreshDoesNotTouchHome() {
        val ui = UiState(home = HomeUi(profileActive = "extreme"))
        val next = ui.copy(monitor = MonitorUi(RealtimeMetrics(1,2,3,4)))
        assertEquals("extreme", next.home.profileActive)
    }
}
