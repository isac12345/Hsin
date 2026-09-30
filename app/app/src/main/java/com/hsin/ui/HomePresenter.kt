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

    // ------------------------------------------------------------------
    // R3: Beranda sesuai mockup (bagian 2 revisi). Kata-kata mockup yang
    // dipakai: Tersedia/Terpasang/Nonaktif. Tanpa badge termal dan tanpa
    // jumlah zona termal sampai kontrak menyediakannya (pending bagian 3).
    // ------------------------------------------------------------------

    /** Satu sel grid status 2 kolom. [showBadge] false = nilai saja. */
    data class GridCell(
        val label: String,
        val value: String,
        val status: LineStatus,
        val showBadge: Boolean = true,
    )

    /** Grid 2x2: Root, Modul, Boot guard, Termal (suhu CPU saja, tanpa badge). */
    fun grid(state: UiState): List<GridCell> {
        val root = when (rootLine(state.error).status) {
            LineStatus.OK -> GridCell("Root", "Tersedia", LineStatus.OK)
            else -> GridCell("Root", "Tidak tersedia", LineStatus.ERROR)
        }
        val module = when {
            state.capability != null -> GridCell("Modul", "Terpasang", LineStatus.OK)
            else -> GridCell("Modul", "Belum diperiksa", LineStatus.UNKNOWN)
        }
        val guard = run {
            val g = state.guard
            if (g != null && g.active == 1) {
                val reason = g.lastReason.ifBlank { "alasan tidak tercatat" }
                GridCell("Boot guard", "Aktif · tuning dilewati ($reason)", LineStatus.ERROR)
            } else {
                GridCell("Boot guard", "Nonaktif", LineStatus.OK)
            }
        }
        val thermal = run {
            val t = state.metrics.cpuTempC
            if (t.readable && t.value != null) {
                GridCell("Termal", "${t.value} ${t.unit}", LineStatus.OK, showBadge = false)
            } else {
                GridCell("Termal", "N/A", LineStatus.UNKNOWN, showBadge = false)
            }
        }
        return listOf(root, module, guard, thermal)
    }

    /** Satu baris hasil apply: badge + `key diminta X → diterapkan Y (alasan)`. */
    data class AppliedRow(val badge: String, val text: String)

    /**
     * Jam dari baris TERAKHIR `apply.log` (kontrak §3.6: tiap baris diawali
     * `YYYY-MM-DD HH:MM:SS`). Null bila tak ada baris berstempel waktu —
     * pemanggil menampilkan "waktu tak tercatat", bukan karangan.
     */
    fun applyTimeOf(logApply: List<String>): String? {
        val stamp = Regex("""^(\d{4}-\d{2}-\d{2}) (\d{2}:\d{2})""")
        for (line in logApply.asReversed()) {
            val m = stamp.find(line.trimStart()) ?: continue
            return m.groupValues[2]
        }
        return null
    }

    /**
     * Kartu "Terakhir diterapkan · HH:MM": maks 3 baris hasil
     * ([UiState.applyResults], kontrak §3.11) + jam dari `apply.log`.
     * Baris kosong = belum ada apply (layar menampilkan state Kosong).
     */
    data class LastApplied(val title: String, val rows: List<AppliedRow>)

    fun lastApplied(state: UiState, maxRows: Int = 3): LastApplied {
        val time = applyTimeOf(state.logApply) ?: "waktu tak tercatat"
        val rows = state.applyResults.values
            .sortedBy { it.key }
            .take(maxRows)
            .map { r ->
                AppliedRow(
                    badge = r.category.ifBlank { "N/A" },
                    text = "${r.key} diminta ${r.requested} → diterapkan ${r.applied} (${r.reason})",
                )
            }
        return LastApplied(title = "Terakhir diterapkan · $time", rows = rows)
    }

    /** Kartu kemampuan: hitungan mentah dari snapshot modul + catatan cache. */
    data class CapabilityRow(val label: String, val value: String)

    fun capabilityRows(state: UiState): List<CapabilityRow> {
        val cap = state.capability ?: return listOf(
            CapabilityRow("CPU policy", "belum diperiksa"),
            CapabilityRow("GPU devfreq", "belum diperiksa"),
            CapabilityRow("zRAM", "belum diperiksa"),
            CapabilityRow("I/O blok", "belum diperiksa"),
        )
        return listOf(
            CapabilityRow("CPU policy", "${cap.cpuPolicies}"),
            CapabilityRow("GPU devfreq", if (cap.gpuNodes > 0) "Ada" else "Tidak"),
            CapabilityRow("zRAM", if (cap.zramSupported) "Ada" else "Tidak"),
            CapabilityRow("I/O blok", "${cap.ioBlocks}"),
        )
    }

    /** Catatan kaki kartu kemampuan: data cache, bukan scan ulang. */
    const val CAPABILITY_FOOTNOTE =
        "Dibaca dari snapshot modul, tidak scan ulang tiap aplikasi dibuka."
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
