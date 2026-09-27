# NOTES.md — HSIN manual

## Kernel HP + root (2026-09-26, inventaris su read-only)
- Kernel jalan: 5.15.211-GrayRavens-Zenithed-Stable-KSUN (SUDAH
  GrayRavens). Root: KernelSU-Next (ksu/ksud/kpm + neozygisk),
  BUKAN Magisk. Aetherium (SukiSU) = ganti sistem root → tolak.
- Nagram: GrayRavens zip = sekeluarga (update aman); Aetherium =
  jangan. Kombo OC GPU: vendor_boot OC + GrayRavens (DTB vendor
  kepakai, driver Mali vendor utuh, do.modules=0).

## OC GPU 1.5GHz vendor_boot (2026-09-26, penasaran user, TERBUKTI)
- File: /sdcard/download/Vendor Boot Overclock Gpu 1.5Ghz.zip (1 img
  VNDRBOOT 100M). Parse DTB beneran (bukan strings): gpu@23100000
  sprd,dvfs-lists top level = 1500000 kHz @1100mV (4 level bawah sama).
- Live HP (su read-only): DT + available_frequencies = top 850000 kHz
  @800mV → HP jalan STOCK, img BELUM flash. Jadi klaim 1.5GHz di file
  BENERAN ADA (bukan teks), tapi di HP sekarang NILAINYA GA SEGITU.
- Catatan jujur: 850→1500 = +76% di Mali-G57 MP1, volt 0.8→1.1V.
  Kalau flash: risiko panas/instabil; driver/thermal/binning bisa
  nahan juga. Bukan bagian HSIN (tanpa ubah keputusan modul).

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

## CPU ke cache 2c (2026-09-26, leader + dev-modul, TERIMA + MERGE)
- Isi (work/cpu-cache → merge f58d2ed, 6 file 265+/47-): detect/apply/
  governor/frequency/scheduler cache-first (fallback identik, live:
  mask online + gov list + [ -w ]); safety 3→1 pass (suhu live,
  max dibanding semua zone, THERMAL_MAXZONE tak dipakai persempit).
- Verifikasi leader: bash-n 6/6, shellcheck 0, diff hanya file boleh;
  literal tuning (angka 4-7 digit + gov) IDENTIK kecuali `1091` dari
  komentar shellcheck-disable (bukan tuning); marker Source ada.
- Sisa jujur: ~6 read/policy + 1 pass zone masih live (nol mutlak
  butuh field cache baru); policy-baru-pasca-scan tak terlihat s/d
  rescan; `fail=2`   battery di sandbox = perilaku lama (bukan regresi).

## GPU ke cache 2d (2026-09-26, leader + dev-modul, TERIMA + MERGE)
- Isi (work/gpu-cache → merge c223501, 4 file 144+/20-): detector/
  devfreq/generic cache-first (OPP dari cache, -4 fork), node hilang
  = SKIP tanpa crash, tanpa OPP = gov saja, read-only = skip.
- Verifikasi leader: bash-n 4/4, shellcheck 0, diff hanya file boleh;
  literal tuning IDENTIK kecuali `1091` komentar (pola sama 2c).
- Sisa jujur: dvfs.sh masih glob (di luar daftar); node/OPP baru
  pasca-scan tak terlihat s/d rescan; kbase tak ikut backup (lama).

## Mem/IO/DVFS ke cache 2e (2026-09-26, leader + dev-modul, TERIMA + MERGE)
- Isi (work/memio-cache → merge 8adc31d, 8 file 265+/76-): mem/io/
  dvfs cache-first (zram via module-param num_devices + log bila tak
  baca; /proc via $HSIN_PROC; dvfs reuse cpu/gpu helper 2c/2d).
- Verifikasi leader: bash-n 8/8, shellcheck 0, diff hanya file boleh;
  literal tuning IDENTIK kecuali 1091/32 (bukan tuning); bug zram
  TERBUKTI (apply.sh panggil apply tanpa detect → selalu not-available).
