# PLAN.md — HSIN manual (modul dulu, tanpa build)

## RENCANA BUAT USER (baca ini aja, bahasa simpel)
- Target: HSIN manual/bebas setting, apply CEPAT (sekarang >15 dtk),
  scan SEKALI-simpan (ganti setting tinggal cek cache, ga scan ulang).
- Status: basis v5-beta1 sudah masuk repo (private). Belum ada yang
  diubah isinya. Tanpa build/zip dulu.
- Yang jalan otomatis (ga perlu kamu): implementasi cache + fix error
  per tweak, kecil per commit, diverifikasi statis dulu (L1).
- TUGAS KAMU (cuma 3, sesuai urutan):
  1. [x] SELESAI (2026-09-26, leader cek su izin user): `date +%s%3N`
     → 13 digit bersih, marker ms DIPERCAYA. HP Android 14, T615.
  2. NANTI tiap fix L1 selesai: flash zip uji + apply manual 1x + kirim
     baris `APPLY-TIME` dari `/data/adb/hsin/logs/debug.log` (itu bukti
     cepat/lambatnya, bukan rasa).
  3. PALING AKHIR: tes rasa (game adem/kenceng) = L2, bilang OK bila enak.
- Urutan kerja saya: cache scan (1) → backup ganda→1 + safety/IO ramping
  (2) → tulis+verify 1x (3) → error per tweak (4) → baru build bila kamu OK.

## Tahap 0 — Inventarisasi + basis rakit (JALAN)
- [x] Repo GitHub isac12345/Hsin dibuat + proyek lokal ~/Hsin.
- [x] Kerangka AGENTS/NOTES/PLAN/STATE ditulis.
- [x] Audit tiap varian di /sdcard/hsin (dev-modul, TERIMA L1 statis:
  v4.2.5-consolidated + v4.2.6-fixed TERKONTAMINASI 9Router;
  v4.2.7 bersih tapi Extreme no-op; v4_0 metadata salah v3.0).
- [x] Pilih 1 basis rakit = hsin-dev v5.0.0-beta1 (0 dangling,
  0 kontaminasi, shellcheck 0, vCode 5001).
- [x] Impor basis ke repo sebagai commit awal rakit (c6e6957, 110 file,
  tanpa build/, secret bersih, push DONE).

## Tahap 1 — Fix isi modul (BELUM, tanpa build)
- [ ] Syarat user (2026-09-26, dikunci): apply sekarang >15 dtk → harus
  singkat. Scan device gampang: scan SEMUA sekali lalu SIMPAN; ganti
  freq CPU/GPU/gov/tweak lain tinggal cek hasil scan itu (support/ga).
- [x] Ukur + peta scan (dev-modul, TERIMA: scan ulang tiap apply =
  biang; desain cache scan_cache.env disetujui arahnya).
- [x] Implementasi cache scan (langkah-1 DONE: core/scan_cache.sh +
  thermal cache-first, merge ab92aa3, push, L1).
- [ ] Langkah-2: fix policy-subshell (throttle no-op) + backup.sh ke
  cache + engine lain (cpu/gpu/mem/io) ke cache, satu per tugas.
- [ ] Tugas kamu-2 (L2): flash + apply + kirim APPLY-TIME (bukti cepat).
- [ ] Daftar error per tweak + code + kompatibilitas device.
- [ ] Fix satu per satu, kecil per commit (satu tujuan per tugas).
- [ ] Verifikasi statis tiap fix (L1). Tanpa flash/build dulu.

## Tahap 2 — Rakit final modul (BELUM, tunggu perintah build)
- [ ] Struktur final + versioning (module.prop sumber tunggal).
- [ ] Build/zip HANYA atas perintah user.
- [ ] L2 = tes HP user.

## Tahap 3 — APK (BELAKANGAN, belum mulai)
- [ ] Desain UI setting manual/bebas (kontras dengan Alpha adaptif).
- [ ] Menunggu modul stabil dulu.

## Aturan
- Tanpa build/zip/flash sampai user bilang.
- Satu tugas = satu tujuan. Verifikasi tiap langkah.
- Tanpa secret di repo. Tanpa force push.
