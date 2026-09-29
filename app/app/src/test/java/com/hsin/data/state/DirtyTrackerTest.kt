package com.hsin.data.state

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Dirty tracking. Semua assertion memanggil kode produksi
 * ([DirtyTracker]); tidak ada logika produksi yang disalin ke dalam test.
 */
class DirtyTrackerTest {

    private fun baseState() = mapOf(
        "cpu_policy_0_gov" to DirtyEntry("schedutil", "schedutil"),
        "io_block_sda_sched" to DirtyEntry("mq-deadline", "mq-deadline"),
    )

    @Test
    fun setOverrideMarksDirtyAndKeepsBase() {
        val s = DirtyTracker.setOverride(baseState(), "cpu_policy_0_gov", "performance")
        val e = s.getValue("cpu_policy_0_gov")
        assertEquals("performance", e.current)
        assertEquals("base tidak boleh berubah karena edit user", "schedutil", e.base)
        assertTrue(e.dirty)
        assertEquals(1, DirtyTracker.dirtyCount(s))
    }

    @Test
    fun setOverrideToSameValueIsNotDirty() {
        val s = DirtyTracker.setOverride(baseState(), "cpu_policy_0_gov", "schedutil")
        assertFalse(s.getValue("cpu_policy_0_gov").dirty)
        assertEquals(0, DirtyTracker.dirtyCount(s))
    }

    @Test
    fun resetKeyKeepsEntryAndClearsDirty() {
        val dirty = DirtyTracker.setOverride(baseState(), "cpu_policy_0_gov", "performance")
        val after = DirtyTracker.resetKey(dirty, "cpu_policy_0_gov")
        val e = after.getValue("cpu_policy_0_gov")
        assertTrue("entry harus tetap ada setelah reset", after.containsKey("cpu_policy_0_gov"))
        assertEquals("current kembali ke base", "schedutil", e.current)
        assertFalse("dirty harus false", e.dirty)
        assertEquals(0, DirtyTracker.dirtyCount(after))
    }

    @Test
    fun resetAllClearsEveryDirtyButKeepsAllKeys() {
        val dirty = DirtyTracker.setOverride(
            DirtyTracker.setOverride(baseState(), "cpu_policy_0_gov", "performance"),
            "io_block_sda_sched", "none",
        )
        assertEquals(2, DirtyTracker.dirtyCount(dirty))
        val after = DirtyTracker.resetAll(dirty)
        assertEquals(0, DirtyTracker.dirtyCount(after))
        assertEquals("semua key harus tetap ada", 2, after.size)
        assertEquals("mq-deadline", after.getValue("io_block_sda_sched").current)
    }

    @Test
    fun resetKeyOnUnknownKeyIsNoOp() {
        val s = baseState()
        assertEquals(s, DirtyTracker.resetKey(s, "tidak_ada"))
    }

    @Test
    fun mergeBaseKeepsUserOverrideAndAddsNewKeys() {
        val dirty = DirtyTracker.setOverride(baseState(), "cpu_policy_0_gov", "performance")
        val newBase = mapOf(
            "cpu_policy_0_gov" to "powersave",   // nilai sistem berubah
            "vfs_cache_pressure" to "100",       // key baru
        )
        val merged = DirtyTracker.mergeBase(dirty, newBase)
        val gov = merged.getValue("cpu_policy_0_gov")
        assertEquals("override user tidak boleh ditimpa", "performance", gov.current)
        assertTrue("base ikut diperbarui", gov.dirty)
        assertEquals("100", merged.getValue("vfs_cache_pressure").current)
        assertFalse("key baru belum diubah", merged.getValue("vfs_cache_pressure").dirty)
    }

    @Test
    fun mergeBaseDropsKeysNoLongerOnDevice() {
        val dirty = baseState()
        val merged = DirtyTracker.mergeBase(dirty, mapOf("cpu_policy_0_gov" to "schedutil"))
        assertFalse("key yang hilang dari device dibuang", merged.containsKey("io_block_sda_sched"))
    }

    @Test
    fun dirtyKeysAreSortedForStableUi() {
        var s = DirtyTracker.setOverride(baseState(), "io_block_sda_sched", "none")
        s = DirtyTracker.setOverride(s, "cpu_policy_0_gov", "performance")
        assertEquals(
            listOf("cpu_policy_0_gov", "io_block_sda_sched"),
            DirtyTracker.dirtyKeys(s),
        )
    }

    @Test
    fun withBaseAddsKeyWithoutMarkingDirty() {
        val s = DirtyTracker.withBase(baseState(), "tfo", "3")
        assertEquals("3", s.getValue("tfo").current)
        assertFalse(s.getValue("tfo").dirty)
    }
}
