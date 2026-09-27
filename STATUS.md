# STATUS.md — HSIN Real-Time Progress Tracker (capability-first)

**Last Updated:** 2026-09-27 (Steps 7-8 DONE `6ea5619` = "Step 6" versi user; Step 6 dokumen DITUNDA, STOP sebelum lanjut)
**Overall Progress:** Phase 1 DONE (4/22) → Phase 2 IN PROGRESS (Steps 5,7,8 DONE; Step 6 ditunda)

---

## 🎯 Master Progress

```
[██████░░░░░░░░░░░░░░] 32% (7/22 steps DONE)

PHASE 1: Testing Infrastructure (Steps 1-4)    [██████████] 100% — DONE
PHASE 2: Boot Guard & Safe Apply (Steps 5-8)   [███████░░░] 75% — Steps 5,7,8 DONE; Step 6 ditunda
PHASE 3: Capability Overrides (Steps 9-12)     [░░░░░░░░░░] 0% — BLOCKED (wait Phase 2)
PHASE 4: Documentation (Steps 13-18)           [░░░░░░░░░░] 0% — BLOCKED (wait Phase 3)
PHASE 5: QA & Release (Steps 19-22)            [░░░░░░░░░░] 0% — BLOCKED (wait Phase 4)
```

---

## 📋 PHASE 1: Testing Infrastructure (Steps 1-4) — DONE

- [x] **Step 1** — `tests/` testing framework + template device report —
  DONE 2026-09-27, merge `7e41841` (Merge work/phase1-tests).
- [x] **Step 2** — `.github/workflows/lint-and-test.yml` (shellcheck
  `-S error`, sh -n, validasi JSON, cek file wajib, format module.prop) —
  DONE 2026-09-27, merge `7e41841` (fix CI `532ff87` di dalamnya).
- [x] **Step 3** — `tests/validate_build.sh` (positif VALID exit 0, negatif
  ERROR exit 1) — DONE 2026-09-27, merge `7e41841`.
- [x] **Step 4** — `core/detector.sh` comprehensive (SoC/GPU/CPU-policy/
  thermal-zone + cache `detected.conf`) — DONE 2026-09-27, commit
  `5b373ea` (`refactor: comprehensive device detection (Phase 1.2, Step 4)`).

### ⛔ Step 5 LAMA — DIREVERT, DIGANTI (bukan bagian antrean)

- `capability/device_overrides.json` keyed by NAMA CHIPSET
  (`unisoc_t615`, `snapdragon_888`, …) — commit `77b3a2b`
  (`feat: device-specific override profiles (Phase 1.2, Step 5)`).
- DIREVERT total via `36d2256`
  (`Revert "feat: device-specific override profiles (Phase 1.2, Step 5)"`,
  2026-09-27, 62 deletions, file hilang dari tree).
- Alasan: pola `DEVICE NAME → RANDOM TWEAK` melanggar prinsip
  capability-first (skill alpha-hsin-engineering). Diganti Step 9 baru:
  `capability/capability_overrides.json` keyed by capability signature.

---

## 📋 PHASE 2: Boot Guard & Safe Apply (Steps 5-8) — NEXT

- [x] **Step 5** — `core/boot_guard.sh` — DONE 2026-09-27, commit `5f3355c`
  (`feat: boot guard with fail-count auto-disable (Phase 2, Step 5)`).
  Threshold >= 2x (perintah user, override PRIORITY_QUEUE yang tulis 3x —
  perlu sinkronisasi susulan, di luar scope Step 5). Bukti L1: sh -n 2/2,
  shellcheck -S error 0, sandbox 10/10 (fresh→applied, 1x→belum aktif,
  2x→AKTIF+skip tuning, counter persisten ts:count, log AKTIF+alasan,
  boot-ok→reset, korup→sanitasi, threshold-env override), jalur logger
  terverifikasi (WARN masuk boot.log). CI push: API GitHub tak terjangkau
  dari Termux (2x coba) — status CI BELUM terkonfirmasi, jujur menunggu.
