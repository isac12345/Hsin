package com.hsin

data class Knob(
    val key: String,
    val label: String,
    val type: String, // choice | range | locked
    val unit: String,
    val options: List<String>,
    val min: Int,
    val max: Int,
    val step: Int,
    val cur: String,
    val def: String,
    val reason: String
)

data class Category(val id: String, val title: String, val knobs: List<Knob>)

data class Live(
    val cpuKhz: Long,
    val gpuHz: Long,
    val cpuTemp: Int,
    val gpuTemp: Int,
    val batPct: Int,
    val batTemp: Int,
    val ramTotalKb: Long,
    val ramUsedKb: Long,
    val loadX100: Int,
    val safeMode: Boolean,
    val overrides: Int
)

data class DeviceInfo(
    val model: String,
    val brand: String,
    val soc: String,
    val kernel: String,
    val android: String,
    val module: String
)

data class ApplyResult(
    val ok: Int,
    val fail: Int,
    val okKeys: Set<String>,
    val failures: List<Pair<String, String>>,
    val error: String
)

data class Preset(val name: String, val values: Map<String, String>)

enum class Setup { Loading, NoRoot, NoModule, Ready }
