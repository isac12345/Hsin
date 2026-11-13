package com.hsin

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.height
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/**
 * Hasil `hsinctl diagnose`. Logika murni (tanpa Android) supaya mudah diuji.
 * [kv] null = gagal; alasannya ada di [error]: module | timeout | root | invalid.
 */
data class DiagOutcome(val kv: Map<String, String>?, val error: String = "")

/** Parse key=value per baris. Output tanpa `diag=1` dianggap tidak valid (map kosong). */
fun parseDiagnose(text: String): Map<String, String> {
    val m = LinkedHashMap<String, String>()
    for (line in text.lines()) {
        val i = line.indexOf('=')
        if (i <= 0) continue
        val k = line.substring(0, i).trim()
        if (k.isEmpty() || k.any { it.isWhitespace() }) continue
        m[k] = line.substring(i + 1).trim()
    }
    return if (m["diag"] == "1") m else emptyMap()
}

/** Kode keluar Root.Res: -3 modul tidak ada, -1 timeout, -2 root/exec gagal. */
fun classifyDiagnose(code: Int, out: String): DiagOutcome {
    if (code == -3) return DiagOutcome(null, "module")
    if (code == -1) return DiagOutcome(null, "timeout")
    if (code == -2) return DiagOutcome(null, "root")
    val m = parseDiagnose(out)
    return if (m.isEmpty()) DiagOutcome(null, "invalid") else DiagOutcome(m)
}

/** Nilai 'na' atau kosong tampil N/A, bukan 0. Kunci hilang: null. */
fun diagVal(m: Map<String, String>, k: String, unit: String = ""): String? {
    val v = m[k] ?: return null
    if (v.isBlank() || v == "na") return "N/A"
    return v + unit
}

/** Teks laporan polos untuk Salin dan Simpan. */
fun diagReportText(m: Map<String, String>, stamp: String): String {
    val sb = StringBuilder()
    sb.append("# HSIN diagnose ").append(stamp).append('\n')
    for ((k, v) in m) sb.append(k).append('=').append(v).append('\n')
    return sb.toString()
}

/** Kelas HP dari DEVICE_TIER modul: low -> 30 FPS, selain itu 60. Null bila modul belum memberi tier. */
fun tierTarget(tier: String?): Int? = when (tier) { null, "" -> null; "low" -> 30; else -> 60 }

@Composable
fun tierLabel(tier: String?): String = when (tier) {
    "low" -> tx("lemah", "low")
    "mid" -> tx("sedang", "mid")
    "high" -> tx("kuat", "high")
    else -> "N/A"
}

/** "Kelas HP: lemah, target FPS 30"; modul lama (tanpa DEVICE_TIER): null. */
@Composable
fun tierLine(device: Map<String, String>): String? {
    val t = device["DEVICE_TIER"]?.trim()?.lowercase()
    val tgt = tierTarget(t) ?: return null
    return tx("Kelas HP: ", "Phone class: ") + tierLabel(t) + tx(", target FPS ", ", target FPS ") + tgt
}

@Composable
private fun diagWarnText(w: String): String = when (w) {
    "below_20_fps" -> tx("FPS 1% terendah di bawah 20 (game patah)", "1% low FPS is under 20 (game stutters)")
    "soc_hot" -> tx("Suhu SoC tinggi", "SoC temperature is high")
    "ovd_profile_mismatch" -> tx("Mode Puncak aktif tapi profil bukan performa", "Peak is on but the profile is not performance")
    else -> w
}

@Composable
private fun diagFpsNote(src: String): String? = when (src) {
    "ok" -> null
    "binder-fail" -> tx("FPS tidak terbaca: sumber binder gagal.", "FPS unreadable: binder source failed.")
    "dump-fail" -> tx("FPS tidak terbaca: dumpsys gagal.", "FPS unreadable: dumpsys failed.")
    "na" -> tx("FPS tidak tersedia (belum ada game aktif atau sumber tidak ada).", "FPS not available (no active game or no source).")
    else -> tx("FPS tidak terbaca (sumber: $src).", "FPS unreadable (source: $src).")
}

@Composable
private fun DRow(k: String, v: String?) {
    Row(Modifier.fillMaxWidth().padding(vertical = 2.dp)) {
        SText(k, 12.sp, SP.dim, modifier = Modifier.weight(0.45f))
        SText(v ?: "N/A", 12.sp, SP.text, FontWeight.Medium, modifier = Modifier.weight(0.55f))
    }
}

@Composable
private fun DNote(t: String, color: Color = SP.dim) {
    Text(t, color = color, fontSize = 11.sp, lineHeight = 14.sp)
}

