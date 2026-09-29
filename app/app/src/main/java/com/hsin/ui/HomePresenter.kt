package com.hsin.ui

import com.hsin.data.state.UiError
import com.hsin.data.state.UiErrorKind
import com.hsin.data.state.UiState

/**
 * Empat tab, navigasi berbasis state (tanpa library navigasi — sesuai
 * keputusan A4). Indeks tab adalah state, bukan yang di-`remember` ulang di
 * tiap recomposisi.
 */
enum class Tab(val title: String) {
    BERANDA("Beranda"),
    KNOB("Knob"),
    MONITOR("Monitor"),
    LOG("Log"),
}

data class NavState(val index: Int = 0) {
    val current: Tab get() = Tab.entries.getOrElse(index) { Tab.BERANDA }

    fun select(i: Int): NavState = if (i == index) this else NavState(i)
}

/**
 * Aksi navigasi di luar UI. Interface supaya HsinViewModel (Android) tidak
 * perlu disentuh dan test bisa memakai stub.
 */
interface NavActions {
    fun onOpenKnobs()
    fun onRestoreBackupConfirmed()
}

/** Turunkan state UI Beranda dari [UiState]. Murni — tanpa Android, tanpa root. */
object HomePresenter {

    data class Line(
        val label: String,
        val value: String,
        val status: LineStatus,
    )

    enum class LineStatus { OK, WARN, ERROR, UNKNOWN }

    /**
     * Status root. `MODULE_NOT_FOUND` = modul belum terpasang: kondisi yang
     * harus tampil ramah, bukan exception mentah.
     */
    fun rootLine(error: UiError?): Line = when (error?.kind) {
        UiErrorKind.MODULE_NOT_FOUND -> Line("Akses root", "Modul belum terpasang", LineStatus.ERROR)
        UiErrorKind.ROOT_UNAVAILABLE -> Line("Akses root", "Tidak tersedia", LineStatus.ERROR)
        UiErrorKind.TIMEOUT -> Line("Akses root", "Melewati batas waktu", LineStatus.WARN)
        UiErrorKind.COMMAND_FAILED -> Line("Akses root", "Perintah ditolak", LineStatus.ERROR)
        UiErrorKind.INVALID_RESPONSE -> Line("Akses root", "Respons tidak terbaca", LineStatus.WARN)
        UiErrorKind.FEATURE_UNSUPPORTED -> Line("Akses root", "Tidak didukung", LineStatus.WARN)
        else -> Line("Akses root", "Siap", LineStatus.OK)
    }

    /** Status modul: dari capability/guard yang sudah terbaca. */
    fun moduleLine(state: UiState): Line = when {
        state.capability == null && state.guard == null ->
            Line("Modul", "Belum diperiksa", LineStatus.UNKNOWN)
        state.capabilityFromCache -> Line("Modul", "Siap (dari cache)", LineStatus.OK)
        else -> Line("Modul", "Siap", LineStatus.OK)
    }

    /**
     * Boot guard lewat `guard-status` (M2). `active=1` = tuning dilewati
     * karena boot gagal berulang; itu yang harus diketahui user.
     */
    fun guardLine(state: UiState): Line {
        val g = state.guard ?: return Line("Boot guard", "Tidak diketahui", LineStatus.UNKNOWN)
        return if (g.active == 1) {
            val reason = g.lastReason.ifBlank { "alasan tidak tercatat" }
            Line("Boot guard", "Aktif · tuning dilewati ($reason)", LineStatus.ERROR)
        } else {
            Line("Boot guard", "Aman", LineStatus.OK)
        }
    }

    /** Termal: suhu dari metrik; sentinel A11 jadi N/A, bukan 0. */
    fun thermalLine(state: UiState): Line {
        val t = state.metrics.cpuTempC
        return if (t.readable) {
            Line("Suhu CPU", "${t.value} ${t.unit}", LineStatus.OK)
        } else {
            Line("Suhu CPU", "N/A", LineStatus.UNKNOWN)
        }
    }

    fun lines(state: UiState): List<Line> = listOf(
        rootLine(state.error),
        moduleLine(state),
        guardLine(state),
        thermalLine(state),
    )

    /**
     * Hasil terakhir yang diterapkan. Baris hasil hanya boleh berasal dari
     * modul (kontrak §3.11) — kalau belum ada siklus apply, jangan mengarang.
     */
    data class LastApply(
        val headline: String,
        val detail: String?,
        val status: LineStatus,
    )

    fun lastApply(state: UiState): LastApply {
        val pending = state.dirtyCount
        return when {
            pending > 0 -> LastApply(
                "Menunggu apply $pending knob",
                "Belum ada hasil dari modul",
                LineStatus.WARN,
            )
            state.applyStatus != null -> LastApply(
                "Apply terakhir: ${state.applyStatus}",
                "Profil ${state.activeProfile ?: "tidak diketahui"}",
                LineStatus.OK,
            )
            else -> LastApply("Belum ada apply", null, LineStatus.UNKNOWN)
        }
    }

    /**
     * Ringkasan kemampuan dari cache. Kalau cache belum terisi, jujur
     * bilang "belum diperiksa" — bukan daftar karangan.
     */
    fun capabilitySummary(state: UiState): String {
        val cap = state.capability ?: return "Belum diperiksa"
        val suffix = if (state.capabilityFromCache) " (cache)" else ""
        return "${cap.supportedKeys.size} knob tersedia$suffix"
    }

    /**
     * "Pulihkan backup" mengembalikan setelan modul ke kondisi sebelum
     * perubahan. Aksinya membatalkan perubahan yang belum di-backup, jadi
     * WAJIB lewat dialog konfirmasi — teks konfirmasinya di sini supaya
     * bisa diuji tanpa UI.
     */
    data class ConfirmRestore(val title: String, val body: String, val confirmLabel: String) {
        companion object {
            val RESTORE = ConfirmRestore(
                title = "Pulihkan backup?",
                body = "Semua tweak yang sedang aktif akan dikembalikan ke kondisi " +
                    "sebelum perubahan terakhir. Perubahan yang belum di-backup hilang.",
                confirmLabel = "Pulihkan",
            )
        }
    }
}

/**
 * Terjemahkan [UiErrorKind] ke kalimat yang bisa dibaca user. Tidak pernah
 * menampilkan exception mentah. [detail] ditambahkan sebagai informasi
 * tambahan, bukan sebagai pesan utama.
 */
fun friendlyError(kind: String, detail: String): String {
    val base = when (kind) {
        "MODULE_NOT_FOUND" -> "Modul HSIN belum terpasang. Pasang modul lalu reboot."
        "ROOT_UNAVAILABLE" -> "Akses root tidak tersedia di perangkat ini."
        "TIMEOUT" -> "Modul menjawab terlalu lama. Coba lagi."
        "COMMAND_FAILED" -> "Modul menolak perintah."
        "INVALID_RESPONSE" -> "Jawaban modul tidak bisa dibaca."
        "FEATURE_UNSUPPORTED" -> "Fitur ini tidak didukung perangkat."
        else -> "Terjadi kesalahan."
    }
    return if (detail.isBlank()) base else "$base ($detail)"
}
