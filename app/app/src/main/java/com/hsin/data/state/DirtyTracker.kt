package com.hsin.data.state

import com.hsin.data.repository.HsinRepository

/**
 * Dirty tracking knob.
 *
 * [base] = nilai yang dibaca dari sistem/profil (tidak pernah berubah karena
 * user mengedit). [current] = nilai yang DIINGINKAN user (override), atau
 * nilai base bila belum ada override. Menghapus override selalu mengembalikan
 * `current` ke `base` — key TIDAK pernah hilang dari peta, supaya UI tetap
 * menampilkan baris knob-nya dengan label "tidak diubah".
 *
 * Bersifat immutable dari luar: setiap aksi mengembalikan peta baru.
 */
object DirtyTracker {

    /** Terapkan override pada satu key. */
    fun setOverride(state: DirtyMap, key: String, value: String): DirtyMap {
        val base = state[key]?.base ?: value
        return state + (key to DirtyEntry(base = base, current = value))
    }

    /** Buang override satu key: `current` kembali ke `base`, entry tetap ada. */
    fun resetKey(state: DirtyMap, key: String): DirtyMap {
        val entry = state[key] ?: return state
        return state + (key to entry.copy(current = entry.base))
    }

    /** Buang SEMUA override; tiap key kembali ke base-nya. */
    fun resetAll(state: DirtyMap): DirtyMap =
        state.mapValues { (_, e) -> e.copy(current = e.base) }

    /** Set key baru yangbelum ada di peta (mis. setelah `knobs` dibaca). */
    fun withBase(state: DirtyMap, key: String, base: String): DirtyMap {
        val existing = state[key]
        return state + (key to DirtyEntry(base = base, current = existing?.current ?: base))
    }

    /**
     * Gabung peta base baru (hasil baca `knobs`) dengan state yang ada.
     *
     * - Key yang sudah punya entri: [DirtyEntry] lama dipertahankan utuh,
     *   jadi override user tidak hilang saat capability di-refresh.
     * - Key baru: masuk dengan `current = base` (belum diubah).
     * - Key yang hilang dari device: tetap dibuang — knob itu sudah tidak
     *   relevan, dan mengirimkannya akan ditolak modul (rc=1).
     */
    fun mergeBase(state: DirtyMap, newBase: Map<String, String>): DirtyMap {
        if (newBase.isEmpty()) return state
        val out = LinkedHashMap<String, DirtyEntry>(newBase.size + state.size)
        for ((key, baseValue) in newBase) {
            val existing = state[key]
            out[key] = existing?.copy(base = baseValue) ?: DirtyEntry(base = baseValue, current = baseValue)
        }
        return out
    }

    /** Key yang berubah, terurut — untuk label "Terapkan (N)" di A10. */
    fun dirtyKeys(state: DirtyMap): List<String> =
        state.entries.filter { it.value.dirty }.map { it.key }.sorted()

    fun dirtyCount(state: DirtyMap): Int = dirtyKeys(state).size

    /**
     * Sesudah apply (A10): reset base ke nilai baru HANYA untuk knob yang
     * modul laporkan APPLIED. FAILED/SKIPPED/UNAVAILABLE TIDAK di-reset —
     * nilai lama tetap jadi acuan "SAAT INI" supaya user bisa coba lagi.
     *
     * - APPLIED: base = applied modul (bila `-`/kosong pakai requested),
     *   current ikut base sehingga tidak dirty lagi.
     * - FALLBACK: sistem kini bernilai applied (Y) sementara user meminta
     *   X — base = applied, current tetap requested sehingga masih dirty
     *   dan badge FALLBACK tetap terlihat (jujur: belum sesuai permintaan).
     * - Lainnya: tidak disentuh.
     *
     * Hanya key yang ada di [state] yang diperbarui; baris hasil untuk key
     * yang sudah hilang dari device diabaikan.
     */
    fun confirmApplied(
        state: DirtyMap,
        results: List<HsinRepository.KnobResult>,
    ): DirtyMap {
        if (state.isEmpty() || results.isEmpty()) return state
        var out = state
        for (r in results) {
            val entry = out[r.key] ?: continue
            when (r.category) {
                "APPLIED" -> {
                    val newBase = when {
                        r.applied.isNotBlank() && r.applied != "-" -> r.applied
                        r.requested.isNotBlank() && r.requested != "-" &&
                            !r.requested.startsWith("(") -> r.requested
                        else -> entry.current
                    }
                    out = out + (r.key to DirtyEntry(base = newBase, current = newBase))
                }
                "FALLBACK" -> {
                    if (r.applied.isNotBlank() && r.applied != "-") {
                        out = out + (r.key to entry.copy(base = r.applied))
                    }
                }
                else -> Unit
            }
        }
        return out
    }
}
