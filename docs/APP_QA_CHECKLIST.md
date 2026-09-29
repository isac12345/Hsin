# APP_QA_CHECKLIST.md — Tes manual aplikasi di HP fisik

Semua nama diverifikasi ke kode (tab di `Tab`, tombol di `*Screen.kt`,
command di `RootClient.kt` allowlist + `docs/APP_CONTRACT.md`).
Hasil diisi angka/log, bukan klaim. Versi beta — tanpa klaim stabil.

## 1. Tanpa root (`su` tidak ada / ditolak)

- [ ] Buka app → Beranda menampilkan banner "Akses root tidak tersedia"
      (`ROOT_UNAVAILABLE`), bukan crash.
- Bukti: ________________

## 2. Modul nonaktif / tidak ada (`/data/adb/modules/hsin/action.sh` hilang)

- [ ] Beranda menampilkan "Modul HSIN belum terpasang"
      (`MODULE_NOT_FOUND`).
- Bukti: ________________

## 3. Run pertama (cache kosong)

- [ ] Beranda → Periksa ulang → capability terisi ("N knob tersedia"),
      guard terbaca via `guard-status` (bukan parsing log).
- Bukti (`knobs` count): ________________

## 4. Apply knob

- [ ] Knob → ubah 1 knob → tombol `Terapkan (1)` → sesudah apply baris hasil
      `diminta X → diterapkan Y (alasan)` + badge `APPLIED` muncul.
- [ ] Ubah 2 knob dengan 1 nilai invalid → hasil parsial: 1 `APPLIED`,
      1 `FAILED`, keduanya tampil per knob (bukan satu status global).
- [ ] Knob `APPLIED` tidak dirty lagi; knob `FAILED` tetap `DIUBAH`.
- Bukti (`knob-list` modul): ________________

## 5. Monitor berhenti saat keluar layar / background

- [ ] Monitor → angka berubah tiap ~2 dtk → pindah ke tab Beranda → kembali:
      polling berhenti saat di luar (tidak ada error, tidak freeze).
- [ ] Monitor → tekan Jeda → angka diam → Lanjut → jalan lagi.
- [ ] Monitor → app ke background → kembali: tidak ada polling menumpuk.
- Bukti: ________________

## 6. Salin laporan bug

- [ ] Log → tab `boot.log` / `apply.log` tampil (maks 200 baris, badge level
      per baris) → Salin ringkasan laporan bug → tempel di catatan:
      berisi `boot guard:`, `capability:`, ekor kedua log.
- Bukti (tempel ringkasan): ________________

## 7. Pulihkan backup + uninstall

- [ ] Beranda → Pulihkan backup → dialog konfirmasi muncul → Pulihkan →
      `rollback` (`Restore ... ok=N fail=M`) sukses atau pesan gagal jujur.
- [ ] Uninstall APK → modul tetap jalan (modul independen dari APK).
- Bukti: ________________

## 8. Kasus tepi lain (A13)

- [ ] Boot guard aktif (`guard-status active=1`) → banner
      "Tuning dilewati — boot guard aktif".
- [ ] `knobs` tanpa field `v` → banner "Versi modul tidak cocok".
- Bukti: ________________
