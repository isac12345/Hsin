# QA_CHECKLIST.md — Checklist Rilis (Phase 5, PQ Step 19)

Setiap item bisa dicek ulang dengan perintah/langkah konkret di
kolom Verifikasi. Cara pakai: `[ ]` → `[x]` + tulis HASIL
(angka/baris log/nilai node), bukan "lancar". Item yang belum lolos
= blocker sesuai kolom Blocker.

Status device checklist ini: **1 device (Unisoc T615 / GPU Mali,
milik developer)** — semua item L2 di bawah merujuk ke device itu
kecuali dinyatakan lain. Item device kedua eksplisit BELUM (lihat
Device Testing).

## Code Quality (CI + lokal)

- [ ] `shellcheck -S error` 0 di semua `.sh` — Verifikasi:
  `find . -type f -name '*.sh' | grep -v '^./build/' | while read -r f;
  do shellcheck -S error "$f" || exit 1; done` (sama seperti CI
  `lint-and-test`). Blocker: ya.
- [ ] `sh -n` 0 error di semua `.sh` — Verifikasi: loop yang sama
  dengan `sh -n "$f"`. Blocker: ya.
- [ ] JSON valid — Verifikasi: `python3 -m json.tool
  capability/capability_overrides.json > /dev/null` (+ tiap
  `config/*.json` yang ada). Blocker: ya.
- [ ] File wajib ada — Verifikasi: `action.sh service.sh
  post-fs-data.sh customize.sh uninstall.sh module.prop
  build_release.sh bin/hsin` (sama seperti CI). Blocker: ya.
- [ ] `module.prop` valid + versi BELUM di-bump — Verifikasi:
  `grep -E '^(id|version|versionCode)=' module.prop` → `id=hsin`,
  `version=v5.0.0-beta1`, `versionCode=5001`. Bump hanya di PQ Step 22
  bila gate lolos + approve user. Blocker: ya.

## Build Quality

- [ ] ZIP valid via `tests/validate_build.sh` — Verifikasi:
  `sh tests/validate_build.sh <path-ZIP>` → exit 0 (cek isi wajib +
  fungsi runtime). Blocker: ya.
- [ ] Ukuran ZIP < 50MB — Verifikasi: `ls -la <ZIP>` /
  `du -h <ZIP>`. Hasil: ___ MB. Blocker: ya.
- [ ] Integrity manifest ada di ZIP — Verifikasi:
  `unzip -l <ZIP> | grep 'core/.integrity.manifest'`
  (dipakai `hsin_protect_integrity` di `core/protect.sh`). Blocker: ya.
- [ ] Fungsi guard ada di bundle rilis — Verifikasi:
  `unzip -p <ZIP> core/runtime.sh | grep -c
  'hsin_boot_guard_check\|hsin_safe_apply\|HSIN_THERMAL_CHECK_STATE\|hsin_engine_run'`
  → 4/4 match group (pelajaran bug thermal_check hilang dari bundle).
  Blocker: ya.

## Device Testing (L2 — 1 device: Unisoc T615 / Mali milik developer)

- [ ] Install: flash ZIP via root manager → `/data/adb/modules/hsin`
  ada → reboot → launcher ≤ 2 menit. Hasil: ___.
- [ ] Boot: `su -c 'cat /data/adb/hsin/service.state'` → `ready`
  (atau `degraded` + alasan tercatat di `error.log`). Hasil: ___.
- [ ] Guard-path nonaktif: `.boot_fail_count` tidak ada/count 0 +
  tuning profil default diterapkan (1 node berubah vs baseline).
- [ ] Guard-path AKTIF: tulis counter 2 → reboot →
  `BOOT-GUARD AKTIF` di `boot.log` + tuning dilewati + launcher
  tetap sampai → hapus counter → reboot → tuning jalan lagi.
- [ ] Profile switch: `hsin apply battery|balanced|performance`
  masing-masing → node berubah + `APPLY-TIME` di `debug.log`.
  Hasil (ms): ___ / ___ / ___.
- [ ] Rollback: `hsin backup` → ubah 1 knob → `hsin restore` →
  node kembali + baris `ROLLBACK` di `rollback.log`.
- [ ] Profil `extreme` BELUM pernah dijalankan di HP fisik sama
  sekali (gate `ALLOW_EXTREME` tidak pernah dibuka; tanpa sandbox
  khusus) — JANGAN aktifkan di luar pengujian terkontrol. Blocker
  untuk klaim apa pun soal `extreme` (lihat KETERBATASAN KERAS di
  `RELEASE_NOTES.md`).
- [ ] Divalidasi di device kedua (vendor/SoC berbeda) — **BELUM,
  blocker untuk klaim multi-device.** Syarat lolos: report L2 penuh
  (TESTING.md) di `tests/device_reports/` + 7 item di atas hijau di
  device itu.

## Stability (30min gaming — device developer sendiri, BUKAN general)

- [ ] Main game/beban berat 30 menit di **perangkat developer
  (Unisoc T615 / Mali)** profil `performance`: catat
  `thermal_check` state tiap 10 menit
  (`grep thermal_check /data/adb/hsin/logs/boot.log`) + suhu
  sentuh. Hasil: ___ / ___ / ___.
- [ ] Tidak ada reboot sendiri / freeze / `BOOT-GUARD AKTIF` tak
  terduga selama 30 menit.
- [ ] Pernyataan jujur: hasil ini HANYA berlaku untuk device di atas.
  Klaim stabilitas general butuh pengulangan di device kedua
  (blocker di atas).

## Edge Cases

- [ ] Reboot saat apply: jalankan `hsin apply performance`, reboot
  di tengah (≤5 detik) → boot berikutnya `service.state` = `ready`
  atau `degraded` (bukan bootloop), counter guard +1 tercatat jujur.
- [ ] Config korup: tulis sampah ke `/sdcard/Android/hsin/hsin.conf`
  → reboot → service selesai (fallback default, tanpa crash) →
  kembalikan config baik. Verifikasi: tidak ada baris crash di
  `error.log` terkait parse.
- [ ] Capability hilang total (sandbox): `sh
  tests/sandbox_degrade.sh` + `sh tests/thermal_sandbox/run.sh`
  → exit 0 (UNKNOWN + default fallback, no-crash).

## Uninstall Bersih

- [ ] Hapus via root manager → reboot → verifikasi:
  `/data/adb/hsin` hilang, `/sdcard/Android/hsin` hilang,
  1 node acuan (governor/policy0) kembali seperti baseline tahap 1
  TESTING.md. Sisa file = temuan (tulis path-nya): ___.

## Klaim Dokumen

- [ ] Tidak ada klaim "production-ready" atau "siap dipakai publik"
  di README/dokumen mana pun sebelum checklist ini 100% lolos DAN
  divalidasi di device kedua — Verifikasi:
  `grep -rin "production-ready\|siap dipakai publik\|production ready"
  README.md TESTING.md TROUBLESHOOTING.md DEVICE_COMPATIBILITY.md
  API.md CHANGELOG.md RELEASE_NOTES.md 2>/dev/null` → kosong.
  Blocker: ya (dokumen).
