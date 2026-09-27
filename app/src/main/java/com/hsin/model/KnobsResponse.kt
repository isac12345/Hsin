package com.hsin.model

import kotlinx.serialization.Serializable

@Serializable
data class KnobsResponse(
    val v: Int,
    val profiles: List<String>,
    val cpu: CpuKnobs,
    val gpu: GpuKnobs,
    val memory: MemoryKnobs,
    val io: IoKnobs,
    val network: NetworkKnobs,
    val display: DisplayKnobs,
    val features: FeaturesKnobs,
    val capabilities: CapabilitiesKnobs
)

@Serializable
data class CpuKnobs(
    val supported: Boolean,
    val policies: List<CpuPolicyKnob>
)

@Serializable
data class CpuPolicyKnob(
    val id: String,
    val hw_max_khz: Long,
    val govs: List<String>,
    val cur_gov: String,
    val opp_khz: List<Long>,
    val writable_min: Boolean,
    val writable_max: Boolean
)

@Serializable
data class GpuKnobs(
    val supported: Boolean,
    val nodes: List<GpuNodeKnob>
)

@Serializable
data class GpuNodeKnob(
    val name: String,
    val govs: List<String>,
    val opp_khz: List<Long>,
    val cur_gov: String,
    val writable: Boolean
)

@Serializable
data class MemoryKnobs(
    val supported: Boolean,
    val swappiness: SwappinessKnob,
    val zram: ZramKnob
)

@Serializable
data class SwappinessKnob(
    val min: Int,
    val max: Int,
    val cur: Int,
    val writable: Boolean,
    val supported: Boolean
)

@Serializable
data class ZramKnob(
    val algos: List<String>,
    val cur: String,
    val writable: Boolean,
    val supported: Boolean
)

@Serializable
data class IoKnobs(
    val supported: Boolean,
    val blocks: List<IoBlockKnob>
)

@Serializable
data class IoBlockKnob(
    val name: String,
    val schedulers: List<String>,
    val cur: String,
    val writable: Boolean
)

@Serializable
data class NetworkKnobs(
    val supported: Boolean,
    val tcp_cc: List<String>,
    val tfo: TfoKnob
)

@Serializable
data class TfoKnob(
    val min: Int,
    val max: Int,
    val cur: Int,
    val supported: Boolean
)

@Serializable
data class DisplayKnobs(
    val supported: Boolean,
    val modes_hz: List<Int>,
    val cur_hz: Int,
    val renderers: List<String>,
    val cur_renderer: String,
    val downscale: DownscaleKnob
)

@Serializable
data class DownscaleKnob(
    val min: Int,
    val max: Int,
    val cur: Int,
    val supported: Boolean
)

@Serializable
data class FeaturesKnobs(
    val dvfs: Boolean,
    val global_rr: Boolean,
    val frame_limit: Boolean,
    val surfaceflinger: Boolean,
    val gaming: Boolean,
    val extreme_optin: Boolean
)

@Serializable
data class CapabilitiesKnobs(
    val available_frequencies_source: String
)

// --- Other response types ---

@Serializable
data class StatusResponse(
    val cpu_temp: Long,
    val gpu_temp: Long,
    val cpu_freq: Long,
    val cpu_freq_big: Long,
    val cpu_freq_little: Long,
    val gpu_freq: Long,
    val cpu_max_khz: Long,
    val gpu_max_khz: Long,
    val ram_used_kb: Long,
    val ram_total_kb: Long,
    val battery_pct: Int,
    val battery_status: String,
    val battery_temp_c: Int,
    val refresh_hz: Int,
    val game_fps: Int,
    val uptime_sec: Long,
    val profile: String,
    val apply_status: String,
    val cpu_load_x100: Int,
    val zram_pct: Int,
    val global_rr_enabled: String,
    val global_rr_reduced: String,
    val global_rr_peak_hz: Int,
    val global_rr_min_hz: Int,
    val dvfs_enabled: String,
    val dvfs_cpu_limit: Int,
    val dvfs_gpu_limit: Int,
    val frame_limit_disabled: String,
    val surfaceflinger_enabled: String
)

@Serializable
data class DeviceResponse(
    val soc: String,
    val gpu: String,
    val kernel: String,
    val ram_kb: String,
    val device_id: String
)

@Serializable
data class ApplyResponse(
    val success: Boolean,
    val message: String
)

@Serializable
data class ConfigSetResponse(
    val success: Boolean,
    val message: String
)

@Serializable
data class GameListResponse(
    val games: List<GameEntry>
)

@Serializable
data class GameEntry(
    val package_name: String,
    val label: String,
    val profile: String
)

@Serializable
data class BackupResponse(
    val success: Boolean,
    val path: String
)

@Serializable
data class ConfigGetResponse(
    val config: Map<String, String>
)

@Serializable
data class LogsResponse(
    val lines: List<String>
)

@Serializable
data class ApplyResponseRaw(
    val stdout: String,
    val exitCode: Int,
    val success: Boolean
)