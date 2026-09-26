# NOTES.md — HSIN manual

## Konsep (2026-09-26, perintah user)
- HSIN = modul + aplikasi, sama kayak Alpha. Bedanya: Alpha adaptif
  (gausah setting manual), HSIN manual/bebas (user setting sesuka hati).
- Fokus: modul dulu, APK belakangan. Jangan build dulu — fix isi file
  HSIN + rakit dari awal.
- Repo: isac12345/Hsin (public, dibuat 2026-09-26). Proyek lokal: ~/Hsin.
- Sumber: /sdcard/hsin/ — 6 zip + hsin-dev (v5.0.0-beta1, struktur
  paling lengkap: core/engine/capability/config/profiles/extreme/bin/
  webroot). User lupa mana yang bagus, tiap file ada error.

## Inventarisasi awal (2026-09-26, leader)
- Zip tertua: HSIN-v3_0-fixed (130 file), HSIN-v4_0 (130 file).
- Beta: HSIN-v4_2_5-beta (135 file).
- Konsolidasi: v4.2.5-consolidated (50 file, +META-INF/bin/core),
  v4.2.6-fixed (50 file), v4.2.7-fixed (50 file).
- hsin-dev: v5.0.0-beta1 (id=hsin, vCode 5001), profil default
  balanced, ALLOW_EXTREME=false. Kandidat basis rakit (perlu audit).
- Peringatan kontaminasi: v4.2.6 core/extreme.sh pernah terkontaminasi
  9router-sync (catatan Alpha). Audit wajib cek pola asing
  (9router/sync/curl keluar) di semua varian.

## PELAJARAN (warisan Alpha, berlaku di sini)
- Klaim pekerja tanpa bukti = jangan percaya, cek diff sendiri.
- Bump versi = cek semua lokasi versi (jangan setengah).
- Pola sed BRE: `\(` = grup, bukan kurung literal; `\n` di pola tak match.
- Harness sandbox wajib set variabel gate profil atau false-pass.
- Threshold thermal: high < critical, jangan samakan.
