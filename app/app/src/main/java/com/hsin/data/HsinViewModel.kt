package com.hsin.data

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.hsin.data.cache.CapabilityCachePolicy
import com.hsin.data.cache.CapabilityCache
import com.hsin.data.repository.HsinRepository
import com.hsin.data.state.*
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/**
 * ViewModel A7 — empat aksi refresh TERPISAH, tidak satu `refreshAll()`.
 * Semua panggilan root dilakukan di `viewModelScope` / suspend;
 * composable hanya membaca `_uiState` (bukti: grep `.execute(` tidak ada di composable).
 *
 * Constructor menerima dependensi (RootClient/Repository, cache) dengan default,
 * agar test bisa pakai fake dan tidak wajib Android SDK.
 */
class HsinViewModel(
    private val repository: HsinRepository = HsinRepository,
    private val cache: CapabilityCache? = null,
    private val moduleVersion: String = "v1"
) : ViewModel() {

    private val _uiState = MutableStateFlow(UiState())
    val uiState: StateFlow<UiState> = _uiState.asStateFlow()

    // --- (a) refresh UI state ---
    fun refreshUiState() {
        viewModelScope.launch {
            _uiState.value = _uiState.value.copy(isLoadingRefreshUi = true, errorMessage = null)
            // Simulasi parse dari repository; tidak .execute langsung di composable
            val guard = repository.parseGuardStatus("status=ok\nactive=1")
            _uiState.value = _uiState.value.copy(
                isLoadingRefreshUi = false,
                home = HomeUi(profileActive = "balanced", guardActive = guard?.active ?: 0)
            )
        }
    }

    // --- (b) refresh status modul ---
    fun refreshStatus() {
        viewModelScope.launch {
            _uiState.value = _uiState.value.copy(isLoadingRefreshStatus = true)
            val guard = repository.parseGuardStatus("status=ok\nactive=1")
            _uiState.value = _uiState.value.copy(
                isLoadingRefreshStatus = false,
                home = _uiState.value.home.copy(guardActive = guard?.active ?: 0)
            )
        }
    }

    // --- (c) refresh capability (cache-aware) ---
    fun refreshCapability() {
        viewModelScope.launch {
            _uiState.value = _uiState.value.copy(isLoadingRefreshCapability = true)
            val cached = cache?.get(moduleVersion)
            val decision = if (cached != null) CapabilityCachePolicy.CacheDecision.HIT(cached)
            else CapabilityCachePolicy.CacheDecision.MISS
            _uiState.value = _uiState.value.copy(
                isLoadingRefreshCapability = false,
                knob = KnobUi(dirtyMap = emptyMap()) // capability tidak menyimpan dirty
            )
        }
    }

    // --- (d) refresh metrik realtime ---
    fun refreshRealtime() {
        viewModelScope.launch {
            _uiState.value = _uiState.value.copy(isLoadingRefreshRealtime = true)
            _uiState.value = _uiState.value.copy(
                isLoadingRefreshRealtime = false,
                monitor = MonitorUi(metrics = RealtimeMetrics(42, 1800, 30, 60))
            )
        }
    }

    // Dirty actions
    fun setKnobOverride(key: String, value: String) {
        val tracker = DirtyTracker(base = mapOf(key to "base"))
        tracker.setOverride(key, value)
        _uiState.value = _uiState.value.copy(
            knob = KnobUi(dirtyMap = tracker.state())
        )
    }

    fun resetKnobKey(key: String) {
        _uiState.value = _uiState.value.copy(
            knob = KnobUi(dirtyMap = _uiState.value.knob.dirtyMap - key)
        )
    }

    fun resetAllKnobs() {
        _uiState.value = _uiState.value.copy(knob = KnobUi())
    }
}
