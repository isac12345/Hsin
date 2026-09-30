package com.hsin.data.state

import org.json.JSONObject

/**
 * Empat sifat data, terpisah supaya hanya satu yang perlu di-refresh saat
 * ticking. Aturan A7: jangan sampai data yang berubah tiap detik ikut
 * di-refresh tiap detik juga.
 *
 * - [Static]: versi/id modul — berubah hanya saat modul di-upgrade.
 * - [Capability]: apa yang device dukung — berubah saat modul berubah.
 * - [CurrentState]: profil aktif, guard, override user — berubah saat user
 *   bertindak atau guard menyala.
 * - [Realtime]: suhu/frekuensi/beban/FPS — berubah tiap detik.
 */
sealed interface DataKind

/** Data statik modul: hanya berubah saat upgrade. */
data class ModuleInfo(
    val moduleVersion: String,
    val moduleId: String,
    val profileList: List<String>,
) : DataKind

/** Capability device, dibaca dari `knobs` (BUKAN `capabilities` — kontrak §3.9). */
data class KnobCapability(
    val supportedKeys: List<String>,
    val allowedValues: Map<String, List<String>>,
    /** min/max yang DILAPORKAN modul untuk knob skalar; disalin apa adanya. */
    val ranges: Map<String, IntRange> = emptyMap(),
    val allowExtreme: Boolean,
    /** Fitur bergate dari `knobs.features`; tampil terkunci, tanpa kontrol. */
    val gated: List<GatedFeature> = emptyList(),
    /**
     * R3 (langsung dari JSON `knobs`, kontrak A3): hitungan mentah untuk
     * kartu kemampuan Beranda. Bukan hasil hitung APK atas key knob —
     * disalin dari struktur `cpu.policies`, `gpu.nodes`, `memory.zram`,
     * `io.blocks` apa adanya.
     */
    val cpuPolicies: Int = 0,
    val gpuNodes: Int = 0,
    val zramSupported: Boolean = false,
    val ioBlocks: Int = 0,
) : DataKind

/** Fitur yang dikunci modul. APK tidak pernah membuka gate extreme. */
data class GatedFeature(val label: String, val available: Boolean, val why: String)

/** Condition boot guard saat ini. */
data class GuardState(
    val active: Int,
    val failCount: Int,
    val threshold: Int,
    val cooldownRemainingSec: Int,
    val lastReason: String,
) : DataKind

/**
 * Satu metrik realtime. [value] null = tidak terbaca (sentinel -1/0 di
 * kontrak §3.1, aturan A11) — UI harus menampilkan "—", bukan 0.
 */
data class Metric(val value: Int?, val unit: String) : DataKind {
    val readable: Boolean get() = value != null
}

/** Kumpulan metrik realtime yang tampil di layar Monitor. */
data class RealtimeMetrics(
    val cpuTempC: Metric,
    val gpuTempC: Metric,
    val cpuFreqMhz: Metric,
    val gpuFreqMhz: Metric,
    val ramUsedKb: Metric,
    val ramTotalKb: Metric,
    val batteryPct: Metric,
    val refreshHz: Metric,
    val loadPercent: Metric,
    val zramPct: Metric,
    /**
     * R3 (kontrak §3.1, sudah ada di JSON `status`): frekuensi per klaster
     * + maksimum untuk bar kartu Frekuensi. Sentinel 0 = tak terbaca
     * (lihat helper baca); klaster kecil 0 disembunyikan presenter.
     */
    val cpuFreqBigMhz: Metric,
    val cpuFreqLittleMhz: Metric,
    val cpuFreqMaxMhz: Metric,
    val gpuFreqMaxMhz: Metric,
) : DataKind {
    companion object {
        /** Semua metrik belum diketahui — dipakai sebelum refresh pertama. */
        fun unknown(): RealtimeMetrics = RealtimeMetrics(
            cpuTempC = Metric(null, "°C"),
            gpuTempC = Metric(null, "°C"),
            cpuFreqMhz = Metric(null, "MHz"),
            gpuFreqMhz = Metric(null, "MHz"),
            ramUsedKb = Metric(null, "KB"),
            ramTotalKb = Metric(null, "KB"),
            batteryPct = Metric(null, "%"),
            refreshHz = Metric(null, "Hz"),
            loadPercent = Metric(null, "%"),
            zramPct = Metric(null, "%"),
            cpuFreqBigMhz = Metric(null, "MHz"),
            cpuFreqLittleMhz = Metric(null, "MHz"),
            cpuFreqMaxMhz = Metric(null, "MHz"),
            gpuFreqMaxMhz = Metric(null, "MHz"),
        )
    }
}

/**
 * Pemetaan output `status` ke [RealtimeMetrics].
 *
 * Aturan A11 / kontrak §3.1: nilai sentinel TIDAK boleh ditampilkan sebagai
 * angka yang sah. Yang jadi sentinel di keluaran `status`:
 * - `battery_pct = -1` → sensor tak terbaca
 * - `refresh_hz = 0` → cache dumpsys tak ada
 * - `game_fps = 0` → tidak ada game berjalan
 * - `cpu_load_x100 = 235` → 2,35 (bagi 100)
 * Suhu di keluaran dalam mili-derajat (`cpu_temp:45000` = 45.0 °C).
 */
