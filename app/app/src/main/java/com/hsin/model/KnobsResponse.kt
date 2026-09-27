package com.hsin.model

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/**
 * Model untuk `action.sh knobs`.
 *
 * Semua field diberi default null: JSON dari modul boleh berubah / key bisa
 * hilang (mis. cache belum pernah ditulis, atau device tanpa node tertentu)
 * dan itu HARUS berakhir sebagai "tidak ditampilkan", bukan crash decode.
 *
 * Nama field Kotlin memakai camelCase + @SerialName karena kunci JSON modul
 * memakai snake_case.
 */
@Serializable
data class KnobsResponse(
    @SerialName("v") val version: Int = 1,
    @SerialName("profiles") val profiles: List<String> = emptyList(),
    @SerialName("cpu") val cpu: CpuKnobs = CpuKnobs(),
    @SerialName("gpu") val gpu: GpuKnobs = GpuKnobs(),
    @SerialName("memory") val memory: MemoryKnobs = MemoryKnobs(),
    @SerialName("io") val io: IoKnobs = IoKnobs(),
    @SerialName("network") val network: NetworkKnobs = NetworkKnobs(),
    @SerialName("display") val display: DisplayKnobs = DisplayKnobs(),
    @SerialName("features") val features: FeaturesKnobs = FeaturesKnobs(),
    @SerialName("capabilities") val capabilities: CapabilitiesKnobs = CapabilitiesKnobs()
)

@Serializable
data class CpuKnobs(
    @SerialName("supported") val supported: Boolean = false,
    @SerialName("policies") val policies: List<CpuPolicyKnob> = emptyList()
)

@Serializable
data class CpuPolicyKnob(
    @SerialName("id") val id: String = "",
    @SerialName("hw_max_khz") val hwMaxKhz: Long = 0L,
    @SerialName("govs") val govs: List<String> = emptyList(),
    @SerialName("cur_gov") val curGov: String = "",
    @SerialName("opp_khz") val oppKhz: List<Long> = emptyList(),
    @SerialName("writable_min") val writableMin: Boolean = false,
    @SerialName("writable_max") val writableMax: Boolean = false
)

@Serializable
data class GpuKnobs(
    @SerialName("supported") val supported: Boolean = false,
    @SerialName("nodes") val nodes: List<GpuNodeKnob> = emptyList()
)

@Serializable
data class GpuNodeKnob(
    @SerialName("name") val name: String = "",
    @SerialName("govs") val govs: List<String> = emptyList(),
    @SerialName("opp_khz") val oppKhz: List<Long> = emptyList(),
    @SerialName("cur_gov") val curGov: String = "",
    @SerialName("writable") val writable: Boolean = false
)

@Serializable
data class MemoryKnobs(
    @SerialName("supported") val supported: Boolean = false,
    @SerialName("swappiness") val swappiness: SwappinessKnob = SwappinessKnob(),
    @SerialName("zram") val zram: ZramKnob = ZramKnob()
)

@Serializable
data class SwappinessKnob(
    @SerialName("min") val min: Int = 0,
    @SerialName("max") val max: Int = 100,
    @SerialName("cur") val cur: Int = 0,
    @SerialName("writable") val writable: Boolean = false,
    @SerialName("supported") val supported: Boolean = false
)

@Serializable
data class ZramKnob(
    @SerialName("algos") val algos: List<String> = emptyList(),
    @SerialName("cur") val cur: String = "",
    @SerialName("writable") val writable: Boolean = false,
    @SerialName("supported") val supported: Boolean = false
)

@Serializable
data class IoKnobs(
    @SerialName("supported") val supported: Boolean = false,
    @SerialName("blocks") val blocks: List<IoBlockKnob> = emptyList()
)

@Serializable
data class IoBlockKnob(
    @SerialName("name") val name: String = "",
    @SerialName("schedulers") val schedulers: List<String> = emptyList(),
    @SerialName("cur") val cur: String = "",
    @SerialName("writable") val writable: Boolean = false
)

