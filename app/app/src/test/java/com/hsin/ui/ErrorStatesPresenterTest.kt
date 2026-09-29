package com.hsin.ui

import com.hsin.data.repository.HsinRepository
import com.hsin.data.state.GuardState
import com.hsin.data.state.UiError
import com.hsin.data.state.UiErrorKind
import com.hsin.data.state.UiState
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * A13 — kasus tepi. Semua test memanggil KODE PRODUKSI
 * ([ErrorStatesPresenter]); tidak ada logika yang disalin ke dalam test.
 */
class ErrorStatesPresenterTest {

    private fun err(kind: UiErrorKind) = UiError(kind, "detail $kind", retryable = true)

    @Test
    fun noRootHasDisplay() {
        val b = ErrorStatesPresenter.transportBanner(UiState(error = err(UiErrorKind.ROOT_UNAVAILABLE)))
        assertNotNull(b)
        assertEquals(ErrorStatesPresenter.Tone.ERROR, b!!.tone)
    }

    @Test
    fun moduleMissingHasDisplay() {
        val b = ErrorStatesPresenter.transportBanner(UiState(error = err(UiErrorKind.MODULE_NOT_FOUND)))
        assertNotNull(b)
        assertTrue(b!!.title.contains("Modul"))
    }

    @Test
    fun timeoutHasDisplay() {
        val b = ErrorStatesPresenter.transportBanner(UiState(error = err(UiErrorKind.TIMEOUT)))
        assertNotNull(b)
        assertEquals(ErrorStatesPresenter.Tone.WARN, b!!.tone)
    }

    @Test
    fun invalidResponseHasDisplay() {
        val b = ErrorStatesPresenter.transportBanner(UiState(error = err(UiErrorKind.INVALID_RESPONSE)))
        assertNotNull(b)
    }

    @Test
    fun noErrorNoBanner() {
        assertNull(ErrorStatesPresenter.transportBanner(UiState()))
    }

    @Test
    fun versionMismatchHasDisplay() {
        val b = ErrorStatesPresenter.versionBanner(UiState(versionMismatch = true))
        assertNotNull(b)
        assertTrue(b!!.title.contains("Versi"))
        assertNull(ErrorStatesPresenter.versionBanner(UiState()))
    }

    @Test
    fun guardActiveShowsTuningDilewati() {
        val s = UiState(
            guard = GuardState(1, 2, 2, 86400, "boot gagal 2 x berturut-turut")
        )
        val b = ErrorStatesPresenter.guardBanner(s)
        assertNotNull(b)
        assertTrue("banner harus sebut tuning dilewati: ${b!!.title}", b.title.contains("dilewati"))
        assertTrue(b.body.contains("boot gagal"))
    }

    @Test
    fun guardInactiveNoBanner() {
        val s = UiState(guard = GuardState(0, 0, 2, 0, "tidak ada state"))
        assertNull(ErrorStatesPresenter.guardBanner(s))
        assertNull(ErrorStatesPresenter.guardBanner(UiState()))
    }

    @Test
    fun degradedOnlyWhenMixed() {
        val mixed = mapOf(
            "a" to HsinRepository.KnobResult("a", "1", "1", "APPLIED", "ok"),
            "b" to HsinRepository.KnobResult("b", "2", "-", "FAILED", "gagal"),
        )
        assertNotNull(ErrorStatesPresenter.degradedBanner(mixed))
        val allOk = mapOf("a" to HsinRepository.KnobResult("a", "1", "1", "APPLIED", "ok"))
        assertNull("semua sukses bukan degraded", ErrorStatesPresenter.degradedBanner(allOk))
        assertNull(ErrorStatesPresenter.degradedBanner(emptyMap()))
    }

    @Test
    fun readOnlyNotesListsUnavailable() {
        val results = mapOf(
            "a" to HsinRepository.KnobResult("a", "1", "-", "UNAVAILABLE", "node read-only"),
            "b" to HsinRepository.KnobResult("b", "2", "2", "APPLIED", "ok"),
        )
        val notes = ErrorStatesPresenter.readOnlyNotes(results)
        assertEquals(1, notes.size)
        assertTrue(notes[0].contains("a"))
    }

    @Test
    fun allBannersOrderedGuardFirst() {
        val s = UiState(
            guard = GuardState(1, 2, 2, 86400, "boot gagal"),
            error = err(UiErrorKind.TIMEOUT),
            versionMismatch = true,
            applyResults = mapOf(
                "a" to HsinRepository.KnobResult("a", "1", "1", "APPLIED", "ok"),
                "b" to HsinRepository.KnobResult("b", "2", "-", "FAILED", "gagal"),
            ),
        )
        val all = ErrorStatesPresenter.allBanners(s)
        assertEquals(4, all.size)
        assertTrue("guard dulu: ${all[0].title}", all[0].title.contains("dilewati"))
    }
}
