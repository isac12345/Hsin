# HSIN Roadmap → 10/10 (Capability-First, Stabil, Production-Ready)

## Definisi 10/10 (BARU — menggantikan definisi lama)

**10/10 BUKAN berarti "support banyak nama chipset di JSON".**
Jumlah nama device di file config tidak membuktikan apa-apa tanpa
validasi hardware nyata. Definisi yang berlaku mulai 2026-09-27:

1. **Capability detection akurat** — signature yang dihitung
   `core/detector.sh` (Step 4) + `load_overrides.sh` (Step 10) cocok
   dengan kondisi nyata device (policy, governor, devfreq writability,
   thermal zones terbukti via log).
2. **Boot guard + safe apply terbukti jalan** — guard aktif saat gagal
   beruntun (Step 5-6), semua tulis lolos write → read-back → verify
   dengan kategori APPLIED / SKIPPED / FALLBACK / FAILED (Step 7-8).
   Tanpa verify = tanpa klaim sukses.
3. **Tervalidasi nyata di minimal 1 device fisik** — saat ini:
   Unisoc/Mali milik user (L2 HP: log boot + apply + APPLY-TIME nyata,
   bukan sandbox saja).
4. **Graceful degrade terbukti di kondisi capability hilang** — simulasi
   sandbox: nol policy, nol thermal zone, GPU tanpa OPP, node read-only →
   module tetap jalan, skip beralasan, tidak crash (Step 12 + Step 22 gate).

Skor stabilitas ditentukan Phase 2 (boot guard + safe apply), BUKAN
banyaknya entry device. Satu device tervalidasi + degrade terbukti >
sepuluh nama chipset tanpa bukti.

---

## Histori Perubahan Arah (kenapa roadmap ini ditulis ulang)

- Roadmap lama menargetkan matriks device-name (T615, SD888, Dimensity,
  Exynos, …) + `device_overrides.json` keyed by nama chipset (Step 5 lama,
  commit `77b3a2b`).
- Pola itu = `DEVICE NAME → RANDOM TWEAK`, dilarang skill
  `alpha-hsin-engineering` (nama sama belum tentu capability sama beda
  ROM/kernel; angka belum divalidasi = klaim palsu).
- 2026-09-27 atas perintah user: Step 5 lama DIREVERT total (`36d2256`),
  antrean 31 → 22 step, boot guard + safe apply dimajukan ke Phase 2,
  overrides diganti capability-signature (Phase 3).
- Detail fase + step: PLAN.md. Status real-time: STATUS.md. Antrean
  eksekusi: PRIORITY_QUEUE.md. File ini = definisi + prinsip + gate,
  bukan duplikat ketiganya.

---

## Prinsip Non-Negosiable (berlaku semua fase)

1. NOL override/profile keyed by nama chipset. Key = capability signature
   (`cpu{1|2+}_gpu{devfreq|kgsl|none}_thermal{0|1|2+}`) + entry `default`.
2. Klaim "mendukung device X" hanya untuk yang tervalidasi hardware nyata.
   Sisanya = "graceful degrade" sampai ada bukti.
3. Boot guard + safe apply = prioritas tertinggi setelah testing infra.
4. Apply tanpa read-back verify = belum selesai. Kategori hasil selalu
   APPLIED / SKIPPED / FALLBACK / FAILED.
5. Keempat file rencana (PLAN, STATUS, PRIORITY_QUEUE, ROADMAP ini) harus
   konsisten: nomor step, status, nama fase sama. Beda = file yang
   tertinggal yang salah.

---

## Peta Fase + Gate (bukan timeline mingguan)

Tidak ada lagi target "minggu N selesai device X" — yang ada GATE per fase.
Fase lanjut hanya bila gate lolos (bukti, bukan klaim).

