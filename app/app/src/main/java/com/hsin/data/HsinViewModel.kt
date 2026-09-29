package com.hsin.data

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.hsin.data.cache.CapabilityCache
import com.hsin.data.cache.CapabilityCachePolicy
import com.hsin.data.repository.HsinRepository
import com.hsin.data.root.RootClient
import com.hsin.data.root.RootError
import com.hsin.data.root.RootResult
import com.hsin.data.state.DirtyTracker
import com.hsin.data.state.GuardState
import com.hsin.data.state.KnobsMapping
import com.hsin.data.state.StatusMapping
import com.hsin.data.state.UiError
import com.hsin.data.state.UiErrorKind
import com.hsin.data.state.UiState
import com.hsin.data.state.logLinesOf
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import org.json.JSONObject

/**
 * ViewModel A7. Empat aksi refresh TERPISAH, masing-masing hanya menyentuh
 * state bagiannya (lihat [UiState]):
 *
 * - [refreshUiState] — `status`: profil aktif + status apply
 * - [refreshStatus] — `guard-status`: kondisi boot guard
 * - [refreshCapability] — `knobs`: daftar knob + nilai valid, lewat cache
 * - [refreshRealtime] — `status`: metrik yang berubah tiap detik
 *
 * Semua panggilan root terjadi di dalam [viewModelScope]. Composable hanya
 * membaca [uiState] — tidak ada suspend di sana.
 *
 * Versi cache: `knobs` punya field `v` (versi skema knob, saat ini 1).
 * Cache capability memakai pasangan `v` + versi app sebagai kunci, jadi
 * upgrade modul ATAU upgrade app otomatis membuat cache tak berlaku.
 */
