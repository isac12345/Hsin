package com.hsin.ui.knob

import com.hsin.data.state.DirtyMap
import com.hsin.data.state.KnobCapability

/**
 * Kategori knob untuk layar Knob.
 *
 * Kategori berasal dari [KnobCapability.supportedKeys] — yaitu dari `knobs`
 * modul. APK TIDAK mengarang daftar kategori: kalau tidak ada key untuk
 * sebuah kategori, kategori itu tidak dibuat. Ini yang membuat knob yang
 * tidak tersedia hilang (bukan tampil dengan nilai karangan).
 */
enum class KnobCategory(val title: String) {
    CPU("CPU"),
    CPU_SCHED("CPU · Scheduler"),
    GPU("GPU"),
    MEMORY("Memori dan VM"),
    IO("I/O"),
    NETWORK("Jaringan"),
    /** Fitur yang dikunci modul; tampil sebagai baris terkunci, bukan kontrol. */
    GATED("Lanjutan (terkunci)"),
}

data class KnobRow(
    val key: String,
    val label: String,
    val kind: KnobKind,
    /** Nilai pilihan yang boleh dipakai; null untuk slider/skalar. */
    val choices: List<String>,
    /** Rentang slider dari `knobs`; hanya untuk [KnobKind.SLIDER]. */
    val range: IntRange?,
    val base: String,
    val current: String,
) {
    val dirty: Boolean get() = current != base
}

enum class KnobKind { CHOICE, SLIDER, TOGGLE, LOCKED }

data class KnobCategoryUi(
    val category: KnobCategory,
    val rows: List<KnobRow>,
    /** Alasan kategori ini tidak punya kontrol (untuk baris terkunci). */
    val lockedReason: String? = null,
) {
    val dirtyCount: Int get() = rows.count { it.dirty }
}

/**
 * Membangun daftar kategori dari capability hasil `knobs`.
 * Murni — tanpa Android, tanpa root, tanpa logika engine.
 */
object KnobCategoryBuilder {

    /**
     * Petakan key knob ke kategori. Urutan kunci penting: pola yang lebih
     * spesifik dicek lebih dulu (`_rate_limit_us` sebelum `_gov`).
     */
    private fun categoryOf(key: String): KnobCategory? = when {
        key.startsWith("cpu_policy_") && key.endsWith("_gov") -> KnobCategory.CPU
        key.startsWith("cpu_policy_") && key.endsWith("_rate_limit_us") -> KnobCategory.CPU
        key.startsWith("cpu_policy_") -> KnobCategory.CPU_SCHED
        key.startsWith("gpu_node_") -> KnobCategory.GPU
        key.startsWith("io_block_") -> KnobCategory.IO
        key in setOf("tcp_cc", "tfo", "backlog") -> KnobCategory.NETWORK
        key in setOf(
            "swappiness", "zram_algo", "vfs_cache_pressure", "dirty_ratio",
            "dirty_background_ratio", "page_cluster", "stat_interval",
        ) -> KnobCategory.MEMORY
        else -> null
    }

    /** Label yang enak dibaca dari key modul. */
    fun labelFor(key: String, base: String): String {
        // `cpu_policy_0_gov` -> "Policy 0 · Governor"
        val parts = key.split("_")
        if (key.startsWith("cpu_policy_") && parts.size >= 4) {
            val id = parts[2]
            val field = parts.drop(3).joinToString(" ").replaceFirstChar { it.uppercase() }
            return "Policy $id · $field"
        }
        if (key.startsWith("gpu_node_")) {
            val rest = key.removePrefix("gpu_node_")
            val idx = rest.lastIndexOf('_')
            if (idx > 0) {
                val node = rest.substring(0, idx).replace('_', '.')
                val field = rest.substring(idx + 1).replaceFirstChar { it.uppercase() }
                return "$node · $field"
            }
        }
        if (key.startsWith("io_block_")) {
            val rest = key.removePrefix("io_block_")
            val idx = rest.lastIndexOf('_')
            if (idx > 0) {
                val blk = rest.substring(0, idx)
                val field = rest.substring(idx + 1).replaceFirstChar { it.uppercase() }
                return "$blk · $field"
            }
        }
        return key.replace('_', ' ').replaceFirstChar { it.uppercase() }
    }

    /**
     * Tentukan jenis kontrol dari nilai yang diizinkan. APK TIDAK memvalidasi
     * governor atau menghitung pemetaan OPP — hanya memilih tampilan berdasarkan
     * bentuk data yang diberikan modul.
     */
    fun kindFor(choices: List<String>, range: IntRange?): KnobKind = when {
        choices.isNotEmpty() -> KnobKind.CHOICE
        range != null && range.first == 0 && range.last == 1 -> KnobKind.TOGGLE
        range != null -> KnobKind.SLIDER
        else -> KnobKind.LOCKED
    }

    /**
     * @param dirty state dari [com.hsin.data.state.DirtyTracker]: key -> base
     *   dan nilai yang diminta user. Sumbu X hanya memakai nilai yang ada di
     *   [KnobCapability]; key lain tidak pernah ditampilkan.
     * @param ranges rentang slider yang dilaporkan `knobs` (disalin apa adanya).
     */
    fun build(
        capability: KnobCapability,
        dirty: DirtyMap,
        ranges: Map<String, IntRange> = capability.ranges,
    ): List<KnobCategoryUi> {
        val grouped = LinkedHashMap<KnobCategory, MutableList<KnobRow>>()
        for (key in capability.supportedKeys) {
            val cat = categoryOf(key) ?: continue
            val entry = dirty[key]
            val base = entry?.base ?: ""
            val current = entry?.current ?: base
            val choices = capability.allowedValues[key].orEmpty()
            val range = ranges[key]
            grouped.getOrPut(cat) { mutableListOf() }.add(
                KnobRow(
                    key = key,
                    label = labelFor(key, base),
                    kind = kindFor(choices, range),
                    choices = choices,
                    range = range,
                    base = base,
                    current = current,
                )
            )
        }
        return KnobCategory.entries.mapNotNull { cat ->
            val rows = grouped[cat] ?: return@mapNotNull null
            KnobCategoryUi(cat, rows.sortedBy { it.key })
        }
    }

    /**
     * Verifikasi bahwa APK tidak melakukan logika engine: nilai slider yang
     * dipilih harus dikirim apa adanya. Fungsi ini hanya mencocokkan string,
     * tidak pernah menghitung atau memvalidasi.
     */
    fun requestedValueFor(row: KnobRow, sliderValue: Float): String =
        when (row.kind) {
            KnobKind.CHOICE -> row.current
            KnobKind.TOGGLE -> if (sliderValue >= 0.5f) "1" else "0"
            KnobKind.SLIDER -> {
                val lo = row.range?.first ?: 0
                val hi = row.range?.last ?: 0
                val snapped = (sliderValue.roundToIntSafe().coerceIn(lo, hi))
                snapped.toString()
            }
            KnobKind.LOCKED -> row.current
        }
}

private fun Float.roundToIntSafe(): Int = kotlin.math.round(this).toInt()
