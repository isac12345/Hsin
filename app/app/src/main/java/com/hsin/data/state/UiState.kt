package com.hsin.data.state

import androidx.compose.runtime.Immutable

/**
 * UiState per layar — immutable, `val` semua, `copy()` untuk perubahan.
 * Tidak mengandung `mutableStateOf`; composable hanya membaca.
 * @Immutable menandai Compose agar skip recomposition tak perlu jika sama.
 */
@Immutable
data class UiState(
    val home: HomeUi = HomeUi(),
    val knob: KnobUi = KnobUi(),
    val monitor: MonitorUi = MonitorUi(),
    val log: LogUi = LogUi(),
    val isLoadingRefreshUi: Boolean = false,
    val isLoadingRefreshStatus: Boolean = false,
    val isLoadingRefreshCapability: Boolean = false,
    val isLoadingRefreshRealtime: Boolean = false,
    val errorMessage: String? = null
)

data class HomeUi(val profileActive: String = "none", val guardActive: Int = 0)
data class KnobUi(val dirtyMap: Map<String, DirtyEntry> = emptyMap())
data class MonitorUi(val metrics: RealtimeMetrics = RealtimeMetrics(0,0,0,0))
data class LogUi(val lines: List<String> = emptyList())

/** Dirty tracking per key: base / current / dirty. */
data class DirtyEntry(
    val base: String,
    val current: String,
    val dirty: Boolean
)
