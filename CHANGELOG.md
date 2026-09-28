# Changelog

Format mengikuti [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

> Versi rilis resmi belum ditentukan — menunggu validasi Phase 5 (QA)
> sebelum version bump di `module.prop` (saat ini tetap
> `v5.0.0-beta1` / `versionCode=5001`, tanpa perubahan di step ini).

## [Unreleased]

Perubahan roadmap capability-first (PQ Step 1–18).

### Added

- `core/boot_guard.sh` — fail-count auto-disable tuning setelah 2 gagal
  berturut-turut + reset saat boot sukses (PQ Step 5–6).
- `core/safe_apply.sh` — gateway tulis sysfs 5 kategori
  (APPLIED/SKIPPED/UNAVAILABLE/FALLBACK/FAILED) dengan write+verify
  (PQ Step 7–8).
- `capability/capability_overrides.json` + `core/load_overrides.sh` —
  override keyed by capability signature + `default_fallback`
  (PQ Step 9–10).
- `core/thermal_check.sh` — guardrail thermal 4 state
  (NORMAL/HIGH/VERY HIGH/CRITICAL + UNKNOWN) berbasis trip_point
  kernel terdeteksi; intervensi hanya di CRITICAL via safe_apply
  (PQ Step 11).
- `core/engine_guard.sh` — kontrak graceful degradation per-engine
  (partial success = return 0, gagal total = warning + lanjut)
  (PQ Step 12).
- Dokumentasi Phase 4: `README.md`, `TESTING.md`,
  `TROUBLESHOOTING.md`, `DEVICE_COMPATIBILITY.md`, `API.md`
  (PQ Step 13–17).

### Changed

- Realignment arsitektur dari device-name ke capability-signature:
  keputusan tuning diambil dari hasil deteksi (`detected.conf` +
  cek `[ -w ]` live), bukan nama chipset; device tak cocok →
  fallback aman + log (PQ Step 9, berlaku semua engine).
- `service.sh`: 6 engine via wrapper degradasi + rangkuman status
  semua engine di status report (PQ Step 12).
- `build_release.sh`: daftar runtime bundle mencakup file inti baru
  (pelajaran: file di luar daftar hilang di ZIP rilis).

### Fixed

- Guard prefix sysfs di `core/scan_cache.sh` agar prefix sandbox
  tidak tertimpa (PQ Step 8).
- `core/thermal_check.sh` hilang dari bundle rilis sejak Step 10 —
  guard thermal diam-diam tidak jalan di modul yang dikirim; sudah
  ditambah ke daftar runtime + dibuktikan via build release
  red-green (temuan verifikasi PQ Step 12).
- Komentar/log menyesatkan yang ditemukan saat audit (status
  `renderFrameRate`, pesan governor tanpa OPP, threshold thermal
  yang salah kalibrasi).

### Reverted

- `capability/device_overrides.json` lama yang keyed by nama chipset
  (pola `DEVICE NAME → RANDOM TWEAK`, melanggar capability-first) —
  direvert total; diganti override berbasis capability signature.
