package com.hsin.data.state

/**
 * UiState aplikasi. Immutable total: semua `val`, perubahan lewat `copy()`.
 *
 * State dipisah per sifat data (lihat [DataKind]) supaya refresh hanya
 * menyentuh bagiannya: satu flag loading per aksi refresh, bukan satu flag
 * global yang membuat semua layar berkedip.
 */
data class UiState(
    // --- static ---
    val module: ModuleInfo? = null,

    // --- capability ---
    val capability: KnobCapability? = null,
    val capabilityFromCache: Boolean = false,

    // --- current state ---
    val guard: GuardState? = null,
    val activeProfile: String? = null,
    val applyStatus: String? = null,
    val dirty: DirtyMap = emptyMap(),

    // --- realtime ---
    val metrics: RealtimeMetrics = RealtimeMetrics.unknown(),

    // --- log ---
    val logLines: List<String> = emptyList(),

    // --- status aksi ---
    val loadingUi: Boolean = false,
    val loadingStatus: Boolean = false,
    val loadingCapability: Boolean = false,
    val loadingRealtime: Boolean = false,
    val error: UiError? = null,
) {
    /** Jumlah knob yang akan berubah kalau apply — untuk label A10. */
    val dirtyCount: Int get() = DirtyTracker.dirtyCount(dirty)

    val dirtyKeys: List<String> get() = DirtyTracker.dirtyKeys(dirty)
}

/**
 * Error yang ditampilkan ke user. [detail] diisi dari pesan [RootError]
 * supaya teks aslinya tidak hilang, tapi jenisnya yang menentukan tindakan.
 */
data class UiError(
    val kind: UiErrorKind,
    val detail: String,
    val retryable: Boolean,
)

enum class UiErrorKind {
    /** `su` tidak tersedia / modul belum terpasang. */
    ROOT_UNAVAILABLE,
    MODULE_NOT_FOUND,
    /** Device tidak mendukung bagian yang diminta. */
    FEATURE_UNSUPPORTED,
    /** Perintah ditolak modul (rc=1 atau `Usage:`). */
    COMMAND_FAILED,
    TIMEOUT,
    /** Output tidak bisa diparse. */
    INVALID_RESPONSE,
    /** Galat lain yang belum dipetakan. */
    UNKNOWN,
}

/**
 * Ambil N baris log terakhir yang tidak kosong. Dipisah dari ViewModel
 * supaya bisa diuji tanpa Android.
 */
fun logLinesOf(output: String, maxLines: Int): List<String> =
    output.lines().filter { it.isNotBlank() }.takeLast(maxLines)

/**
 * Ambil (ok, fail) dari baris `Restore <nama> done. ok=N fail=M` pada
 * keluaran `rollback`. Null kalau baris itu tidak ada — pemanggil tidak
 * boleh mengarang angka hasil pemulihan.
 */
fun parseRollbackDetail(output: String): Pair<Int, Int>? {
    val line = output.lines().firstOrNull { it.contains("ok=") && it.contains("fail=") }
        ?: return null
    val ok = Regex("ok=(\\d+)").find(line)?.groupValues?.get(1)?.toIntOrNull() ?: return null
    val fail = Regex("fail=(\\d+)").find(line)?.groupValues?.get(1)?.toIntOrNull() ?: return null
    return ok to fail
}
