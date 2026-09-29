package com.hsin.data.state

import com.hsin.data.cache.CapabilityCachePolicy
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Siklus refresh capability: cache HIT/MISS dan Konsekuensi ke dirty state.
 *
 * Test ini memakai [CapabilityCachePolicy] (murni) + [KnobsMapping] (murni)
 * lewat fungsi yang sama dengan yang dipakai ViewModel, sehingga tidak
 * butuh Android. Yang diuji: HIT tidak memanggil root, MISS memanggilnya,
 * dan override user tidak hilang saat base di-refresh.
 */
class CapabilityRefreshTest {

    /** [name] sudah memuat ekstensi `.txt`. */
    private fun fixture(name: String): String {
        val s = javaClass.getResourceAsStream("/fixtures/$name")
            ?: error("fixture $name tidak ada")
        return s.bufferedReader().use { it.readText() }.trim().lines().last()
    }

    /** Simulasi siklus refresh capability dengan cache di memori. */
    private class FakeCache {
        var stored: String? = null
        var putCount = 0
        var clearCount = 0

        fun get(token: String): CapabilityCachePolicy.Decision =
            CapabilityCachePolicy.evaluate(stored, token)

        fun put(token: String, knobsJson: String) {
            putCount++
            if (CapabilityCachePolicy.evaluate(stored, token) is CapabilityCachePolicy.Decision.Hit) return
            stored = CapabilityCachePolicy.build(token, knobsJson)
        }

        fun clear() {
            clearCount++
            stored = null
        }
    }

    @Test
    fun firstRefreshIsMissThenSecondIsHit() {
        val cache = FakeCache()
        val token = "knobs_v1_app_1.0"
        val knobsJson = fixture("knobs_sandbox.txt")

        // Siklus 1: cache kosong -> MISS -> baca dari root lalu simpan
        val first = CapabilityCachePolicy.evaluate(cache.get(token).let {
            if (it is CapabilityCachePolicy.Decision.Hit) "hit" else "miss"
        }, token)
        assertTrue("siklus pertama harus MISS", first is CapabilityCachePolicy.Decision.Miss)
        cache.put(token, knobsJson)
        assertEquals(1, cache.putCount)

        // Siklus 2: cache terisi -> HIT, tidak perlu root lagi
        val second = cache.get(token)
        assertTrue("siklus kedua harus HIT", second is CapabilityCachePolicy.Decision.Hit)
        assertEquals("tidak ada penulisan tambahan", 1, cache.putCount)
    }

    @Test
    fun hitYieldsSameCapabilityAsRoot() {
        val cache = FakeCache()
        val token = "knobs_v1_app_1.0"
        val knobs = fixture("knobs_sandbox.txt")
        cache.put(token, knobs)
        val fromRoot = KnobsMapping.parse(JSONObject(knobs), allowExtreme = false)
        val hit = cache.get(token) as CapabilityCachePolicy.Decision.Hit
        val fromCache = KnobsMapping.parse(hit.payload, allowExtreme = false)
        assertEquals("kapabilitas dari cache harus sama dengan dari root", fromRoot.capability, fromCache.capability)
        assertEquals(fromRoot.baseValues, fromCache.baseValues)
    }

    @Test
    fun moduleUpgradeInvalidatesCache() {
        val cache = FakeCache()
        cache.put("knobs_v1_app_1.0", fixture("knobs_sandbox.txt"))
        // Upgrade modul -> v=2
        assertTrue(
            "versi baru harus MISS",
            CapabilityCachePolicy.evaluate(cache.stored, "knobs_v2_app_1.0") is CapabilityCachePolicy.Decision.Miss,
        )
    }

    @Test
    fun invalidateCacheForcesRefetch() {
        val cache = FakeCache()
        val token = "knobs_v1_app_1.0"
        cache.put(token, fixture("knobs_sandbox.txt"))
        assertTrue(cache.get(token) is CapabilityCachePolicy.Decision.Hit)
        cache.clear()
        assertTrue(
            "setelah clear harus MISS",
            cache.get(token) is CapabilityCachePolicy.Decision.Miss,
        )
        assertEquals(1, cache.clearCount)
    }

    @Test
    fun overrideUserSurvivesCapabilityRefresh() {
        val cache = FakeCache()
        val token = "knobs_v1_app_1.0"
        val knobsJson = fixture("knobs_sandbox.txt")
        val parsed = KnobsMapping.parse(JSONObject(knobsJson), allowExtreme = false)

        var dirty: DirtyMap = DirtyTracker.mergeBase(emptyMap(), parsed.baseValues)
        val key = "cpu_policy_0_gov"
        assertFalse("awalnya belum dirty", dirty.getValue(key).dirty)

        // User memilih governor lain
        dirty = DirtyTracker.setOverride(dirty, key, "performance")
        assertTrue(dirty.getValue(key).dirty)

        // Capability di-refresh lagi (mis. user buka layar dan tarik-tarik)
        val parsedAgain = KnobsMapping.parse(JSONObject(knobsJson), allowExtreme = false)
        dirty = DirtyTracker.mergeBase(dirty, parsedAgain.baseValues)
        assertEquals("override user harus bertahan", "performance", dirty.getValue(key).current)
        assertTrue("masih dirty", dirty.getValue(key).dirty)
    }

    @Test
    fun allowExtremeFlipsOnlyCapabilityNotBase() {
        val knobs = JSONObject(fixture("knobs_sandbox.txt"))
        val off = KnobsMapping.parse(knobs, allowExtreme = false).capability
        val on = KnobsMapping.parse(knobs, allowExtreme = true).capability
        assertFalse(off.allowExtreme)
        assertTrue(on.allowExtreme)
        assertEquals("daftar key tidak berubah hanya karena flag", off.supportedKeys, on.supportedKeys)
    }
}
