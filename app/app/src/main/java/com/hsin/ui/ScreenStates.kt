package com.hsin.ui

import com.hsin.data.state.RealtimeMetrics
import com.hsin.data.state.UiState

/**
 * Resolver fase layar R2 (murni, tanpa Android — bisa unit-test JVM).
 *
 * Aturan APP_PLAN §0.11: tiap layar (Beranda, Knob, Monitor, Log) punya 4
 * state eksplisit — Memuat, Gagal, Kosong, Isi. Tidak ada kondisi yang
 * merender layar kosong (foto bug `knob_reference`, `knob_empty_reference`,
 * `hsin_blank_reference` tidak boleh terulang).
 *
 * Prioritas: LOADING > ERROR > EMPTY > CONTENT. LOADING/ERROR hanya
 * full-screen bila data yang dibutuhkan layar BELUM ADA SAMA SEKALI; kalau
 * data sudah ada, layar tetap menampilkan isi (+ banner error inline di
 * Beranda) supaya refresh berkala tidak membuat layar berkedip.
 */
enum class ScreenPhase { LOADING, ERROR, EMPTY, CONTENT }

object ScreenStates {

    /** Beranda punya data bila salah satu dari status/capability sudah terbaca. */
    fun homeHasData(state: UiState): Boolean =
        state.capability != null ||
            state.guard != null ||
            state.activeProfile != null ||
            state.applyStatus != null

    fun home(state: UiState): ScreenPhase {
        if (!homeHasData(state)) {
            if (state.loadingUi || state.loadingStatus || state.loadingCapability) return ScreenPhase.LOADING
            if (state.error != null) return ScreenPhase.ERROR
            return ScreenPhase.EMPTY
        }
        return ScreenPhase.CONTENT
    }

    /**
     * Knob butuh `capability`; [contentCount] = jumlah kategori + baris
     * terkunci yang berhasil dibangun (0 = scan kosong).
     */
    fun knob(state: UiState, contentCount: Int): ScreenPhase {
        if (state.capability == null) {
            if (state.loadingCapability) return ScreenPhase.LOADING
            if (state.error != null) return ScreenPhase.ERROR
            return ScreenPhase.EMPTY
        }
        if (contentCount == 0) return ScreenPhase.EMPTY
        return ScreenPhase.CONTENT
    }

    /** Monitor butuh minimal satu metrik terbaca (bukan sentinel unknown). */
    fun monitor(state: UiState): ScreenPhase {
        if (state.metrics == RealtimeMetrics.unknown()) {
            if (state.loadingRealtime) return ScreenPhase.LOADING
            if (state.error != null) return ScreenPhase.ERROR
            return ScreenPhase.EMPTY
        }
        return ScreenPhase.CONTENT
    }

    /** Log butuh minimal satu baris dari kedua file. */
    fun log(state: UiState): ScreenPhase {
        val hasLogs = state.logBoot.isNotEmpty() || state.logApply.isNotEmpty()
        if (!hasLogs) {
            if (state.loadingLogs) return ScreenPhase.LOADING
            if (state.error != null) return ScreenPhase.ERROR
            return ScreenPhase.EMPTY
        }
        return ScreenPhase.CONTENT
    }
}