@Serializable
data class NetworkKnobs(
    @SerialName("supported") val supported: Boolean = false,
    @SerialName("tcp_cc") val tcpCc: List<String> = emptyList(),
    @SerialName("tfo") val tfo: TfoKnob = TfoKnob()
)

@Serializable
data class TfoKnob(
    @SerialName("min") val min: Int = 0,
    @SerialName("max") val max: Int = 3,
    @SerialName("cur") val cur: Int = 0,
    @SerialName("supported") val supported: Boolean = false
)

@Serializable
data class DisplayKnobs(
    @SerialName("supported") val supported: Boolean = false,
    @SerialName("modes_hz") val modesHz: List<Int> = emptyList(),
    @SerialName("cur_hz") val curHz: Int = 0,
    @SerialName("renderers") val renderers: List<String> = emptyList(),
    @SerialName("cur_renderer") val curRenderer: String = "",
    @SerialName("downscale") val downscale: DownscaleKnob = DownscaleKnob()
)

@Serializable
data class DownscaleKnob(
    @SerialName("min") val min: Int = 1,
    @SerialName("max") val max: Int = 99,
    @SerialName("cur") val cur: Int = 1,
    @SerialName("supported") val supported: Boolean = false
)

@Serializable
data class FeaturesKnobs(
    @SerialName("dvfs") val dvfs: Boolean = false,
    @SerialName("global_rr") val globalRr: Boolean = false,
    @SerialName("frame_limit") val frameLimit: Boolean = false,
    @SerialName("surfaceflinger") val surfaceflinger: Boolean = false,
    @SerialName("gaming") val gaming: Boolean = false,
    @SerialName("extreme_optin") val extremeOptin: Boolean = false
)

@Serializable
data class CapabilitiesKnobs(
    @SerialName("available_frequencies_source") val availableFrequenciesSource: String = ""
)

// --- Status / device -------------------------------------------------------

@Serializable
data class StatusResponse(
    @SerialName("cpu_temp") val cpuTemp: Long = 0L,
    @SerialName("gpu_temp") val gpuTemp: Long = 0L,
    @SerialName("cpu_freq") val cpuFreq: Long = 0L,
    @SerialName("cpu_freq_big") val cpuFreqBig: Long = 0L,
    @SerialName("cpu_freq_little") val cpuFreqLittle: Long = 0L,
    @SerialName("gpu_freq") val gpuFreq: Long = 0L,
    @SerialName("cpu_max_khz") val cpuMaxKhz: Long = 0L,
    @SerialName("gpu_max_khz") val gpuMaxKhz: Long = 0L,
    @SerialName("ram_used_kb") val ramUsedKb: Long = 0L,
    @SerialName("ram_total_kb") val ramTotalKb: Long = 0L,
    @SerialName("battery_pct") val batteryPct: Int = -1,
    @SerialName("battery_status") val batteryStatus: String = "",
    @SerialName("battery_temp_c") val batteryTempC: Int = 0,
    @SerialName("refresh_hz") val refreshHz: Int = 0,
    @SerialName("game_fps") val gameFps: Int = 0,
    @SerialName("uptime_sec") val uptimeSec: Long = 0L,
    @SerialName("profile") val profile: String = "",
    @SerialName("apply_status") val applyStatus: String = "",
    @SerialName("cpu_load_x100") val cpuLoadX100: Int = 0,
    @SerialName("zram_pct") val zramPct: Int = 0,
    @SerialName("dvfs_cpu_limit") val dvfsCpuLimit: Int = 100,
    @SerialName("dvfs_gpu_limit") val dvfsGpuLimit: Int = 100
)

@Serializable
data class DeviceResponse(
    @SerialName("soc") val soc: String = "",
    @SerialName("gpu") val gpu: String = "",
    @SerialName("kernel") val kernel: String = "",
    @SerialName("ram_kb") val ramKb: String = "",
    @SerialName("device_id") val deviceId: String = ""
)

@Serializable
data class KnobOverrides(
    @SerialName("count") val count: Int = 0,
    @SerialName("overrides") val overrides: Map<String, String> = emptyMap()
)
