package com.hsin.data.state

/**
 * Dirty tracking knob — tiga nilai per key: base / current / dirty.
 * Edit bertahan saat rotasi karena ViewModel di-scope activity (`viewModel()`),
 * bukan `remember {}`.
 */
class DirtyTracker(private val base: Map<String, String> = emptyMap()) {

    private val overrides = mutableMapOf<String, String>()

    fun setOverride(key: String, value: String) {
        overrides[key] = value
    }

    fun resetKey(key: String) {
        overrides.remove(key)
    }

    fun resetAll() {
        overrides.clear()
    }

    fun state(): Map<String, DirtyEntry> {
        val result = mutableMapOf<String, DirtyEntry>()
        val allKeys = base.keys + overrides.keys
        for (k in allKeys) {
            val b = base[k] ?: ""
            val c = overrides[k] ?: b
            result[k] = DirtyEntry(base = b, current = c, dirty = c != b)
        }
        return result.toMap()
    }

    fun isDirty(key: String): Boolean = state()[key]?.dirty == true
}
