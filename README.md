# HSIN v6.1.0

Game booster (modul Magisk/KernelSU/APatch + app) dengan tampilan game space. Mesin modul diambil dari Alpha Fusion
(Uperf + fas-rs + Overdrive + game hooks), jadi fiturnya sama dan sudah teruji di perangkat. Beda: nama dan tampilan.

## Mode
| HSIN | Alpha |
|---|---|
| Hemat | profil harian (battery) |
| Seimbang | balanced |
| Performa | performance |
| Puncak | performance + Overdrive (CPU/GPU dikunci penuh, tanpa batas) |

## Fitur
- Game space landscape (bisa potret): Beranda, Game, Rekaman, Pengaturan. Animasi digambar sendiri (jalan walau skala animasi HP 0.0).
- Per game: mode, resolusi (downscale Game Mode API), luncurkan langsung.
- Floating logo/FPS (CPU, GPU, suhu, ganti mode, rekam FPS CSV), rekam layar, bersihkan RAM, Jangan ganggu, refresh rate game.
- Pengaturan → Semua alat: thermal, auto profil, memori, dexopt, render, live check, log, dll (dari Alpha).
- Bahasa Indonesia / English.

## Pasang
Flash `HSIN-v6.1.0-module.zip` (APK ikut terpasang) → reboot → buka HSIN. Modul ini memakai id yang sama dengan Alpha Fusion,
jadi menggantikannya. Hapus app Alpha Control lama supaya tidak ada dua app.

## Build
GitHub Actions → build → Run workflow. Secrets opsional: `KEYSTORE_BASE64`, `KEYSTORE_PASSWORD`, `KEY_ALIAS`, `KEY_PASSWORD` (tanpa itu APK ditandatangani debug key). Keystore tidak boleh masuk repo.

Kredit: Alpha Fusion, Uperf, fas-rs (lihat NOTICE-gamebank.md dan app).
