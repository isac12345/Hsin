package com.hsin.data.cache

import org.junit.Assert.*
import org.junit.Test

class CapabilityCachePolicyTest {

    @Test
    fun versionSameAndValidJson_isHit() {
        val json = "{\"v\":\"v1\",\"cap\":{\"cpu\":true}}"
        val d = CapabilityCachePolicy.evaluate(json, "v1")
        assertTrue(d is CapabilityCachePolicy.CacheDecision.HIT)
    }

    @Test
    fun versionDifferent_isMiss() {
        val d = CapabilityCachePolicy.evaluate("{\"v\":\"v2\",\"cap\":{}}", "v1")
        assertTrue(d is CapabilityCachePolicy.CacheDecision.MISS)
    }

    @Test
    fun brokenJson_isMissNotCrash() {
        val d = CapabilityCachePolicy.evaluate("{bad", "v1")
        assertTrue(d is CapabilityCachePolicy.CacheDecision.MISS)
    }

    @Test
    fun blankString_isMiss() {
        assertTrue(CapabilityCachePolicy.isCacheMiss(CapabilityCachePolicy.evaluate("", "v1")))
    }

    @Test
    fun capMissing_isStillHitIfVersionMatches() {
        // Cache menyimpan data meski capa tidak lengkap
        val d = CapabilityCachePolicy.evaluate("{\"v\":\"v1\"}", "v1")
        assertTrue(d is CapabilityCachePolicy.CacheDecision.HIT)
    }

    @Test
    fun clearImpliesMiss() {
        // Simulasi: after clear, get returns null → treated as MISS by caller
        assertTrue(CapabilityCachePolicy.isCacheMiss(CapabilityCachePolicy.CacheDecision.MISS))
    }
}
