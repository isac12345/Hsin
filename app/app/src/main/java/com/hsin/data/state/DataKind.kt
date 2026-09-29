package com.hsin.data.state

/**
 * EMPAT SIFAT DATA — pemisahan tegas agar ViewModel tahu mana yang
 * tidak perlu di-refresh tiap tick (aturan A7 §2, kontrak §4).
 *
 * - Static: versi, id, list command — jarang berubah.
 * - Capability: apa yang device dukung (`knobs`, bukan `capabilities`
 *   karena capabilities tak bisa disandbox dan bukan sumber kebenaran —
 *   kontrak §3.9, D3). Klik ini menyimpan hanya hasil `knobs`.
 * - CurrentState: profil aktif, override user, guard status, knob results.
 * - Realtime: suhu, frekuensi, beban, FPS — berubah tiap detik.
 */

/** Penanda statis — tidak berubah selama session. */
interface StaticData

/** Penanda kemampuan device (dari `knobs`, bukan `capabilities`). */
interface CapabilityData

/** Penanda kondisi saat ini (edit user, guard, hasil). */
interface CurrentStateData

/** Penanda metrik realtime — perlu refresh terpisah. */
interface RealtimeData

/** Data statis modul (versi, id, command list). */
data class ModuleStatic(
    val moduleVersion: String,
    val moduleId: String,
    val allowedCommands: List<String>
) : StaticData

/** Capability hasil `knobs` (tanpa `capabilities`). */
data class KnobCapability(
    val cpuSupported: Boolean,
    val gpuSupported: Boolean,
    val memorySupported: Boolean,
    val ioSupported: Boolean,
    val networkSupported: Boolean,
    val displaySupported: Boolean,
    val profileList: List<String>
) : CapabilityData

/** Hasil knob-list (current state per key). */
data class KnobCurrent(
    val key: String,
    val requested: String,
    val applied: String,
    val category: String,
    val reason: String
) : CurrentStateData

/** Metrik realtime (berubah tiap tick). Sentinel A11: nilai -1 atau 0 tidak terbaca → null. */
data class RealtimeMetrics(
    val temperatureC: Int?,
    val frequencyMhz: Int?,
    val loadPercent: Int?,
    val fps: Int?
) : RealtimeData
