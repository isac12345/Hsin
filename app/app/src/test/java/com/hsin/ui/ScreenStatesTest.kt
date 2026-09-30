package com.hsin.ui

import com.hsin.data.state.GuardState
import com.hsin.data.state.KnobCapability
import com.hsin.data.state.RealtimeMetrics
import com.hsin.data.state.UiError
import com.hsin.data.state.UiErrorKind
import com.hsin.data.state.UiState
import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * Resolver fase layar R2 (aturan APP_PLAN §0.11: tidak ada layar blank).
 *
 * Tiap layar diuji 4 fasenya: Memuat > Gagal > Kosong > Isi. LOADING/Gagal
 * hanya full-screen bila data BELUM ADA; kalau data sudah ada, fase selalu
 * CONTENT (refresh berkala tidak boleh membuat layar berkedip).
 */
class ScreenStatesTest {

    private val err = UiError(UiErrorKind.MODULE_NOT_FOUND, "", false)
    private val cap = KnobCapability(
        supportedKeys = listOf("cpu_policy_0_gov"),
        allowedValues = mapOf("cpu_policy_0_gov" to listOf("performance")),
        allowExtreme = false,
    )

    // ---- Beranda ----

    @Test
    fun homeFreshStateIsEmpty() {
        assertEquals(ScreenPhase.EMPTY, ScreenStates.home(UiState()))
    }

    @Test
    fun homeLoadingWhileFirstFetch() {
        assertEquals(
            ScreenPhase.LOADING,
            ScreenStates.home(UiState(loadingCapability = true)),
        )
    }

    @Test
    fun homeErrorWithoutData() {
        assertEquals(ScreenPhase.ERROR, ScreenStates.home(UiState(error = err)))
    }

    @Test
    fun homeContentOnceGuardRead() {
        val s = UiState(guard = GuardState(0, 0, 3, 0, ""))
        assertEquals(ScreenPhase.CONTENT, ScreenStates.home(s))
    }

    @Test
    fun homeStaysContentDuringRefresh() {
        val s = UiState(guard = GuardState(0, 0, 3, 0, ""), loadingStatus = true, error = err)
        assertEquals("refresh tidak boleh mengosongkan layar", ScreenPhase.CONTENT, ScreenStates.home(s))
    }

    // ---- Knob ----

    @Test
    fun knobFreshStateIsEmpty() {
        assertEquals(ScreenPhase.EMPTY, ScreenStates.knob(UiState(), 0))
    }

    @Test
    fun knobLoadingWhileCapabilityFetch() {
        assertEquals(
            ScreenPhase.LOADING,
            ScreenStates.knob(UiState(loadingCapability = true), 0),
        )
    }

    @Test
    fun knobErrorWithoutCapability() {
        assertEquals(ScreenPhase.ERROR, ScreenStates.knob(UiState(error = err), 0))
    }

    @Test
    fun knobEmptyScanIsEmptyNotContent() {
        assertEquals(
            "scan kosong bukan isi",
            ScreenPhase.EMPTY,
            ScreenStates.knob(UiState(capability = cap), 0),
        )
    }

    @Test
    fun knobContentWhenCategoriesExist() {
        assertEquals(ScreenPhase.CONTENT, ScreenStates.knob(UiState(capability = cap), 3))
    }

    // ---- Monitor ----

    @Test
    fun monitorFreshStateIsEmpty() {
        assertEquals(ScreenPhase.EMPTY, ScreenStates.monitor(UiState()))
    }

    @Test
    fun monitorLoadingOnFirstTick() {
        assertEquals(
            ScreenPhase.LOADING,
            ScreenStates.monitor(UiState(loadingRealtime = true)),
        )
    }

    @Test
    fun monitorErrorWithoutMetrics() {
        assertEquals(ScreenPhase.ERROR, ScreenStates.monitor(UiState(error = err)))
    }

    @Test
    fun monitorContentOnceMetricsRead() {
        val m = RealtimeMetrics.unknown().copy(cpuTempC = RealtimeMetrics.unknown().cpuTempC.copy(value = 45))
        assertEquals(ScreenPhase.CONTENT, ScreenStates.monitor(UiState(metrics = m)))
    }

    // ---- Log ----

    @Test
    fun logFreshStateIsEmpty() {
        assertEquals(ScreenPhase.EMPTY, ScreenStates.log(UiState()))
    }

    @Test
    fun logLoadingWhileFetching() {
        assertEquals(
            ScreenPhase.LOADING,
            ScreenStates.log(UiState(loadingLogs = true)),
        )
    }

    @Test
    fun logErrorWithoutLines() {
        assertEquals(ScreenPhase.ERROR, ScreenStates.log(UiState(error = err)))
    }

    @Test
    fun logContentOnceLinesExist() {
        assertEquals(
            ScreenPhase.CONTENT,
            ScreenStates.log(UiState(logBoot = listOf("[INFO] boot ok"))),
        )
    }
}
