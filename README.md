# HSIN v6.0.0

Modul Magisk/KernelSU/APatch (game booster) + app Kotlin/Compose. Satu build di GitHub Actions menghasilkan:
`HSIN-v6.0.0.apk` dan `HSIN-v6.0.0-module.zip`.

## Isi
- **Game Space** (tampilan utama, landscape/portrait): Beranda dengan 4 mode (Hemat ★, Bawaan ★★, Seimbang ★★★, Boost ★★★★), statistik CPU/GPU/Suhu/RAM, Bersihkan RAM, Jangan ganggu, carousel game + tombol MULAI GAME. Animasi digambar sendiri lewat jam frame, jadi tetap jalan walau skala animasi HP = 0.
- Mode sebanding dengan namanya: Hemat membatasi CPU ±70% dan GPU ±55%; Seimbang CPU/GPU penuh dengan minimum dinaikkan; **Boost mengunci CPU/GPU di frekuensi tertinggi, governor performa, batas panas dilonggarkan (tanpa batas)**.
- Per game: mode dan resolusi (Game Mode API, 50–100%) sendiri, diterapkan saat game dibuka dari HSIN dan dipulihkan saat ditutup.
- Floating FPS (logo → panel): FPS, CPU, GPU, suhu, ganti mode cepat, rekam FPS ke CSV (Download). Tab Rekaman menampilkan ringkasan rekaman.
- Lanjutan (Pengaturan → Lanjutan): tuning manual penuh seperti v5 (knob, preset, profil per game, monitor, tema).
- Pengaman: batas panas, mode aman saat boot gagal, deteksi modul tuning lain (Alpha, Uperf, fas-rs, dll).

## Gambar bawaan (sudah terpasang, bisa ditimpa sebelum build)
| File | Fungsi |
|---|---|
| `app/src/main/res/drawable-nodpi/banner_default.jpg` | banner di Dash |
| `app/src/main/res/drawable-nodpi/wallpaper_default.jpg` | wallpaper tema Carbon |
| `app/src/main/res/drawable-nodpi/ic_launcher_foreground.png` | ikon app (432×432, isi penting di tengah) |

Nama file harus sama. Warna latar ikon: `app/src/main/res/values/ic_launcher_background.xml`.

## Build
1. Push semua isi folder ini ke repo GitHub (branch `main`).
2. (Opsional, supaya tanda tangan APK stabil) isi Secrets: `KEYSTORE_BASE64`, `KEYSTORE_PASSWORD`, `KEY_ALIAS`, `KEY_PASSWORD`. Tanpa secret, APK ditandatangani debug key. Keystore tidak boleh masuk repo (`.gitignore` memblokirnya).
3. Actions → build → Run workflow → unduh artifact.

## Pasang
Pasang `HSIN-v6.0.0-module.zip` → reboot → pasang APK → beri izin root.
Modul HSIN lama dengan id sama akan tergantikan; data lama di `/data/adb/hsin` tidak dipakai lagi.

## Tes modul tanpa HP
`bash tests/sandbox.sh dash` (juga `bash`): pohon sysfs palsu, 114 pemeriksaan (knob, boot, pengaman panas, per game, mode Hemat/Seimbang/Boost, deteksi modul lain).
