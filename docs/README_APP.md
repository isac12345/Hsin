# README_APP.md — Aplikasi controller HSIN (beta)

Versi app: `1.0.0-beta` (`applicationId=com.hsin`, `versionCode=1`).
Status: BETA — belum divalidasi di HP fisik bersama modul. Tidak ada klaim
stabil / siap rilis / production-ready.

## Cara build (HANYA via GitHub Actions)

Termux tidak punya JDK/Android SDK yang cocok untuk AGP — build lokal di
Termux DILARANG (APP_PLAN §6). Build lewat workflow manual `build-apk`:

1. Buka tab Actions → workflow `build-apk` → Run workflow.
2. Tunggu sampai `compileDebugKotlin` + packaging sukses (`gh run list`
   menampilkan `success` untuk `build-apk`).
3. Unduh artefak `hsin-debug-apk` (retensi terbatas — segera simpan).

Konfigurasi kunci (terverifikasi ke kode): `app/app/build.gradle.kts`
(`applicationId=com.hsin`, `minSdk=26`, `targetSdk=34`, `compileSdk=34`,
tanpa NDK); manifest `app/app/src/main/AndroidManifest.xml` (1 activity,
NOL permission, tanpa service/receiver/provider).

## Cara pasang

1. Pasang modul HSIN dulu, reboot.
2. Pasang APK (`hsin-debug-apk`), buka tab Beranda → Periksa ulang.
3. Beri akses root saat diminta (tiap command via `su -c "sh
   /data/adb/modules/hsin/action.sh <cmd>"`, timeout 15 dtk per command).

## Permission

NOL permission Android. Akses hardware hanya lewat modul via root
(allowlist 31 subcommand di `RootClient.kt`: `info device capabilities
status guard-status warn logs apply backup rollback conflicts export
renderer-apply renderer-state downscale-enable/disable/status
refresh-lock-enable/disable/status export-debug list-apps game-list/add/remove
knobs knob-set/knob-list/knob-reset config-get/set`).

## State yang didukung (4 tab)

- **Beranda** (`HomeScreen.kt`): status root/modul/boot-guard/termal,
  hasil terakhir, ringkasan capability, tombol Buka knob / Pulihkan backup
  (dialog konfirmasi wajib) / Periksa ulang, banner kasus tepi (A13).
- **Knob** (`KnobScreen.kt`): kategori dari `knobs` modul, kontrol
  pilihan/slider/toggle, baris terkunci untuk fitur bergate, tombol
  `Terapkan (N)` → hasil per knob `diminta X → diterapkan Y (alasan)`
  (A9/A10).
- **Monitor** (`MonitorScreen.kt`): polling `status` tiap ~2 dtk, hanya saat
  layar terlihat + foreground, tombol Jeda/Lanjut; tak tersedia = `N/A`
  (A11).
- **Log** (`LogScreen.kt`): tab `boot.log`/`apply.log` (200 baris terakhir),
  badge level per baris, tombol Salin ringkasan laporan bug + Muat ulang
  (A12).

Semua error tampil ramah (tanpa exception mentah): tanpa root, modul
hilang, versi tak cocok, timeout, respons invalid, guard aktif, parsial,
read-only (A13, `ErrorStatesPresenter.kt`).
