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

data class Policy(val id: Int, val cur: Long, val min: Long, val max: Long, val hw: Long, val gov: String)

data class Live(
    val cpuKhz: Long,
    val cores: Int,
    val policies: List<Policy>,
    val gpuHz: Long,
    val gpuMaxHz: Long,
    val gpuGov: String,
    val cpuTemp: Int,
    val gpuTemp: Int,
    val tempMax: Int,
    val batPct: Int,
    val batTemp: Int,
    val charging: Boolean,
    val ramTotalKb: Long,
    val ramUsedKb: Long,
    val swapTotalKb: Long,
    val swapUsedKb: Long,
    val loadX100: Int,
    val cpuTotal: Long,
    val cpuIdle: Long,
    val safeMode: Boolean,
    val thermalTrip: Boolean,
    val gameMode: Boolean,
    val gameActive: String,
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

data class GameProfile(val pkg: String, val label: String, val values: Map<String, String>)

data class AppItem(val pkg: String, val label: String)

data class ThermalCfg(val on: Boolean, val limit: Int, val trip: Boolean)

enum class Setup { Loading, NoRoot, NoModule, Ready }