/** Layar Diagnose: kartu hasil `hsinctl diagnose`. Tanpa polling; segarkan hanya lewat tombol. */
@Composable
fun DiagnoseScreen(vm: AppViewModel) {
    val out = vm.diag
    val m = out?.kv
    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Section(tx("DIAGNOSE", "DIAGNOSE")) {
            DNote(tx("Satu pembacaan dari modul untuk memastikan mode benar-benar jalan. Tidak diperbarui otomatis.", "One reading from the module to confirm the mode really runs. Not refreshed automatically."))
            val tl = tierLine(vm.device)
            if (tl != null) SText(tl, 12.sp, SP.text, FontWeight.Medium)
            HBtn(if (vm.diagBusy) tx("Membaca...", "Reading...") else tx("SEGARKAN", "REFRESH"), Modifier.fillMaxWidth(), solid = !vm.diagBusy) { if (!vm.diagBusy) vm.runDiagnose() }
            if (m != null) {
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    HBtn(tx("Salin", "Copy"), Modifier.weight(1f)) { vm.copyDiagnose() }
                    HBtn(tx("Simpan laporan", "Save report"), Modifier.weight(1f)) { vm.saveDiagnose() }
                }
            }
        }
        if (out == null) {
            if (!vm.diagBusy) DNote(tx("Belum ada hasil.", "No result yet."))
            return@Column
        }
        if (m == null) {
            Section(tx("HASIL", "RESULT")) {
                SText(
                    when (out.error) {
                        "module" -> "MODULE_NOT_FOUND: " + tx("modul HSIN tidak ditemukan", "HSIN module not found")
                        "timeout" -> tx("Waktu habis, modul tidak menjawab.", "Timed out, the module did not answer.")
                        "root" -> tx("Root tidak bisa dijalankan.", "Root could not be run.")
                        else -> tx("Respons tidak valid dari modul.", "Invalid response from the module.")
                    }, 13.sp, SP.red, FontWeight.Medium
                )
            }
            return@Column
        }
        var missing = false

        val modeKeys = listOf("profile", "ovd", "cpu_owner")
        if (modeKeys.any { m.containsKey(it) }) {
            Section(tx("MODE", "MODE"), 0) {
                DRow(tx("Profil", "Profile"), diagVal(m, "profile"))
                val ovd = m["ovd"]
                DRow(tx("Puncak", "Peak"), when (ovd) { null -> null; "1" -> tx("aktif", "on"); "0" -> tx("tidak aktif", "off"); else -> "N/A" })
                DRow(tx("Pengatur CPU", "CPU owner"), diagVal(m, "cpu_owner"))
            }
        } else missing = true

        val tempKeys = listOf("soc_temp_c", "batt_temp_c", "thermal_warm_c")
        if (tempKeys.any { m.containsKey(it) }) {
            Section(tx("SUHU", "TEMPERATURE"), 0) {
                DRow(tx("SoC", "SoC"), diagVal(m, "soc_temp_c", " °C"))
                DRow(tx("Baterai", "Battery"), diagVal(m, "batt_temp_c", " °C"))
                DRow(tx("Ambang hangat", "Warm limit"), diagVal(m, "thermal_warm_c", " °C"))
            }
        } else missing = true

        val fpsKeys = listOf("fps_avg", "fps_p1", "stall_ms", "frames", "fps_src")
        if (fpsKeys.any { m.containsKey(it) }) {
            Section(tx("FPS", "FPS"), 0) {
                DRow(tx("Rata-rata", "Average"), diagVal(m, "fps_avg"))
                DRow(tx("1% terendah", "1% low"), diagVal(m, "fps_p1"))
                DRow(tx("Jeda terpanjang", "Longest stall"), diagVal(m, "stall_ms", " ms"))
                DRow(tx("Jumlah frame", "Frames"), diagVal(m, "frames"))
                DRow(tx("Sumber", "Source"), diagVal(m, "fps_src"))
                val note = m["fps_src"]?.let { diagFpsNote(it) }
                if (note != null) DNote(note)
                DNote(tx("Dihitung dari jendela 10 detik terakhir.", "Computed over the last 10 seconds."))
            }
        } else missing = true

        val applyKeys = listOf("apply_applied", "apply_skipped", "apply_failed")
        if (applyKeys.any { m.containsKey(it) }) {
            Section(tx("TWEAK DITERAPKAN", "APPLY"), 0) {
                DRow(tx("Berhasil", "Applied"), diagVal(m, "apply_applied"))
                DRow(tx("Dilewati", "Skipped"), diagVal(m, "apply_skipped"))
                DRow(tx("Gagal", "Failed"), diagVal(m, "apply_failed"))
                DNote(tx("Dari 500 baris log terakhir.", "From the last 500 log lines."))
            }
        } else missing = true

        val w = m["warn"]
        if (w != null) {
            Section(tx("PERINGATAN", "WARNINGS"), 0) {
                val list = w.split(',').map { it.trim() }.filter { it.isNotEmpty() && it != "none" && it != "na" }
                if (list.isEmpty()) {
                    SText(if (w == "na") "N/A" else tx("Tidak ada peringatan.", "No warnings."), 12.sp, SP.text)
                } else for (x in list) Text("• " + diagWarnText(x), color = SP.red, fontSize = 12.sp, lineHeight = 15.sp)
            }
        } else missing = true

        if (missing) DNote(tx("Modul lama, perbarui.", "Old module, please update."), SP.red)
        Spacer(Modifier.height(4.dp))
    }
}
