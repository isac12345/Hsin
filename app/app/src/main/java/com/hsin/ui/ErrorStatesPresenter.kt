package com.hsin.ui

import com.hsin.data.repository.HsinRepository
import com.hsin.data.state.UiErrorKind
import com.hsin.data.state.UiState

/**
 * Presenter kasus tepi A13 (murni, tanpa Android).
 *
 * Delapan state (spec A13), semuanya dari data nyata:
 * 1. tanpa root → `error.kind == ROOT_UNAVAILABLE`
 * 2. modul tidak ada/dinonaktifkan → `MODULE_NOT_FOUND`
 * 3. versi modul tidak cocok → [UiState.versionMismatch] (knobs terbaca
 *    tapi field `v` hilang — skema tak dikenal, cache dilewati)
 * 4. timeout → `TIMEOUT`
 * 5. respons tidak valid → `INVALID_RESPONSE`
 * 6. boot guard aktif → `guard.active == 1` via `guard-status` (M2);
 *    banner "tuning dilewati"
 * 7. degraded (sukses parsial) → [UiState.applyResults] berisi FAILED
 * 8. node read-only → [UiState.applyResults] berisi UNAVAILABLE
 *
 * Tidak ada threshold/klasifikasi sendiri; semua dari modul.
 */
object ErrorStatesPresenter {

    data class Banner(val title: String, val body: String, val tone: Tone)

    enum class Tone { ERROR, WARN, INFO }

    /** Banner utama untuk error transport/parse (satu per state). Null bila tidak ada error. */
    fun transportBanner(state: UiState): Banner? {
        val e = state.error ?: return null
        val kind = e.kind
        val detail = e.detail
        return when (kind) {
            UiErrorKind.ROOT_UNAVAILABLE -> Banner(
                "Akses root tidak tersedia",
                if (detail.isBlank()) "Perangkat ini tidak memberi akses root ke aplikasi." else detail,
                Tone.ERROR,
            )
            UiErrorKind.MODULE_NOT_FOUND -> Banner(
                "Modul HSIN belum terpasang",
                if (detail.isBlank()) "Pasang modul lalu reboot." else detail,
                Tone.ERROR,
            )
            UiErrorKind.TIMEOUT -> Banner(
                "Modul menjawab terlalu lama",
                if (detail.isBlank()) "Coba lagi." else detail,
                Tone.WARN,
            )
            UiErrorKind.INVALID_RESPONSE -> Banner(
                "Jawaban modul tidak bisa dibaca",
                if (detail.isBlank()) "Format di luar kontrak." else detail,
                Tone.WARN,
            )
            UiErrorKind.COMMAND_FAILED -> Banner(
                "Modul menolak perintah",
                if (detail.isBlank()) "Periksa knob yang dikirim." else detail,
                Tone.ERROR,
            )
            UiErrorKind.FEATURE_UNSUPPORTED -> Banner(
                "Fitur tidak didukung perangkat",
                if (detail.isBlank()) "Node tidak ada di device ini." else detail,
                Tone.WARN,
            )
            UiErrorKind.UNKNOWN -> Banner("Terjadi kesalahan", detail, Tone.WARN)
        }
    }

    /** Banner versi (terpisah dari transport — skema knobs tak dikenal). */
    fun versionBanner(state: UiState): Banner? =
        if (state.versionMismatch) Banner(
            "Versi modul tidak cocok",
            "Skema knob (field v) tidak terbaca — cache dilewati, selalu baca dari modul.",
            Tone.WARN,
        ) else null

    /** Banner boot guard aktif (kontrak M2, bukan parsing log). */
    fun guardBanner(state: UiState): Banner? {
        val g = state.guard ?: return null
        if (g.active != 1) return null
        val reason = g.lastReason.ifBlank { "alasan tidak tercatat" }
        return Banner("Tuning dilewati — boot guard aktif", reason, Tone.ERROR)
    }

    /** Banner degraded: sebagian knob APPLIED, sebagian FAILED. */
    fun degradedBanner(results: Map<String, HsinRepository.KnobResult>): Banner? {
        if (results.isEmpty()) return null
        val failed = results.values.count { it.category == "FAILED" }
        val applied = results.values.count { it.category == "APPLIED" }
        if (failed == 0 || applied == 0) return null
        return Banner(
            "Sebagian knob gagal diterapkan",
            "$applied berhasil, $failed gagal — lihat status per knob di layar Knob.",
            Tone.WARN,
        )
    }

    /** Daftar knob read-only (UNAVAILABLE) untuk ditampilkan per knob. */
    fun readOnlyNotes(results: Map<String, HsinRepository.KnobResult>): List<String> =
        results.values
            .filter { it.category == "UNAVAILABLE" }
            .sortedBy { it.key }
            .map { "${it.key}: ${it.reason.ifBlank { "tidak tersedia di perangkat" }}" }

    /** Semua banner aktif untuk layar Beranda, urutan: guard, transport, versi, degraded. */
    fun allBanners(state: UiState): List<Banner> {
        val out = mutableListOf<Banner>()
        guardBanner(state)?.let { out.add(it) }
        transportBanner(state)?.let { out.add(it) }
        versionBanner(state)?.let { out.add(it) }
        degradedBanner(state.applyResults)?.let { out.add(it) }
        return out
    }
}
