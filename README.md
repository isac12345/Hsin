# HSIN v5.0.0

Modul Magisk (tuning manual) + app Kotlin/Compose. Satu build di GitHub Actions menghasilkan dua file:
`HSIN-v5.0.0.apk` dan `HSIN-v5.0.0-module.zip`.

## Ganti gambar (sebelum build)
Timpa dua file ini dengan gambarmu, NAMA FILE HARUS SAMA:

| File | Ukuran saran | Fungsi |
|---|---|---|
| `app/src/main/res/drawable-nodpi/banner_default.jpg` | 1200×500 atau lebih, JPG | banner bawaan di Dash |
| `app/src/main/res/drawable-nodpi/ic_launcher_foreground.png` | 432×432, PNG transparan, isi di tengah (zona aman ±66%) | ikon app |

Warna latar ikon: `app/src/main/res/values/ic_launcher_background.xml`.
Banner dan wallpaper juga bisa diganti dari dalam app (ikon gear di banner).

## Build
1. Push semua isi folder ini ke repo GitHub (branch `main`).
2. (Opsional, supaya APK stabil tiap update) isi Secrets: `KEYSTORE_BASE64`, `KEYSTORE_PASSWORD`, `KEY_ALIAS`, `KEY_PASSWORD`.
   Tanpa secret, APK ditandatangani debug key. Keystore tidak boleh masuk repo (`.gitignore` sudah memblokir).
3. Actions → build → Run workflow → unduh artifact.

## Pasang
Pasang `HSIN-v5.0.0-module.zip` di Magisk/KernelSU/APatch → reboot → pasang APK → beri izin root.
Modul lama (v4) dengan id sama akan tergantikan; data lama di `/data/adb/hsin` tidak dipakai lagi.

## Tes modul tanpa HP
`bash tests/sandbox.sh dash` (pohon sysfs palsu, 50 pemeriksaan).
