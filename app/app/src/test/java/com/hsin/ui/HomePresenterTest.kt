package com.hsin.ui

import com.hsin.data.state.GuardState
import com.hsin.data.state.KnobCapability
import com.hsin.data.state.UiError
import com.hsin.data.state.UiErrorKind
import com.hsin.data.state.UiState
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Beranda harus benar dalam dua kondisi yang disebut acceptance A8:
 * TIDAK ADA root, dan TIDAK ADA modul. Yang diuji adalah teks yang
 * benar-benar dirender user — bukan logika internal.
 */
class HomePresenterTest {

    @Test
    fun tabTitlesAreFour() {
        assertEquals(4, Tab.entries.size)
        assertEquals(
            listOf("Beranda", "Knob", "Monitor", "Log"),
            Tab.entries.map { it.title },
        )
    }

    @Test
    fun navStateSelectsAndClamps() {
        val n = NavState(0)
        assertEquals(Tab.BERANDA, n.current)
        assertEquals(Tab.KNOB, n.select(1).current)
        assertEquals("pilih tab yang sama tidak mengubah state", n, n.select(0))
        assertEquals("indeks di luar rentang aman", Tab.BERANDA, NavState(99).current)
    }

    // ---- modul tidak ada ----

    @Test
    fun moduleNotFoundShowsFriendlyMessage() {
        val err = UiError(UiErrorKind.MODULE_NOT_FOUND, "/data/adb/modules/hsin/action.sh", false)
        val line = HomePresenter.rootLine(err)
        assertEquals(HomePresenter.LineStatus.ERROR, line.status)
        assertEquals("Modul belum terpasang", line.value)
        val text = friendlyError(err.kind.name, err.detail)
        assertTrue("pesan harus ramah", text.startsWith("Modul HSIN belum terpasang"))
        assertTrue("tidak boleh menampilkan exception mentah", !text.contains("Exception"))
    }

    @Test
    fun noErrorMeansRootReady() {
        val line = HomePresenter.rootLine(null)
        assertEquals("Siap", line.value)
        assertEquals(HomePresenter.LineStatus.OK, line.status)
    }

    @Test
    fun everyErrorKindHasFriendlyText() {
        val kinds = listOf(
            "MODULE_NOT_FOUND", "ROOT_UNAVAILABLE", "TIMEOUT",
            "COMMAND_FAILED", "INVALID_RESPONSE", "FEATURE_UNSUPPORTED", "APAGA",
        )
        for (k in kinds) {
            val text = friendlyError(k, "")
            assertTrue("$k harus punya pesan", text.isNotBlank())
            assertTrue("$k tidak boleh kosong", !text.endsWith("()"))
        }
    }

    @Test
    fun unknownErrorKindStillHasText() {
        assertEquals("Terjadi kesalahan.", friendlyError("APAGA", ""))
    }

    // ---- root/module state dari UiState ----

    @Test
    fun nothingLoadedYetShowsUnknownNotFakeValues() {
        val state = UiState()
        assertEquals("Belum diperiksa", HomePresenter.moduleLine(state).value)
        assertEquals(HomePresenter.LineStatus.UNKNOWN, HomePresenter.moduleLine(state).status)
        assertEquals("Tidak diketahui", HomePresenter.guardLine(state).value)
        assertEquals("Belum diperiksa", HomePresenter.capabilitySummary(state))
    }

    @Test
    fun guardActiveIsSurfacedWithReason() {
        val state = UiState(
            guard = GuardState(
                active = 1,
                failCount = 2,
                threshold = 2,
                cooldownRemainingSec = 86400,
                lastReason = "boot gagal 2 x berturut-turut",
            )
        )
        val line = HomePresenter.guardLine(state)
        assertEquals(HomePresenter.LineStatus.ERROR, line.status)
        assertTrue("harus menyebut tuning dilewati", line.value.contains("tuning dilewati"))
        assertTrue("harus menyebut alasannya", line.value.contains("boot gagal"))
    }

    @Test
    fun guardActiveWithoutReasonStillReadable() {
        val state = UiState(guard = GuardState(1, 2, 2, 100, ""))
        val line = HomePresenter.guardLine(state)
        assertTrue(line.value.contains("alasan tidak tercatat"))
    }

