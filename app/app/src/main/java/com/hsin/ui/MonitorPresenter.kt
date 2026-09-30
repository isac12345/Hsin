package com.hsin.ui

import com.hsin.data.state.Metric
import com.hsin.data.state.RealtimeMetrics
import java.util.Locale

/**
 * Presenter Monitor A11 (murni, tanpa Android).
 *
 * Aturan:
 * - Sumber metrik = JSON `status` via [RealtimeMetrics] (kontrak §3.1);
 *   APK tidak membaca sysfs langsung.
 * - Metrik tak tersedia = "N/A" (bukan 0) — sentinel -1/0 sudah jadi
 *   `Metric(null, ...)` di [StatusMapping].
 * - TIDAK ada klasifikasi termal dengan threshold sendiri (Larangan Keras
 *   APP_PLAN §6): presenter hanya menampilkan suhu apa adanya; klasifikasi
 *   termal milik modul.
 */
object MonitorPresenter {

    data class Line(
        val label: String,
        val display: String,
        val readable: Boolean,
    )

    fun lines(m: RealtimeMetrics): List<Line> = listOf(
        line("Suhu CPU", m.cpuTempC.value, m.cpuTempC.unit, m.cpuTempC.readable),
        line("Suhu GPU", m.gpuTempC.value, m.gpuTempC.unit, m.gpuTempC.readable),
        line("CPU", m.cpuFreqMhz.value, m.cpuFreqMhz.unit, m.cpuFreqMhz.readable),
        line("GPU", m.gpuFreqMhz.value, m.gpuFreqMhz.unit, m.gpuFreqMhz.readable),
        line("RAM pakai", m.ramUsedKb.value, m.ramUsedKb.unit, m.ramUsedKb.readable),
        line("RAM total", m.ramTotalKb.value, m.ramTotalKb.unit, m.ramTotalKb.readable),
        line("Baterai", m.batteryPct.value, m.batteryPct.unit, m.batteryPct.readable),
        line("Refresh", m.refreshHz.value, m.refreshHz.unit, m.refreshHz.readable),
        line("Beban", m.loadPercent.value, m.loadPercent.unit, m.loadPercent.readable),
        line("zRAM", m.zramPct.value, m.zramPct.unit, m.zramPct.readable),
    )

    private fun line(label: String, value: Int?, unit: String, readable: Boolean): Line =
        if (readable && value != null) Line(label, "$value $unit", true)
        else Line(label, "N/A", false)

    // ------------------------------------------------------------------
    // R3: Monitor sesuai mockup (bagian 2 revisi). Tanpa baris per policy
    // dan tanpa badge state termal sampai kontrak menyediakannya (pending
    // bagian 3). Beban GPU = "N/A" (tak ada key-nya di kontrak — jujur,
    // bukan 0).
    // ------------------------------------------------------------------

    /** Satu baris frekuensi + fraksi untuk bar (null = tanpa bar). */
    data class FreqLine(val label: String, val display: String, val fraction: Float?)

    /** Kartu Frekuensi: rata-rata + big/little (sembunyi bila 0) + GPU + bar. */
    fun freqLines(m: RealtimeMetrics): List<FreqLine> {
        val out = mutableListOf(
            FreqLine("CPU rata-rata", mhz(m.cpuFreqMhz), fractionOf(m.cpuFreqMhz, m.cpuFreqMaxMhz)),
            FreqLine("Klaster besar", mhz(m.cpuFreqBigMhz), fractionOf(m.cpuFreqBigMhz, m.cpuFreqMaxMhz)),
        )
        // Klaster kecil disembunyikan bila 0 (sentinel → tak terbaca).
        if (m.cpuFreqLittleMhz.readable) {
            out += FreqLine(
                "Klaster kecil",
                mhz(m.cpuFreqLittleMhz),
                fractionOf(m.cpuFreqLittleMhz, m.cpuFreqMaxMhz),
            )
        }
        out += FreqLine("GPU", mhz(m.gpuFreqMhz), fractionOf(m.gpuFreqMhz, m.gpuFreqMaxMhz))
        return out
    }

    /** Satu baris kartu Suhu dan memori. */
    data class MemLine(
        val label: String,
        val display: String,
        val readable: Boolean,
        val fraction: Float? = null,
    )

    /** Kartu Suhu dan memori: suhu CPU/GPU, RAM GB + bar, Beban GPU N/A. */
    fun memLines(m: RealtimeMetrics): List<MemLine> = listOf(
        MemLine("Suhu CPU", celsius(m.cpuTempC), m.cpuTempC.readable),
        MemLine("Suhu GPU", celsius(m.gpuTempC), m.gpuTempC.readable),
        MemLine("RAM", ramGb(m.ramUsedKb, m.ramTotalKb), m.ramUsedKb.readable && m.ramTotalKb.readable,
            fractionOf(m.ramUsedKb, m.ramTotalKb)),
        // Tak ada key beban GPU di kontrak §3.1 — tampil N/A, bukan 0.
        MemLine("Beban GPU", "N/A", false),
    )

    private fun mhz(m: Metric): String =
        if (m.readable && m.value != null) "${m.value} ${m.unit}" else "N/A"

    private fun celsius(m: Metric): String =
        if (m.readable && m.value != null) "${m.value} ${m.unit}" else "N/A"

    private fun ramGb(used: Metric, total: Metric): String {
        if (!used.readable || !total.readable || used.value == null || total.value == null) return "N/A"
        return "${gb(used.value)} / ${gb(total.value)} GB"
    }

    private fun gb(kb: Int): String = String.format(Locale.US, "%.1f", kb / 1_000_000.0)

    /** Fraksi nilai/maks untuk bar; null bila maks tak diketahui/nol. */
    fun fractionOf(value: Metric, max: Metric): Float? {
        val v = value.value
        val mx = max.value
        if (!value.readable || !max.readable || v == null || mx == null || mx <= 0) return null
        return (v.toFloat() / mx.toFloat()).coerceIn(0f, 1f)
    }
}
