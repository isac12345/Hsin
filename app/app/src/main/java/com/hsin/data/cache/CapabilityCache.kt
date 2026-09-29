package com.hsin.data.cache

import android.content.Context
import android.content.SharedPreferences
import org.json.JSONObject

/**
 * Cache capability lokal. [SharedPreferences], tanpa database.
 *
 * Semua keputusan HIT/MISS ada di [CapabilityCachePolicy] (murni, teruji
 * lokal); kelas ini hanya menjembatani ke storage Android.
 */
class CapabilityCache(private val prefs: SharedPreferences) {

    fun get(currentVersion: String): CapabilityCachePolicy.Decision =
        CapabilityCachePolicy.evaluate(prefs.getString(CapabilityCachePolicy.KEY, null), currentVersion)

    /**
     * Simpan hasil `knobs` untuk versi [moduleVersion]. Tidak menimpa cache
     * yang lebih baru (kalau ada probe paralel, hasil lama tidak boleh
     * menimpa hasil baru).
     */
    fun put(token: String, knobs: JSONObject) {
        val existing = CapabilityCachePolicy.evaluate(
            prefs.getString(CapabilityCachePolicy.KEY, null),
            token
        )
        if (existing is CapabilityCachePolicy.Decision.Hit) return
        prefs.edit()
            .putString(CapabilityCachePolicy.KEY, CapabilityCachePolicy.build(token, knobs))
            .apply()
    }

    /** Buang cache (permintaan refresh user). */
    fun clear() {
        prefs.edit().remove(CapabilityCachePolicy.KEY).apply()
    }

    companion object {
        fun create(context: Context): CapabilityCache =
            CapabilityCache(context.getSharedPreferences("hsin_cache", Context.MODE_PRIVATE))
    }
}
