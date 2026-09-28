# Release Notes (draft — Phase 5, PQ Step 20)

**Status: BELUM DIRILIS — menunggu validasi device kedua (L2), lihat
`QA_CHECKLIST.md` dan `DEVICE_COMPATIBILITY.md`.**

## Headline

HSIN v5.0.0-beta1: fondasi defensive (boot guard + safe apply +
thermal guardrail + degradasi per-engine + override berbasis
capability-signature). Draft ini disiapkan sebelum gate rilis;
nomor versi definitif hanya ditetapkan di PQ Step 22 bila gate lolos.

## Fitur (Phase 2–3)

- **Boot guard** — tuning dilewati otomatis setelah 2 boot gagal
  berturut-turut; reset saat boot sukses (`core/boot_guard.sh`).
- **Safe apply** — tiap tulis sysfs terverifikasi read-back dan
  dikategorikan jujur: APPLIED / SKIPPED / UNAVAILABLE / FALLBACK /
  FAILED (`core/safe_apply.sh`).
- **Thermal guardrail** — 4 state (NORMAL/HIGH/VERY HIGH/CRITICAL +
  UNKNOWN) dari trip_point kernel terdeteksi; intervensi hanya di
  CRITICAL via safe_apply (`core/thermal_check.sh`).
- **Graceful degradation per-engine** — satu engine gagal tidak
  menghentikan yang lain; sukses parsial dihitung sukses; summary
  semua engine di log (`core/engine_guard.sh`).
- **Capability-signature overrides** — tuning per signature
  (`capability/capability_overrides.json` + loader), fallback aman
  bila tidak cocok; tanpa nama chipset sebagai kunci.
- **Dokumentasi Phase 4** — README, TESTING, TROUBLESHOOTING,
  DEVICE_COMPATIBILITY, API, CHANGELOG.

## Keterbatasan (jujur)

- Semua fitur di atas **baru tervalidasi di 1 device** (Unisoc T615 /
  GPU Mali, milik developer): sandbox L1 hijau + pemakaian langsung.
  Report L2 (`tests/device_reports/`) masih kosong.
- **Device lain = graceful degrade, belum tervalidasi**: modul akan
  skip aman + log beralasan bila capability tidak cocok — perilaku
  itu yang teruji (sandbox), bukan performa/suhu di device tersebut.
- Butuh L2 di HP: checklist `QA_CHECKLIST.md` belum 100% lolos dan
  validasi device kedua (vendor/SoC berbeda) belum ada. Sampai dua
  itu terpenuhi, tidak ada klaim kelayakan pakai umum.
- Profil `extreme` butuh opt-in eksplisit (`ALLOW_EXTREME=true`,
  default `false`) dan belum tes rasa.
- **KETERBATASAN KERAS — profil `extreme` belum pernah dijalankan di
  HP fisik sama sekali** (bukan "sudah dites tapi belum ada catatan
  rasa"): gate-nya tidak pernah dibuka di mana pun — default `false`
  di semua config, tidak ada sandbox khusus extreme, tidak ada
  catatan run di HP. Secara desain ini profil paling berisiko
  (`extreme/frequency_unlock.sh`, `gpu_override.sh`,
  `thermal_override.sh` + watchdog `safety_monitor.sh`: frequency
  unlock, GPU override, thermal trip override). Mengaktifkannya =
  wilayah yang belum teruji; JANGAN aktifkan di luar pengujian
  terkontrol sampai ada validasi khusus extreme.
