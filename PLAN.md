# PLAN.md — HSIN manual (modul dulu, tanpa build)

## Tahap 0 — Inventarisasi + basis rakit (JALAN)
- [x] Repo GitHub isac12345/Hsin dibuat + proyek lokal ~/Hsin.
- [x] Kerangka AGENTS/NOTES/PLAN/STATE ditulis.
- [x] Audit tiap varian di /sdcard/hsin (dev-modul, TERIMA L1 statis:
  v4.2.5-consolidated + v4.2.6-fixed TERKONTAMINASI 9Router;
  v4.2.7 bersih tapi Extreme no-op; v4_0 metadata salah v3.0).
- [x] Pilih 1 basis rakit = hsin-dev v5.0.0-beta1 (0 dangling,
  0 kontaminasi, shellcheck 0, vCode 5001).
- [ ] Impor basis ke repo sebagai commit awal rakit (tanpa build).

## Tahap 1 — Fix isi modul (BELUM, tanpa build)
- [ ] Daftar error per file (shellcheck + bash-n + baca statis).
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
