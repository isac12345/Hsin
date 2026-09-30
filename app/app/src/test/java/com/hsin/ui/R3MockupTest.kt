package com.hsin.ui

import com.hsin.data.repository.HsinRepository
import com.hsin.data.state.GuardState
import com.hsin.data.state.KnobCapability
import com.hsin.data.state.KnobsMapping
import com.hsin.data.state.RealtimeMetrics
import com.hsin.data.state.StatusMapping
import com.hsin.data.state.UiState
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * R3: Beranda + Monitor sesuai mockup (bagian 2 revisi, mapping interim).
 *
 * Setiap nilai diuji ketertelusurannya ke kontrak: grid memakai kata mockup
 * (Tersedia/Terpasang/Nonaktif), jam dari `apply.log`, hitungan dari JSON
 * `knobs`, frekuensi/bar dari JSON `status`. Tanpa badge termal, tanpa zona
 * termal, tanpa baris per policy, tanpa versi modul (pending bagian 3).
 */
class R3MockupTest {

    private val cap = KnobCapability(
        supportedKeys = listOf("cpu_policy_0_gov"),
        allowedValues = mapOf("cpu_policy_0_gov" to listOf("schedutil")),
        allowExtreme = false,
        cpuPolicies = 2,
        gpuNodes = 1,
        zramSupported = true,
        ioBlocks = 2,
    )

    // ---- grid status ----

    @Test
    fun gridFreshStateUsesMockupWords() {
        val cells = HomePresenter.grid(UiState())
        assertEquals("Root", cells[0].label)
        assertEquals("Tersedia", cells[0].value)
        assertEquals("Terpasang/Belum diperiksa", "Belum diperiksa", cells[1].value)
        assertEquals("Nonaktif", cells[2].value)
        assertEquals("tanpa data suhu = N/A", "N/A", cells[3].value)
        assertFalse("termal tanpa badge", cells[3].showBadge)
    }

    @Test
    fun gridWithDataAndGuardActive() {
        val s = UiState(
            capability = cap,
            guard = GuardState(1, 2, 3, 100, "boot gagal 2x"),
            metrics = RealtimeMetrics.unknown().copy(
                cpuTempC = RealtimeMetrics.unknown().cpuTempC.copy(value = 45),
            ),
        )
        val cells = HomePresenter.grid(s)
        assertEquals("Terpasang", cells[1].value)
        assertTrue("alasan guard tampil", cells[2].value.contains("boot gagal 2x"))
        assertEquals("45 °C", cells[3].value)
    }

    // ---- terakhir diterapkan ----

    @Test
    fun applyTimeFromLastStampedLine() {
        val lines = listOf(
            "2026-09-28 12:38:36 [scan] mulai",
            "baris rusak tanpa stempel",
            "2026-09-28 12:38:37 [ENGINE] Profile applied",
        )
        assertEquals("12:38", HomePresenter.applyTimeOf(lines))
    }

    @Test
    fun applyTimeNullWithoutStamp() {
        assertNull(HomePresenter.applyTimeOf(listOf("rusak", "")))
        assertNull(HomePresenter.applyTimeOf(emptyList()))
    }

    @Test
    fun lastAppliedMaxThreeRowsSorted() {
        fun r(k: String) = HsinRepository.KnobResult(k, "1", "1", "APPLIED", "ok")
        val s = UiState(
            applyResults = mapOf("d" to r("d"), "b" to r("b"), "a" to r("a"), "c" to r("c")),
            logApply = listOf("2026-09-28 09:15:00 [ENGINE] ok"),
        )
        val last = HomePresenter.lastApplied(s)
        assertEquals("Terakhir diterapkan · 09:15", last.title)
        assertEquals(3, last.rows.size)
        assertEquals(listOf("a", "b", "c"), last.rows.map { it.text.split(" ").first() })
        assertTrue(last.rows[0].text.contains("diminta 1 → diterapkan 1 (ok)"))
    }

