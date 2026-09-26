# NOTES.md — HSIN manual

## Konsep (2026-09-26, perintah user)
- HSIN = modul + aplikasi, sama kayak Alpha. Bedanya: Alpha adaptif
  (gausah setting manual), HSIN manual/bebas (user setting sesuka hati).
- Fokus: modul dulu, APK belakangan. Jangan build dulu — fix isi file
  HSIN + rakit dari awal.
- Repo: isac12345/Hsin (PRIVATE atas perintah user, dibuat 2026-09-26). Proyek lokal: ~/Hsin.
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

## Audit varian (2026-09-26, leader + dev-modul, TERIMA, L1 statis)
- Pekerja: audit read-only 6 zip + hsin-dev (scratch tmp, sumber
  utuh, ~/Hsin tak disentuh). Verifikasi leader: kontaminasi via
  `unzip -p core/extreme.sh | grep` + `grep -r` hsin-dev + cek
  extreme/ + git clean — SEMUA klaim inti cocok.
- Hasil: v3_0-fixed 130 entri bersih; v4_0 label v4 tapi isi v3.0/300
  (metadata salah); v4_2_5-beta 135 entri bersih; v4.2.5-consolidated
  TERKONTAMINASI (core/extreme.sh curl 127.0.0.1:20128 + timpa
  opencode.json); v4.2.6-fixed MASIH terkontaminasi (klaim "fixed"
  salah — hanya hapus marker, kode 9Router utuh, lolos bash-n karena
  Python dalam single-quote); v4.2.7 bersih kode tapi Extreme no-op
  (source 4 file extreme/* yang tak ada di zip); keluarga 50-file =
  capability/extreme/tools hilang, engine 34→1.
- bash-n: 0 gagal di SEMUA varian (terbukti tak bisa tangkap
  kontaminasi). shellcheck hsin-dev: 0 error.
- Keputusan: BASIS = hsin-dev v5.0.0-beta1 (38/38 referensi resolve,
  0 dangling, 0 kontaminasi, vCode 5001 tertinggi, id=hsin sama).
- PELAJARAN audit: label "-fixed" jangan dipercaya tanpa grep ulang;
  bash-n hijau ≠ bersih.

## Audit timing apply + peta scan (2026-09-26, leader + dev-modul, TERIMA)
- Peta: boot scan 1x (service.sh hsin_detect_all + capability, re-detect
  bila device.txt hilang); TAPI tiap apply manual/boost scan ULANG:
  cpu_detect, gpu_detect (3x), thermal_detect + read 3x, mem, io 4 glob,
  topo. Monitor tiap 10-15s dumpsys (terpisah, bukan apply).
- Koreksi hipotesis leader: hsin_safe_write retry-sleep 0 CALL SITE
  (tidak di jalur apply); sleep 1 SF hanya di live path (apply pakai
  boot path); capability_scan.sh 565 baris MATI (tak di-source runtime).
- Estimasi kasar apply manual T615 ≈ 3.5-9s (>15s bila zone/block 40+
  + flash/binder lambat). Biang terbesar: thermal 3-pass x3 call
  (1.1-3.6s), backup full tiap manual (~0.3-1.2s), binder settings
  5-8x (0.5-1.5s), source ~45 file (0.2-0.4s).
- Desain cache (disetujui arahnya, belum coding): $HSIN_DATA/
  scan_cache.env flat KEY=VALUE (topologi+node valid, bukan suhu);
  tulis saat boot + rescan manual + auto bila hilang/versi naik;
  engine apply baca cache + 1 test [-w], fallback scan lama bila
  cache absen; invalidasi via BOOT_ID/versi/rescan/>6 jam.
- Urutan fix: 1) cache + collapse thermal 3→1 pass; 2) backup ganda→1,
  safety 3→1, io 4→1 glob; 3) write+verify 1x + benahi marker.
  Ukur via APPLY-TIME (TERJAWAB 2026-09-26, cek su langsung izin user:
  `date +%s%3N` → `1790419620875` 13 digit bersih, Android 14, T615.
  Marker MILIDETIK DIPERCAYA di HP ini, bukan 0ms).
- PELAJARAN: file 500+ baris tak di-source = beban mati, jangan takut
  hapus/matikan; hipotesis lambat wajib diverifikasi call-site dulu.

## Cache scan langkah-1 (2026-09-26, leader + dev-modul, TERIMA + MERGE)
- Isi (work/scan-cache → merge ab92aa3, 8 file 698+/151-): modul baru
  core/scan_cache.sh (502 baris, cache $HSIN_DATA/scan_cache.env flat,
  tulis atomik, komit-setelah-valid, TTL 6 jam + BOOT_ID); thermal
  baca cache + [ -w ] tanpa fork + collapse 3→1 pass + marker
  `Zones from: cache|scan`; hook service boot + hsin-cli rescan +
  action capabilities; fallback scan lama bila cache absen/rusak.
- Verifikasi leader: main utuh pra-merge, bash-n 8/8, shellcheck 0,
  tanpa TODO/curl, marker ada, diff hanya file boleh. Klaim sandbox
  (cache-hit tanpa glob ulang, fallback identik, sampah→scan exit 0,
  old 16s→cache 0.2s di Termux) konsisten dengan kode yang dibaca.
- BUG LAMA ditemukan pekerja (belum fix, di luar scope): policy
  dipanggil dalam $( ) (apply.sh:41/:62) → HSIN_THERMAL_POLICY/
  PERF_TARGET di parent selalu default → cap thermal praktis no-op.
  Masuk antrean langkah-2 (fix = throttle nyata aktif, perlu L2 HP).
- Sisa glob: thermal/backup.sh masih glob (di luar daftar) → langkah-2.
- PELAJARAN: angka sandbox Termux ≠ HP — klaim cepat wajib L2
  via APPLY-TIME di HP sebelum bilang selesai.

## Backup ke cache 2b (2026-09-26, leader + dev-modul, TERIMA + MERGE)
- Isi (work/backup-cache → merge 5e80e74, 3 file 87+/20-): backup.sh
  baca zone dari cache (fallback glob, tanpa glob saat cache-hit);
  koordinasi HSIN_APPLY_BACKUP → 1 snapshot per apply manual, boost
  tetap skip; cpu/apply reuse snapshot (step 4/6/7 saja).
- Verifikasi leader: bash-n 3/3, shellcheck 0, diff hanya file boleh,
  logika cache-first + backup-once ada di kode. Uji sandbox pekerja
  (cache-hit 0 glob, fallback identik, zone siluman tak ikut,
  roundtrip persis, manual=1 snapshot/boost=0) konsisten.
- Sisa jujur: cooling_device* masih glob (cache tak simpan, di luar
  scope); zona tanpa type tak ikut backup (konsisten detect/policy);
  rollback CPU kini via session-restore (perlu L2 HP).
- Worktree sisa wt-policy-fix (tugas cancel) ikut dibersihkan.

## PELAJARAN (warisan Alpha, berlaku di sini)
- Klaim pekerja tanpa bukti = jangan percaya, cek diff sendiri.
- Bump versi = cek semua lokasi versi (jangan setengah).
- Pola sed BRE: `\(` = grup, bukan kurung literal; `\n` di pola tak match.
- Harness sandbox wajib set variabel gate profil atau false-pass.
- Threshold thermal: high < critical, jangan samakan.
