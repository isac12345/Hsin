# Prompt untuk agent (OpenCode) — build HSIN v5.0.0

Konteks: repo ini sudah lengkap (modul `module/`, app `app/`, tes `tests/`, workflow `.github/workflows/build.yml`). Versi tetap **v5.0.0**. Tugasmu HANYA membuat build hijau dan mempertahankan perilaku yang sudah ada.

## Aturan keras
1. Jangan menulis ulang desain/fitur. Perbaiki hanya error kompilasi, resource, atau Gradle.
2. Jangan menambah dependency selain yang ada di `app/build.gradle.kts`. Jangan menaikkan versi AGP/Kotlin/Compose tanpa error yang memaksa.
3. Jangan pernah commit keystore (`*.jks`, `*.keystore`). Kunci hanya dari GitHub Secrets.
4. Jangan mengubah `module/` kecuali tes `bash tests/sandbox.sh dash` dan `bash` gagal. Kontrak ada di `docs/CONTRACT.md`; app dan modul harus tetap cocok.
5. Satu perbaikan per commit, pesan commit jelas. Jangan refactor.

## Langkah
1. `bash tests/sandbox.sh dash` dan `bash tests/sandbox.sh bash` harus PASS=50 FAIL=0.
2. Jalankan workflow `build`. Jika gagal, baca log, perbaiki error PERTAMA saja, push, ulangi.
3. Jika error Kotlin: perbaiki di file yang disebut (`app/src/main/java/com/hsin/*.kt`) dengan perubahan sekecil mungkin (import hilang, tipe, nama).
4. Jika R8/minify bermasalah: tambah rule di `app/proguard-rules.pro`, jangan matikan minify kecuali tidak ada jalan lain (catat alasannya).
5. Setelah hijau: pastikan artifact berisi `HSIN-v5.0.0.apk` dan `HSIN-v5.0.0-module.zip`.

## Verifikasi (laporkan hasilnya jujur, termasuk yang TIDAK bisa dicek)
- APK: ukuran, `applicationId=com.hsin`, `versionName=5.0.0`.
- ZIP modul: berisi `module.prop`, `customize.sh`, `service.sh`, `action.sh`, `uninstall.sh`, `core/lib.sh`, `META-INF/com/google/android/update-binary`.
- Yang hanya bisa dites di HP: root, tampilan, penulisan sysfs nyata. Jangan klaim sudah beres.

## Larangan
Jangan menambah mode profil (battery/balanced/performance), WebUI, bubble, atau notifikasi. HSIN = tuning manual penuh + preset buatan user.
