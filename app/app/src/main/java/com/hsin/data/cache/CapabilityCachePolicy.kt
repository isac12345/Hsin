package com.hsin.data.cache

import org.json.JSONObject

/**
 * Logika cache capability — murni JVM, bisa diuji lokal tanpa Android.
 * Aturan: key menyertakan versi modul; JSON rusak / versi beda → MISS;
 * `clear()` eksplisit; tidak menyimpan `capabilities`; serialisasi `org.json`.
 */
object CapabilityCachePolicy {

    fun buildKey(moduleVersion: String): String = "hsin_capability_cache_v$moduleVersion"

    /** Keputusan cache berdasarkan input string + versi. */
    fun evaluate(rawJson: String?, moduleVersion: String): CacheDecision {
        if (rawJson == null || rawJson.isBlank()) return CacheDecision.MISS
        return try {
            val obj = JSONObject(rawJson)
            val v = obj.optString("v", "")
            if (v != moduleVersion) return CacheDecision.MISS
            val cap = obj.optJSONObject("cap") ?: obj
            CacheDecision.HIT(cap.toString())
        } catch (_: Exception) {
            CacheDecision.MISS
        }
    }

    fun isCacheHit(decision: CacheDecision): Boolean = decision is CacheDecision.HIT
    fun isCacheMiss(decision: CacheDecision): Boolean = decision is CacheDecision.MISS

    sealed class CacheDecision {
        data class HIT(val payload: String) : CacheDecision()
        object MISS : CacheDecision()
    }
}
