# HSIN v5.0.0

Modul Magisk/KernelSU/APatch (tuning manual) + app Kotlin/Compose. Satu build di GitHub Actions menghasilkan:
`HSIN-v5.0.0.apk` dan `HSIN-v5.0.0-module.zip`.

## Isi
- Tuning manual: hanya knob yang kamu ubah yang ditulis, lalu diterapkan ulang tiap boot. Bisa direset per knob.
- Profil per game (eksperimental, default mati): game dibuka → setelan game; ditutup → kembali Global.
- Pengaman panas, mode aman saat boot gagal, deteksi modul lain (Alpha, Uperf, fas-rs, dll).
- Preset buatan sendiri + ekspor/impor lewat clipboard.
- Empat tema (Carbon, Terminal, Paper, Blueprint). Banner dan wallpaper bisa diganti dari gear di banner.
- Monitor: pemakaian CPU nyata (dari /proc/stat), frekuensi per policy, GPU, suhu, RAM, swap, baterai. Tanpa grafik naik-turun.

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
Pasang `HSIN-v5.0.0-module.zip` → reboot → pasang APK → beri izin root.
Modul HSIN lama dengan id sama akan tergantikan; data lama di `/data/adb/hsin` tidak dipakai lagi.

## Tes modul tanpa HP
`bash tests/sandbox.sh dash` (juga `bash`): pohon sysfs palsu, 96 pemeriksaan (knob, boot, pengaman panas, per game, deteksi modul lain).