```
Phase 1: Testing Infrastructure (Steps 1-4) — DONE 2026-09-27
  Gate: CI hijau + merge terbukti (7e41841, 5b373ea). LOLOS.

Phase 2: Boot Guard & Safe Apply (Steps 5-8) — NEXT
  Gate: sandbox red-green guard + verify-matrix safe_apply +
        A/B migrasi cpu identik + CI hijau.

Phase 3: Capability Overrides (Steps 9-12) — BLOCKED (wait Phase 2)
  Gate: signature match di device tervalidasi + fallback default
        terlog di signature asing + thermal cap-only + sandbox
        capability-hilang PASS.

Phase 4: Documentation (Steps 13-18) — BLOCKED (wait Phase 3)
  Gate: klaim device jujur (validated vs degrade) di semua dokumen.

Phase 5: QA & Release (Steps 19-22) — BLOCKED (wait Phase 4)
  Gate RILIS (Step 22): Phase 2-3 DONE + L2 HP nyata PASS +
        sandbox degrade PASS → BARU BOLEH bump versionCode stabil.
        Tanpa L2 = tanpa rilis stabil.
```

---

## Klaim Device yang Jujur (template untuk semua dokumen)

| Kelas | Syarat klaim | Status saat ini |
|---|---|---|
| TERVALIDASI | L2 HP nyata: boot log + apply log + APPLY-TIME + tes rasa | Unisoc/Mali milik user (L2 menyusul Phase 2-3) |
| GRACEFUL DEGRADE | Sandbox capability-hilang PASS + fallback default terlog | Semua device lain (menunggu bukti) |
| DILARANG | Nama chipset di JSON tanpa bukti + klaim "support/tested" | Dihapus dari roadmap ini |

---

## Referensi Pola Implementasi (bukan duplikat kode)

Detail acceptance + commit message per step ada di PRIORITY_QUEUE.md.
Referensi arsitektur:

- Boot guard: pola fail-count + auto-disable + reset-on-success dari
  `service.sh` repo isac12345/Alpha (lihat Step 5-6).
- Safe apply: pola cek exist + writable → write → read-back → kategorikan
  dari `apply_tweak()` Alpha (lihat Step 7-8).
- Signature: dihitung dari `detected.conf` (Step 4) + cek `[ -w ]` live
  (lihat Step 9-10). Contoh: `cpu2+_gpu-devfreq_thermal2+`.
- Thermal: kelas NORMAL / HIGH / VERY HIGH / CRITICAL dari zone terdeteksi,
  cap-only (tidak pernah menaikkan limit profil/user), tanpa zone = no-op
  jujur (lihat Step 11).
- Pelajaran lama yang tetap berlaku: fungsi set-global jangan dipanggil
  dalam `$( )` (subshell menghilangkan state); threshold high < critical;
  `| while` hanya untuk print; cache kosong = tolak, bukan terima.

---

## Summary Table: Jalan Menuju 10/10 (BARU)

| Fase | Fokus | Gate | Hasil |
|---|---|---|---|
| **1** | Testing infra | CI hijau + merge | ✅ DONE (4/22) |
| **2** | Boot guard + safe apply | Sandbox + A/B + CI | ⏳ NEXT — penentu skor stabilitas |
| **3** | Capability overrides | Match + fallback + cap-only + degrade PASS | ⏳ BLOCKED |
| **4** | Dokumentasi jujur | Validated vs degrade terpisah | ⏳ BLOCKED |
| **5** | QA + gate rilis | L2 HP + degrade PASS → bump version | ⏳ BLOCKED |
| | **TOTAL** | **22 step** | **HSIN 10/10 = 4 kriteria definisi di atas ✅** |

---

## Kesimpulan

**HSIN jadi 10/10** dengan fokus pada: capability detection yang akurat,
boot guard + safe apply yang terbukti, satu device tervalidasi nyata, dan
graceful degrade yang teruji — bukan dengan menambah nama chipset.

Stability, reliability, dan kejujuran klaim. Itu 10/10.
