package com.hsin.data.state

/**
 * Tiga nilai per knob: apa yang di sistem/profil ([base]), apa yang sedang
 * wanted user ([current]), dan apakah keduanya berbeda ([dirty]).
 *
 * Sengaja TIDAK memakai `Boolean` dirty yang disimpan terpisah: `dirty` selalu
 * dihitung dari `base != current`, jadi tidak mungkin tidak sinkron.
 */
data class DirtyEntry(
    val base: String,
    val current: String,
) {
    /** true kalau nilai yang diminta user berbeda dari nilai sistem. */
    val dirty: Boolean get() = current != base
}

/** Peta key -> [DirtyEntry] pada satu titik waktu. */
typealias DirtyMap = Map<String, DirtyEntry>
