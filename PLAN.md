# PLAN.md — HSIN manual (arsitektur capability-first)

## KENAPA ARAH BERUBAH (baca dulu sebelum kerja — histori, bukan teori)

- Dulu (Step 5 lama, commit `77b3a2b`): `capability/device_overrides.json`
  keyed by NAMA CHIPSET (`unisoc_t615`, `snapdragon_888`, `dimensity_9200`,
  `exynos_1280`, …). Nilai tuning per device ditulis tangan berdasarkan nama.
- Masalahnya: itu pola `DEVICE NAME → RANDOM TWEAK` — dilarang skill
  `alpha-hsin-engineering`. Nama chipset tidak menjamin capability sama
  (satu "Snapdragon 888" di ROM/kernel berbeda bisa beda governor, OPP
  table, thermal zone, node writable). Angka per-chipset yang belum
  divalidasi di hardware nyata = klaim palsu + risiko apply ke node yang
  tidak ada/tidak cocok.
- Keputusan user 2026-09-27: Step 5 DIREVERT total (`36d2256`), file
  `capability/device_overrides.json` DIHAPUS dari tree. Penggantinya:
  override keyed by CAPABILITY SIGNATURE — hasil deteksi
  `core/detector.sh` (Step 4): mis. jumlah CPU policy, governor yang
  tersedia, devfreq writable atau tidak, jumlah thermal zone. Device yang
  tidak cocok signature mana pun → fallback aman default, bukan skip total
  dan bukan override belum tervalidasi.
- Prioritas juga dibalik: boot guard + safe apply (Phase 2) dimajukan
  melewati device overrides (Phase 3). Alasan: boot guard + safe apply
  yang membedakan modul stabil vs berisiko bootloop — skor stabilitas
  paling ditentukan di sini, bukan di banyaknya nama chipset di JSON.
- Aturan klaim device (berlaku semua file): "mendukung device X" HANYA
  untuk yang BENERAN divalidasi di hardware asli (saat ini: Unisoc/Mali
  milik user). Device lain = "graceful degrade" sampai ada bukti test nyata.
- Total step berubah 31 → 22 (lihat PRIORITY_QUEUE.md): Step 5 lama dihapus,
  thermal JSON angka-tetap diganti `thermal_check.sh`, migrasi 7 engine
  diringkas jadi 1 bukti pola (engine/cpu), bump versionCode dipindah ke
  gate rilis Phase 5.

## RENCANA BUAT USER (baca ini aja, bahasa simpel)

- Target: HSIN manual/bebas setting, apply CEPAT + AMAN (tidak bootloop,
  tidak tulis buta ke node yang tidak ada). Semua pilihan user tetap lewat
  aplikasi (3 tab: Status, Knobs, Logs).
- Status: fondasi SELESAI (Step 1-4: testing framework, CI, validasi build,
  detector). Berikutnya: boot guard + safe apply (Step 5-8), baru overrides
  + thermal (Step 9-12), dokumentasi (Step 13-18), QA + rilis (Step 19-22).
- Yang jalan otomatis (ga perlu kamu): perbaikan kode modul + app, kecil
  per commit, diverifikasi statis dulu (L1).
