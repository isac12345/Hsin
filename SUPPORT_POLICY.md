# SUPPORT_POLICY.md — Kebijakan Dukungan (Phase 5, PQ Step 21)

## SLA Respons

Best-effort, **tanpa jaminan waktu respons** — proyek masih beta dan
dikelola developer individu. Tidak ada angka jam/hari yang dijanjikan.

Yang dijamin: laporan yang menyertakan log lengkap (lihat "Cara
melapor bug yang berguna" di bawah) lebih mungkin ditangani daripada
laporan tanpa bukti. Laporan tanpa log kemungkinan besar tidak bisa
ditindaklanjuti.

## Kanal Support

Satu-satunya kanal yang nyata (terverifikasi di repo ini):

- **GitHub Issues** di `isac12345/Hsin` — repo ini privat, jadi hanya
  kolaborator yang punya akses.

Tidak ada grup Telegram, Discord, email, atau kanal lain — semua itu
tidak ada di repo dan tidak diakui. (Audit 2026-09-27: `.github/`
hanya berisi `workflows/`, tanpa issue template; tidak ada alamat
kontak di `module.prop` maupun dokumen.)

## Matriks Kompatibilitas

Tidak diduplikasi di sini — satu-satunya sumber kebenaran adalah
`DEVICE_COMPATIBILITY.md` (PQ Step 16): 1 device tervalidasi,
sisanya graceful degrade. Bila kedua dokumen bertentangan, yang
berlaku adalah `DEVICE_COMPATIBILITY.md`.

## Yang TIDAK Didukung

- **Profil `extreme`** — belum pernah dijalankan di HP fisik sama
  sekali (lihat KETERBATASAN KERAS di `RELEASE_NOTES.md`).
  Kerusakan akibat mengaktifkan `ALLOW_EXTREME=true` di luar
  pengujian terkontrol bukan tanggung jawab dukungan ini.
- **Device selain yang tervalidasi** — ditangani sebagai graceful
  degrade (skip aman + log), bukan sebagai bug yang wajib difix.
  Laporan yang berguna untuk device baru: capability detection
  lengkap (lihat bawah), bukan tuntutan support.
- **Modifikasi pihak ketiga** yang bypass `boot_guard.sh`, menulis
  sysfs di luar `safe_apply.sh`, atau menambah file tanpa daftar
  runtime `build_release.sh` (lihat Safety Warning di `API.md`).

## Cara Melapor Bug yang Berguna

Rujuk (jangan salin ulang): lokasi log di `TROUBLESHOOTING.md`,
prosedur + template di `TESTING.md`. Sertakan minimal:

1. `service.state` + potongan `boot.log`/`error.log` yang relevan
   (`/data/adb/hsin/logs/`).
2. Output status boot guard: isi `.boot_fail_count` + baris `guard`
   di `boot.log`.
3. Hasil capability detection: `device.txt` (atau `hsin device`).
4. Untuk klaim device baru: isi template capability TESTING.md,
   bukan nama chipset saja.
