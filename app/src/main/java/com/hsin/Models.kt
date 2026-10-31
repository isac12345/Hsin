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

/** Ringkasan satu rekaman FPS (Download/Hsin_fps_*.csv). */
data class RecItem(
    val name: String,
    val pkg: String,
    val secs: Int,
    val avg: Double,
    val low1: Double,
    val max: Double,
    val tMax: Int,
    val series: List<Float>
)

fun parseRec(name: String, text: String): RecItem? {
    val lines = text.lines().filter { it.isNotBlank() }
    if (lines.size < 4) return null
    val h = lines[0].split(',')
    val iT = h.indexOf("t_detik"); val iP = h.indexOf("paket"); val iF = h.indexOf("fps"); val iC = h.indexOf("suhu_c")
    if (iT < 0 || iF < 0) return null
    val fps = ArrayList<Float>()
    var pkg = ""; var secs = 0; var tMax = 0
    for (i in 1 until lines.size) {
        val c = lines[i].split(',')
        if (c.size <= iF) continue
        if (iP >= 0 && pkg.isEmpty()) pkg = c[iP]
        secs = c[iT].toIntOrNull() ?: secs
        val f = c[iF].toFloatOrNull()
        if (f != null && f <= 480f) fps.add(f)
        if (iC >= 0 && c.size > iC) { val t = c[iC].toIntOrNull() ?: 0; if (t in 1..105 && t > tMax) tMax = t }
    }
    if (fps.size < 3) return null
    val sorted = fps.sorted()
    val k = maxOf(1, sorted.size / 100)
    return RecItem(name, pkg, secs, fps.average(), sorted.take(k).average(), sorted.last().toDouble(), tMax, fps)
}
