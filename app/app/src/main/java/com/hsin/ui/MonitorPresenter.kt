package com.hsin.ui

import com.hsin.data.state.RealtimeMetrics

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
}
