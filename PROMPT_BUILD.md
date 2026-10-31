# Prompt untuk agent (OpenCode) — build HSIN v5.0.0

Konteks: repo ini lengkap (modul `module/`, app `app/`, tes `tests/`, workflow `.github/workflows/build.yml`). Versi **v5.0.0** dan tidak boleh diubah: jangan menaikkan versi, jangan menulis "5.1" atau versi lain di kode, nama file, README, atau commit. Tugasmu: membuat build hijau dan mempertahankan perilaku yang ada.

## Aturan keras
1. Jangan menulis ulang desain/fitur. Perbaiki hanya error kompilasi, resource, atau Gradle, dengan perubahan sekecil mungkin.
2. Jangan menambah dependency atau menaikkan versi AGP/Kotlin/Compose kecuali error memaksa (catat alasannya).
3. Jangan pernah commit keystore (`*.jks`, `*.keystore`). Kunci hanya dari GitHub Secrets.
4. Jangan mengubah `module/` kecuali `bash tests/sandbox.sh dash` atau `bash` gagal. Kontrak app↔modul ada di `docs/CONTRACT.md` dan harus tetap cocok.
5. Satu perbaikan per commit, pesan commit jelas. Tanpa refactor, tanpa fitur baru.
6. (Direvisi v6.0.0 atas keputusan pemilik) Mode Hemat/Bawaan/Seimbang/Boost dan floating FPS DIIZINKAN. Tetap dilarang: WebUI dan notifikasi selain notifikasi wajib service floating. Boost tidak boleh dibatasi.

## Langkah
1. `bash tests/sandbox.sh dash` dan `bash tests/sandbox.sh bash` harus `PASS=96 FAIL=0`.
2. Jalankan workflow `build`. Jika gagal, baca log, perbaiki error PERTAMA saja, push, ulangi.
3. Error Kotlin: perbaiki di `app/src/main/java/com/hsin/*.kt` (import hilang, tipe, nama). Catatan: jangan membuat fungsi `setX` untuk properti `var x by mutableStateOf` (bentrok setter JVM); pakai nama lain.
4. R8/minify bermasalah: tambah rule di `app/proguard-rules.pro`; jangan matikan minify kecuali tidak ada jalan lain.
5. Setelah hijau: artifact harus berisi `HSIN-v5.0.0.apk` dan `HSIN-v5.0.0-module.zip`.

## Laporan (jujur, termasuk yang TIDAK bisa dicek)
- APK: ukuran, `applicationId=com.hsin`, `versionName=5.0.0`.
- ZIP modul: `module.prop`, `customize.sh`, `service.sh`, `daemon.sh`, `action.sh`, `uninstall.sh`, `core/lib.sh`, `META-INF/com/google/android/update-binary`.
- Hanya bisa dites di HP: root, tampilan, penulisan sysfs nyata, deteksi game lewat cpuset. Jangan klaim sudah beres.