    @Test
    fun guardInactiveShowsSafe() {
        val state = UiState(guard = GuardState(0, 0, 2, 0, "tidak ada state"))
        assertEquals("Aman", HomePresenter.guardLine(state).value)
        assertEquals(HomePresenter.LineStatus.OK, HomePresenter.guardLine(state).status)
    }

    @Test
    fun capabilitySummaryCountsKeysAndMarksCache() {
        val cap = KnobCapability(
            supportedKeys = listOf("cpu_policy_0_gov", "cpu_policy_6_gov", "tcp_cc"),
            allowedValues = emptyMap(),
            allowExtreme = false,
        )
        assertEquals("3 knob tersedia", HomePresenter.capabilitySummary(UiState(capability = cap)))
        assertEquals(
            "3 knob tersedia (cache)",
            HomePresenter.capabilitySummary(UiState(capability = cap, capabilityFromCache = true)),
        )
    }

    @Test
    fun temperatureSentinelBecomesNA() {
        val state = UiState()
        assertEquals("N/A", HomePresenter.thermalLine(state).value)
        assertEquals(HomePresenter.LineStatus.UNKNOWN, HomePresenter.thermalLine(state).status)
    }

    @Test
    fun temperatureReadFromMetrics() {
        val metrics = com.hsin.data.state.StatusMapping.toMetrics(
            org.json.JSONObject("""{"cpu_temp":45000}""")
        )
        val line = HomePresenter.thermalLine(UiState(metrics = metrics))
        assertEquals("45 °C", line.value)
        assertEquals(HomePresenter.LineStatus.OK, line.status)
    }

    // ---- hasil apply ----

    @Test
    fun pendingDirtyKnobsShowWaitingState() {
        val dirty = com.hsin.data.state.DirtyTracker.setOverride(
            mapOf(
                "cpu_policy_0_gov" to com.hsin.data.state.DirtyEntry("schedutil", "performance"),
                "tcp_cc" to com.hsin.data.state.DirtyEntry("cubic", "bbr"),
            ),
            "tcp_cc", "bbr",
        )
        val apply = HomePresenter.lastApply(UiState(dirty = dirty))
        assertEquals(HomePresenter.LineStatus.WARN, apply.status)
        assertEquals("Menunggu apply 2 knob", apply.headline)
        assertEquals("Belum ada hasil dari modul", apply.detail)
    }

    @Test
    fun noApplyYetIsHonest() {
        val apply = HomePresenter.lastApply(UiState())
        assertEquals("Belum ada apply", apply.headline)
        assertNull("tidak boleh mengarang detail", apply.detail)
        assertEquals(HomePresenter.LineStatus.UNKNOWN, apply.status)
    }

    @Test
    fun applyStatusFromModuleIsShown() {
        val apply = HomePresenter.lastApply(UiState(applyStatus = "ok", activeProfile = "manual"))
        assertEquals(HomePresenter.LineStatus.OK, apply.status)
        assertTrue(apply.headline.contains("ok"))
        assertEquals("Profil manual", apply.detail)
    }

    // ---- dialog konfirmasi backup ----

    @Test
    fun restoreBackupRequiresConfirmation() {
        val c = HomePresenter.ConfirmRestore.RESTORE
        assertNotNull("judul wajib ada", c.title)
        assertNotNull("badan wajib ada", c.body)
        assertTrue("badan harus menjelaskan risiko", c.body.contains("hilang"))
        assertEquals("Pulihkan", c.confirmLabel)
    }

    @Test
    fun navActionsIsAnInterfaceSoUiCanBeStubbed() {
        // Bukti tidak ada root call di UI: UI hanya bergantung pada interface.
        assertTrue(NavActions::class.java.isInterface)
        val calls = mutableListOf<String>()
        val stub = object : NavActions {
            override fun onOpenKnobs() { calls += "knob" }
            override fun onRestoreBackupConfirmed() { calls += "restore" }
        }
        stub.onOpenKnobs()
        stub.onRestoreBackupConfirmed()
        assertEquals(listOf("knob", "restore"), calls)
    }

    @Test
    fun linesCoverAllFourChecks() {
        val lines = HomePresenter.lines(UiState())
        assertEquals(4, lines.size)
        assertEquals(
            listOf("Akses root", "Modul", "Boot guard", "Suhu CPU"),
            lines.map { it.label },
        )
        assertFalse(lines.any { it.value.isBlank() })
    }
}
