package com.hsin.data.state

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Pemetaan `status` ke metrik, termasuk aturan sentinel A11: nilai -1 dan 0
 * di keluaran `status` berarti "tidak terbaca", bukan angka yang sah.
 * Diuji terhadap fixture sandbox nyata (`status.txt`).
 */
class StatusMappingTest {

    /** Fixture sudah memuat ekstensi `.txt`, jadi tidak ditambah lagi. */
    private fun fixture(name: String): String {
        val s = javaClass.getResourceAsStream("/fixtures/$name")
            ?: error("fixture $name tidak ada")
        return s.bufferedReader().use { it.readText() }
    }

    @Test
    fun parsesRealSandboxStatusFixture() {
        val json = JSONObject(fixture("status.txt").trim().lines().last())
        val m = StatusMapping.toMetrics(json)
        assertNotNull(m)
        // Fixture sandbox: sensor tak terbaca -> harus jadi null, bukan 0
        assertNull("battery_pct=-1 = sentinel", m.batteryPct.value)
        assertNull("refresh_hz=0 = sentinel", m.refreshHz.value)
        assertFalse("battery tidak terbaca", m.batteryPct.readable)
    }

    @Test
    fun nullJsonProducesAllUnknownMetrics() {
        val m = StatusMapping.toMetrics(null)
        assertTrue(
            "semua metrik harus tidak terbaca",
            !m.cpuTempC.readable && !m.gpuTempC.readable && !m.cpuFreqMhz.readable &&
                !m.loadPercent.readable && !m.batteryPct.readable
        )
    }

    @Test
    fun temperatureIsMilliDegreesConvertedToCelsius() {
        val json = JSONObject("""{"cpu_temp":45000,"gpu_temp":42000}""")
        val m = StatusMapping.toMetrics(json)
        assertEquals(45, m.cpuTempC.value)
        assertEquals(42, m.gpuTempC.value)
        assertEquals("°C", m.cpuTempC.unit)
    }

    @Test
    fun loadX100BecomesPercent() {
        val json = JSONObject("""{"cpu_load_x100":235}""")
        val m = StatusMapping.toMetrics(json)
        assertEquals(2, m.loadPercent.value)
        assertEquals("%", m.loadPercent.unit)
    }

    @Test
    fun zeroTemperatureIsTreatedAsUnknown() {
        val json = JSONObject("""{"cpu_temp":0,"gpu_temp":0}""")
        val m = StatusMapping.toMetrics(json)
        assertNull("0 °C = sensor tak terbaca, bukan nol derajat", m.cpuTempC.value)
    }

    @Test
    fun frequencyFromKhzBecomesMhz() {
        val json = JSONObject("""{"cpu_freq":1488500,"gpu_freq":400000}""")
        val m = StatusMapping.toMetrics(json)
        assertEquals(1488, m.cpuFreqMhz.value)
        assertEquals(400, m.gpuFreqMhz.value)
    }

    @Test
    fun batteryOutOfRangeIsUnknown() {
        assertNull(StatusMapping.readBattery(JSONObject("""{"battery_pct":-1}"""))?.value)
        assertNull(StatusMapping.readBattery(JSONObject("""{"battery_pct":150}"""))?.value)
        assertEquals(45, StatusMapping.readBattery(JSONObject("""{"battery_pct":45}"""))?.value)
    }

    @Test
    fun missingKeyIsUnknownNotZero() {
        val m = StatusMapping.toMetrics(JSONObject("""{"cpu_temp":45000}"""))
        assertNull(m.gpuTempC.value)
        assertEquals(45, m.cpuTempC.value)
    }

    @Test
    fun profileAndApplyStatusReadFromStatusJson() {
        val json = JSONObject("""{"profile":"performance","apply_status":"ok"}""")
        assertEquals("performance", StatusMapping.readProfile(json))
        assertEquals("ok", StatusMapping.readApplyStatus(json))
    }

    @Test
    fun allowExtremeReadAsBooleanFromConfigJson() {
        // Kontrak §5 butir 4: config-get mengembalikan string, bukan boolean
        val json = JSONObject(fixture("config_get.txt").trim())
        assertFalse(StatusMapping.readAllowExtreme(json))
        assertTrue(StatusMapping.readAllowExtreme(JSONObject("""{"allow_extreme":"true"}""")))
        assertFalse(StatusMapping.readAllowExtreme(null))
    }

    @Test
    fun activeProfileParsedFromInfoTextOutput() {
        // `info` bukan JSON: "HSIN Universal Engine\nProfile aktif: none\n..."
        val info = "HSIN Universal Engine\nProfile aktif: performance\n\nCPU: 1087 MHz, 0°C\n"
        assertEquals("performance", StatusMapping.readActiveProfileFromInfo(info))
        assertNull(StatusMapping.readActiveProfileFromInfo("HSIN Universal Engine\n"))
    }
}
