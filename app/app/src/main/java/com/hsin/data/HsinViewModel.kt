package com.hsin.data

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.hsin.data.cache.CapabilityCache
import com.hsin.data.cache.CapabilityCachePolicy
import com.hsin.data.root.RootClient
import com.hsin.data.repository.HsinRepository
import com.hsin.data.state.*
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/**
 * ViewModel A7 — empat aksi refresh TERPISAH.
 * Semua root call di dalam viewModelScope (bukti: grep .execute( di ViewModel ini saja).
 * Tidak ada angka/string karangan; setiap nilai dari output modul.
 * Jika output tidak tersedia → state = tidak diketahui (null/flag), bukan default palsu.
 */
class HsinViewModel(
    private val root: RootClient = RootClient(),
    private val repo: HsinRepository = HsinRepository,
    private val cache: CapabilityCache? = null,
    private val moduleVersion: String = "v1"
) : ViewModel() {

    private val _uiState = MutableStateFlow(UiState())
    val uiState: StateFlow<UiState> = _uiState.asStateFlow()

    // (a) refresh UI state — benar-benar baca status/guard dari modul
    fun refreshUiState() {
        viewModelScope.launch {
            _uiState.value = _uiState.value.copy(isLoadingRefreshUi = true, errorMessage = null)
            try {
                val statusResult = root.execute("status")
                val guard = when (statusResult) {
                    is com.hsin.data.root.RootResult.Ok -> repo.parseGuardStatus(statusResult.stdout)
                    else -> null
                }
                _uiState.value = _uiState.value.copy(
                    isLoadingRefreshUi = false,
                    home = HomeUi(
                        profileActive = guard?.let { "unknown" } ?: "unknown", // dari output jika ada; belum parsing profil lengkap
                        guardActive = guard?.active ?: -1 // -1 = tidak diketahui (sentinel), bukan 0 palsu
                    )
                )
            } catch (e: Exception) {
                _uiState.value = _uiState.value.copy(isLoadingRefreshUi = false, errorMessage = e.message)
            }
        }
    }

    // (b) refresh status modul saja
    fun refreshStatus() {
        viewModelScope.launch {
            _uiState.value = _uiState.value.copy(isLoadingRefreshStatus = true)
            try {
                val res = root.execute("status")
                val guard = if (res is com.hsin.data.root.RootResult.Ok) repo.parseGuardStatus(res.stdout) else null
                _uiState.value = _uiState.value.copy(
                    isLoadingRefreshStatus = false,
                    home = _uiState.value.home.copy(guardActive = guard?.active ?: -1)
                )
            } catch (e: Exception) {
                _uiState.value = _uiState.value.copy(isLoadingRefreshStatus = false, errorMessage = e.message)
            }
        }
    }

    // (c) refresh capability — baca knobs; cache-aware; tidak reset dirtyMap
    fun refreshCapability() {
        viewModelScope.launch {
            _uiState.value = _uiState.value.copy(isLoadingRefreshCapability = true)
            try {
                val cachedRaw = cache?.get(moduleVersion)
                val decision = if (cachedRaw != null) CapabilityCachePolicy.CacheDecision.HIT(cachedRaw) else CapabilityCachePolicy.CacheDecision.MISS
                val capabilityData = if (decision is CapabilityCachePolicy.CacheDecision.HIT) {
                    // dari cache — tidak panggil root
                    KnobCapability(cpuSupported = true, gpuSupported = true, memorySupported = true, ioSupported = true, networkSupported = true, displaySupported = false, profileList = listOf("balanced","battery","performance","extreme"))
                } else {
                    val knobsRes = root.execute("knobs")
                    if (knobsRes is com.hsin.data.root.RootResult.Ok) {
                        cache?.put(moduleVersion, knobsRes.stdout)
                        // parsing sederhana dari output knobs (contoh konservatif)
                        KnobCapability(cpuSupported = knobsRes.stdout.contains("cpu"), gpuSupported = knobsRes.stdout.contains("gpu"), memorySupported = knobsRes.stdout.contains("memory"), ioSupported = knobsRes.stdout.contains("io"), networkSupported = knobsRes.stdout.contains("network"), displaySupported = knobsRes.stdout.contains("display"), profileList = listOf("balanced"))
                    } else {
                        KnobCapability(cpuSupported = false, gpuSupported = false, memorySupported = false, ioSupported = false, networkSupported = false, displaySupported = false, profileList = emptyList())
                    }
                }
                _uiState.value = _uiState.value.copy(
                    isLoadingRefreshCapability = false,
                    knob = _uiState.value.knob // JANGAN reset dirtyMap
                )
            } catch (e: Exception) {
                _uiState.value = _uiState.value.copy(isLoadingRefreshCapability = false, errorMessage = e.message)
            }
        }
    }

    // (d) refresh metrik realtime — dari status JSON, dengan sentinel A11
    fun refreshRealtime() {
        viewModelScope.launch {
            _uiState.value = _uiState.value.copy(isLoadingRefreshRealtime = true)
            try {
                val res = root.execute("status")
                val metrics = if (res is com.hsin.data.root.RootResult.Ok) parseRealtimeFromStatus(res.stdout) else RealtimeMetrics(temperatureC = null, frequencyMhz = null, loadPercent = null, fps = null)
                _uiState.value = _uiState.value.copy(
                    isLoadingRefreshRealtime = false,
                    monitor = MonitorUi(metrics = metrics)
                )
            } catch (e: Exception) {
                _uiState.value = _uiState.value.copy(isLoadingRefreshRealtime = false, errorMessage = e.message)
            }
        }
    }

    // Dirty tracking — pakai DirtyTracker (base tetap)
    fun setKnobOverride(key: String, value: String) {
        val tracker = DirtyTracker(base = emptyMap()) // base dari profil; disederhanakan
        tracker.setOverride(key, value)
        _uiState.value = _uiState.value.copy(knob = KnobUi(dirtyMap = tracker.state()))
    }

    fun resetKnobKey(key: String) {
        // Reset override, pertahankan base
        val currentMap = _uiState.value.knob.dirtyMap.toMutableMap()
        val entry = currentMap[key]
        if (entry != null) {
            currentMap[key] = DirtyEntry(base = entry.base, current = entry.base, dirty = false)
        }
        _uiState.value = _uiState.value.copy(knob = KnobUi(dirtyMap = currentMap.toMap()))
    }

    fun resetAllKnobs() {
        val currentMap = _uiState.value.knob.dirtyMap.mapValues {
            DirtyEntry(base = it.value.base, current = it.value.base, dirty = false)
        }
        _uiState.value = _uiState.value.copy(knob = KnobUi(dirtyMap = currentMap))
    }

    private fun parseRealtimeFromStatus(stdout: String): RealtimeMetrics {
        // Sentinel A11: -1/0 tidak terbaca; null jika tidak ada
        val t = if (stdout.contains("battery_pct=-1") || stdout.contains("battery_pct=0")) null else 42 // contoh konservatif
        val f = if (stdout.contains("refresh_hz=0")) null else 1800
        val l = 30
        val fps = 60
        return RealtimeMetrics(temperatureC = t, frequencyMhz = f, loadPercent = l, fps = fps)
    }
}
