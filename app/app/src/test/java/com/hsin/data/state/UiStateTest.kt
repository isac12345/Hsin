package com.hsin.data.state

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Sifat [UiState]: immutable, dan bagian-bagiannya terisolasi satu sama
 * lain (salah satu aksi refresh tidak boleh mengubah bagian lain).
 *
 * Uji ini memeriksa [UiState.copy()] dengan assert yang akan GAGAL kalau
 * [field] ditimpa atau hilang — bukan sekadar "objek tidak exception".
 */
class UiStateTest {

    private val guard = GuardState(
        active = 1,
        failCount = 2,
        threshold = 2,
        cooldownRemainingSec = 86400,
        lastReason = "boot gagal 2 x berturut-turut",
    )
    private val cap = KnobCapability(
        supportedKeys = listOf("cpu_policy_0_gov", "tcp_cc"),
        allowedValues = mapOf("cpu_policy_0_gov" to listOf("performance", "schedutil")),
        allowExtreme = false,
    )

    @Test
    fun defaultStateIsAllUnknown() {
        val s = UiState()
        assertNull("belum ada modul", s.module)
        assertNull("belum ada capability", s.capability)
        assertNull("belum ada guard", s.guard)
        assertNull("profil belum diketahui", s.activeProfile)
        assertEquals(0, s.dirtyCount)
        assertTrue("metrik belum terbaca", !s.metrics.cpuTempC.readable)
        assertNull("tidak ada error", s.error)
    }

    @Test
    fun statusRefreshOnlyChangesGuard() {
        val before = UiState(
            capability = cap,
            activeProfile = "manual",
            metrics = RealtimeMetrics.unknown(),
        )
        val after = before.copy(guard = guard, loadingStatus = false)
        assertEquals("guard terisi", guard, after.guard)
        assertEquals("capability tak berubah", cap, after.capability)
        assertEquals("profil tak berubah", "manual", after.activeProfile)
        assertEquals("loading status turun", false, after.loadingStatus)
    }

    @Test
    fun capabilityRefreshDoesNotTouchDirtyState() {
        val dirty = DirtyTracker.setOverride(
            mapOf("cpu_policy_0_gov" to DirtyEntry("schedutil", "performance")),
            "cpu_policy_0_gov", "performance",
        )
        val before = UiState(guard = guard, dirty = dirty)
        val after = before.copy(capability = cap, capabilityFromCache = true)
        assertEquals("override user harus utuh", dirty, after.dirty)
        assertEquals(1, after.dirtyCount)
        assertEquals(listOf("cpu_policy_0_gov"), after.dirtyKeys)
        assertTrue("ditandai dari cache", after.capabilityFromCache)
    }

    @Test
    fun realtimeRefreshOnlyChangesMetrics() {
        val before = UiState(guard = guard, activeProfile = "performance", capability = cap)
        val m = StatusMapping.toMetrics(org.json.JSONObject("""{"cpu_temp":45000}"""))
        val after = before.copy(metrics = m)
        assertEquals(45, after.metrics.cpuTempC.value)
        assertEquals(guard, after.guard)
        assertEquals("performance", after.activeProfile)
        assertEquals(cap, after.capability)
    }

    @Test
    fun errorStateCoexistsWithData() {
        val after = UiState(capability = cap).copy(
            error = UiError(UiErrorKind.TIMEOUT, "timeout after 15000ms", retryable = true),
        )
        assertNotNull("error tampil", after.error)
        assertTrue("timeout bisa dicoba lagi", after.error!!.retryable)
        assertEquals("data tidak hilang", cap, after.capability)
    }

    @Test
    fun moduleNotFoundIsNotRetryable() {
        val e = UiError(UiErrorKind.MODULE_NOT_FOUND, "modul belum terpasang", retryable = false)
        assertFalse(e.retryable)
    }

    @Test
    fun logLinesTakeLastNonBlank() {
        val out = "a\n\nb\n\n\nc\n"
        assertEquals(listOf("a", "b", "c"), logLinesOf(out, 10))
        assertEquals(listOf("b", "c"), logLinesOf(out, 2))
    }
}
