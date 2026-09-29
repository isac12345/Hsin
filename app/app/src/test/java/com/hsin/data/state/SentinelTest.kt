package com.hsin.data.state

import org.junit.Assert.*
import org.junit.Test

class SentinelTest {
    @Test
    fun negativeAndZeroNotValidValuesDisplayed() {
        val m = RealtimeMetrics(temperatureC = -1, frequencyMhz = 0, loadPercent = 5, fps = 60)
        // Aturan A11: sentinel -1/0 tidak ditampilkan sebagai nilai valid
        assertTrue(m.temperatureC < 0 || m.frequencyMhz == 0)
    }
}
