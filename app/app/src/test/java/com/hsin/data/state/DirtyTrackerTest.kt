package com.hsin.data.state

import org.junit.Assert.*
import org.junit.Test

class DirtyTrackerTest {

    @Test
    fun setOverrideMakesDirty_andCurrentChanges() {
        val tracker = DirtyTracker(base = mapOf("cpu_gov" to "schedutil"))
        tracker.setOverride("cpu_gov", "performance")
        val s = tracker.state()["cpu_gov"]!!
        assertEquals("schedutil", s.base)
        assertEquals("performance", s.current)
        assertTrue(s.dirty)
    }

    @Test
    fun resetToBaseMakesCleanButKeepsEntry() {
        val tracker = DirtyTracker(base = mapOf("cpu_gov" to "schedutil"))
        tracker.setOverride("cpu_gov", "performance")
        tracker.resetKey("cpu_gov")
        val s = tracker.state()["cpu_gov"]!!
        assertEquals("schedutil", s.current)
        assertFalse(s.dirty)
        assertTrue(tracker.state().containsKey("cpu_gov")) // entry tetap ada
    }

    @Test
    fun resetAllClears() {
        val tracker = DirtyTracker(base = mapOf("a" to "1"))
        tracker.setOverride("a", "2")
        tracker.resetAll()
        assertTrue(tracker.state().isEmpty() || tracker.state()["a"]!!.current == "1")
    }

    @Test
    fun baseNotChangedByEdit() {
        val tracker = DirtyTracker(base = mapOf("k" to "v0"))
        tracker.setOverride("k", "v1")
        assertEquals("v0", tracker.state()["k"]!!.base)
    }
}
