package com.hsin.ui.knobs

/**
 * Baris UI untuk layar Knobs.
 *
 * Model ini datar (satu daftar, tanpa daftar bersarang) karena adaptor
 * RecyclerView hanya boleh memetakan position -> tepat satu tipe baris.
 * Versi sebelumnya memakai daftar bersarang + cast antar-tipe, yang
 * berakhir jadi header yang dirender sebagai isi (atau sebaliknya).
 *
 * [sink] menentukan ke mana pilihan user dikirim:
 *  - [Sink.KNOB]  -> `action.sh knob-set <id> <value>` (value bebas, tulis
 *                    ke $HSIN_DATA/user_knobs.env, dibaca saat apply).
 *  - [Sink.CONFIG]-> `action.sh config-set <id> <value>` (hanya 7 kunci
 *                    yang di-whitelist modul; id harus salah satunya).
 */
sealed interface KnobRow {
    val id: String

    data class Header(val title: String) : KnobRow {
        override val id: String get() = "header:$title"
    }

    data class Choice(
        override val id: String,
        val title: String,
        val options: List<String>,
        val selectedIndex: Int,
        val enabled: Boolean = true,
        val sink: Sink = Sink.KNOB,
        val hint: String? = null
    ) : KnobRow

    data class Toggle(
        override val id: String,
        val title: String,
        val checked: Boolean,
        val enabled: Boolean = true,
        val sink: Sink = Sink.CONFIG,
        val hint: String? = null
    ) : KnobRow

    /** Nilai yang hanya bisa dibaca (belum ada jalur tulis di modul). */
    data class ReadOnly(val title: String, val value: String) : KnobRow {
        override val id: String get() = "ro:$title:$value"
    }

    enum class Sink { KNOB, CONFIG }
}