- BUG antrean: aktifkan hsin_zram_detect di apply (perilaku berubah:
  zram mulai ditulis → perlu L2 hati-hati).
- Sisa: hsin_vm_read masih cat; node baru pasca-scan tak terlihat.

## Audit error per tweak 2f (2026-09-26, leader + dev-modul, TERIMA)
- Metode: harness sysfs palsu t1-t11, repo 0 berubah (verifikasi
  leader: porcelain kosong). Temuan (14, bukti harness):
- KRITIS #1 OOM proteksi MATI: HSIN_OOM_PROTECTED newline-separated
  tapi cek `case " $LIST "` pola spasi → system_server/zygote/SF/lmkd
  TAK PERNAH cocok (terbukti od -c + rc=1) → daemon bisa diobok.
  Fix 1-2 baris (satu baris spasi).
- #2 zram mati total (varian tak sinkron, sudah antrean 2e).
- #3 dvfs "OK applied" BOHONG: `echo > node && _applied++` (dvfs.sh:
  70,110) hitung redirect sukses, bukan nilai nyata (terbukti max
  tetap) → user percaya throttle aktif padahal tidak.
- #4 oom.sh:140 tanpa [-w]+verify (released 3 padahal 0).
- #5 zram readback absen; #6 devfreq.sh dead-code (0 pemanggil);
  #7 thermal_manager status kosong; #8 scheduler salah var log;
  #9 apply_sched no-op 0 pemanggil; #10 DEVFRES = false positive
  (dipakai konsisten 4x); #11 safety global bocor (kosmetik);
  #12 sisa | while benign; #13 komentar disksize salah; #14 91 /proc
  literal (penghalang sandbox, bertahap).
- Antrean fix: 1) OOM-protected 2) zram 3) dvfs-verify 4) oom-verify
  5) zram-readback 6) thermal-status 7) scheduler-log 8) dead-code
  putuskan 9) generic-msg 10) /proc→$HSIN_PROC bertahap.

## Fix zram #2 (2026-09-26, leader + dev-modul, TERIMA + MERGE)
- Isi (work/zram-fix → merge 8bcca04, 2 file 43+/19-): apply step 1
  panggil hsin_zram_detect + log; zram_apply normalisasi numerik +
  fallback var + tulis hanya bila [-w] + algo tersedia, selain itu
  skip+WARN; absen → return 0.
- Verifikasi leader: bash-n 2/2, shellcheck 0, diff hanya file boleh;
  mapping algo (zstd/lz4 + swappiness) utuh. Uji pekerja 4/4 (tulis
  ok=2, tak-tersedia skip+WARN, absen no-crash, read-only skip).
- Jujur: tulis kini AKTIF (dulu mati); kernel bisa tolak EBUSY →
  skip+WARN;   `memory state` masih tampil not-available (di luar scope).

## Fix dvfs #3 (2026-09-26, leader + dev-modul, TERIMA + MERGE)
- Isi (work/dvfs-verify → merge 319238a, 1 file 61+/19-): tulis clamp
  via hsin_node_write_verify + counter _fail + WARN per node + lapor
  "OK x / SKIP y"; rc=1 hanya bila semua gagal (sebagian tetap 0).
- Verifikasi leader: bash-n OK, shellcheck 0, diff 1 file; logika
  verify+fail ada di kode. Red-green pekerja: kode lama "OK applied"
  padahal max tetap (terbukti), kode baru SKIP+WARN+rc=1.
- Catatan: log tetap dvfs.log (bukan boot.log, demi diff minimal).

## Fix oom #4 (2026-09-26, leader + dev-modul, TERIMA + MERGE)
- Isi (work/oom-verify → merge ea9325a, 1 file 36+/12-): release via
  hsin_oom_set (tulis+readback) + ok/skip jujur + WARN per gagal +
  /proc via $HSIN_PROC (sandboxable) + logger.
- Verifikasi leader: bash-n OK, shellcheck 0, diff 1 file; proteksi
  byte-identik (md5 sama); logika jujur ada di kode. Red-green
  pekerja: lama "released 4" padahal 3, baru "released 3, skipped 2".