- [ ] **Step 6** — integrasi boot guard ke `service.sh` (cek di awal boot,
  skip tuning + exit bersih bila guard aktif, reset bila boot sukses) —
  PENDING / DITUNDA: user memerintahkan safe_apply dulu (Step 6 versi user
  = Step 7+8 dokumen ini, selesai di bawah). Perlu keputusan user kapan
  integrasi service.sh dikerjakan.
- [x] **Step 7** — `core/safe_apply.sh` — DONE 2026-09-27, commit `6ea5619`
  (`feat: safe sysfs write gateway with 5 result categories` = "Step 6"
  versi perintah user). Gateway 5 kategori (APPLIED=0 / SKIPPED=2 /
  UNAVAILABLE=3 / FALLBACK=4 / FAILED=1), referensi `apply_tweak()` Alpha
  (common/engine.sh) TANPA chmod paksa (read-only = SKIPPED beralasan).
  Write+verify inti REUSE `hsin_node_write_verify()` existing
  (core/sysfs.sh, tanpa duplikasi). Bukti L1: sh -n + shellcheck
  `-S error` 0, sandbox 11/11 (hilang/read-only/ditolak/ngawur
  ±alternatif/sukses/log/counter/engine-palsu/logger).
- [x] **Step 8** — migrasi 1 engine sebagai bukti pola — DONE 2026-09-27,
  commit `6ea5619` (sama). Dipilih `engine/io/readahead.sh` (risiko
  terkecil: 71 baris, 1 write site, non-kritis) BUKAN engine/cpu
  (backup/restore path = risiko lebih tinggi; cpu menyusul setelah pola
  approved). A/B tanpa override IDENTIK (512=512). Plus 1 baris
  build_release.sh: safe_apply.sh + boot_guard.sh masuk daftar runtime
  (tanpanya hilang di ZIP release — kelas bug scan_cache dulu; boot_guard
  ikut diperbaiki karena celah yang sama dari Step 5).

---

## 📋 PHASE 3: Capability-Driven Overrides & Thermal Safety (Steps 9-12) — BLOCKED

- [ ] **Step 9** — `capability/capability_overrides.json` keyed by
  CAPABILITY SIGNATURE (mis. `cpu2+_gpu-devfreq_thermal2+`) + entry
  `default` fallback aman. NOL nama chipset sebagai key.
- [ ] **Step 10** — `core/load_overrides.sh` — hitung signature dari
  `detected.conf` + writability live, pilih entry cocok, fallback
  `default` + log bila tidak cocok.
- [ ] **Step 11** — `core/thermal_check.sh` — threshold NORMAL / HIGH /
  VERY HIGH / CRITICAL dari thermal_zone TERDETEKSI. Tanpa zone →
  no-op + log (bukan crash, bukan throttle buta).
- [ ] **Step 12** — graceful degradation formal — engine gagal != module
  gagal (counter applied/failed, partial success = return 0).

---

## 📋 PHASE 4: Documentation (Steps 13-18) — BLOCKED

- [ ] **Step 13** — README.md (quick start, profil, log, uninstall).
- [ ] **Step 14** — TESTING.md (prosedur + template laporan).
- [ ] **Step 15** — TROUBLESHOOTING.md (masalah umum + langkah debug).
- [ ] **Step 16** — DEVICE_COMPATIBILITY.md ("TERVALIDASI" vs
  "GRACEFUL DEGRADE" — jangan klaim rata; saat ini tervalidasi:
  Unisoc/Mali milik user).
- [ ] **Step 17** — API.md (untuk modder).
- [ ] **Step 18** — CHANGELOG.md.

---

## 📋 PHASE 5: QA & Release (Steps 19-22) — BLOCKED

- [ ] **Step 19** — QA_CHECKLIST.md (kode, build + validasi zip, device,
  fungsional, stabilitas, edge case, uninstall).
