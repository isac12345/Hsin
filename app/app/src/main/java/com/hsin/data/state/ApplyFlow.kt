package com.hsin.data.state

import com.hsin.data.repository.HsinRepository
import com.hsin.data.root.RootClient
import com.hsin.data.root.RootError
import com.hsin.data.root.RootResult

/**
 * Alur Terapkan A10 (murni, tanpa Android).
 *
 * Kontrak (docs/APP_CONTRACT.md):
 * - §2: app mengirim N× `knob-set <key> <val>` lalu 1× `apply manual`.
 *   `apply` berjalan background ("OK: Applying ... (running in
 *   background...)"), jadi hasil BUKAN rc apply melainkan bacaan
 *   `knob-list` sesudahnya (§3.11, §5 butir 2).
 * - §3.11: tiap baris hasil `key=<k> requested=<r> applied=<a>
 *   category=<c> reason="<alasan>"`, kategori ∈
 *   APPLIED|SKIPPED|FALLBACK|UNAVAILABLE|FAILED (§4).
 * - §5 butir 5: rc=0 + `Usage:` = COMMAND_FAILED; modul tak pernah
 *   mengembalikan TIMEOUT/ROOT_UNAVAILABLE/MODULE_NOT_FOUND (transport APK).
 *
 * Aturan A10:
 * - Hanya knob dirty yang dikirim (via [DirtyTracker.dirtyKeys]).
 * - Hasil dibaca PER KNOB dari modul; sukses parsial = sebagian APPLIED,
 *   sebagian FAILED — bukan satu status global.
 * - Tidak ada klaim sukses dari rc semata.
 * - Fungsi ini suspend tapi tidak menyentuh main thread sendiri;
 *   pemanggil (ViewModel) menjalankannya di `viewModelScope.launch`
 *   sehingga UI tidak freeze (RootClient sudah `Dispatchers.IO`).
 */
object ApplyFlow {

    /** Hasil alur apply. */
    sealed class Outcome {
        /** Tidak ada knob dirty — tidak ada root call. */
        data object Empty : Outcome()

        /** Siklus selesai; [results] langsung dari modul (per knob). */
        data class Completed(val results: List<HsinRepository.KnobResult>) : Outcome()

        /**
         * Siklus gagal di level transport/parse; [partial] berisi hasil
         * per-knob yang sempat terkumpul (mis. knob-set yang ditolak),
         * bisa kosong bila gagal sebelum ada hasil apa pun.
         */
        data class Failed(
            val error: RootError,
            val reason: String,
            val partial: List<HsinRepository.KnobResult> = emptyList(),
        ) : Outcome()
    }

    /**
     * Jalankan siklus apply untuk knob dirty.
     *
     * @param profile profil untuk `apply` — selalu `"manual"` di HSIN
     *   (mode manual murni M1/M1b; modul tidak menulis knob tanpa override).
     */
    suspend fun apply(
        root: RootClient,
        dirty: DirtyMap,
        profile: String = "manual",
    ): Outcome {
        val keys = DirtyTracker.dirtyKeys(dirty)
        if (keys.isEmpty()) return Outcome.Empty

        val synthetic = mutableListOf<HsinRepository.KnobResult>()

        // 1) N× knob-set, hanya untuk knob dirty (allowlist A6).
        for (key in keys) {
            val value = dirty.getValue(key).current
            when (val res = root.execute("knob-set", listOf(key, value))) {
                is RootResult.Success -> Unit // override tersimpan; hasil final dari knob-list
                is RootResult.Error -> {
                    // Modul menolak (rc=1 ERROR:) atau transport gagal.
                    // Catat per knob sebagai FAILED — jangan mengarang APPLIED.
                    // Kalau transport mati total (ROOT_UNAVAILABLE /
                    // MODULE_NOT_FOUND / TIMEOUT), hentikan siklus.
                    if (res.type == RootError.ROOT_UNAVAILABLE ||
                        res.type == RootError.MODULE_NOT_FOUND ||
                        res.type == RootError.TIMEOUT
                    ) {
                        return Outcome.Failed(res.type, res.message, synthetic.toList())
                    }
                    synthetic.add(
                        HsinRepository.KnobResult(
                            key = key,
                            requested = value,
                            applied = "-",
                            category = "FAILED",
                            reason = res.message,
                        )
                    )
                }
            }
        }

        // 2) 1× apply. rc=0 hanya berarti "diterima/background",
        //    BUKAN bukti tiap knob sukses.
        when (val res = root.execute("apply", listOf(profile))) {
            is RootResult.Success -> Unit
            is RootResult.Error -> return Outcome.Failed(res.type, res.message, synthetic.toList())
        }

        // 3) Baca hasil PER KNOB dari modul.
        val listRes = root.execute("knob-list")
        when (listRes) {
            is RootResult.Error -> return Outcome.Failed(listRes.type, listRes.message, synthetic.toList())
            is RootResult.Success -> {
                when (val parsed = HsinRepository.parseKnobList(listRes.output)) {
                    is HsinRepository.KnobParseResult.InvalidResponse ->
                        return Outcome.Failed(
                            RootError.INVALID_RESPONSE,
                            parsed.reason,
                            synthetic.toList(),
                        )
                    is HsinRepository.KnobParseResult.Ok -> {
                        // Gabung: synthetic FAILED (knob-set ditolak) menimpa
                        // baris modul untuk key itu — modul tidak menerima
                        // override-nya, jadi baris modul (SKIPPED lama) akan
                        // menutupi kegagalan bila tidak ditimpa.
                        if (synthetic.isEmpty()) return Outcome.Completed(parsed.items)
                        val byKey = parsed.items.associateBy { it.key }.toMutableMap()
                        for (s in synthetic) byKey[s.key] = s
                        return Outcome.Completed(byKey.values.sortedBy { it.key })
                    }
                }
            }
        }
    }
}
