package com.hsin.data.cache

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Kebijakan cache capability. Logika murni — diuji tanpa Android.
 * Aturan: satu key tetap + versi DI DALAM payload; versi beda, JSON rusak,
 * atau `knobs` kosong = MISS (bukan crash, bukan data basi).
 */
class CapabilityCachePolicyTest {

    private val knobsJson = """{"v":1,"profiles":["manual","balanced"],"cpu":{"supported":true}}"""

    @Test
    fun sameVersionAndValidPayloadIsHit() {
        val raw = CapabilityCachePolicy.build("knobs_v1_app_1.0", JSONObject(knobsJson))
        val d = CapabilityCachePolicy.evaluate(raw, "knobs_v1_app_1.0")
        assertTrue("harus HIT, dapat: $d", d is CapabilityCachePolicy.Decision.Hit)
    }

    @Test
    fun differentModuleVersionIsMiss() {
        val raw = CapabilityCachePolicy.build("knobs_v1_app_1.0", JSONObject(knobsJson))
        val d = CapabilityCachePolicy.evaluate(raw, "knobs_v2_app_1.0")
        assertTrue(d is CapabilityCachePolicy.Decision.Miss)
        assertTrue("alasannya harus menyebut versi", (d as CapabilityCachePolicy.Decision.Miss).reason.contains("versi beda"))
    }

    @Test
    fun differentAppVersionIsMiss() {
        val raw = CapabilityCachePolicy.build("knobs_v1_app_1.0", JSONObject(knobsJson))
        val d = CapabilityCachePolicy.evaluate(raw, "knobs_v1_app_2.0")
        assertTrue(d is CapabilityCachePolicy.Decision.Miss)
    }

    @Test
    fun brokenJsonIsMissNotCrash() {
        val d = CapabilityCachePolicy.evaluate("{bukan json", "knobs_v1_app_1.0")
        assertTrue(d is CapabilityCachePolicy.Decision.Miss)
        assertEquals("json rusak", (d as CapabilityCachePolicy.Decision.Miss).reason)
    }

    @Test
    fun nullOrBlankIsMiss() {
        assertTrue(CapabilityCachePolicy.evaluate(null, "v") is CapabilityCachePolicy.Decision.Miss)
        assertTrue(CapabilityCachePolicy.evaluate("", "v") is CapabilityCachePolicy.Decision.Miss)
        assertTrue(CapabilityCachePolicy.evaluate("   ", "v") is CapabilityCachePolicy.Decision.Miss)
    }

    @Test
    fun missingVersionFieldIsMiss() {
        val d = CapabilityCachePolicy.evaluate("""{"knobs":{"a":1}}""", "knobs_v1_app_1.0")
        assertTrue(d is CapabilityCachePolicy.Decision.Miss)
        assertEquals("versi hilang", (d as CapabilityCachePolicy.Decision.Miss).reason)
    }

    @Test
    fun missingKnobsFieldIsMiss() {
        val raw = """{"v":"knobs_v1_app_1.0"}"""
        val d = CapabilityCachePolicy.evaluate(raw, "knobs_v1_app_1.0")
        assertTrue(d is CapabilityCachePolicy.Decision.Miss)
    }

    @Test
    fun emptyKnobsObjectIsMiss() {
        val raw = CapabilityCachePolicy.build("tok", JSONObject())
        val d = CapabilityCachePolicy.evaluate(raw, "tok")
        assertTrue("knobs kosong = MISS", d is CapabilityCachePolicy.Decision.Miss)
    }

    @Test
    fun keyIsConstantSoOldVersionsDoNotAccumulate() {
        // Versi disimpan di payload, bukan di nama key: upgrade modul tidak
        // menyisakan entri lama menumpuk.
        assertEquals("hsin_capability", CapabilityCachePolicy.KEY)
        val a = CapabilityCachePolicy.build("tok_v1", JSONObject(knobsJson))
        val b = CapabilityCachePolicy.build("tok_v2", JSONObject(knobsJson))
        // v1 -> miss setelah v2 tersimpan
        assertTrue(CapabilityCachePolicy.evaluate(a, "tok_v2") is CapabilityCachePolicy.Decision.Miss)
        assertTrue(CapabilityCachePolicy.evaluate(b, "tok_v2") is CapabilityCachePolicy.Decision.Hit)
    }

    @Test
    fun hitPayloadKeepsKnobsContent() {
        val raw = CapabilityCachePolicy.build("tok", JSONObject(knobsJson))
        val hit = CapabilityCachePolicy.evaluate(raw, "tok") as CapabilityCachePolicy.Decision.Hit
        assertTrue("payload harus memuat profil manual", hit.payload.toString().contains("manual"))
    }
}
