package com.hsin.data.cache

import android.content.Context
import android.content.SharedPreferences

/**
 * Cache capability lokal — SharedPreferences, TANPA database.
 * Key menyertakan versi modul; `clear()` eksplisit; JSON rusak/versi beda → MISS (bukan crash).
 * Tidak menyimpan `capabilities` (kontrak §3.9); hanya `knobs` hasil.
 */
class CapabilityCache(private val prefs: SharedPreferences) {

    private val KEY = "hsin_capability"

    fun put(version: String, jsonPayload: String) {
        // Satu key tetap; versi disimpan dalam payload. Versi lama otomatis tertimpa.
        prefs.edit().putString(KEY, "{\"v\":\"$version\",\"cap\":$jsonPayload}").apply()
    }

    fun get(version: String): String? {
        val raw = prefs.getString(KEY, null) ?: return null
        val decision = CapabilityCachePolicy.evaluate(raw, version)
        return if (decision is CapabilityCachePolicy.CacheDecision.HIT) raw else null
    }

    fun clear() {
        prefs.edit().remove(KEY).apply()
    }

    companion object {
        fun create(context: Context): CapabilityCache =
            CapabilityCache(context.getSharedPreferences("hsin_capability", Context.MODE_PRIVATE))
    }
}
