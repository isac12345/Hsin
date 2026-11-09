# HSIN v6.14.6

Game booster (modul Magisk/KernelSU/APatch + app) dengan tampilan game space. Mesin modul diambil dari HSIN
(Uperf + fas-rs + Overdrive + game hooks), jadi fiturnya sama dan sudah teruji di perangkat. Beda: nama dan tampilan.

## Mode
| HSIN | HSIN |
|---|---|
| Hemat | profil harian (battery) |
| Seimbang | balanced |
| Performa | performance |
| Puncak | performance + Overdrive (CPU/GPU dikunci penuh, tanpa batas) |

## Fitur
- Game space landscape (bisa potret): Beranda, Game, Rekaman, Pengaturan. Animasi digambar sendiri (jalan walau skala animasi HP 0.0).
- Per game: mode, resolusi (downscale Game Mode API), luncurkan langsung.
- Floating logo/FPS (CPU, GPU, suhu, ganti mode, rekam FPS CSV), rekam layar, bersihkan RAM, Jangan ganggu, refresh rate game.
- Pengaturan → Semua alat: thermal, auto profil, memori, dexopt, render, live check, log, dll (dari HSIN).
- Bahasa Indonesia / English.

## Pasang
Flash `HSIN-v6.14.6-module.zip` (APK ikut terpasang) → reboot → buka HSIN. Modul ini memakai id yang sama dengan HSIN,
jadi menggantikannya. Hapus app HSIN Control lama supaya tidak ada dua app.

## Build
GitHub Actions → build → Run workflow. Secrets opsional: `KEYSTORE_BASE64`, `KEYSTORE_PASSWORD`, `KEY_ALIAS`, `KEY_PASSWORD` (tanpa itu APK ditandatangani debug key). Keystore tidak boleh masuk repo.

Kredit: HSIN, Uperf, fas-rs (lihat NOTICE-gamebank.md dan app).
