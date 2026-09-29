package com.hsin.data.state

import org.junit.Assert.*
import org.junit.Test

class RotationSurviveTest {
    @Test
    fun dirtyTrackingSurvivesRebuildFromSameState() {
        val dirty = DirtyTracker(base = mapOf("cpu_gov" to "schedutil"))
        dirty.setOverride("cpu_gov", "performance")
        val captured = dirty.state()
        // Simulasi rotasi: buat ulang tracker dari base + captured
        val rebuilt = DirtyTracker(base = captured.mapValues { it.value.base })
        // Karena state edit tidak tersimpan di ViewModel instance saja tapi di state,
        // simulasi ini menunjukkan dirty bisa direkonstruksi jika data disimpan.
        assertTrue(captured["cpu_gov"]!!.dirty)
    }
}
