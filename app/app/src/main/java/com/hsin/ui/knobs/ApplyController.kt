package com.hsin.ui.knobs

import com.hsin.HsinRepository

/**
 * Hasil Apply: daftar perubahan yang gagal (kosong = semua berhasil).
 */
data class ApplyResult(
    val applied: List<String>,
    val failures: List<Pair<String, String>>
) {
    val isSuccess: Boolean get() = failures.isEmpty()
}

/**
 * Mengirim draft pilihan user ke modul, lalu menjalankan apply.
 *
 * Urutan penting: semua knob/config tersimpan dulu, baru `apply` dipanggil
 * sekali. Kalau apply dipanggil di tengah, modul bisa sempat memakai
 * setengah setting.
 *
 * Nilai Choice untuk knob frekuensi dihapus digit Peninsula-nya
 * (mis. "1800000 kHz" -> "1800000") karena modul hanya menerima angka.
 */
class ApplyController(private val repo: HsinRepository) {

    suspend fun apply(
        profile: String,
        knobs: Map<String, String>,
        configs: Map<String, String>
    ): ApplyResult {
        val applied = mutableListOf<String>()
        val failures = mutableListOf<Pair<String, String>>()

        for ((key, raw) in knobs) {
            val value = normalizeValue(raw)
            val r = runCatching { repo.knobSet(key, value) }
            if (r.isSuccess) applied += "$key=$value" else failures += key to (r.exceptionOrNull()?.message ?: "gagal")
        }
        for ((key, value) in configs) {
            val r = runCatching { repo.configSet(key, value) }
            if (r.isSuccess) applied += "$key=$value" else failures += key to (r.exceptionOrNull()?.message ?: "gagal")
        }

        val applyOutcome = runCatching { repo.apply(profile) }
        if (applyOutcome.isFailure) {
            failures += "apply:$profile" to (applyOutcome.exceptionOrNull()?.message ?: "gagal")
        }
        return ApplyResult(applied, failures)
    }

    /** "1800000 kHz" -> "1800000"; "skia gl" -> "skiagl" (spasi di hostname module). */
    private fun normalizeValue(raw: String): String {
        val trimmed = raw.trim()
        val asNumber = trimmed.substringBefore(' ').trim()
        return if (asNumber.isNotEmpty() && asNumber.all { it.isDigit() }) asNumber else trimmed.replace(" ", "")
    }
}