- TUGAS KAMU (urutan):
  1. [x] SELESAI (2026-09-26): `date +%s%3N` → 13 digit, marker ms DIPERCAYA.
  2. [x] SELESAI (2026-09-27): BUILD ZIP modul + APK lewat GitHub Actions
     berhasil (APK run #36296279179, Modul run #36296491773).
  3. [ ] L2 (nanti, setelah Phase 2-3 selesai): flash zip, apply manual 1x,
     kirim baris `APPLY-TIME` dari `/data/adb/hsin/logs/debug.log`.
  4. [ ] L2.app: pasang APK, cek tiap tweak bisa dipilih + Apply berhasil.
  5. [ ] PALING AKHIR: tes rasa (game adem/kenceng) = L2, bilang OK.
- DILARANG naikkan versionCode ke rilis stabil sebelum Phase 2-3 selesai
  DAN divalidasi di HP nyata (gate Step 22).

## Fase 1 — Testing Infrastructure (Step 1-4, SELESAI)

- [x] Step 1: `tests/` testing framework + template device report.
- [x] Step 2: `.github/workflows/lint-and-test.yml` (shellcheck `-S error`,
  sh -n, validasi JSON, cek file wajib, format module.prop).
- [x] Step 3: `tests/validate_build.sh` (validasi pra/pasca-zip).
- [x] Step 4: `core/detector.sh` — deteksi SoC/GPU/CPU-policy/thermal-zone
  komprehensif + cache `detected.conf` (fondasi signature capability).
- Detail hash/commit: lihat STATUS.md (Step 1-4 DONE dengan hash asli).

## Fase 2 — Boot Guard & Safe Apply (Step 5-8, BERIKUTNYA)

- [ ] Step 5 (NEXT): `core/boot_guard.sh` — referensi pola dari repo
  isac12345/Alpha (`service.sh`): hitung boot fail count, auto-disable
  tuning kalau gagal berturut-turut, log jelas kapan guard aktif.
- [ ] Step 6: integrasi boot guard ke `service.sh` (cek di awal boot,
  skip tuning + exit bersih bila guard aktif, reset bila boot sukses).
- [ ] Step 7: `core/safe_apply.sh` — referensi `apply_tweak()` dari Alpha:
  cek node exist + writable, write, read-back, verify, kategorikan hasil
  APPLIED / SKIPPED / FALLBACK / FAILED. Tanpa verify = tanpa klaim sukses.
- [ ] Step 8: migrasi minimal SATU engine (`engine/cpu`) ke `safe_apply.sh`
  sebagai bukti pola terpakai (engine lain menyusul setelah pola terbukti).

## Fase 3 — Capability-Driven Overrides & Thermal Safety (Step 9-12)

- [ ] Step 9: `capability/capability_overrides.json` — keyed by CAPABILITY
  SIGNATURE, BUKAN nama chipset (ganti total rencana Step 5 lama yang
  direvert). Format signature baku, mis.
  `cpu2+_gpu-devfreq_thermal2+`, plus entry `default` sebagai fallback aman.
- [ ] Step 10: `core/load_overrides.sh` — hitung signature device dari
  `detected.conf` + cek writability live, pilih entry cocok, fallback ke
  `default` bila tidak ada yang cocok (dengan log alasannya).
- [ ] Step 11: `core/thermal_check.sh` — threshold NORMAL / HIGH /
  VERY HIGH / CRITICAL berbasis data thermal_zone yang TERDETEKSI, bukan
  angka tetap per chipset. Tanpa thermal zone → fitur thermal degrade
  jadi no-op + log, bukan crash dan bukan throttle buta.
- [ ] Step 12: graceful degradation formal — engine gagal != module gagal
  (counter applied/failed per engine, partial success = return 0, service
  lanjut ke engine berikut).

## Fase 4 — Documentation (Step 13-18)

- [x] Step 13: README.md (DONE `a9e4e03`). Step 14: TESTING.md (DONE
  `50bf8e6`). Step 15: TROUBLESHOOTING.md (DONE `ce4dfbd`).
  Step 16: DEVICE_COMPATIBILITY.md (DONE `1f362e7`).
  Step 17: API.md (DONE `b37b0f2`). Step 18: CHANGELOG.md
  (`## [Unreleased]`, DONE `3c46f66`).

## Fase 5 — QA & Release (Step 19-22)

- [x] Step 19: QA_CHECKLIST.md (DONE `ed5e34e`).
- [x] Step 20: RELEASE_NOTES.md (DONE `a7e90e5`, pesan tanpa versi).
- [x] Step 21: SUPPORT_POLICY.md (DONE `1734654`).
- [ ] Step 22: GATE RILIS = BELUM LOLOS (dievaluasi 2026-09-27, lihat
  STATUS.md "GATE RILIS"): device_reports kosong, QA 0/25, device
  kedua + extreme belum. `module.prop` tetap v5.0.0-beta1/5001.
  Berikutnya: TESTING.md di HP fisik + report L2 pertama.

## Aturan

- **Build hanya lewat GitHub Actions** (perintah user 2026-09-27). Termux
  tidak punya JDK/Android SDK → Termux = tulis source + verifikasi statis.
- Workflow build MANUAL (workflow_dispatch): tidak ada build otomatis saat push.
- Tanpa flash/sentuh perangkat tanpa izin.
- Satu tugas = satu tujuan. Verifikasi tiap langkah (L1 = bukti konkret).
- L2 wajib sebelum menyebut selesai; tanpa L2 status tetap "tunggu HP test".
- Apply tidak pernah diklaim sukses tanpa write → read-back → verify
  (APPLIED / SKIPPED / FALLBACK / FAILED).
- Tanpa secret di repo. Tanpa force push.
- Nomor step + status di PLAN.md, STATUS.md, PRIORITY_QUEUE.md,
  ROADMAP_10_10.md harus SELALU sama — bila tidak sama, yang salah adalah
  file yang tidak diupdate, bukan rencana.

## GIT SAFETY RULES (permanen, berlaku semua step — perintah user 2026-09-27)

- DILARANG force-push (`--force`, `--force-with-lease`, atau varian apa pun)
  atau `git commit --amend` pada commit yang SUDAH di-push, dalam kondisi
  apa pun — termasuk untuk memperbaiki dokumentasi sendiri.
  (Preseden pelanggaran: STATUS.md Step 6 diduplikat, diperbaiki via amend +
  force-with-lease. Isinya benar, caranya salah.)
- Kalau ada kesalahan di commit yang sudah di-push (typo, duplikat, data
  salah), perbaiki dengan COMMIT BARU yang korektif (revert atau fix
  commit), bukan menulis ulang history.
- Aturan ini permanen untuk semua step selanjutnya, tidak hanya untuk
  kasus STATUS.md kemarin.