    @Test
    fun lastAppliedEmptyWithoutResults() {
        val last = HomePresenter.lastApplied(UiState())
        assertTrue("belum ada apply = baris kosong", last.rows.isEmpty())
        assertTrue(last.title.contains("waktu tak tercatat"))
    }

    // ---- kemampuan ----

    @Test
    fun capabilityRowsNullIsHonest() {
        val rows = HomePresenter.capabilityRows(UiState())
        assertTrue(rows.all { it.value == "belum diperiksa" })
    }

    @Test
    fun capabilityRowsFromSnapshot() {
        val rows = HomePresenter.capabilityRows(UiState(capability = cap))
        assertEquals("2", rows[0].value)
        assertEquals("Ada", rows[1].value)
        assertEquals("Ada", rows[2].value)
        assertEquals("2", rows[3].value)
    }

    @Test
    fun knobsParseCountsRawSections() {
        val knobs = JSONObject(
            """{"v":1,"cpu":{"policies":[
              {"id":"0","govs":["schedutil"],"cur_gov":"schedutil"},
              {"id":"6","govs":["schedutil"],"cur_gov":"schedutil"}]},
             "gpu":{"nodes":[
              {"name":"23100000.gpu","govs":["simple_ondemand"],"cur_gov":"simple_ondemand"}]},
             "memory":{"zram":{"supported":true,"algos":["zstd"],"cur":"zstd"}},
             "io":{"blocks":[
              {"name":"sda","schedulers":["cfq"],"cur":"cfq"},
              {"name":"sdb","schedulers":[],"cur":""}]},
             "network":{"tcp_cc":[]}}""",
        )
        val parsed = KnobsMapping.parse(knobs, allowExtreme = false)
        assertEquals(2, parsed.capability.cpuPolicies)
        assertEquals(1, parsed.capability.gpuNodes)
        assertTrue(parsed.capability.zramSupported)
        assertEquals(2, parsed.capability.ioBlocks)
    }

    // ---- monitor ----

    private fun statusJson() = JSONObject(
        """{"cpu_freq":1488500,"cpu_freq_big":1820000,"cpu_freq_little":0,
           "gpu_freq":400000,"cpu_max_khz":1820000,"gpu_max_khz":850000,
           "ram_used_kb":3000000,"ram_total_kb":8000000,
           "cpu_temp":45000,"gpu_temp":0}""",
    )

    @Test
    fun statusParsesBigLittleMax() {
        val m = StatusMapping.toMetrics(statusJson())
        assertEquals(1488, m.cpuFreqMhz.value)
        assertEquals(1820, m.cpuFreqBigMhz.value)
        assertNull("little 0 = sentinel", m.cpuFreqLittleMhz.value)
        assertEquals(1820, m.cpuFreqMaxMhz.value)
        assertEquals(850, m.gpuFreqMaxMhz.value)
    }

    @Test
    fun freqLinesHideLittleWhenZero() {
        val rows = MonitorPresenter.freqLines(StatusMapping.toMetrics(statusJson()))
        assertEquals(listOf("CPU rata-rata", "Klaster besar", "GPU"), rows.map { it.label })
        assertEquals("1488 MHz", rows[0].display)
        assertEquals(1488f / 1820f, rows[0].fraction!!, 0.001f)
        assertEquals(400f / 850f, rows[2].fraction!!, 0.001f)
    }

    @Test
    fun memLinesRamGbAndGpuLoadNa() {
        val rows = MonitorPresenter.memLines(StatusMapping.toMetrics(statusJson()))
        assertEquals("45 °C", rows[0].display)
        assertEquals("N/A", rows[1].display)
        assertEquals("3.0 / 8.0 GB", rows[2].display)
        assertEquals(0.375f, rows[2].fraction!!, 0.001f)
        assertEquals("Beban GPU", rows[3].label)
        assertEquals("N/A", rows[3].display)
        assertFalse(rows[3].readable)
    }

    @Test
    fun fractionNullWithoutMax() {
        val m = RealtimeMetrics.unknown()
        assertNull(MonitorPresenter.fractionOf(m.cpuFreqMhz, m.cpuFreqMaxMhz))
    }
}