class HsinViewModel(
    private val root: RootClient = RootClient(),
    private val cache: CapabilityCache? = null,
    private val appVersion: String = APP_VERSION,
) : ViewModel() {

    private val _uiState = MutableStateFlow(UiState())
    val uiState: StateFlow<UiState> = _uiState.asStateFlow()

    /**
     * Token versi untuk cache. `null` = belum diketahui; selama itu cache
     * dilewati (selalu ambil dari root) supaya tidak ada cache basi.
     */
    @Volatile
    private var cacheToken: String? = null

    // ------------------------------------------------------------------
    // (a) UI state — profil aktif + status apply
    // ------------------------------------------------------------------
    fun refreshUiState() {
        viewModelScope.launch {
            _uiState.update { it.copy(loadingUi = true, error = null) }
            when (val res = call("status")) {
                is RootResult.Success -> {
                    val json = HsinRepository.parseStatus(res.output)
                    _uiState.update {
                        it.copy(
                            loadingUi = false,
                            activeProfile = StatusMapping.readProfile(json)
                                ?: StatusMapping.readActiveProfileFromInfo(res.output),
                            applyStatus = StatusMapping.readApplyStatus(json),
                        )
                    }
                }
                is RootResult.Error -> fail(Loading.UI, res)
            }
        }
    }

    // ------------------------------------------------------------------
    // (b) status modul — boot guard
    // ------------------------------------------------------------------
    fun refreshStatus() {
        viewModelScope.launch {
            _uiState.update { it.copy(loadingStatus = true) }
            when (val res = call("guard-status")) {
                is RootResult.Success -> {
                    val g = HsinRepository.parseGuardStatus(res.output)
                    _uiState.update {
                        it.copy(
                            loadingStatus = false,
                            guard = g?.let {
                                GuardState(
                                    active = it.active,
                                    failCount = it.failCount,
                                    threshold = it.threshold,
                                    cooldownRemainingSec = it.cooldownRemainingSec,
                                    lastReason = it.lastReason,
                                )
                            },
                        )
                    }
                }
                is RootResult.Error -> fail(Loading.STATUS, res)
            }
        }
    }

    // ------------------------------------------------------------------
    // (c) capability — `knobs` (sumber pilihan valid), cache-aware
    // ------------------------------------------------------------------
    fun refreshCapability(forceReload: Boolean = false) {
        viewModelScope.launch {
            _uiState.update { it.copy(loadingCapability = true) }
            val token = cacheToken

            if (!forceReload && token != null && cache != null) {
                when (val hit = cache.get(token)) {
                    is CapabilityCachePolicy.Decision.Hit -> {
                        applyCapability(hit.payload, fromCache = true, fetchAllowExtreme())
                        return@launch
                    }
                    is CapabilityCachePolicy.Decision.Miss -> Unit
                }
            }

            when (val res = call("knobs")) {
                is RootResult.Success -> {
                    val knobsJson = try {
                        JSONObject(res.output)
                    } catch (e: Exception) {
                        _uiState.update {
                            it.copy(
                                loadingCapability = false,
                                error = UiError(UiErrorKind.INVALID_RESPONSE, "knobs: ${e.message}", retryable = true),
                            )
                        }
                        return@launch
                    }
                    // Simpan di cache dengan token versi yang baru diketahui.
                    resolveToken(knobsJson)?.let { token ->
                        cacheToken = token
                        cache?.put(token, knobsJson)
                    }
                    applyCapability(knobsJson, fromCache = false, fetchAllowExtreme())
                }
                is RootResult.Error -> fail(Loading.CAPABILITY, res)
            }
        }
    }

    // ------------------------------------------------------------------
    // (d) realtime — metrik `status`
    // ------------------------------------------------------------------
    fun refreshRealtime() {
        viewModelScope.launch {
            _uiState.update { it.copy(loadingRealtime = true) }
            when (val res = call("status")) {
                is RootResult.Success -> {
                    val json = HsinRepository.parseStatus(res.output)
                    _uiState.update {
                        it.copy(loadingRealtime = false, metrics = StatusMapping.toMetrics(json))
                    }
                }
                is RootResult.Error -> fail(Loading.REALTIME, res)
            }
        }
    }

    // ------------------------------------------------------------------
    // Log
    // ------------------------------------------------------------------
    fun refreshLog(maxLines: Int = 200) {
        viewModelScope.launch {
            when (val res = call("logs")) {
                is RootResult.Success ->
                    _uiState.update { it.copy(logLines = logLinesOf(res.output, maxLines)) }
                is RootResult.Error -> fail(Loading.NONE, res)
            }
        }
    }

    // ------------------------------------------------------------------
    // Aksi edit knob (belum memanggil root — itu urusan A10)
    // ------------------------------------------------------------------
    fun setKnobOverride(key: String, value: String) {
        _uiState.update { it.copy(dirty = DirtyTracker.setOverride(it.dirty, key, value)) }
    }

    /** Buang override satu key; `current` kembali ke `base`, key tetap tampil. */
    fun resetKnobKey(key: String) {
        _uiState.update { it.copy(dirty = DirtyTracker.resetKey(it.dirty, key)) }
    }

    /** Buang semua override; tiap key kembali ke base-nya. */
    fun resetAllKnobs() {
        _uiState.update { it.copy(dirty = DirtyTracker.resetAll(it.dirty)) }
    }

    /** Buang cache lalu ambil ulang dari root (aksi "refresh" di UI). */
    fun invalidateCache() {
        viewModelScope.launch {
            cache?.clear()
            cacheToken = null
            refreshCapability(forceReload = true)
        }
    }

    fun clearError() {
        _uiState.update { it.copy(error = null) }
    }

    // ------------------------------------------------------------------
    // Helper
    // ------------------------------------------------------------------
    private suspend fun call(cmd: String, vararg args: String): RootResult =
        try {
            root.execute(cmd, args.toList())
        } catch (e: Exception) {
            RootResult.Error(RootError.ROOT_UNAVAILABLE, e.message ?: e.toString())
        }

    /**
     * Terapkan capability ke state. [allowExtreme] sudah dibaca pemanggil
     * (butuh panggilan root, jadi harus di dalam coroutine).
     */
    private fun applyCapability(knobsJson: JSONObject, fromCache: Boolean, allowExtreme: Boolean) {
        val parsed = KnobsMapping.parse(knobsJson, allowExtreme)
        _uiState.update {
            it.copy(
                loadingCapability = false,
                capability = parsed.capability,
                capabilityFromCache = fromCache,
                dirty = DirtyTracker.mergeBase(it.dirty, parsed.baseValues),
            )
        }
    }

    /**
     * `config-get` tidak menerima argumen dan mengembalikan satu baris JSON
     * berisi seluruh setelan (kontrak §3.5). Kegagalan tidak mematikan:
     * `allow_extreme` dianggap false, jadi UI tidak menawarkan extreme.
     */
    private suspend fun fetchAllowExtreme(): Boolean =
        when (val res = call("config-get")) {
            is RootResult.Success -> try {
                StatusMapping.readAllowExtreme(JSONObject(res.output))
            } catch (_: Exception) {
                false
            }
            is RootResult.Error -> false
        }

    /**
     * Token cache dari `knobs.v` (versi skema knob) + versi app. Kalau `v`
     * tidak terbaca, token null: cache TIDAK diisi dan tidak dibaca, jadi
     * setiap refresh ambil dari root. Lebih sering ambil root daripada
     * menyajikan data kedaluwarsa.
     */
    private fun resolveToken(knobsJson: JSONObject): String? {
        val v = knobsJson.optInt("v", -1)
        if (v < 0) return null
        return "knobs_v${v}_app_$appVersion"
    }

    private fun fail(loading: Loading, res: RootResult.Error) {
        val kind = res.type.toUiKind()
        _uiState.update {
            it.copy(
                loadingUi = it.loadingUi && loading != Loading.UI,
                loadingStatus = it.loadingStatus && loading != Loading.STATUS,
                loadingCapability = it.loadingCapability && loading != Loading.CAPABILITY,
                loadingRealtime = it.loadingRealtime && loading != Loading.REALTIME,
                error = UiError(
                    kind = kind,
                    detail = res.message,
                    retryable = kind != UiErrorKind.MODULE_NOT_FOUND,
                ),
            )
        }
    }
}

/** Penanda aksi refresh yang sedang berjalan, untuk mengatur flag loading. */
enum class Loading { UI, STATUS, CAPABILITY, REALTIME, NONE }

internal fun RootError.toUiKind(): UiErrorKind = when (this) {
    RootError.ROOT_UNAVAILABLE -> UiErrorKind.ROOT_UNAVAILABLE
    RootError.MODULE_NOT_FOUND -> UiErrorKind.MODULE_NOT_FOUND
    RootError.FEATURE_UNSUPPORTED -> UiErrorKind.FEATURE_UNSUPPORTED
    RootError.COMMAND_FAILED -> UiErrorKind.COMMAND_FAILED
    RootError.TIMEOUT -> UiErrorKind.TIMEOUT
    RootError.INVALID_RESPONSE -> UiErrorKind.INVALID_RESPONSE
}

/** Versi app; cache capability juga terikat ke sini. */
const val APP_VERSION = "1.0.0-beta"