- Bonus: oom.sh kini bisa di-sandbox penuh (dulu 9 /proc literal).

## Fix zram-readback #5 (2026-09-26, leader + dev-modul, TERIMA + MERGE)
- Isi (work/zram-readback → merge bcb09f0, 1 file 34+/1-): fungsi
  hsin_zram_algo_live (cocok = dalam [siku] atau nilai persis);
  ok hanya bila live cocok, selain itu skip+WARN + live dicatat.
- Verifikasi leader: bash-n OK, shellcheck 0, diff 1 file; mapping
  algo utuh (0 baris mapping terhapus). Matriks 8 format cocok/skip
  benar + red-green (dulu ok=1tenang, kini skip+WARN).
- Bug tetangga antrean: pre-check case tak lepas [siku] → algo aktif
  bisa ter-skip sebagai "tak didukung" (task terpisah).

## Fix precheck-siku #6 (2026-09-26, leader langsung, task cancel)
- Isi (78742cc, 1 file +8/-2): pre-check apply + probe balanced
  lepas [siku] via tr (cek dukungan saja; readback #5 tetap ketat).
- Bukti: bash-n OK, shellcheck 0, uji 5 kasus (4 readback + balanced
  `[zstd]`→zstd yang dulu jatuh lz4). Push DONE.

## Fix thermal-status #7 (2026-09-27, leader langsung, ≤20 baris)
- Bug: thermal_manager.sh 2 call site (`hsin_thermal_engine_manage` +
  `monitor`) pakai `_status=$(hsin_thermal_classify ...)` padahal
  fungsi itu tak echo apa-apa (hasil via global HSIN_THERMAL_STATE).
  Akibat ganda: `_status` selalu kosong ("Current: 45°C ()") DAN
  assignment global hilang di subshell (induk tetap nilai basi).
  Pola benar (apply.sh/monitor.sh) = panggil lalu baca global.
- Isi (e20a351, 1 file +4/-2): 2 site jadi `hsin_thermal_classify`
  lalu `_status="$HSIN_THERMAL_STATE"`.
- Bukti: bash-n OK, shellcheck 0, uji red-green (lama `[]`+STATE basi,
  baru `[hot]`; cool→normal, panic→panic).
- Sisa cabang basi work/zram-precheck (varian helper c78cb22, diganti
  78742cc saat task cancel) dibersihkan (worktree remove + branch -D).

## Fix scheduler-log #8 (2026-09-27, leader langsung, 1 baris)
- Bug: engine/cpu/scheduler.sh:97 log
  `top-app/foreground -> BIG ($_cpus)` padahal `$_cpus` tak pernah
  di-set di `hsin_cpu_cpuset_apply` (hanya var loop di
  `hsin_cpu_topo_detect`) → log cetak kosong/sisa basi policy
  terakhir (bisa LITTLE), sementara tulis aktual pakai $HSIN_CPU_BIG.
- Isi (3034cf4, 1 file 1+-1-): log pakai `($HSIN_CPU_BIG)`.
  IO scheduler (engine/io/scheduler.sh) dicek bersih ($_name/$_ok/
  $_skip semua ter-set).
- Bukti: bash-n OK, shellcheck 0, demo (basi LITTLE vs BIG benar),
  sisa `$_cpus` di file hanya di dalam topo_detect (sah).

## PELAJARAN (warisan Alpha, berlaku di sini)
- Klaim pekerja tanpa bukti = jangan percaya, cek diff sendiri.
- Bump versi = cek semua lokasi versi (jangan setengah).
- Pola sed BRE: `\(` = grup, bukan kurung literal; `\n` di pola tak match.
- Harness sandbox wajib set variabel gate profil atau false-pass.
- Threshold thermal: high < critical, jangan samakan.
- Fungsi set-global + `$( )` = hasil hilang 2x (tangkapan kosong + induk
  basi). Panggil langsung lalu baca global (pelajaran fix #7).
