package com.hsin.data.cache

import org.json.JSONObject

/**
 * Keputusan cache capability — logika murni (tanpa Android) supaya bisa
 * diuji di JVM biasa.
 *
 * Aturan:
 * - Satu key tetap, versi modul disimpan DI DALAM payload (bukan di nama
 *   key). Kalau versi disimpan di nama key, setiap upgrade meninggalkan
 *   entri lama menumpuk tanpa pernah dibersihkan.
 * - Versi payload ≠ versi sekarang → MISS (cache diabaikan, ditimpa).
 * - JSON rusak / kosong / tanpa `knobs` → MISS, tidak melempar exception.
 * - Yang disimpan hanya hasil `knobs`, tidak pernah `capabilities`
 *   (kontrak §3.9: `capabilities` tidak bisa disandbox dan bukan sumber
 *   kebenaran).
 */
object CapabilityCachePolicy {

    const val KEY = "hsin_capability"
    const val FIELD_VERSION = "v"
    const val FIELD_KNOBS = "knobs"

    sealed class Decision {
        /** Cache dipakai; [payload] adalah isi `knobs` apa adanya. */
        data class Hit(val payload: JSONObject) : Decision()

        /** Cache tidak dipakai. [reason] hanya untuk log/diagnostik. */
        data class Miss(val reason: String) : Decision()
    }

    /**
     * Bentuk payload cache. [token] sudah memuat versi skema knob dan
     * versi app oleh pemanggil.
     */
    fun build(token: String, knobs: JSONObject): String =
        JSONObject()
            .put(FIELD_VERSION, token)
            .put(FIELD_KNOBS, knobs)
            .toString()

    fun evaluate(raw: String?, currentVersion: String): Decision {
        if (raw.isNullOrBlank()) return Decision.Miss("kosong")
        val obj = try {
            JSONObject(raw)
        } catch (_: Exception) {
            return Decision.Miss("json rusak")
        }
        val version = obj.optString(FIELD_VERSION)
        if (version.isBlank()) return Decision.Miss("versi hilang")
        if (version != currentVersion) {
            return Decision.Miss("versi beda: cache=$version sekarang=$currentVersion")
        }
        if (!obj.has(FIELD_KNOBS)) return Decision.Miss("field knobs hilang")
        val knobs = obj.optJSONObject(FIELD_KNOBS) ?: return Decision.Miss("knobs bukan objek")
        if (knobs.length() == 0) return Decision.Miss("knobs kosong")
        return Decision.Hit(knobs)
    }
}