- [ ] **Step 20** — RELEASE_NOTES.md (fitur + keterbatasan jujur).
- [ ] **Step 21** — SUPPORT_POLICY.md (SLA, kanal, matriks kompatibilitas).
- [ ] **Step 22** — final status update + GATE RILIS: versionCode baru HANYA
  bila Phase 2-3 selesai DAN tervalidasi di HP nyata (L2). Tanpa L2 = tanpa
  rilis stabil.

---

## ⚠️ Known Issues (out of scope — dicatat, belum diperbaiki)

- `core/scan_cache.sh:47` — set `HSIN_SYSFS_BLOCK` TANPA guard
  `[ -n ... ] ||`, menimpa prefix sandbox yang di-export harness dan
  bertabrakan dengan reset `HSIN_IO_BLOCKS(_READY)` di
  `engine/io/scheduler.sh` (baris 17-19, jalan tiap file di-source) —
  merusak state test sandbox IO (test terpaksa seed `HSIN_IO_BLOCKS`
  manual pasca-source; terbukti saat Step 6 skenario 10, 2x gagal sebelum
  ketemu akar).
- Prioritas: FIX SEBELUM lanjut kerja apa pun di `engine/io/` berikutnya
  (`readahead.sh` baru dimigrasi ke safe_apply, `scheduler.sh` berbagi
  source yang sama — risiko test false-positive kalau dibiarkan).
- Belum fix sekarang karena di luar scope Step 6 (perintah user).

---

## 📊 Summary Stats (konsisten dengan checkbox di atas — hitung ulang tiap update)

| Metric | Value |
|---|---|
| **Total Steps** | 22 |
| **Completed** | 7 (Steps 1-5, 7-8; Step 6 dokumen ditunda) |
| **Next** | Keputusan user: Step 6 dokumen (integrasi service.sh) atau lanjut Phase 3 |
| **Reverted** | 1 (Step 5 lama, `36d2256`) |
| **Pending** | 15 (Step 6 + Steps 9-22) |
| **Expected Commits** | ~18 (1 per step, tanpa force push) |

---

## 🔄 Update Instructions

**After each step completion:**

1. Update checkbox step (tandai done bila selesai, pending bila belum).
2. Tulis tanggal + hash commit asli (dari `git log`, jangan dikarang).
3. Update Master Progress bar + Summary Stats di atas (WAJIB sama dengan
   hitungan checkbox — bug lama: progress 0% padahal task sudah checklist).
4. Pastikan nomor step sama di PLAN.md, STATUS.md, PRIORITY_QUEUE.md,
   ROADMAP_10_10.md. Bila beda, update file yang tertinggal.

---

## 🚦 Phase Transition Rules

- ✅ **Phase 1 → Phase 2:** Steps 1-4 DONE (terpenuhi 2026-09-27).
- ✅ **Phase 2 → Phase 3:** Steps 5-8 DONE + CI hijau.
- ✅ **Phase 3 → Phase 4:** Steps 9-12 DONE + sandbox capability-hilang PASS.
- ✅ **Phase 4 → Phase 5:** Steps 13-18 DONE.
- ✅ **Phase 5 → RELEASE:** Steps 19-22 DONE + L2 HP nyata PASS + gate
  versionCode lolos (Phase 2-3 tervalidasi HP).

---

## 🎯 Success Criteria (Final Release = definisi 10/10 baru)

- [ ] Capability detection akurat (signature cocok di device tervalidasi).
- [ ] Boot guard + safe apply terbukti jalan (sandbox + HP nyata).
- [ ] Tervalidasi nyata di minimal 1 device fisik (Unisoc/Mali user).
- [ ] Graceful degrade terbukti di kondisi capability hilang (sandbox test).
- [ ] ShellCheck 0 errors, sh -n 0 errors, JSON valid semua.
- [ ] Klaim device jujur: "tervalidasi" vs "graceful degrade".

---

**Next Step:** Step 6 — integrasi boot guard ke `service.sh` (STOP — butuh approve user sebelum lanjut, per perintah 2026-09-27).