object StatusMapping {

    private const val MILLI = 1000

    /** Ambil nilai yang benar-benar terbaca, atau null untuk sentinel. */
    fun readInt(json: JSONObject, key: String): Int? {
        if (!json.has(key) || json.isNull(key)) return null
        val raw = json.optInt(key, Int.MIN_VALUE)
        if (raw == Int.MIN_VALUE) return null
        return if (raw < 0) null else raw
    }

    fun readC(json: JSONObject, key: String): Metric? {
        val milli = readInt(json, key) ?: return null
        if (milli == 0) return null
        return Metric(milli / MILLI, "°C")
    }

    fun readMhzFromKhz(json: JSONObject, key: String): Metric? {
        val khz = readInt(json, key) ?: return null
        if (khz == 0) return null
        return Metric(khz / MILLI, "MHz")
    }

    fun readRaw(json: JSONObject, key: String, unit: String): Metric? {
        val v = readInt(json, key) ?: return null
        if (v == 0) return null
        return Metric(v, unit)
    }

    /** Load: keluaran `cpu_load_x100` = persen x 100. */
    fun readLoadPercent(json: JSONObject): Metric? {
        val x100 = readInt(json, "cpu_load_x100") ?: return null
        if (x100 == 0) return null
        return Metric(x100 / 100, "%")
    }

    /**
     * `allow_extreme` dari `config-get` (kontrak §5 butir 4). Nilai modul
     * berupa string "true"/"false", bukan boolean.
     */
    fun readAllowExtreme(configJson: JSONObject?): Boolean =
        configJson?.optString("allow_extreme")?.trim()?.equals("true", ignoreCase = true) ?: false

    /**
     * Profil aktif dari `info` (baris "Profile aktif: <nama>") — dipakai kalau
     * JSON `status` tidak punya `profile`.
     */
    fun readActiveProfileFromInfo(infoOutput: String): String? =
        infoOutput.lineSequence()
            .map { it.trim() }
            .firstOrNull { it.startsWith("Profile aktif:", ignoreCase = true) }
            ?.substringAfter(':')
            ?.trim()
            ?.takeIf { it.isNotEmpty() }

    /** Battery: sentinel -1 (tak ada sensor). */
    fun readBattery(json: JSONObject): Metric? {
        if (!json.has("battery_pct") || json.isNull("battery_pct")) return null
        val pct = json.optInt("battery_pct", -1)
        if (pct < 0 || pct > 100) return null
        return Metric(pct, "%")
    }

    /**
     * Bangun [RealtimeMetrics] dari JSON `status`. Field yang tidak ada atau
     * bernilai sentinel menjadi `Metric(null, ...)`.
     */
    fun toMetrics(json: JSONObject?): RealtimeMetrics {
        if (json == null) return RealtimeMetrics.unknown()
        val u = RealtimeMetrics.unknown()
        return RealtimeMetrics(
            cpuTempC = readC(json, "cpu_temp") ?: u.cpuTempC,
            gpuTempC = readC(json, "gpu_temp") ?: u.gpuTempC,
            cpuFreqMhz = readMhzFromKhz(json, "cpu_freq") ?: u.cpuFreqMhz,
            gpuFreqMhz = readMhzFromKhz(json, "gpu_freq") ?: u.gpuFreqMhz,
            ramUsedKb = readRaw(json, "ram_used_kb", "KB") ?: u.ramUsedKb,
            ramTotalKb = readRaw(json, "ram_total_kb", "KB") ?: u.ramTotalKb,
            batteryPct = readBattery(json) ?: u.batteryPct,
            refreshHz = readRaw(json, "refresh_hz", "Hz") ?: u.refreshHz,
            loadPercent = readLoadPercent(json) ?: u.loadPercent,
            zramPct = readRaw(json, "zram_pct", "%") ?: u.zramPct,
            cpuFreqBigMhz = readMhzFromKhz(json, "cpu_freq_big") ?: u.cpuFreqBigMhz,
            cpuFreqLittleMhz = readMhzFromKhz(json, "cpu_freq_little") ?: u.cpuFreqLittleMhz,
            cpuFreqMaxMhz = readMhzFromKhz(json, "cpu_max_khz") ?: u.cpuFreqMaxMhz,
            gpuFreqMaxMhz = readMhzFromKhz(json, "gpu_max_khz") ?: u.gpuFreqMaxMhz,
        )
    }

    /** Profil aktif + status apply dari JSON `status` (string, boleh "none"). */
    fun readProfile(json: JSONObject?): String? =
        json?.optString("profile")?.takeIf { it.isNotBlank() && it != "null" }

    fun readApplyStatus(json: JSONObject?): String? =
        json?.optString("apply_status")?.takeIf { it.isNotBlank() && it != "null" }
}
