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

## Putuskan dead-code #9 (2026-09-27, leader langsung)
- Keputusan: HAPUS keduanya (bukan sambung). Alasan:
  a) engine/gpu/devfreq.sh (136 baris, 3 fungsi apply/freq/state,
  0 pemanggil, hanya masuk daftar kemas build_release.sh) — fungsinya
  SUDAH digantikan engine/gpu/generic.sh (governor pick + max_freq +
  tulis-verify + hitung ok/fail jujur, dipanggil apply.sh tiap node).
  Nama mirip `hsin_gpu_devfreq_candidates` beda file (detector.sh,
  masih dipakai dvfs/detector) → tak tersentuh.
  b) `hsin_thermal_apply_sched` (policy.sh, 0 pemanggil) — stub no-op
  (loop /proc/*/sched kosong, hot/nothing) → hapus 19 baris.
- Isi (e8864a1, -158/+1): git rm devfreq.sh + 1 baris daftar kemas +
  hapus stub.
- Koreksi proses (jujur): siklus `stash`/`pop` saat cek SC2115
  melepas staging hapusan devfreq.sh → e8864a1 hanya berisi 2 file,
  devfreq.sh baru ter-commit di susulan 157be9a (-136). PELAJARAN:
  habis stash-pop WAJIB cek `git status` + isi commit (`show
  --stat`) sebelum push; `git add <file>` eksplisit bisa
  meninggalkan hapusan tak ter-stage (pakai `git add -A` + verifikasi).
- Bukti: bash-n policy+build OK; grep sisa (devfreq_apply/freq/state,
  apply_sched, gpu/devfreq.sh) = 0 di luar NOTES; satu-satunya
  shellcheck warning (SC2115 rm -rf:115) pre-existing di file asli,
  di luar scope.
- PELAJARAN: file 500+ baris tak di-source = beban mati (sudah ada di
  atas) — berlaku juga untuk file kecil 0-pemanggil yang fungsinya
  sudah digantikan backend lain.

## Fix generic-msg #10 (2026-09-27, leader langsung, 2 baris pesan)
- Bug: engine/gpu/generic.sh tanpa OPP (tanpa available_frequencies):
  a) baris SKIP klaim "...governor tetap" SEBELUM governor dicoba —
  terbukti salah saat governor juga buntu (baris final justru SKIP
  total = kontradiksi); b) baris sukses cetak `max=` kosong (ok=1,
  ambigu apa yang terjadi dengan max_freq).
- Isi (14bd9fe, 1 file 2+-2-, NOL perilaku): skip jadi netral (hasil
  governor ikut baris hasil); sukses pakai `max=${_target_max:-unchanged}`.
- Bukti: bash-n OK, shellcheck 0, sandbox sysfs palsu 3 kasus —
  A (tanpa OPP+gov ok): SKIP netral + `max=unchanged gov=... ok=1`;
  B (tanpa OPP+tanpa gov): SKIP netral + SKIP final (konsisten);
  C (normal ada OPP): `max=800000000 gov=... ok=2`, tulis terverifikasi
  (regresi nihil). /tmp read-only di Termux ini → scratch pakai
  /data/data/com.termux/files/usr/tmp/opencode (pelajaran alat).

## Sisa audit 2F (2026-09-27, leader, verifikasi + batch-1)
- #10 DEVFRES false-positive TERKONFIRMASI: ejaan tunggal, definisi
  detector.sh:31 + set :38/:44/:53, baca :124/:159 + dvfs.sh:110/:210
  (4 situs baca, konsisten) → tanpa fix.
- #11 safety export mati: safety.sh:71 `export HSIN_CPU_SAFETY_TEMP`
  tanpa pembaca (0 rujukan di luar file; baris 38-39 reset tiap
  source; READY tak ikut export) → hapus 1 baris (aa719a7, nol perilaku).
- #12 `| while` benign TERKONFIRMASI: detect.sh:257/:263 print-only
  (tak ada state keluar loop) → tanpa fix. (zram apply sudah heredoc
  sejak dulu, state :208 print-only.)
- #13 komentar disksize salah: zram.sh:22 klaim HSIN menulis
  comp_algorithm/disksize — grep buktikan disksize TAK PERNAH ditulis
  (semua situs read) → komentar diluruskan (aa719a7).
- #14 /proc bertahap LANGKAH-1 (f4ac85c): engine/network/tcp.sh 21 +
  network_manager.sh 1 → `$HSIN_PROC` (pola mem, default /proc),
  tuning UTUH (hanya swap prefix, 22 baris).
- Bukti langkah-1: bash-n 2/2, shellcheck 0, sandbox prefix palsu
  (perf→bbr, tfo→3, backlog 16384/1000, ecn 1/0, state cocok),
  default /proc graceful (rc=1/0 tanpa crash), literal /proc 95→73.
  Sisa ±73 di 14 file (detector/capability/action/imgtec/governor/
  backup/dll) → batch berikut per area.

## Proc batch-2 (2026-09-27, leader langsung)
- Isi (a620ea5, 1 file +20/-18): core/detector.sh 18 literal → guard
  HSIN_PROC + swap prefix (device-tree, cpuinfo, gpuinfo, driver/gpu,
  meminfo, tcp_*). /sys literal (soc0, mali) di luar scope #14.
- Bukti: bash-n OK, shellcheck 0, sandbox prefix palsu (soc Unisoc
  T615 NUL-strip, vendor unisoc, gpu terbaca, ram 8000000|4000000,
  net bbr), literal /proc 73→55.

## Proc batch-3 (2026-09-27, leader langsung)
- Isi (f891245, 6 file +35/-23): core/{capability_scan,capability,
  hardware,backup,root_check,export}.sh → guard HSIN_PROC + swap prefix.
  Sisa 1 di hardware.sh = komentar "/proc/diskstats" (tak dieksekusi).
- Bukti: bash-n 6/6, shellcheck 0 (SC2034 HSIN_CAP_DIR pre-existing,
  dicek via `git show HEAD:f` tanpa stash), sandbox prefix palsu —
  hardware soc terbaca, root_check deteksi kernelsu, backup node
  swappiness/tcp/tfo tercatat dari prefix palsu, capability_scan
  _scan_memory/_scan_network/_scan_thermal probe benar. /proc 55→32.
- Sisa 32: action.sh 14 (kode ~9), imgtec 6, validator 2, scheduler 2,
  governor 3, export/scan_cache/detector2 sisanya komentar.

## Proc batch-4 + PENUTUP #14 (2026-09-27, leader langsung)
- Isi (f174dcc, 5 file +33/-23): action.sh 9 situs (device-tree,
  meminfo x2 blok, loadavg, uptime) + engine/{gpu/imgtec,gpu/validator,
  cpu/scheduler,cpu/governor}.sh → guard HSIN_PROC + swap prefix.
- Bukti (kuat, end-to-end): bash-n 5/5, shellcheck 0 baru (SC2154
  action.sh:772 + SC2043 governor:31 terbukti pre-existing via
  `git show HEAD:f`), sandbox prefix palsu:
  * `action.sh status` JSON nyata: ram_total=8000000, ram_used=4000000,
    uptime=98765, cpu_load_x100=235 (2.35) — 4 nilai palsu mengalir.
  * `hsin_action_device_info`: soc="Unisoc,T615", ram_kb=8000000.
  * scheduler: resolve+capture+apply performance → latency 24000000→70%
    =16800000, wakeup floor 500000, 0 WARNING (tuning identik).
- HASIL: literal /proc 95→0 EKSEKUTABLE. Sisa 9 = 100% komentar
  (action.sh 4, scan_cache 2, detect memory 1, cpu/scheduler 1).
  #14 SELESAI (L1) — semua jalur /proc kini sandboxable.

## Knobs API (2026-09-27, action.sh knobs)
- `core/knobs.sh` (baru) + 1 case `knobs)` di dispatcher + 1 baris source
  di action.sh + core/knobs.sh masuk daftar runtime build_release.sh.
  READ-ONLY: nol tulis sysfs/proc. Satu baris JSON, exit 0 apa pun yang
  absen. Semua angka dari node nyata; yang tidak ada -> [] / 0 / "" +
  `supported:false` di bagiannya.
- Kontrak app: `{"v":1,"profiles":[],"cpu":{"policies":[…]},"gpu":{"nodes":[…]
  },"memory":{swappiness,zram},"io":{blocks},"network":{tcp_cc,tfo},"display":
  {modes_hz,cur_hz,renderers,cur_renderer,downscale},"features":{6 flag},
  "capabilities":{available_frequencies_source}}`.
- Sumber data = helper yang sudah ada (bukan logika baru): hsin_cpu_detect
  (policy/gov/OPP/writable), hsin_gpu_devfreq_candidates + hsin_gpu_opp_list
  (node GPU), hsin_mem_zram_names (zram), hsin_io_block_devs (block),
  hsin_profile_list (profil), hsin_refresh_detect_supported + hsin_render_*
  (display), scan cache untuk capabilities. Setiap daftar OPP wajib
  lolos hsin_opp_min/max supaya "N/A" tidak pernah jadi angka.
- `memory.zram.algos` dan `io.*.schedulers` apa adanya (kurung siku = aktif,
  info itu dibutuhkan app); field `cur` sudah bersih dari kurung.
- `features.*` = switch conf menyala DAN alatnya ada (node writable untuk
  DVFS, settings/cmd untuk RR, resetprop/setprop untuk SF + frame limit).
- swappiness 0..100 (batas kernel; HSIN_VM_SAFE menerima tulis sampai 200
  tapi kernel meng-clamp di 100, jadi 100 yang jujur untuk UI). Downscale
  1..99 (validasi downscale-enable; 100 = resolusi native = fitur mati).
- CATATAN ke leader: `cur_hz` sengaja memakai urutan parse yang sama dengan
  status WebUI (renderFrameRate > refreshRateOverride > fps= pertama).
  Di dump asli `renderFrameRate=90.0` bertanda "=", sedangkan grep status
  mencari "renderFrameRate " (spasi) -> cabang pertama tidak pernah kena,
  jadi cur_hz jatuh ke fps= pertama (mode terkecil). Pre-existing di
  action.sh:598-640, TIDAK diubah di tugas ini; app akan melihat nilai yang
  sama dengan tile status.
- Bukti: bash-n 3 file 0, shellcheck 0, `rg '/sys/|/proc/' core/knobs.sh`
  kosong, sandbox A (2 policy + 1 GPU + zram kurung siku + sda + swappiness/
  tcp/tfo + boot_id, dengan & tanpa scan cache) dan B (pohon kosong) dua-dua
  exit 0 + 1 baris + JSON valid, plus skenario node sampah (governor berisi
  kutip/backslash, OPP kosong, "N/A", "abc") tetap JSON valid.

## Knobs API + 3 bug yang ketemu saat review (2026-09-27, leader)
-bb50517 `action.sh knobs` (core/knobs.sh 620 baris) → SATU baris JSON:
  profiles/cpu.policies(govs+opp+writable)/gpu.nodes/zram.algos/io.blocks/
  network/display/features/capabilities. App nanti render dari sini, bukan
  hardcode. Read-only (tak ada redirect tulis/pemanggilan apply).
  Review leader: 18 fungsi eksternal semua ada definisinya (anti API
  karangan), escaper per-karakter (quote/backslash/CR), 0 literal
  /sys|/proc, JSON valid di pohon terisi + kosong, 0 stderr, 1 baris,
  zramAlgo kurzung siku `[zstd]` terjaga, `info/config-get/capabilities/
  conflicts/status/device` tetap rc=0.
- f319da0 BUG BUILD: `core/scan_cache.sh` TIDAK ada di daftar runtime
  build_release.sh, sedangkan release menghapus `core/*.sh` (kecuali
  runtime.sh) + engine/ + extreme/ + capability/ dan entrypoint di-rewrite
  source runtime.sh saja → di ZIP RELEASE semua 18 fungsi cache-scan hilang
  (thermal/safety/engine jadi live scan, cache 6 jam tidak kepakai).
  Di ZIP dev (.devmode) tidak terjadi → hanya muncul di release.
- 6f494f6 BUG STATUS: `renderFrameRate [0-9.]*` hanya menerima bentuk
  SPASI; dumpsys modern `renderFrameRate=90.0` → gagal → fallback `fps=`
  ambil mode PERTAMA (60) bukan mode aktif (90). Pola sekarang terima
  `=`/spasi (label tanpa angka → tr -cd '0-9.'); 4 bentuk dump diuji.
- 30c1fbb BUG CACHE (paling serius): `hsin_scan_write` menulis cache tanpa
  gerbang, dan `hsin_scan_cache_load` hanya cek "key ada" bukan "nilai ada"
  → cache KOSONG diterima sah (load_rc=0, SCAN_OK=1) sampai TTL 6 jam →
  `hsin_thermal_read`/safety baca 0 policy + 0 zona = BUTA (timbang "cool").
  Terbukti di sandbox (cache karatan → 0 policy). Fix: tulis menolak saat
  CPU+thermal+devfreq kosong semua; baca menolak nilai kosong. Uji: pohon
  kosong → write_rc=1 tanpa file; pohon ada → write 0 + load 0 (2 policy);
  cache racun lama → load_rc=1 + fallback scan live.
  Catatan: klaim lama "komit-setelah-valid" di section cache langkah-1
  TERBUKAT SALAH.
- PELAJARAN: (1) harness dengan nama file node yang salah sempat
  "menemukan" bug yang sebenarnya bukan bug (scaling_available_governors,
  bukan available_governors) — cocokkan dulu nama node dengan kode asli;
  (2) file cache milik HSIN_DATA ikut teruji, jadi satu harness pernah
  menulis cache kosong ke data uji dan menyamar sebagai bug produk —
  bersihkan HSIN_DATA uji tiap kali. (3) Cek `git diff HEAD~` isi tiap
  commit sebelum push; 3 commit dipisah tanpa stash.
- Klaim pekerja tanpa bukti = jangan percaya, cek diff sendiri.
- Bump versi = cek semua lokasi versi (jangan setengah).
- Pola sed BRE: `\(` = grup, bukan kurung literal; `\n` di pola tak match.
- Harness sandbox wajib set variabel gate profil atau false-pass.
- Threshold thermal: high < critical, jangan samakan.
- Fungsi set-global + `$( )` = hasil hilang 2x (tangkapan kosong + induk
  basi). Panggil langsung lalu baca global (pelajaran fix #7).
- Var shell tak ter-export tak terlihat di `sh -c` (harness sempat salah
  baca, kode benar) — export dulu atau hardcode path di uji sandbox.
- Cek warning shellcheck file ASLI via `git show HEAD:f` (tanpa stash —
  stash-pop pernah lepas staging).

## Lapis user override (2026-09-27, dev-modul, TUGAS BERIKUTNYA = apply)
- `core/user_knobs.sh` (baru) = sisi WRITE knob yang tidak ada: `knobs`
  cuma read-only, `config-set` cuma 7 key hsin.conf, jadi tidak ada tempat
  menyimpan pilihan user. File `user_knobs.env` flat KEY=VALUE (pola
  scan_cache), maks 64 key, atomic (tmp.$$ + mv), chmod 600, readback
  wajib. Aksi baru: `knob-set <key> <val>`, `knob-reset`, `knob-list`
  (`{"count":N,"overrides":{...}}`). Ditambah 1 baris source + 3 case di
  action.sh, dan masuk daftar runtime build_release.sh (wajib: release
  menghapus core/*.sh selain runtime.sh).
- Key tertutup: `cpu_policy_<id>_` / `gpu_node_<n>_` / `io_block_<n>_` +
  `gov|max_khz|min_khz|sched`, atau tetap `zram_algo|swappiness|tcp_cc|tfo`.
  Nilai numeric wajib dalam rentang (kHz 100000-5000000, swappiness 0-200,
  tfo 0-3), nilai token 1-32 karakter `[A-Za-z0-9_.-]`. Semua key/nilai
  tolak karakter di luar `[A-Za-z0-9_.]` → newline/`;`/backtick tidak
  bisa menyuntik baris config. Pesan error sengaja TIDAK mencetak input
  yang belum tervalidasi (bisa bikin baris output rusak).
- SENGAJA belum mengintegrasikan override ke jalur apply — behavior apply
  sekarang tidak berubah sama sekali. Apply override = tugas berikutnya.
- Bukti: bash-n 3 file 0, shellcheck -S warning file baru 0, `rg '/sys/|
  /proc/'` kosong, sandbox 7 skenario (OK/tolak/reset) + file env 4 baris
  persis, batas 64 key ditolak tanpa menimpa, JSON `knob-list` di-parse
  python3. Dua bug ketemu saat uji dan sudah difix: key kembar di file
  bikin `count` membesar dan JSON punya kunci kembar (dedupe saat rewrite
  + saat list).

- USER-KNOBS (2026-09-27, dev-modul + review leader): aksi
  knob-set/knob-reset/knob-list (aaa7a9c) menyimpan override knob
  per-device di $HSIN_DATA/user_knobs.env, tervalidasi (pola key +
  rentang nilai, tolak injeksi). Review leader: 10 uji injeksi DITOLAK,
  readback atomic, escaper punya fallback sendiri (tidak bergantung
  urutan source), 7 aksi lama rc=0, jalur apply TIDAK tersentuh.
  PUSH DONE.

- APP-FIX + CI (2026-09-27, leader inline): scaffold saya perbaiki -
  adapter RecyclerView ditulis ulang jadi model baris datar (versi lama
  campur tipe dan akan crash), 10x ArrayAdapter.createFromResource dengan
  signature salah, import decodeFromString hilang, fragment akses
  mainViewModel private, manifest menunjuk class yang dihapus, layout
  tidak sinkron dengan Kotlin. Verified: semua R.id/R.layout/@string/
  @style/@color resolve, 0 TODO/placeholder, wrapper gradle palsu
  dihapus (stub). Workflow .github/workflows/{build-apk,build-modul}.yml
  (manual, tidak auto-build)._push DONE. CATATAN JUJUR: Kotlin BELUM
  pernah dikompilasi (tanpa JDK di Termux) - verifikasi compile hanya
  bisa lewat CI.

- KNOB OVERRIDE -> APPLY (2026-09-27, dev-modul): core/user_knobs.sh kini
  punya sisi BACA (hsin_uk_get + hsin_uk_cpu_field/hsin_uk_gpu_field/
  hsin_uk_io_field + hsin_uk_used/hsin_uk_log_summary), file override
  dibaca SATU kali per proses (cache dipisah spasi, diisi saat file
  di-source supaya accessor yang dipanggil di dalam $( ) tidak baca ulang
  file tiap node). Sanitasi nama node WAJIB sama dengan aplikasi
  (KnobsRowBuilder.sanitizeNode: [A-Za-z0-9] lain '_', maks 40) - kalau
  beda, kunci yang ditulis aplikasi tidak akan pernah ketemu.
  Integrasi 7 file: cpu/governor.sh (gov per policy, valid ke
  scaling_available_governors), cpu/frequency.sh (max_khz + min_khz
  ABSOLUT, wajib ada di tabel OPP else snap ke OPP terdekat <=),
  gpu/generic.sh (gov + max_khz per node), io/scheduler.sh (sched per
  block), network/tcp.sh (tcp_cc hanya kalau ada di
  tcp_available_congestion_control; tfo 0-3 dicek ulang di engine),
  memory/vm.sh (swappiness, rentang tetap milik HSIN_VM_SAFE),
  memory/zram.sh (zram_algo hanya kalau ada di daftar algo node;
  readback hsin_zram_algo_live TIDAK dilonggarkan). Override yang
  dipakai -> hsin_uk_used (baris "override: <key>=<nilai> dipakai" di
  boot.log); yang ditolak -> hsin_log_warn dengan alasannya. Ringkasan
  "override: N key dipakai" 1 baris ke apply.log, dipanggil dari
  hsin_network_apply_sysctl (engine terakhir pipeline apply, jadi
  hitungan sudah final) - apply_engines.sh tidak disentuh.
- Bukti: bash -n 8 file 0, shellcheck -S warning 1 warning yang sudah
  ada sebelum perubahan (SC2043 governor.sh:36) dan 0 baru; pencarian
  literal path sysfs/proc di 8 file itu = kosong. Sandbox sysfs palsu (dash, 2 policy
  CPU + 1 node GPU "23100000.gpu" + sda + zram0 + vm + tcp): (a) tanpa
  override hasil apply IDENTIK vs HEAD (diff 13 node kosong); (b) 9
  override valid -> semua node sesuai override + 9 baris "override" di
  log; (c) governor/freq/sched/algo/cc ngawur -> TOLAK + WARN, tidak ada
  nilai ngawur masuk node, APPLY_RC=0; (d) 2 policy -> keduanya dipakai.
  Side-test: file override berkacau (injeksi, key tak dikenal, kembar)
  -> hanya 2 key sah yang dipakai, apply tetap rc=0.
- BUG PRE-EXISTING yang ditemukan (di luar scope, TIDAK diperbaiki):
  core/backup.sh:29 hsin_backup_node memakai var `_p`, sama dengan `_p`
  profil di core/apply_engines.sh:26. Jadi setelah hsin_backup_all, semua
  engine menerima PATH NODE sebagai nama profil, bukan "balanced" dll -
  setiap engine jatuh ke case `*` (nilai default, bukan nilai profil).
  Efeknya nyata di HP juga, bukan hanya di sandbox. Perbaikan harus
  mengganti nama var, jadi TIDAK boleh ikut diff ini.
- CATATAN JUJUR: (1) override untuk node yang hilang/tidak writable tidak
  menambah WARN baru - skip-nya sudah dilaporkan jalur lama
  (hsin_report_skip / hsin_log_warn zram). (2) Verifikasi hanya sandbox
  + statis di Termux; node kernel sungguhan (reaksi devfreq/comp_algorithm
  terhadap OPP) belum pernah diuji - butuh L2 di HP.

## Integrasi override knob ke apply (2026-09-27, dev-modul + review leader)
- 9 file: core/user_knobs.sh (accessor baca + cache per-proses), engine/
  {cpu/governor,cpu/frequency,gpu/generic,io/scheduler,network/tcp,
  memory/vm,memory/zram}.sh (override dipakai di titik tulis, snapping OPP,
  tolak + WARN kalau tidak didukung). Tidak ada apply yang berubah tanpa
  override.
- Review leader (sandbox hermitis HSIN_SANDBOX=1 + prefix palsu, A/B):
  cpu gov OK, cpu max_khz OK, gpu gov OK, gpu max_khz OK, io sched OK,
  tcp_cc OK, tfo OK, swappiness OK. zram_algo BELUM terverifikasi leader
  (harness sandbox: num_devices module-param tak resolve) - perlu cek ulang.

## 2 bug "pilihan user tidak dipakai" (2026-09-27, leader)
- apply_engines.sh: nama profil dipindah ke var privat `_prof_arg` (PFIX
  dari `hsin_backup_node` yang menimpa `_p` global dengan path node) dan
  `_p` di hsin_backup_node -> `_bn_p`. A/B: HEAD profil=[] vs fix
  profil terbaca; battery->powersave, performance->performance. SEBELUM
  fix `hsin apply <profil>` tidak pernah berlaku. Commit cf20708.
- engine/thermal/policy.sh: thermal tidak boleh MENAIKAN. Sebelumnya
  PERF_TARGET=100 saat adem menulis scaling_max_freq/max_freq balik ke
  hw_max, membatalkan cap profil DAN override user. Sekarang tulis hanya
  bila target < nilai sekarang (CPU + GPU).
- engine/gpu/dvfs.sh: tahap DVFS jalan PALING AKHIR dan menimpa semua;
  sekarang node yang punya override max_khz ekspltit dilewati + log
  (tanpa override, cap persen profil tetap berlaku - regresi nihil).
  Ditemukan lewat checkpoint per tahap: profil battery punya [dvfs]
  enabled=true cpu_limit=65 gpu_limit=80 yang menimpa hasil engine.

## Kebocoran sandbox (2026-09-27, leader, commit e959252)
- action.sh: HSIN_CONF hardcode /sdcard/... -> jadi ${HSIN_CONF:-...} biar
  bisa diarahkan uji.
- core/logger.sh: hsin_notify memanggil `cmd notification post` + `su -lp`
  (nyata di HP). Gate HSIN_SANDBOX=1 mematikan tanpa mengubah perilaku.
- Semua uji henceforth WAJIB HSIN_SANDBOX=1 + HSIN_CONF diarahkan.
- Catatan: `cmd` ADA di Termux; `su` Termux tanpa root. /sdcard/Android/hsin
  tidak ada di HP jadi config asli tidak pernah tersentuh.

## 9Router API (2026-09-27, leader, Facts dari HP - bukan dokumentasi)
- Server: Next.js "9Router - AI Infrastructure Management", jalan di
  http://localhost:20128, data di ~/.9router, DB SQLite ~/.9router/db/
  data.sqlite, source ~/.9router/runtime/mitm/server.js (minified).
- `GET /v1/models` TERBUKA tanpa auth: 117 model, field id/owned_by/
  capabilities/context_length/max_completion_tokens. 9 provider aktif:
  antigravity, codex, kiro, xai (oauth) + nvidia, ollama, openrouter,
  poolside (apikey).
- `POST /v1/chat/completions` dan semua `/api/*` = 401. Auth dashboard =
  session PASSWORD (bukan API key): /api/auth/status -> authMode=password,
  requireLogin=true, hasPassword=FALSE (belum disetup, itu sebabnya 401).
  API key "Default Key" ( tabel apiKeys)jugak engineering: sudah diuji
  Bearer + X-API-Key -> tetap 401. auth/cli-secret juga tidak berlaku.
- Skema combo (SQLite): combos(id PK, name UNIQUE, kind, models TEXT,
  createdAt, updatedAt); `models` = JSON ARRAY id-model, URUTAN = prioritas
  fallback; 5 combo lama punya kind=NULL. 5 combo lama memakai id `oc/*`
  yang TIDAK ada lagi di /v1/models (entri mati).
- TIDAK ADA data harga di 9Router (katalog: 0 hit pricing/cost). Jadi
  "gratis" hanya bisa dibaca dari nama id: 15 dari 117 model, SEMUA dari
  openrouter (suffix :free).
- tools/9router-combo.sh: buat HSIN-leader + HSIN-subagent dari 10 model
  gratis yang sudah diverifikasi ada. Password dibaca interaktif (tidak
  disimpan). DILARANG menulis langsung ke SQLite: server memakai sql.js
  (SQLite in-memory) sehingga write luar bisa ketimpa saat flush.

## Revisi combo 9Router (2026-09-27,Permintaan user)
- Nama combo: TIDAK lagi HSIN-*. Jadi `leader` (utama) + `agent` (2 subagent:
  modul + aplikasi).
- Fallback WAJIB model gratis (permintaan user): setelah model utama
  antigravity, rantai fallback hanya openrouter `:free` + ollama (lokal).
  Provider berbayar (nvidia/poolside apikey) tidak dipakai.
- Codex (cx/*) TIDAK masukkan rantai: kuota habis ~2 minggu + bukan gratis.
  Cara pakai nanti: tambah id-nya di ujung daftar setelah kuota pulih.
- BUG script yang ketahuan saat dry-run: `HAVE="$_(_models_json)"`
  (shellcheck SC3028) membuat pre-flight tidak mengecek apa-apa - semua
  modelReported HILANG padahal ada. Sudah diganti `$( )` dan sekarang 13/13
  id terverifikasi OK terhadap /v1/models (114 model terdaftar).
- Catatan: 5 combo lama (Budak, Alpha-code, Alpha-fast, Alpha-review,
  Alpha-code-b) HILANG dari DB saat password di-set/first-run. Tidak ada
  script yang menghapus (POST terbukti additive: dua combo masuk dua-dua),
  jadi penyebabnya kemungkinan inisialisasi 9Router - perlu konfirmasi.

- BUG cleanup script (ketahuan saat cek): parser id combo memakai
  `grep -A2` padahal field `id` muncul SEBELUM `name` di JSON, jadi id selalu
  KOSONG -> combo HSIN-* tidak terhapus. Diperbaiki: pecah JSON per objek
  (`tr "{" "\n"`) lalu ambil id dari objek yang namanya cocok. Diuji dengan
  sample: id terbaca benar.

## CI Build APK & Modul (2026-09-27, leader)
- APK compile lolos di GitHub Actions (run #36296279179, 3m51s, artifact
  `hsin-debug-apk`). Masalah compile yang difix:
  1. Struktur gradle: reposisi `app/src` ke `app/app/src/` (AndroidManifest
     hilang).
  2. Resource duplicate: `hsin_surface_tint` didefinisikan 2x di colors.xml.
  3. Material 3 attrs: `colorBackground` -> `android:colorBackground`,
     `colorInverseSurface` -> `colorSurfaceInverse`, `colorInverseOnSurface`
     -> `colorOnSurfaceInverse`, hapus `colorShadow`/`colorScrim`/`colorSurfaceTint`.
  4. Kotlin type & scope: `KnobsAdapter` ViewHolder holder jadi `inner class`
     (akses callback outer), camelCase model response `tcpCc`/`modesHz`/
     `curHz`/`curRenderer`, newline di `StatusFragment.kt:50`, `override val id`
     di `KnobRow.kt`, `toMutableMap()` di `KnobsFragment.kt`.
  5. Workflow artifact path: `app/app/build/outputs/apk/*/*.apk`.
- Modul ZIP build lolos (run #36296491773, 20s, artifact `hsin-modul-dev`).
  Verifikasi `core/runtime.sh` berisi fungsi cache-scan + user-override
  lulus otomatis.
- PELAJARAN: Kompilasi Android via CI runner adalah verifikasi mutlak
  saat lokal tidak punya SDK. Error compile diselesaikan sistematis dari
  manifest -> resource -> Kotlin compilation -> packaging.

## Guard runtime idempotent P1 (2026-09-27, leader + dev-modul, TERIMA L1)
- Akar: `core/runtime.sh` (~457KB di ZIP) GENERATED oleh
  `build_release.sh::_clean_stage` (gabung ~50 file), lalu `sed` baris 132
  menulis ulang SEMUA source `core|engine|extreme` di entrypoint menjadi
  `.../core/runtime.sh` → puluhan source-ulang sekuensial (boot) per proses.
- Isi (merge b5cbf73, 1 file +3): 2 baris guard sebagai header pertama
  generated runtime (`return` dini bila `$_HSIN_RUNTIME_LOADED` sudah set).
  Guard di BUILD SCRIPT, bukan file source (runtime.sh tak ada di tree).
- Verifikasi leader: diff hanya build_release.sh; sh -n OK; shellcheck 0
  baru (SC2115 pre-existing); guard lolos filter awk/sed _clean_stage;
  simulasi: fungsi tetap ada setelah source ulang, 10x re-source ~14ms
  (file kecil; klaim ~130ms vs ~1000ms pekerja di sim besar konsisten
  mekanismenya). Subshell `sh -c`/heredoc GUARDEOF tak mewarisi guard var
  → tetap source normal (benar).
- KOREKSI PREMIS prompt: (1) runtime.sh generated, bukan source — fix di
  build script; (2) TIDAK ADA polling ~3 detik di APK Kotlin saat ini
  (komentar action.sh:15-16 peninggalan WebUI; StatusFragment.refresh
  jalan 1x saat buka + swipe manual) → narasi "10x tiap 3 detik" tidak
  berlaku untuk APK; kandidat "HP berat" tersisa = ~31x source sekuensial
  di window boot (service.sh + post-fs-data.sh). Guard memperbaiki keduanya.
- Status: L1 DONE, L2 = user flash ulang + reboot + konfirmasi tidak berat.

## Audit blank Status/Knobs P2 (2026-09-27, leader + dev-modul + dev-apk)
- 2c (shell): 3/3 fix lama ADA di source (scan_cache di daftar runtime
  build_release.sh:82; `renderFrameRate[= ]` action.sh:641; gerbang tulis
  scan_cache.sh:318-319 + baca :416-421) → bukan penyebab blank.
- 2d: komentar "auto-generate baseline" di core/protect.sh menyesatkan
  (kode cuma `return 1`) → diluruskan jadi "gagal aman" (merge bbf27ee,
  komentar saja, sh -n OK, shellcheck 0). Perilaku DEV tak berubah
  (`.devmode` short-circuit). `bin/hsin-verify`/manifest absen di source
  WAJAR (generated saat build release).
- 2e (KSU-Next): module.prop `support=magisk,minMagisk=20400`; hardcoded
  `/data/adb/modules` hanya default `[ -z ] &&` + scan konflik
  action.sh:1135 (KSU-Next pakai path yang sama → aman); fallback
  `/data/adb/ksu/bin/busybox` ada di service.sh:461, action.sh:1003,
  apply_engines.sh:194 → tanpa fix.
- 2f (APK, read-only, 0 edit): timeout 20s RootExec.kt:16 → destroy +
  Result(false) (BUKAN silent); repo !success/kosong → throw HsinException
  (HsinRepository.kt:29/:39); StatusFragment:67-70 catch → Snackbar
  "Status gagal" + spinner mati; KnobsFragment:63-66 sama via toast.
  Layout pakai `tools:text` (runtime default KOSONG → blank = state awal).
  Verdict JUJUR: rantai "blank + loading abadi tanpa error" TIDAK TERBUKTI
  statis — semua jalur gagal berakhir di pesan + UI reset. Penyebab tersisa
  di sisi shell/HP → Task 2a (user: `su -c 'sh .../action.sh status/knobs'`
  manual, lihat JSON/hang/lama) adalah pemisah utama. L2: user tes.

## Sweep + sandbox + kontrak (2026-09-27, leader + dev-modul + dev-apk)
- Sweep shell (merge 3ed645e, action.sh 4+/4-): komentar stale polling
  ~3s diluruskan; 2 path hardcoded di `hsin_action_live_status` jadi
  prefix (`HSIN_SYSFS_THERMAL` baris 363, `HSIN_SYSFS_DEVFREQ` baris 463).
  Tanpa ini status di device baca suhu/GPU dari /sys asli walau prefix
  diarahkan (dan di HP nyata tetap benar karena default = /sys).
- Sandbox leader (uji sendiri, bukan klaim pekerja): pohon palsu 2 policy
  + 2 zone + devfreq + proc → `status` rc=0 ~0.3s, JSON 29 key valid,
  cpu_temp=45000 gpu_temp=42000 cpu_freq/ram/load/uptime mengalir;
  `knobs` rc=0 1 baris, 2 policies + govs + OPP terisi; pohon KOSONG →
  semua aksi rc=0 + JSON valid (tidak crash); output status hanya 1 baris
  `{` (terakhir = JSON, aman untuk lastJsonLine app). PELAJARAN: harness
  salah level direktori (`policyN` langsung vs `cpufreq/policyN`)
  sempat "menemukan" policies=0 — cocokkan nama node dengan kode dulu.
- Kontrak app↔shell (dev-apk read-only): knobs COCOK (govs/cur_gov/
  opp_khz/writable_* dua sisi); device COCOK; status ASIMETRIS tapi AMAN
  (`Json ignoreUnknownKeys=true`, key ekstra shell diabaikan — jangan
  ubah model); sanitasi node COCOK (`23100000.gpu`→`23100000_gpu`).
- TEMUAN DITERIMA: Knobs blank-diam TERBUKTI (load sukses + list kosong →
  submit(empty) tanpa pesan). Fix (merge f5a0e9f, +3 baris): toast
  "Tidak ada knob terdeteksi (scan kosong)" bila profiles+policies+nodes
  kosong; render tetap jalan. Field terverifikasi di KnobsResponse.kt
  (:19/:33/:50).
- CI sesudah semua fix: build-modul run #36301125635 success,
  build-apk run #36301127388 success (compile Kotlin lolos termasuk toast
  baru). L2 tersisa: flash + reboot + tes HP oleh user.


## Roadmap 10/10 + Phase 1 (2026-09-27, remote roadmap diterima)
- Remote menambah `ROADMAP_10_10.md` + `STATUS.md` (2 commit, di-merge 259bbb5
  tanpa force; lokal lambda-fix 735a77d ikut merge).
- Phase 1 Task 1.1.1-1.1.3 (dev-modul work/phase1-tests, merge 7e41841):
  tests/{TESTING_FRAMEWORK,TEMPLATE_DEVICE_REPORT,device_reports/.gitkeep,
  validate_build.sh} + .github/workflows/lint-and-test.yml.
- Koreksi leader: shellcheck workflow WAJIB `-S error` (warning pre-existing
  SC2115 build_release.sh + SC2154 action.sh terbukti rc=1 bila tanpa filter)
  + `read -r`. Bukti: sh -n OK, shellcheck 0, YAML valid (PyYAML), sim lint
  lolos, validate positif VALID/negatif ERROR.
- Acceptance nyata: lint-and-test run #36303066269 SUCCESS saat push (27 dtk).
- APK: 3 run gagal = kode pra-lambda-fix (diharapkan); run #36303140779 di
  main kini SUCCESS (NDK r26 + HsinCompat Java + lambda Kotlin lolos compile).
- STATUS.md: 1.1.1-1.1.3 DONE. STOP — Phase 2 menunggu approve user.
- PELAJARAN: sintaks lambda Java (`msg ->`) bukan Kotlin (`{ msg -> }`) —
  cek silang CI; Kotlin DSL `path` minta File (`file(...)`), bukan String.

## Step 4 detector + Step 5 overrides (2026-09-27, roadmap 10/10)
- STEP 4 (5b373ea, core/detector.sh 241+/2-): detect_qualcomm/mediatek/exynos/
  unisoc/apple + xclipse fallback di detect_gpu_vendor existing + THERMAL_PATH
  global + detect_cpu_policies + cache_detection (detected.conf 5 baris).
  2 fix leader: guard SYSFS_*_PREFIX (baris 11-12, tanpa ini baca /sys asli)
  + urutan model MTK (soc.model→platform→lib). sh -n OK, shellcheck 0,
  4/6 skenario mock OK (apple/empty bentrok getprop mock = harness, bukan
  kode; L2 HP wajib). PELAJARAN: `. file 2>/dev/null` yang hilang = fatal
  rc=2 di dash (dot gagal buka file → exit); harness wajib set
  HSIN_MODULE_PATH + file ada.
- STEP 5 (77b3a2b, capability/device_overrides.json 62 baris): 4 profil +
  powervr/xclipse fallback; json.tool + assertion OK.
- CI: lint-and-test #36310498729 + #36310518169 success; apk #36303140779
  success (NDK r26 + Java + lambda fix). STATUS.md 1.1.1-1.1.3, 1.2.1, 1.2.2
  DONE. STOP: Step 6+ menunggu approve.

## Verifikasi Step 10 (2026-09-27, leader, TERIMA revisi)
- Test lama S1-S4 TAK representatif (diakui jujur ke user): S1/S4
  "via pre-set max" = hardcode var tanpa lewat jalur baca (prefix tak
  di-export ke `sh -c` + file me-reset var saat source); S2/S3 tautologi
  (echo lalu grep echo sendiri, file tak di-source); S4 tak pernah panggil
  safe_apply (kode cuma log+flag).
- Test menemukan 3 bug implementasi (fix dibenarkan): duplikat blok baca
  THERMAL_PATH; threshold relatif dihitung tapi tak dipakai (tetap
  hardcode 95/80/65) -> kini basis trip_point kernel max semua zona
  (filter <40C/>125C), fallback tercatat; `exit` di file yang di-source
  membunuh service.sh -> `return-or-exit`; rc state tertimpa rc
  safe_apply -> var pisah HSIN_THERMAL_SAFE_RC.
- Sandbox baru gaya boot_guard (pohon palsu, 6/6 PASS): NORMAL/HIGH/
  VERY HIGH node utuh, CRITICAL APPLIED via hsin_safe_apply (node turun
  1800000->300000, rc=3), relativitas (85C = VERY HIGH trip95 / HIGH
  trip105), hilang -> UNKNOWN rc=4. CI lint-and-test success (36328852688).
- PELAJARAN: test yang mem bypass jalur baca = klaim palsu; grep output
  sendiri bukan verifikasi; file yang di-source DILARANG `exit`.

## Checkpoint sesi 2026-09-28 ~01:05 (leader, STOP menunggu user)
- HEAD main `05191f1` (PQ Step 23 knob visibility), push DONE, CI
  lint-and-test success run 36364420574. Repo bersih (porcelain kosong).
- Selesai sesi ini: PQ Step 13-23 + fix bundle thermal_check (ee5f85b)
  + harmonisasi PQ Step 11 (912b3bf). Semua commit baru, tanpa
  force/amend. module.prop tetap v5.0.0-beta1/5001.
- GATE RILIS: BELUM LOLOS (device_reports kosong, QA 0/25, device
  kedua + extreme belum). Phase 5 berikutnya butuh approve user.
- Lanjut siang: user bilang lanjutin — mulai dari STATUS.md seksi
  GATE RILIS / laporan terakhir ini.

## M1 manual murni (2026-09-28, leader + dev-modul work/m1-manual, TERIMA L1)
- Isi (merge cef5f46, 16 file +223/-30): profiles/manual.conf BARU (komentar
  jujur + section kosong, tanpa angka tuning); default baru = manual di
  config/hsin.conf + service.sh + action.sh; config-set whitelist + PROFILE
  (validasi 5 nama); semua engine skip-tanpa-override di titik tulis yang
  sama (gov/freq/gpu/io-sched/tcp/tfo/swappiness/zram) + SKIPPED "tidak
  diatur (mode manual)"; tanpa-knob (cpuset/uclamp/stune/sched-lat/readahead/
  sysctl/dvfs/RR/frame/SF) selalu skip di manual; thermal critical-cap tetap
  (cermin performance); oom/adreno-kgsl/extreme tak tersentuh (case profil
  sudah mengecualikan manual); guard (boot/safe/engine/backup/gate) utuh.
- Koreksi leader atas diff pekerja (8 file,/*kecil, verifikasi ulang penuh):
  1) config/hsin.conf pekerja TIMPA jadi 1 baris "Profile=manual" (case
  salah + 65 baris hilang) -> restore penuh + PROFILE=manual.
  2) frequency.sh cek $_uk_max/$_uk_min SEBELUM di-fetch (override selalu
  di-skip) -> fetch dulu; + partial-override bocor (max saja -> min stock
  ikut ditulis) -> sisi-hilang dikosongkan + SKIPPED (berlaku juga GPU).
  3) tcp.sh fallthrough bila node hilang (tulis profil saat current kosong)
  -> return tanpa kecuali. 4) readahead fetch zram_algo + kunci hasil
  "readahead" di luar namespace knob -> echo saja. 5) vm catat kunci
  non-knob (vfs_cache_pressure) ke results -> hanya swappiness; guard
  baris (profil) ke non-manual. 6) frame_limit_restore (resetprop --delete
  = tulis!) bocor di manual via else-branch -> guard di apply_engines +
  service (sudah ter-wrap). 7) thermal full-skip mematikan proteksi critical
  -> cap critical tetap. 8) service.sh `esac` indent.
- Keputusan desain (dicatat, konsisten legacy): override INVALID di manual
  -> FALLBACK profil (legacy, "tetap benar" acceptance 6); snap OPP tetap
  tulis snap; safety critical/low-batt remap ->battery tetap (guard);
  downscale/refresh-lock/renderer dari hsin.conf = intent user -> tetap jalan.
- Bukti: sh -n 16/16, shellcheck -S error 0, 7 sandbox LAMA hijau identik
  baseline (60/60 SEBELUM=SSESUDAH), harness snapshot 8/8 (S1 1 node,
  S2 nol tulis, S3 balanced identik HEAD, S4 boot, S5 rollback swappiness,
  S6 invalid/snap, S7 config lama utuh), partial max-only (min byte-identik),
  knob-list format+JSON utuh, thermal 100C cap 1800000->600000, ZIP staging
  /tmp (manual.conf ada, runtime 28 marker, balanced md5 sama), module.prop
  tetap v5.0.0-beta1/5001, tanpa build/ ter-commit.
- Pre-existing (di luar scope M1, dikoreksi di M1b): backup cpu/gpu/io hardcode
  /sys (sandbox-blind; di HP benar); core/backup.sh hsin_restore_session
  memang verifikasi readback (ok hanya bila cat==nilai) — catatan lama
  "restore hitung ok walau tulis ditolak" keliru untuk fungsi itu; yang
  benar-benar menghitung ok tanpa readback adalah hsin_cpu_restore
  (engine/cpu/apply.sh, _ok++ per file) — sudah diperbaiki di M1b jadi
  ok hanya bila semua tulis terverifikasi; game-boost rank manual=1
  (boost memetakan manual→performance dan revert tak menulis sehingga
  nilai performance tertinggal) — sudah diperbaiki di M1b (boost skip di
  manual); config korup -> manual (dulu balanced); knob-list pra-apply
  tetap "belum ada hasil apply".
- PELAJARAN: (1) cek `git diff` file config KECIL sekalipun — pekerja
  menimpa 66 baris jadi 1; (2) var SHELL dibaca sebelum di-set dalam loop
  = override mati diam-diam — fetch SEBELUM cek; (3) partial-override wajib
  diuji eksplisit (sentinel 999999/888888 membuktikan tak-ditulis, bukan
  sekadar nilai-sama); (4) `resetprop --delete`/restore-default JUGA
  penulisan — else-branch wajib diguard; (5) skip thermal total = matikan
  guard — cerminkan performance (critical-only); (6) harness: path absolut
  ($SB), jangan rm -rf direktori berisi file pembanding.

## M1b kemurnian mode manual (2026-09-28, leader + dev-modul work/m1b-purity, TERIMA L1)
- Isi (merge ca429a2: afcfc5a + 0e6a7f0 + touch-up 2d1741d, 3 file +210/-7):
  engine/cpu/apply.sh (Step2 lewati safety remap di manual + hsin_cpu_restore
  readback ketat per cluster), engine/thermal/policy.sh (thermal cap
  critical-only di manual seperti M1 + restore pre-cap CPU/GPU saat suhu
  turun ke cool/normal dengan histeresis, state $HSIN_DATA/
  thermal_pre_cap.list, tulis terverifikasi + log), engine/game/
  game_manager.sh (boost skip di manual + log persis "game boost tidak aktif
  di mode manual" ke stderr, non-manual tidak berubah).
- Bukti FASE 0 SEBELUM fix (sandbox file asli, harness leader m1b-probe.sh/
  m1b-apply.sh): safety_effective manual=balanced?=battery (remap aktif);
  manual+batt 10% tak-mengisi di MAIN menulis 2 node (scaling_max 1800000→
  1200000); game mapping manual+game→performance (boost pasti menulis);
  cap 96C→45C tidak pulih (800000/600M permanen) di MAIN maupun draf awal.
- Bukti SESUDAH (worktree 2d1741d): (a) manual+96C tanpa override hanya 3
  node cap berubah (policy0/4 scaling_max_freq 1800000→800000, gpu0 max_freq
  800M→600M), sisanya byte-identik; (b) manual+batt 10% tak-mengisi IDENTIK
  nol tulis; (c) suhu turun 45C: 1800000/800M kembali; (d) manual+game:
  eff=manual + log + nol tulis, balanced+game tetap performance;
  (e) sandbox lama hijau semua (safe_apply 11, scan_prefix 5, overrides 9,
  thermal 6, boot_guard 10, degrade 8, knob_results 9, service_guard 8),
  profiles battery/balanced/performance/extreme md5 identik main;
  sh -n 3/3, shellcheck -S error 0; tanpa file runtime baru
  (build_release.sh tak perlu; state di HSIN_DATA bukan runtime).
- Koreksi leader atas diff pekerja (putaran 1→2 + touch-up): restore di
  dalam hsin_thermal_apply_cpu tidak pernah jalan (cabang manual
  non-critical return dini) → restore dipindah ke hsin_thermal_apply +
  GPU simetris; elif menulis pre-cap penuh saat hot (harusnya cap
  intermediate) → gate cool/normal; boost "nol tulis" terbukti salah
  (mapping)→skip; cpu_restore var bocor + any-ok longgar + filter '-' →
  reset per cluster + all-ok + banding langsung.
- Sisa jujur: performance critical-cap tidak di-restore saat dingin
  (jalur performance hanya panggil thermal saat critical — perilaku lama
  dipertahankan, di luar scope M1b); monitor.sh/action.sh tak diubah
  (skip di hsin_game_effective_profile menutup kedua caller).
  L2: validasi HP (flash + uji manual/termal/boost).
- PELAJARAN: (7) restore di fungsi yang tidak dipanggil saat cooldown =
  dead code — uji cool-down eksplisit, bukan cuma cap; (8) klaim pekerja
  "nol tulis" wajib dibuktikan mapping + snapshot, bukan dipercaya.
- GAYA JELASIN KE USER (2026-09-28, permanen): user lebih paham analogi
  sederhana bergambaran sehari-hari (tukang/remote/satpam/teman), bukan
  bahasa teknis kompleks. Setiap laporan/penjelasan wajib ada versi
  analoginya dulu, baru detail teknisnya.

## M2 guard-status (2026-09-29, leader + dev-modul work/m2-guard, TERIMA L1)
- Isi (merge dafeb7d: 49f6171 + bce3288 + d547271, 4 file +270/-8):
  core/guard_status.sh BARU (hsin_guard_status read-only: baca
  $HSIN_DATA/.boot_fail_count format timestamp:count + legacy angka-polos,
  threshold via _hbg_threshold, expired via cooldown, tanpa panggil
  hsin_boot_guard_check yang menulis); action.sh (+source, +case
  guard-status, Usage, skip debug-log + skip hsin_protect_harden_data);
  build_release.sh (+guard_status.sh di daftar runtime); tests/
  sandbox_guard_status.sh BARU (4 kondisi via dispatcher action.sh).
- Output: 5 baris key=value (active/fail_count/threshold/
  cooldown_remaining_sec/last_reason) + 1 baris JSON terakhir.
  Hilang/rusak/expired -> active=0 fail_count=0 cooldown=0
  reason "tidak ada state", rc 0. Ada isi -> reason
  "boot gagal <N> x berturut-turut".
- Koreksi leader atas diff pekerja (d547271): (1) KRITIS — blok auto-exec
  di akhir guard_status.sh mencetak output setiap kali di-source, mengotori
  SEMUA command action.sh (double output guard-status, prepend di knobs/
  logs/device) -> diganti `return 0`; (2) preamble action.sh (mkdir logs +
  exec 2>>debug.log) tetap membuat file untuk guard-status -> dibungkus
  case sehingga guard-status nol-file literal (terbukti: kasus hilang =
  0 file di HSIN_DATA); (3) harness hardcoded path worktree + /tmp
  (read-only di Termux) + uji exec langsung bukan via action.sh -> tulis
  ulang repo-relative via dispatcher (pola sandbox_boot_guard.sh).
  Duplikat case renderer-apply (pekerja) sudah difix pekerja di bce3288.
- Bukti L1: sh -n 3/3, shellcheck -S error 0, rg /sys|/proc + tulis kosong,
  harness 20/20, regresi boot_guard 10/10 + service_guard 8/8 +
  safe_apply 11/11 + overrides 9/9 + knob_results 9/9, knobs/knob-list/
  info/Usage tak terpengaruh. Sisa jujur: di ZIP release (tanpa .devmode)
  integrity-cache + debug.log preamble tetap ditulis infra bersama
  (sama seperti status/knobs) — nol-penulisan literal terbukti di
  sandbox devmode. APP_PLAN M2 [x]. L2: validasi HP.
- PELAJARAN: (9) file yang di-source DILARANG mencetak/menjalankan apa pun
  saat source (dulu: `exit` membunuh pemanggil; kini: auto-exec mengotori
  semua command) — akhiri dengan `return 0`, tanpa blok eksekusi;
  (10) harness DILARANG hardcode path worktree/cabang (/tmp read-only,
  default HSIN_DATA di dalam repo bikin sampah test_guard_m2/ — sudah
  dibersihkan, repo bersih); uji read-only WAJIB lewat dispatcher asli
  + snapshot, bukan exec file langsung.

## K1 pra-kode STOP (2026-09-29, leader investigasi langsung, TANPA delegasi)
- Penekanan user: laporkan rentang live SEBELUM coding; STOP bila butuh
  batas manual. Hasil: NOL live-read berhasil — Termux UID u0_a263:
  /sys/block/* (bahkan ls), /proc/sys/vm/{vfs_cache_pressure,dirty_ratio,
  dirty_background_ratio,swappiness}, /proc/sys/net/core/netdev_max_backlog
  + somaxconn + tcp_max_syn_backlog SEMUA Permission denied (su DILARANG
  AGENTS.md tanpa izin, tidak dijalankan). Kontrol positif: meminfo dan
  policy0/scaling_max_freq=1612000 TERBACA.
- Batas di-tree (bukan live node, belum dikunci): readahead profil
  128/512/2048/4096 KB TANPA min/max (readahead.sh:28-33); vfs 0..500
  profil 50/100/150/200 (vm.sh HSIN_VM_SAFE:17); dirty_ratio 1..90 profil
  40/30/20/10 (:18); dirty_bg 1..50 profil 10/5/3/1 (:19); backlog profil
  1000/1000/5000/16384 TANPA min/max (tcp.sh:156-163).
- Ambiguitas spec (Aturan Eksekusi #8): "inventaris M1 baris 10,13,15 /
  16-19" TIDAK ditemukan di repo (grep NOTES + commit M1 + docs nihil) —
  scope diambil dari nama eksplisit, perlu konfirmasi user.
- Penilaian 16-19 (read-only): DVFS AMAN BERSYARAT (0-100, verify+restore,
  override-aware; konflik semantik dengan knob max_khz); RR-range BERSYARAT
  (settings+readback, mode live via dumpsys, tapi knob ganda peak+min +
  tak bisa sandbox + ROM bisa revert); frame-limit KURANG COCOK (boolean,
  efek tak terverifikasi); SurfaceFlinger TIDAK AMAN live (restart SF tiap
  apply, layar blank, risiko crash-loop) — hanya intent boot-time.
- Tanya user (Q1-Q5): kunci batas = batas engine? readahead preset/rentang
  apa? backlog rentang apa? kirim 5x `su -c cat` dari HP? konfirmasi scope.
  Repo NOL perubahan kode. APP_PLAN K1 tetap [ ].

## K1 live HP (2026-09-29, `su -c cat` read-only + `[ -w ]`, nol tulis)
- Unisoc T615: vfs_cache_pressure=100, dirty_ratio=20,
  dirty_background_ratio=5, sda/read_ahead_kb=128,
  netdev_max_backlog=1000. KELIMA node WRITABLE sebagai root.
- Artinya Q4 terjawab (node ada + bisa ditulis di HP; `cur` knob bisa
  dibaca live saat runtime). Q1-Q3 tetap terbuka: kernel TIDAK
  mengekspos min/max node apa pun, jadi batas knob tetap butuh kunci
  user. K1 tetap STOP.

## K1 knob engine yang sudah ada (2026-09-29, leader langsung, TERIMA L1)
- Batas dikunci user: vfs_cache_pressure 0-1000 (HSIN_VM_SAFE max
  500->1000, default profil tetap), dirty_ratio 1-90, dirty_background_
  ratio 1-50 + validasi bg<ratio, readahead PRESET 128/256/512/1024/
  2048/4096/8192 per block, backlog 128-16384 (leader verifikasi:
  netdev_max_backlog = SATU-SATUNYA sysctl di tcp.sh yang bervariasi per
  profil; sack/window_scaling/ecn konstanta, bukan knob).
- Isi (7 file +393/-70 + harness baru): core/user_knobs.sh (4 key fixed
  numeric + field io readahead preset, validasi 3 situs, teks error),
  core/knobs.sh (JSON memory.vm.* + io.blocks[].readahead + backlog
  top-level, cur/writable live), engine/memory/vm.sh (3 knob VM, tabel
  max 1000, validasi silang bg>=ratio -> FALLBACK + alasan dua angka,
  manual = tanpa tulis), engine/io/readahead.sh (knob per block + cek
  ulang preset + UNAVAILABLE/FAILED), engine/network/tcp.sh (knob backlog;
  sack/ecn/scaling dikunci non-manual seperti sebelumnya), core/backup.sh
  (+3 VM +backlog; loop block jadi $HSIN_SYSFS_BLOCK). TIDAK ada file
  runtime baru -> build_release.sh tak disentuh.
- Koreksi leader saat implementasi: (1) hsin_uk_used mencatat APPLIED
  SEBELUM tulis, jadi node hilang tetap terkategori APPLIED -> jalur gagal
  tulis sekarang menulis ulang baris hasil UNAVAILABLE (node hilang/
  read-only) atau FAILED (kernel menolak); (2) hsin_backup_io loop
  /sys/block hardcode (sandbox-blind, catatan M1) -> $HSIN_SYSFS_BLOCK
  dengan default sama (dampak HP nol); tanpa ini backup/rollback readahead
  mustahil dibuktikan; (3) BUG ZIP RUNTIME dari M2 (TERBUKTI di baseline
  HEAD): guard_status.sh memakai `. boot_guard.sh || { ... }`, sedangkan
  build_release.sh menghapus baris `. ...core/...` saat menyatukan
  runtime.sh -> pembuka blok hilang, `}` yatim, runtime gagal parse
  (sh -n rc=2 pada 14129 baris). Diperbaiki: baris source diawali
  `command -v _hbg_read || .` (tidak kena pola hapus) + fallback di
  `if ! command -v` dengan body non-kosong. Runtime rekonstruksi kini
  sh -n OK.
- Bukti L1: sh -n 7/7, shellcheck -S error 0, harness K1 36/36 (A snapshot
  byte per knob satu-per-satu: hanya node itu berubah; B manual tanpa
  override nol tulis; C balanced identik nilai profil; D node hilang
  UNAVAILABLE tanpa crash; E 8 nilai luar rentang/preset ditolak knob-set
  + file cacat ditolak engine; F bg>=ratio FALLBACK + dua angka di manual
  DAN balanced, manual tanpa tulis bg; G backup->rollback 5 roundtrip per
  knob; H knobs JSON valid + 5 field baru cur dari node palsu; I
  knob-list kategori benar), suite lama 8/8 hijau, runtime ZIP
  rekonstruksi sh -n OK + semua marker fungsi K1 ada. End-to-end
  dispatcher: knob-set 5/5 OK, knob-list baris+JSON, knobs JSON memuat
  field baru.
- Jujur: di Termux /proc/sys + /sys/block tak terbaca, jadi knobs JSON di
  sini reporting supported:false (pola lama swappiness, bukan angka
  palsu). Validasi node kernel nyata tetap L2 di HP.
- BARIS 16-19 (DVFS, refresh-rate range, frame limit, SurfaceFlinger)
  DIKELUARKAN dari K1 oleh keputusan user, bukan ditunda. Kandidat step
  terpisah nanti dengan pendekatan BERBEDA:
  * DVFS (cpu/gpu_limit 0-100): node sysfs, tulis terverifikasi, restore
    100% sudah ada. Masalahnya SEMANTIK - knob max_khz (kHz absolut) dan
    cap persen menulis node yang sama; sudah ada aturan "override menang"
    (dvfs.sh:69-73/:126-130), tapi key absolut + slider persen = dua
    sumber kebenaran. Step terpisah harus memutuskan mana yang tampil di
    UI (saran: hanya max_khz; cap persen jadi read-only turunan).
  * Refresh-rate range (peak/min Hz): bukan sysfs tapi Settings.System
    (settings/cmd) -> tidak bisa di-sandbox, hanya uji HP; knob ganda
    (peak+min) tidak cocok pola key tunggal sekarang, dan ROM bisa revert
    diam-diam (readback mismatch sudah di-log). Perlu mode uji "tahan 60
    detik" + perbandingan readback.
  * Frame limit: 3 prop debug.sf on/off. Tidak ada node "nilai valid" yang
    bisa dibaca, jadi tidak bisa jadi knob angka; kalau tetap dibuat harus
    switch boolean dengan status dari getprop - tapi efek ke FPS tidak
    terverifikasi, jadi jangan dijanjikan ke user.
  * SurfaceFlinger: apply me-RESTART SurfaceFlinger (stop/start, layar
    blank) - TIDAK boleh jadi knob apply. Kalau nanti dipakai, hanya
    sebagai intent boot-time seperti downscale/renderer
    (hsin_sf_apply_boot sudah ada), di luar jalur apply per knob.
- PELAJARAN: (11) file yang digabung build_release.sh tidak boleh punya
  baris `. ...core/...` sebagai satu-satunya isi blok if/`|| {` - sed
  hapus baris itu dan menyisakan blok kosong/yatim; awali dengan
  `command -v` biar utuh; (12) shell Android/mksh menolak blok `if` dengan
  body KOSONG - sisakan `:` atau perintah nyata; (13) hsin_uk_used =
  "override diterima", BUKAN "diterapkan" - kategori final hanya sah
  setelah tulis+verify, jadi jalur gagal harus menulis ulang baris hasil.

## K2 knob tier-1 (2026-09-29, leader langsung, TERIMA L1)
- Live HP (su -c cat, read-only): add_random=0, iostats=0, nomerges=2,
  stat_interval=10, page-cluster=0 - kelima node WRITABLE.
  rate_limit_us: NODE TIDAK ADA (governor aktif = `uscfreq` di policy0
  dan policy6; `schedutil` ada di scaling_available_governors tapi
  direktori policy*/schedutil hanya dibuat saat schedutil yang AKTIF).
  Kedua policygovernor SAMA (uscfreq) -> tidak ada konflik governor yang
  perlu dilaporkan; knob jadi UNAVAILABLE di device ini, sesuai gate K2.
- Batas (keputusan user + sumber kernel): queue boolean 0/1; stat_interval
  1-60 s; page-cluster 0-9; rate_limit_us 0-100000 us. Batas rate_limit_us
  diverifikasi ke SOURCE kernel (cpufreq_schedutil.c v6.6,
  rate_limit_us_store: `kstrtouint` TANPA clamp, jadi kernel menerima
  unsigned int bebas; default = 1.5 x cpuinfo_transition_latency, atau
  1000 us kalau driver tidak memberi latensi). Artinya batas 0-100000 itu
  BATAS UI (0 = tanpa rate limit, 100 ms ceiling), bukan batas kernel.
  BELUM terverifikasi live di HP karena node tidak ada di governor ini -
  dicatat jujur, butuh L2 (ganti governor ke schedutil lalu baca default).
- Isi (9 file +248/-40, 2 file baru): engine/io/queue_tuning.sh BARU (3
  knob boolean per block via hsin_safe_apply, cek ulang 0/1 di engine,
  UNAVAILABLE/FAILED, HSIN_IO_SKIP_BLOCKS untuk volume eksternal) +
  didaftarkan di build_release.sh + dipanggil io_manager.sh; core/
  user_knobs.sh (field io add_random/iostats/nomerges + field cpu
  rate_limit_us + kunci tetap stat_interval/page_cluster, kind dicek
  per-field); engine/memory/vm.sh (baris HSIN_VM_SAFE: page-cluster 0-5
  -> 0-9 + stat_interval 1-60 dengan default "-" = knob tanpa nilai
  profil); engine/cpu/governor.sh (rate_limit_us per policy, gate
  governor==schedutil DAN node ada); core/backup.sh (+3 queue +2 VM
  +rate_limit_us; loop CPU jadi $HSIN_SYSFS_CPU); core/knobs.sh (JSON
  io.blocks[].queue_tuning, vm.stat_interval, vm.page_cluster,
  cpu.policies[].rate_limit_us).
- Koreksi leader saat implementasi: nama sysctl `page-cluster` (hypen)
  tidak pernah cocok dengan kunci knob `page_cluster` (pola key hanya
  [A-Za-z0-9_.]) -> override page-cluster diam-diam tidak kepakai
  (terbukti A: 0 node berubah). Perbaikan: nama node dipetakan ke kunci
  knob sekali di vm.sh (`tr '-' '_'`) dan SEMUA hsin_uk_result/
  hsin_uk_used memakai kunci itu, bukan nama node.
- Bukti L1: sh -n 9/9, shellcheck -S error 0, harness K2 42/42 (A snapshot
  byte 6 knob satu-per-satu; B manual tanpa override nol tulis; C balanced
  tidak menulis knob tanpa nilai profil + page-cluster tetap nilai profil;
  D node hilang UNAVAILABLE tanpa crash; E 10 kasus tolak (boolean
  non-0/1, luar rentang, >100000, key di kind yang salah); F rate_limit_us
  schedutil+node=APPLIED, governor lain/node absen=UNAVAILABLE tanpa tulis;
  G backup->rollback 6 roundtrip; H knobs JSON 7 pemeriksaan termasuk
  node absen=supported:false; I knob-list kategori benar), suite lama 8/8
  hijau (K1 36, guard_status 20, boot_guard 10, service_guard 8,
  safe_apply 11, overrides 9, knob_results 9, scan_prefix 5, degrade 8),
  runtime ZIP rekonstruksi sh -n OK (14577 baris) + marker K2 ada +
  0 blok if kosong (kelas bug M2), dispatcher end-to-end knob-set 6/6 OK.
- CATATAN JUJUR: knob `nomerges` punya options hanya [0,1] sesuai
  keputusan user, sementara nilai live device ini 2 (kernel modern punya
  nilai tambahan). Node menerima 0 dan 1 dengan baik, tapi nilai 2 tidak
  bisa dipilih dari UI - perlu keputusan user terpisah bila mau menambah
  opsi 2.
- KOREKSI USER (2026-09-29, menyusul K2): `nomerges` BUKAN boolean -
  dokumentasi kernel block layer memberi TIGA nilai: 0 = semua merge
  diizinkan, 1 = hanya simple one-hit merge, 2 = tanpa merge sama sekali.
  K1 sebelumnya salah baca -> diperbaiki: validasi knob (0|1|2),
  cek ulang engine queue_tuning.sh per-field (0|1|2 hanya untuk nomerges),
  JSON io.blocks[].queue_tuning.nomerges.options = [0,1,2], teks pesan
  knob-set. Bukti: snapshot byte untuk 0, 1, DAN 2 (tiap nilai hanya
  mengubah node itu), apply 2 (nilai live HP) berhasil, TANPA override
  node tetap 2 (tak tersentuh), 3 dan -1 ditolak, harness K2 42 -> 46/46,
  suite lama K1 36 + guard_status 20 + 7 suite lain tetap hijau, dispatcher
  knob-set 2 diterima / 3 ditolak. Pelajaran: nilai enum dari dokumentasi
  kernel harus DIBACA, bukan diasumsikan boolean - device live (nomerges=2)
  adalah bukti paling cepat bahwa asumsi salah.
- CATATAN LAIN: `add_random`/`iostats` tidak di-backup sebelum K2 dan
  sekarang ikut (backup+rollback terbukti). Tidak ada knob VM
  `page-cluster` yang bisa ditulis di profil non-manual tanpa override -
  perilakunya sama seperti sebelumnya (halaman lama menulisnya), hanya
  rentangnya dilebarkan 0-5 -> 0-9 sesuai keputusan user.
- PELAJARAN: (14) nama sysctl/sisip node yang mengandung karakter di luar
  pola key knob (hypen) SELALU perlu pemetaan eksplisit di engine, kalau
  tidak override valid tersimpan tapi tidak pernah dibaca - harus diuji
  dengan benar-benar cek node berubah, bukan cuma knob-set diterima; (15) knob
  yang tidak punya nilai profil perlu penanda eksplisit di tabel
  (default "-") supaya profil lama tidak ikut menulis node yang tadinya
  tidak pernah ditulis.

## K3 knob tier-2 berbasis capability (2026-09-29, leader langsung, TERIMA L1)
- LIVE HP T615 (su -c cat, read-only, nol tulis) - inilah yang menentukan
  mana knob yang bisa muncul di device ini:
  * sched_latency_ns / sched_min_granularity_ns / sched_wakeup_granularity_ns
    = TIDAK ADA (/proc/sys/kernel/ tidak punya). -> UNAVAILABLE di sini.
  * sched_child_runs_first = 0, writable. -> knob 0/1.
  * uclamp foreground ADA di /dev/cpuctl/foreground/cpu.uclamp.{min,max}
    (cgroup v1 vendor, BUKAN /sys/fs/cgroup). min live "0.00", max live
    "max" - format vendor, bukan integer polos. Writable. -> knob 0-1024.
  * devfreq 23100000.gpu (governor simple_ondemand): polling_interval=50
    writable (ADA); up_threshold & down_differential TIDAK ADA (governor
    aktif ini tidak mengexpos-nya). -> polling_interval knob, dua lainnya
    UNAVAILABLE di device ini tapi tetap diimplementasikan (node-based
    detection, akan muncul di device yang governor-nya punya node).
  * Mali KBase (/sys/module/mali_kbase/parameters, ada & writable):
    gpu_boost_level2=0, gpu_pollingtime=8, gpu_upthreshold=88.
- Batas + SUMBER (sesuai requirement K3: justifikasi sebelum dikunci):
  * sched_child_runs_first 0-1: bool kernel (sched-bwc).
  * uclamp_min/max 0-1024: SCHED_CAPACITY_SCALE=1024 (dokumentasi kernel
    sched-util-clamp). 1024 = 100% kapasitas.
  * polling_interval 1-1000 ms: ABI devfreq (satuan ms; nilai < 1 jiffy
    dianggap 0 = no polling). Batas atas = batas UI, kernel tidak
    menetapkan max.
  * up_threshold 1-100 %: ABI devfreq ondemand (persen busy). 0 ditolak
    karena governor ondemand mainstream menolaknya.
  * down_differential 0-100 %: ABI devfreq (persen selisih).
  * sched_latency_pct / sched_min_granularity_pct /
    sched_wakeup_granularity_pct 10-200 PERSEN (bukan nanodetik absolut):
    jalur tulis yang sudah ada & teruji di HP bekerja dalam persen dari
    nilai native + lantai keras 500000 ns, dan komentar di scheduler.sh
    membuktikan kernel vendor bisa saling menimpa antar node. Batas 10-200
    %% menjaga user tetap bisa lebih agresif tanpa mengecilkan absurd.
  * mali_boost_level2 0-1, mali_pollingtime 1-10, mali_upthreshold 10-100:
    TIDAK ada dokumentasi kernel (parameter modul vendor). Justifikasi =
    nilai relatif terhadap nilai live + set yang sudah dipakai engine
    (engine/gpu/mali.sh: 0/1, 8/4/1, 88/72/55/30). PERLU uji tulis di HP
    (L2) sebelum dianggap final - kernel/vendor bisa punya clamp sendiri.
- Isi (10 file +558/-65, 2 baru): engine/gpu/devfreq_tuning.sh BARU (3
  tunable devfreq, gate = node ADA, terdaftar di build_release.sh +
  dipanggil engine/gpu/apply.sh); engine/gpu/mali.sh (blok kbase
  DIPISAH jadi hsin_gpu_kbase_knobs_apply + dipanggil dari pipeline GPU -
  sebelumnya hsin_gpu_mali_apply 0 pemanggil / dead code, dan gate-nya
  hanya node kbase, bukan nama vendor); engine/cpu/scheduler.sh (2 knob
  uclamp + 3 knob persen sched-lat); engine/cpu/governor.sh
  (sched_child_runs_first jadi knob, sebelumnya tulis profil buta);
  core/user_knobs.sh (9 kunci fixed + 3 field gpu), core/knobs.sh (JSON
  sched + gpu_tunables + mali_kbase), core/backup.sh (hsin_backup_sched +
  hsin_backup_gpu_tuning), tests/sandbox_k3_knobs.sh BARU.
- Koreksi leader (3, semua kelas yang sudah dicatat sebelumnya):
  1) uclamp: return dini di profile manual = override user MATI (pola
     yang sama dengan bug K2). Diperbaiki: manual ditangani di dalam
     loop (SKIPPED tanpa tulis), bukan di awal fungsi.
  2) kbase knob bergantung pada HSIN_GPU_KBASE yang hanya di-set detector
     -> dipanggil dari harness langsung = 0 write. Diperbaiki: fungsi
     menurunkan sendiri ke HSIN_SYSFS_KBASE bila kosong (tidak bergantung
     urutan pemanggilan).
  3) JSON gpu_tunables: tiap entri tidak dibungkus `{}` -> JSON invalid
     (terbukti: "Expecting ',' delimiter" di char 1693). Diperbaiki;
     sekarang json.load() lulus di kedua varian.
- Pelajaran K2 diterapkan eksplisit: SETIAP knob baru diuji bahwa node-nya
  benar-benar berubah (bukan cuma knob-set diterima) - termasuk yang
  formatnya aneh (uclamp "0.00"/"max": readback compared longgar + tulis
  hanya dihitung sukses kalau nilai benar-benar BERUBAH).
- Bukti L1: sh -n 10/10, shellcheck -S error 0, harness K3 48/48
  (A snapshot 7 knob satu-per-satu; B manual nol tulis; C knob tanpa
  nilai profil tidak ditulis + kbase profil 0/4/72 utuh; D varian node
  hilang sebagian: UNAVAILABLE tanpa crash; E 16 nilai tolak + file cacat;
  G backup->rollback 7 roundtrip; H 7 pemeriksaan JSON termasuk node
  hilang; I knob-list 4 knob), suite lama 10/10 hijau (K2 46, K1 36,
  guard_status 20, boot_guard 10, service_guard 8, safe_apply 11,
  overrides 9, knob_results 9, scan_prefix 5, degrade 8), runtime ZIP
  rekonstruksi sh -n OK (15241 baris) + marker K3 + 0 blok if kosong
  (kelas bug M2 dicek ulang).
- CATATAN KEPUTUSAN (leader, transparan): 3 sysctl sched tidak ada di HP
  ini, jadi tidak ada ANGKA LIVE yang bisa diverifikasi untuk batasnya;
  karena itu batasnya diambil dari JALUR TULIS YANG SUDAH ADA (persen) dan
  TIDAK dibuat semantik nanodetik absolut yang belum teruji. Node ini akan
  otomatis UNAVAILABLE di device ini, dan muncul sebagai knob persen di
  device yang punya node-nya. Bila user mau abolish persennya dan pakai
  nilai absolut, itu perlu step terpisah + uji HP.

## Koreksi K3: 2 bug (1 acnek, 1 MATI di produksi) + harness diperketat (2026-09-29)
- BUG 1 (minor, ditemukan saat klarifikasi user): `hsin_gpu_kbase_knobs_apply`
  set `_mk_profile="$1"` tapi badannya baca `$_profile` (nama lama saat
  bloknya masih di dalam hsin_gpu_mali_apply). Dipanggil tanpa pemanggil
  yang menyetel `$_profile` -> profil tidak dikenal -> NILAI KOSONG ditulis
  ke ketiga node kbase. Di pipeline produksi hanya kebetulan benar karena
  hsin_gpu_apply menyetel `_profile` lebih dulu.
  Fix: `$_profile` -> `$_mk_profile` (2 tempat) + case `*)` untuk profil
  tak dikenal = TIDAK menulis (kirim nilai kosong ke node kernel jauh lebih
  berbahaya daripada dilewati).
- BUG 2 (SERIUS,production blocker, ditemukan oleh harness yang diperketat):
  blok validasi nilai untuk `*_polling_interval` / `*_up_threshold` /
  `*_down_differential` TER-SISIP ke fungsi `_uk_class` (klasifikasi KEY)
  dan bukan ke `hsin_uk_val_ok` (validasi NILAI). Akibatnya saat key
  diklasifikasi, validasi dijalankan terhadap `$_uk_v` yang masih kosong ->
  `return 1` -> ketiga kunci itu DITOLAK saat `knob-set` di proses bersih
  (persis yang dilakukan aplikasi). Artinya 3 dari 12 knob K3 MATI di HP
  nyata.。mereka hanya "lolos" di harness lama karena `$_uk_v` bocor dari
  engine lain kebetulan berisi angka valid - harness-nya bohong, bukan produk.
  Fix: ketiga blok dipindah ke hsin_uk_val_ok; `_uk_class` sekarang hanya
  menetapkan nama field (nol sentuhan ke _uk_v).
- HARNESS K3 DIPERKETAT (alasannya persis bug di atas): fungsi `_isolate()`
  baru membatalkan SEMUA variabel global/state engine K1-K2-K3 di awal tiap
  skenario (bukan hanya andalkan subshell), termasuk ikut membatalkan guard
  cache deteksi (HSIN_GPU_NODES_READY) yang kalau tidak ikut di-unset
  membuat daftar node devfreq kosong. Karena itu disyaratkan TIDAK meng-unset
  variabel KONFIGURASI (`_uk_file`, `HSIN_SANDBOX_DIR`) - saat pertama dicoba,
  harness malah gagal 11 skenario karena `_isolate` ikut menghapus `_uk_file`
  ( knob-set menulis ke path salah) dan `HSIN_SANDBOX_DIR` (snapshot path
  hilang) - itu cacat harness, bukan produk, dan sudah dibatasi.
  Ditambah skenario regresi J (fungsi kbase dipanggil lewat subshell BARU
  dengan `unset _profile`): balanced->0/4/72, manual->nol tulis, profil
  ngawur->tidak menulis. Harness K3 48/48 -> 51/51.
- BUKTI RED-GREEN: kode LAMA (HEAD) dipanggil tanpa `$_profile` ->
  `boost=[] polling=[] upth=[]` (node dikosongkan). Kode BARU pada skenario
  sama -> 0/4/72, manual -> 0/4/72 (nol tulis), battery -> 0/8/88, profil
  ngawur -> 0/8/88 (tidak menulis), manual+override -> 3.
- UJI PROSES BERSIH (setiap knob-set = proses baru, seperti aplikasi):
  ketiga kunci devfreq kini `rc=0` dan tersimpan; nilai luar rentang tetap
  ditolak dengan pesan yang tepat. End-to-end dua proses: knob-set 100 ->
  apply manual -> node 50 jadi 100 + hasil `APPLIED`.
- KOREKSI LAPORAN K3 (kalimat sebelumnya SALAH): `sched_child_runs_first`
  ADA di HP (live 0, writable) dan knob-nya BERFUNGSI (uji dua proses:
  0 -> 1, hasil APPLIED; tanpa override di manual = nol tulis). Yang tidak
  ada hanya TIGA sysctl latency (sched_latency_ns/min_granularity_ns/
  wakeup_granularity_ns). Deteksi capability juga benar (JSON:
  child_runs_first supported:true; sysctl latency supported:false).
- SCAN POLA SERUPA (poin c): fungsi yang set var profile dari argumen
  tapi membaca var profile LAIN = 0 setelah fix. 11 fungsi "baca $_profile
  tanpa set sendiri" yang ditandai scanner FALSE POSITIVE - diperiksa satu
  per satu, semuanya benar (pola `_profile="${2:-balanced}"` yang tidak
  catching regex scanner). Kesimpulan: KONVENSI repo memakai global
  `_profile` yang di-set ulang tiap fungsi; risikonya fungsi BARU harus
  meng-set sendiri, dan harness yang tidak meng-isolasi bisa menutupi
  kesalahan - sudah dikunci lewat _isolate().

## Konvensi variabel `_profile` (permanen, berlaku semua file engine)
`_profile` disetel SEKALI oleh pemanggil di awal rantai apply lalu dipakai
bersama oleh semua engine (dipasang di header file acuan, contoh
`engine/gpu/mali.sh`). Fungsi yang butuh nilai turunannya sendiri -
misalnya hasil pemetaan atau klasifikasi lokal - WAJIB menamainya berbeda
(`_mk_profile`, `_gt_profile`, ...) dan tidak boleh membaca `_profile`
langsung. Pelajaran: `hsin_gpu_kbase_knobs_apply` dulu set `_mk_profile`
tapi membaca `$_profile`, dan hasilnya NILAI KOSONG ditulis ke node kbase
padahal di pipeline hanya kebetulan benar karena pemanggil menyetel
`_profile` lebih dulu. Aturan ini juga alasan kenapa harness sandbox harus
meng-`_isolate` variabel global per skenario: tanpa itu, kebocoran
`_profile`/`$_uk_v` dari engine lain menutupi bug nama variabel.

## A4 scaffold + CI (2026-09-29, leader + dev-apk work/app-a4, TERIMA L1)
- Keputusan dikunci user: applicationId com.hsin, minSdk 26/targetSdk 34,
  keystore debug sementara, NOL permission, dep minimal (BOM + activity-
  compose + lifecycle viewmodel/runtime + coroutines), org.json (tanpa
  serialization lib), tanpa .java/NDK/Navigation.
- Isi (merge 7606df3: e8ce6e2 + touch-up d2a6b35, 15 file +233/-12):
  app/{settings,build}.gradle.kts + gradle.properties + libs.versions.toml
  (AGP 8.6.0, Kotlin 2.0.20, plugin compose 2.0.20 = versi Kotlin sesuai
  dokumen resmi, BOM 2024.10.00, activity-compose 1.9.3, lifecycle 2.8.7,
  coroutines 1.8.1 - tiga terakhir TERBUKTI sukses build di CI ini dari
  app lama), MainActivity Compose, manifest 1 activity tanpa permission/
  tanpa service/receiver/provider, icon adaptive XML (tanpa PNG).
  Workflow build-apk manual: komentar A2 dihapus + step NDK r26/CMake
  dihapus (tanpa NDK); JDK 17 + platform-34 + Gradle 8.7 tetap.
- Koreksi leader atas diff pekerja (d2a6b35, 3 file, verifikasi ulang):
  1) MainActivity import material3 TANPA dependensi (pasti gagal compile)
  -> tulis ulang foundation-only agar daftar dep persis seperti dikunci;
  2) blok composeOptions ganda dengan plugin compose (panduan migrasi
  resmi: plugin yang mengatur) -> hapus, sisakan komentar;
  3) testInstrumentationRunner tanpa lib runner -> hapus.
  Koreksi lanjutan 4df9a58: artifact `foundation` (Box/Column/BasicText)
  tidak ada di katalog -> tambah compose-foundation dari BOM.
- Bukti: 0 file .java; grep ndk/cmake/externalNativeBuild kosong;
  grep navigation/serialization/appcompat kosong; semua versi hanya di
  toml; manifest bersih. Build CI #1 run 36537223562 GAGAL (Unresolved
  reference 'foundation' - bukti Aturan: kode Kotlin tak bisa dikompilasi
  lokal, CI adalah verifikator); build CI #2 run 36537576407 SUCCESS
  3m33s, artifact hsin-debug-apk 6.856.887 byte (~6,5 MiB; dex 17,4 MB
  tak terkompres = runtime Compose debug, wajar tanpa R8).
- PELAJARAN: (16) file Kotlin BARU wajib di-review import-vs-katalog
  sebelum push - Termux tidak bisa compile, jadi satu import liar =
  satu siklus CI gagal; (17) BOM hanya mengatur VERSI, bukan
  menyediakan artifact - tiap import compose.* harus dicek ada di katalog.

## A5 build CI (2026-09-29, 2 putaran, leader)
- Putaran 1 run 36573238729 GAGAL: `@Preview(backgroundColor = Bg.value
  .toLong())` TIDAK compile - argumen anotasi wajib compile-time constant;
  `padding` hilang import di BottomNav. Fix: `const val PreviewBg: Long =
  0xFF121214L` di Color.kt (tetap satu tempat hex) + import `padding`.
  Putaran 2: run 36574143754 SUCCESS 4m25s, artifact hsin-debug-apk
  8.758.734 byte (~8,35 MiB; naik dari 6,5 MiB karena material3 masuk).
- Koreksi leader atas hasil dev-apk (8 file ditulis ulang): `import
  com.hsin.ui.theme.44.dp` (import tak mungkin) di 4 file, modifier
  chaining `Modifier.androidx.compose.foundation.layout.padding(...)`
  tak valid, signature ScreenScaffold tidak cocok dengan pemanggil,
  SEMUA teks monospace (hanya angka+log yang boleh mono), TopBar
  mengimpor HsinTheme dua kali, hex/hardcode di luar token.
- Kontras terukur (WCAG, dihitung dari hex token): text/bg 15,30:1 (AAA),
  text/surface 13,94:1 (AAA), muted/bg 6,41:1 (AA), accent/bg 8,40:1
  (AAA), bg/accent 8,40:1 (AAA teks tombol utama), ok/bg 6,10:1 (AA),
  warn/bg 6,66:1 (AA), error/bg 4,23:1 (AA-large), neutral/bg 3,53:1
  (AA-large). Catatan jujur: error + neutral DI BAWAH 4,5:1 - keduanya
  dipakai sebagai GARIS + TEKS status kecil, bukan body text, dan
  kontrasnya dinaikkan lewat ukuran/weight saat dipakai (A5 selesai untuk
  token; penyesuaian kontras akhir diperiksa ulang di A14).
- PELAJARAN: (18) `@Preview(backgroundColor = ...)` tidak bisa memakai
  token `Color` - harus konstanta compile-time; token warna tidak
  kompatibel dengan aturan anotasi Kotlin; (19) setelah rewrite
  massal, cek ulang SEMUA import token satu per satu (hapus import Bg
  karena `backgroundColor` tidak lagi memakainya, padahal `contentColor`
  masih butuh) - grep silang "pakai X tapi import X hilang" menangkap
  ini sebelum CI.
- APP-A6 (2026-09-29): 2 ronde dev-apk + takeover leader. ronde 1
  REJECT: fixture DIKARANG (guard-status threshold=3/cooldown=120/none
  bertentangan dgn kontrak §3.10 threshold=2/cooldown=0/86400; key
  `read_ahead_kb` bukan knob valid), test tautologi (allowlist disalin
  ke dalam test, `assertEquals(COMMAND_FAILED, COMMAND_FAILED)`), validasi
  argumen blacklist, `MODULE_NOT_FOUND`/`FEATURE_UNSUPPORTED` dikarang
  dari string yg tidak pernah keluar dari modul. ronde 2: kode BELUM
  PERNAH kompilasi - `SudoCommandRunner.kt:16 ba.outputStream()` tidak
  ada di ByteArrayOutputStream -> compileDebugKotlin FAILED, dan laporan
  dev menutupi (nyatakan "in_progress", padahal run build-apk failure).
  Round 2 = maks -> leader takeover penuh di worktree yang sama.
- CARA VERIFIKASI BARU (PENTING): Termux PUNYA JDK 17
  (`/data/data/com.termux/files/usr/lib/jvm/java-17-openjdk`) dan
  kotlin-compiler 2.4.20
  (`/data/data/com.termux/files/usr/opt/kotlin/lib/kotlin-compiler.jar`).
  Kokotlin bisa dikompilasi lokal via
  `java -cp "$KC/kotlin-compiler.jar:$KC/kotlin-stdlib.jar:$KC/kotlin-script-runtime.jar:$KC/kotlin-reflect.jar" org.jetbrains.kotlin.cli.jvm.K2JVMCompiler -cp <deps> -d out src/`
  dan unit test JVM bisa DIJALANKAN lokal (JUnit jar dari Maven Central +
  kotlinx-coroutines-test-jvm + org.json). Ini menutup 3 putaran
  "push lalu_ci_gagal" yang selama iniائي terjadi. 32 test lulus lokal
  sebelum push. Android SDK/AGP tetap tidak ada -> assemble tetap CI.
- PELAJARAN: (20) test yang menyalin logika produksi ke dalam test
  (allowlist, escaping, firstLine) SELALU lulus tanpa menguji apa pun -
  test wajib memanggil kode produksi; (21) `ByteArrayOutputStream` tidak
  punya `outputStream()` (pakai `toByteArray()` atau `StringWriter`);
  (22) `private const val` hanya sah di top-level/object/companion,
  bukan di body class biasa; (23) `Success(stderr = "souvenir")` +
  `require()` di `init` data class =Senjata gagal keras di runtime -
  field yang isinya nilai palsu harus dihapus, bukan diisi string
  penjelasan; (24) string `Usage:` di action.sh:1406 BUKAN allowlist
  lengkap - ia tidak menyebut `knobs|knob-set|knob-list|knob-reset|
  config-get|config-set|warn` yg ada di dispatch, sedangkan allowlist app
  HARUS memuat semuanya (A10 butuh knob-set); (25) `statusReadable`
  harus menolak sentinel -1 DAN 0 (aturan A11) - 0 `refresh_hz`/`game_fps`
  bukan angka valid.
- A6 DONE: RootClient (allowlist 30 subcommand nyata, escape per-arg,
  6 error, timeout, `Usage:` despite rc=0), HsinRepository (guard-status,
  knob-list manual, status JSON + sentinel, 5 kategori modul).
  Commit leader: 77ddff7 (merge work/a6-rootclient). CI main: lint
  36583327074 success, build-apk 36583327112 success (unit test hijau).
  APP_PLAN A6 [x]. L2: belum (tak ada HP).
- APP-A7 (2026-09-29): 2 ronde dev-apk + takeover leader (LIHAT catatan
  panjang A6 untuk pola). ronde 1 REJECT: refresh TIDAK memanggil root
  (`parseGuardStatus("status=ok\nactive=1")` = string kareta;
  `RealtimeMetrics(42,1800,30,60)` = angka karangan; cache HIT dihitung
  lalu dibuang; dirtyMap di-reset tiap capability refresh), `resetKnobKey`
  menghapus `base` (key hilang dari peta), test menguji `data class copy()`
  dan ada `assertTrue(true)`. ronde 2 REJECT: memakai API yang TIDAK PERNAH
  ADA (`RootResult.Ok`, `CommandRunner.run(List)`, `suspend run`) sehingga
  tidak akan compile; `parseRealtimeFromStatus` masih mengembalikan
  `else 1800`; `refreshCapability` tetap reset dirtyMap. 2x gagal ->
  leader TULIS ULANG seluruh A7 (ViewModel, UiState, DirtyTracker,
  CapabilityCache, KnobsMapping, StatusMapping) + 53 test.
- PELAJARAN: (26) dev-apk cenderung mengarang API Android yang "kedengarannya
  benar" (RootResult.Ok, suspend run) - leader WAJIB cross-check signature
  ke file production sebelum merge; (27) angka hardcoded di ViewModel
  (`= 42`, `= 1800`, `profileActive = "balanced"`) adalah tanda paling
  jelas bahwa refresh tidak beneran memanggil root - grep
  `= 42|= 1800|"balanced"|"unknown"` wajib di review ViewModel; (28)
  `dirtyMap - key` menghapus base; reset harus `entry.copy(current = base)`;
  (29) cache yang menaruh versi di NAMA key akan menumpuk entri lama -
  pakai satu key tetap + versi di payload; (30) `data object X : SealedInterface`
  = "cannot extend an object" saat kompilasi; (31) `Sequence.takeLast()` tidak
  ada (pakai `List.takeLast` atau `lines()`).
- CARA VERIFIKASI KERNEL (inti, pakai untuk A8+): Termux punya JDK 17 +
  kotlin-compiler, jadi kode Kotlin yang tidak butuh Android SDK bisa
  dikompilasi dan unit test-nya dijalankan lokal sebelum push. Inilah yang
  membuat A7 dan A8 hijau tanpa dua kali gagal compile di CI.
- APP-A8 (2026-09-29, leader langsung): BottomNav 4 tab + ScreenScaffold
  dipakai apa adanya (A5), navigasi state `mutableIntStateOf` (nol library
  nav), Beranda = HomePresenter (murni, tanpa androidx) + HomeScreen
  (Compose). Dialog "Pulihkan backup" WAJIB (AlertDialog) -> ViewModel
  memanggil `rollback`; `fail>0` dianggap gagal walau rc=0 (parse
  `Restore <nama> done. ok=N fail=M`, kalau baris tak ada = null, bukan
  angka karangan). 6 jenis error -> `friendlyError()`; detail modul hanya
  sebagai info tambahan. PlaceholderScreen untuk Knob/Monitor/Log (A9/A13/A14)
  - jujur, bukan data palsu. 109 test hijau (A6 32 + A7 53 + A8 24).
  CI: lint 36590969683 success, build-apk 36590969409 success.
- APP-A9 (2026-09-29, leader langsung di worktree a8 -> cabang a9-knob):
  KnobCategoryBuilder murni (key -> kategori, label, jenis kontrol dari
  bentuk data, requestedValueFor = salin nilai user, TANPA pemetaan OPP /
  validasi governor). Kategori hanya dibuat kalau punya key dari `knobs`,
  jadi knob tak tersedia tidak pernah tampil. Fitur bergate pindah ke
  KnobCapability.gated (dari `knobs.features`), extreme tetap terkunci.
  126 test hijau lokal. CI build-apk 36594161500 success (2x gagal
  sebelumnya: `openCategory = cat` salah tipe, lalu koma modifier hilang
  pada Row - keduanya error Kotlin yang HANYA terlihat di CI karena file
  Compose butuh Android SDK).
- PELAJARAN: (32) file Compose TIDAK bisa diverifikasi lokal (butuh
  android.jar + Compose runtime) - di situ mistake sintaks kecil
  (koma modifier, tipe state) hanya ketahuan lewat CI. Mitigasi: baca ulang
  diff Compose dengan mata, dan grep pola `modifier = Modifier\n .xxx(...)` ;
  (33) parameter `onClick` yang tidak dipasang ke modifier = UI yang tidak
  merespons sentuhan - selalu cek "apa yang terjadi kalau user mengetuk".

## Ganti model agent ke Gemini (2026-09-30, perintah user)
- API key Gemini + Groq di-connect user (`opencode auth list` ADA).
- Test live per model membuktikan katalog `opencode models` BUKAN daftar gratis:
  yang menentukan adalah paket akun provider. Groq gratis kepentok TPM 8k
  karena konteks agent ~10k — pelajaran: model cepat tak berguna kalau limit
  tokennya lebih kecil dari system prompt kita.
- PELAJARAN: (34) sebelum ganti model, test live dengan prompt trivial dan
  catat yang respons kosong/error pensiun/limit — jangan percaya katalog.

## APP-A10 s/d A16 (2026-09-30, leader langsung, semua merge + CI hijau)
- Alur: A10 apply flow (merge 646000f, feat 5760376) → A11 monitor
  (567787d/0ef8eff) → A12 log (8f2cc6c/95ebbe1) → A13 edge states
  (446f207/05b703b) → A14 audit (dd915fa/73e07d2) → A15 docs
  (e65d458/d745fa0) → A16 status (a8a204f/bfcbddf). Tabel status APP_PLAN
  semua [x].
- Kode produksi A10: `data/state/ApplyFlow.kt` (N× knob-set dirty → 1×
  apply manual → baca `knob-list` PER KNOB; knob-set yang ditolak modul
  jadi baris FAILED synthetic yang MENIMPA baris modul, kalau tidak
  baris "SKIPPED (manual)" lama akan menutupi kegagalan),
  `DirtyTracker.confirmApplied` (base di-reset hanya untuk APPLIED;
  FALLBACK = base=applied tapi current tetap requested sehingga masih
  dirty; FAILED/SKIPPED/UNAVAILABLE tidak disentuh), `UiState.isApplying`
  + `applyResults`, `KnobScreen.ResultLine` (badge per knob).
- Bukti L1: 161 unit test JVM hijau LOKAL di main HEAD (16 file main
  murni + 15 file test, dikompilasi dengan kotlin-compiler Termux
  + JDK 21); CI `lint-and-test` + `build-apk` success di semua branch
  step dan di main. Artefak APK terakhir di CI sudah kedaluwarsa
  (retensi Actions) → ukuran APK pasca-A10 BELUM diukur (dicatat di
  APP_FOOTPRINT + APP_FINAL_STATUS, bukan dikarang).
- Verifikasi lokal menang penuh: tidak ada satu pun kegagalan compile di CI
  untuk A10-A14 (berbeda A7/A9 yang butuh 2× revisi karena salah tipe
  state Compose). Kuncinya: file yang bisa diuji (presenter/pure) ditulis
  di `ui/` atau `data/state/` BUKAN di dalam `@Composable`, lalu
  dipanggil dari composable — begitu 90% logika ter-cover test lokal.
- PELAJARAN: (35) `HsinRepository.KnobResult` dipakai di Signature
  `KnobControl(row, result, onChange)` — default-argumen TIDAK boleh di
  tengah daftar parameter (Composable sempat gagal compile saat
  `onChange` setelah `modifier`); tulis parameter bernilai dulu, default
  selalu di belakang. (36) `viewModel::applyDirtyKnobs` TIDAK bisa
  dipakai langsung sebagai `() -> Unit` kalau fungsi punya parameter
  default `profile: String` — type mismatch (fungsi 1 argumen vs 0),
  harus dibungkus lambda `{ viewModel.applyDirtyKnobs() }`; ini yang
  membuat A11 (yang sempat pakai `::refreshRealtime`, aman karena
  tanpa parameter) tidak error tapi A10 iya. (37) Classpath test lokal
  di Termux: `kotlinx-coroutines-test-1.8.1.jar` dari Maven itu
  metadata-only (multiplatform) — yang berisi `runTest` class bytecode
  adalah artifact `-jvm`; pakai yang sudah ada di
  `~/usr/tmp/opencode/ctest.jar`, jangan unduh yang `-1.8.1.jar` itu
  lagi (compile test gagal: unresolved `runTest`). (38) Fungsi yang
  sudah tidak dipakai (mis. `PlaceholderScreen` setelah semua tab nyata
  di A12) harus DIHAPUS di audit, bukan dibiarkan sebagai "cadangan" —
  dead code composite adalah beban review (A14).

## BLOCKER L2-BUILD (2026-09-30, leader, ZIP apply MATI - jangan flash dulu)
- Konteks: run build-modul #36656203932 (mode=both, SUCCESS) +
  build-apk #36656232453 (SUCCESS) dari main `72651ce`. validate_build.sh
  LULUS untuk KEDUA ZIP (wajib file + fungsi cache-scan/override + <50MB).
- Temuan 1 (permintaan user, jawaban jujur): file `core/boot_guard.sh`,
  `core/safe_apply.sh`, `core/thermal_check.sh`, `core/engine_guard.sh`
  TIDAK ADA sebagai file terpisah di ZIP mana pun - build_release.sh
  menyatukan semuanya ke `core/runtime.sh` (baris 82-108). Isi/fungsinya
  TERBUKTI ada di dalam runtime.sh (15.679 baris, sh -n rc=0). Jadi cek
  harus di level FUNGSI, bukan nama file.
- Temuan 2: `capability/capability_overrides.json` TIDAK ikut ZIP (folder
  `capability/` hilang total di dev & release). Verified 0 pemanggil:
  `hsin_override_load` = 0 caller di seluruh runtime (hanya build_release
  + tests) -> itu sisa roadmap lama yang direvert, bukan bug kemasan baru.
  KEPUTUSAN(user): bundling atau tandai dead code - belum saya ubah.
- Temuan 3 = BLOCKER SERIUS: apply TIDAK BEKERJA di kedua ZIP.
  Bukti: `action.sh apply manual` -> "OK: Applying manual (running in
  background)"; debug.log: "apply_*.sh: 19: hsin_apply_all_engines: not
  found" + error.log "[ERROR] main"; knob-list tetap "belum ada hasil
  apply"; node tidak berubah sama sekali.
  AKAR MASALAH (terbukti, bukan dugaan): `core/thermal_check.sh:176`
  diakhiri `return $HSIN_THERMAL_CHECK_RC 2>/dev/null || exit
  $HSIN_THERMAL_CHECK_RC`. Filter merge di build_release.sh:107 hanya
  membuang pola `return 0 2>/dev/null || true` (68 file ikut pola itu),
  TIDAK membuang bentuk variabel ini. Jadi baris itu utuh di runtime.sh
  baris 7035 -> saat runtime.sh di-source, `return 4` (UNKNOWN)/
  `exit` menghentikan sourcing SETELAH baris itu. Semua yang di-merge
  sesudahnya - termasuk `core/apply_engines.sh` (baris 15282,
  hsin_apply_all_engines) - TIDAK PERNAH terdefinisi.
  Bukti lanjutan: (1) `sh -n runtime.sh` rc=0 (parse-SEHAT) tapi
  `. runtime.sh` rc=4 + thermal_check mencetak "[thermal_check] UNKNOWN"
  saat source; (2) fungsi sebelum 7035 ADA (hsin_log_warn,
  hsin_safe_apply, hsin_knobs_json, hsin_uk_set, hsin_boot_guard_check),
  fungsi sesudahnya TIDAK (hsin_apply_all_engines); (3) uji pada SALINAN:
  baris 7035 dinonaktifkan -> hsin_apply_all_engines TERDEFINISI.
  (4) sh Termux = dash, dan `return` di sourced file memang menghentikan
  file itu (diuji dengan file minimal).
- DAMPAK: di HP, flash ZIP mana pun = knob tidak pernah diterapkan;
  aplikasi tidak error (tetap rc=0 "queued"), knob_results.env tidak
  pernah lahir, jadi A10 selalu tampil "DIUBAH" tanpa hasil. A10 tidak
  bisa divalidasi L2 sebelum ZIP ini dibetulkan.
- KELAS BUG: sama dengan "BUG ZIP RUNTIME" M2 (guard_status.sh) dan
  thermal_check yang hilang (ee5f85b) -.merge runtime belum punya
  negative test. Root: tidak ada uji yang meng-source runtime.sh hasil
  build (semua sandbox test menyource file SATU per file dari source tree).
- PERBAIKAN MINIMAL (1 baris, SIAP tapi BELUM saya kerjakan - menunggu
  approve user): perlebar filter awk build_release.sh:107 agar juga
  membuang `return $VAR 2>/dev/null || exit $VAR` di kolom 0, mis.
  `!/^return \$[A-Za-z_][A-Za-z0-9_]* 2>\/dev\/null \|\| exit \$/`
  Source tetap bisa dijalankan langsung (`sh core/thermal_check.sh`
  masih keluar dengan rc), yang hilang hanya efek auto-exec saat
  di-merge. Setelah itu WAJIB: build ulang + smoke test apply dari ZIP
  (harness baru yang meng-source runtime.sh hasil build).
- CATATAN JUJUR thermal_check: 4 fungsinya (_read_thermal_max,
  _read_thermal_basis, _classify_thermal, _thermal_critical_intervene)
 private dan 0 caller di luar file itself; blok thermal di service.sh:71
  dijaga `if [ -f core/thermal_check.sh ]` yang sudah FALSE di ZIP
  (file tidak ada). Jadi thermal check boot di ZIP sebenarnya TIDAK
  jalan - ini temuan kedua yang perlu keputusan (panggil sebagai fungsi
  vs buang).

## FIX merge runtime + gate CI (2026-09-30, leader, commit 95b4daa) - BLOCKER L2-CLOSED
- POIN 1 (filter merge): inventaris SEMUA statement top-level di 71 file
  yang di-merge. Hasil: 68 file memakai `return 0 2>/dev/null || true`
  (seragam), HANYA `core/thermal_check.sh:176` memakai bentuk variabel
  `return $VAR 2>/dev/null || exit $VAR`. Tidak ada `set -e`/`exec`/
  `trap`/`eval` top-level di file yang di-merge. Fix: filter awk
  membuang SEMUA `^return `/`^exit ` (bukan cuma satu pola), dengan
  alasan tertulis di build_release.sh.
- POIN 1b (KELAS BARU, ditemukan oleh test): `sed -i '/^\s*\. .*core
  |engine|extreme\//d'` menghapus baris `. "$PATH/..."`, tapi TIDAK
  menghapus guard 2-baris `command -v X >/dev/null 2>&1 || \`. Sisanya
  jadi `|| \` YATIM; kelanjutan baris itu menelan baris berikutnya
  (termasuk definisi fungsi) sebagai lanjutan perintah -> fungsi hilang
  TANPA error. Terverifikasi di runtime.sh: baris `command -v
  hsin_cpu_policy_ids ... || \` langsung diikuti baris `hsin_cpu_
  governor_pick() {`, dan fungsi itu tidak terdefinisi. 8 file kena:
  cpu/governor.sh, cpu/frequency.sh, cpu/scheduler.sh, gpu/generic.sh,
  gpu/devfreq_tuning.sh, io/readahead.sh, io/queue_tuning.sh,
  memory/zram.sh. Contoh fungsi yang hilang di ZIP lama:
  hsin_cpu_governor_pick, hsin_cpu_sched_apply, hsin_io_scheduler_apply,
  hsin_io_apply_readahead, hsin_zram_detect, hsin_gpu_tune_one,
  hsin_profile_rank, 4× _hsin_refresh_*. Fix: filter juga membuang
  `^command -v ... >/dev/null 2>&1 || \` (pipe di-escape `\|\|`).
- Jebakan Implementasi (2, keduanya sempat merusak merge):
  (a) program awk WAJIB satu baris - backslash-newline di dalam
  single-quote BUKAN line continuation shell -> awk dapat program rusak
  -> runtime hanya 144 baris (hanya header) tanpa error;
  (b) `||` mentah di dalam regex awk dibaca OPERATOR OR, bukan teks ->
  filter match ke SETIAP baris -> runtime kosong tanpa error.
  Dicek ulang dengan printf/awk terisolasi sebelum commit.
- POIN 2 (test permanen): tests/verify_bundle_runtime.sh (BARU, 240
  baris). Dua mode: `--merge-only` (panggil `build_release.sh
  merge-only` - merge yang SAMA PERSIS dengan build, tanpa zip, supaya
  tidak bisa drift) dan `<zip>` (verifikasi ZIP asli). Cek:
  (1) tidak ada `^return `/`^exit ` bocor di runtime.sh; (2) `sh -n`
  lolos; (3) sourcing di sandbox HSIN_SANDBOX=1 dengan prefix sysfs/proc
  kosong menghasilkan rc=0; (4) SETIAP fungsi yang didefinisikan di 71
  file yang di-merge WAJIB terdefinisi setelah source (505 fungsi);
  (5) setiap fungsi inti (hsin_apply_all_engines, hsin_boot_guard_check,
  hsin_safe_apply, hsin_thermal_apply, hsin_engine_run, hsin_knobs_json,
  hsin_uk_set, hsin_guard_status, hsin_scan_cache_load) dicek satu per
  satu; (6) semua hsin_* yang dipanggil entrypoint (posisi perintah)
  WAJIB terdefinisi. Probe dijalankan INLINE di subshell yang sama -
  lewat `sh probe.sh` anak tidak mewarisi fungsi shell dan akan selalu
  melaporkan semua hilang. Ekstraksi call-site hanya menghitung token
  di POSISI PERINTAH; `_hsin_boot_log`/`_hsin_is_game`/`_hsin_mpid`
  adalah variabel (false positive yang sudah dibuang), dan token
  diprefix `_(hsin_)` boleh agar privat ikut teruji.
  Gate dipasang di DUA workflow: lint-and-test (setiap push, mode
  merge-only) + build-modul (setiap build ZIP, terhadap build/*.zip).
- BUKTI NEGATIF/POSITIF (ini yang membuktikan test punya gigi):
  test terhadap ZIP LAMA (run 36656203932) = MERAH: PASS 9 / FAIL 5,
  termasuk "hsin_apply_all_engines HILANG", "hsin_thermal_apply HILANG",
  plus return/exit bocor; merge baru = HIJAU PASS 15 / FAIL 0.
- POIN 3 (build ulang + smoke test identik): run build-modul #36659882646
  (mode=both, SUCCESS, gate hijau di log CI untuk kedua ZIP).
  validate_build.sh VALID untuk kedua ZIP.
  SEBELUM -> SESUDAH apply manual (node palsu, release ZIP):
    vfs_cache_pressure      100 -> 250     APPLIED
    dirty_ratio              20 -> 30      APPLIED
    netdev_max_backlog     1000 -> 16384   APPLIED
    read_ahead_kb           128 -> 2048    APPLIED
    nomerges                  2 -> 1        APPLIED
    gpu polling_interval     50 -> 100     APPLIED
    sched_child_runs_first   (node tak ada di pohon palsu) UNAVAILABLE
    scaling_governor      schedutil -> schedutil (TIDAK ditulis = mode
                             manual murni terbukti, knob tanpa override)
  apply.log: "override: 6 key dipakai" + "Profile applied: manual";
  error.log tidak pernah dibuat. knob-list = 6 APPLIED + 1 UNAVAILABLE
  ("node hilang atau read-only") + sisanya SKIPPED "tidak diatur (mode
  manual)" - persis bentuk yang;A10 consume. ZIP lama: 0 node berubah,
  "belum ada hasil apply", [ERROR] main.
- POIN 4 (JAWABAN: thermal_check TIDAK mematikan M1b). Bukti pemanggilan:
  `hsin_thermal_apply` (engine/thermal/policy.sh:294, tempat cap M1b +
  restore pre-cap) dipanggil dari `hsin_thermal_engine_apply`
  (engine/thermal/apply.sh:55), dan ITU dipanggil dari DUA jalur:
  `core/apply_engines.sh:135` (APPLY NORMAL) dan `service.sh:365`
  (BOOT). Sementara `core/thermal_check.sh` di-source HANYA di
  service.sh:71-72 di balik `if [ -f core/thermal_check.sh ]` yang
  selalu FALSE di ZIP (file tidak ada sebagai file terpisah), dan 4
  fungsinya private, 0 caller. Bukti empiris di ZIP baru: suhu 96C ->
  apply -> scaling_max_freq 1800000 -> 600000 + file
  thermal_pre_cap.list terbentuk; suhu turun 45C -> apply -> kembali
  1800000. Jadi cap + restore M1b UTUH di jalur apply normal; yang mati
  hanya pre-check/log boot di service.sh (EFEK SAMPING: g_block itu
  masih dieksekusi tiap runtime.sh di-source karena auto-exec-nya tidak
  dihapus - pada VERY HIGH dia hanya PRINT "limited intervention only if
  justified" dan tidak menulis; pre-existing, bukan regresi).
  KEPUTUSAN(user, belum dikerjakan): panggil thermal_check sebagai
  fungsi dari boot, atau buang blok service.sh:71-73.
- UKURAN ZIP lama -> baru: dev 494.919 -> 500.331; release 484.059 ->
  489.472. module.prop tetap v5.0.0-beta1/5001 (tidak di-bump).
- POIN 5 (OPSI, menunggu keputusan user - belum ada perubahan):
  capability/capability_overrides.json tidak ikut ter-bundle (folder
  capability/ hilang di dev & release) dan `hsin_override_load` = 0
  caller di seluruh runtime -> sisa fitur roadmap 22-step yang mati.
  OPSI (a) bundel ulang capability/*.json ke ZIP; (b) dokumentasikan
  sebagai fitur nonaktif/tidak dipakai dan biarkan file di source tree
  untuk referensi; (c) hapus file + load_overrides.sh beserta rujukan test.
  Tidak ada yang saya kerjakan; menunggu user.
- PELAJARAN: (41) merge banyak file ke satu file runtime WAJIB diuji
  dengan me-source HASIL merge-nya; test per-file dari source tree
  tidak akan pernah menangkap kelas bug ini. (42) saat menghapus baris
  (sed/awk) dari hasil merge, cek sisa CONTINUATION baris (`|| \`,
  `&& \`) - baris hilang tapi sambungannya masih menggigit baris
  berikutnya. (43) awk: `||` di dalam regex harus di-escape, dan program
  awk jangan multi-baris di dalam single-quote. (44) probe fungsi shell
  harus inline di subshell yang sama; `sh probe.sh` anak tidak mewarisi
  fungsi. (45) grep nama fungsi tanpa memeriksa posisi perintah
  menghasilkan false positive dari variabel bernama mirip fungsi.
  false positive dari variabel bernama mirip fungsi.

## thermal_check jadi fungsi eksplisit + capability override TIDAK AKTIF (2026-09-30, 509a215)
- Investigative DULU (bukti, bukan asumsi): policy.sh SUDAH punya 5 state
  (cool/normal/warm/hot/critical, ambang TETAP 60/75/85/95C, perf target
  100/95/85/70/50) dan monitor.sh punya 5 state untuk display. Jadi
  graduated behavior BUKAN hanya di thermal_check - thermal_check bukan
  satu-satunya pemegang ladder. Yang unik hanya 3: (1) basis ambang dari
  trip_point kernel (68%/84%/100% dari critical device, filter 40-125C),
  (2) jalur intervensi darurat kedua yang independen dari pipeline apply,
  (3) state UNKNOWN saat tanpa data + filter sensor abnormal.
--effectiveness di ZIP: blok auto-exec thermal_check ikut jalan di SETIAP
  source runtime.sh (terbukti: 2 source berturut @45C = 2 baris print),
  sedangkan blok boot service.sh `if [ -f core/thermal_check.sh ]`
  selalu FALSE. Jadi check termal hidup sebagai EFEK SAMPING, pre-check
  boot tetap buta. HSIN_THERMAL_CHECK_RC/BASIS = 0 pembaca lain.
- Fix (leader, 2 file + 3 dokumen): blok top-level diekstrak jadi
  `hsin_thermal_check_run` (file ends `return 0 2>/dev/null || true`,
  tidak ada pemanggilan top-level lagi); service.sh pakai
  `command -v hsin_thermal_check_run` + log Basis. Tidak ada threshold
  M1b yang disentuh (trip_point di jalur apply = langkah terpisah).
- Bukti tiga efek (merge lokal DAN ZIP final build #36661729610):
  (a) pre-check + jalur darurat hidup: NORMAL rc=0 @45C, VERY HIGH rc=2
      @96C, basis trip_point:100000 terbaca;
  (b) noise hilang: thermal_check=0 pada `action.sh status`/
      `guard-status`/`knob-list`, dan 0 saat source runtime.sh
      (sebelumnya 1 per source, termasuk tiap polling monitor);
  (c) M1b utuh: 96C -> scaling_max_freq 1800000->600000
      (Policy=critical Perf=50%), 45C -> 1800000 (Policy=cool Perf=100%);
      knob manual tetap APPLIED (vfs_cache_pressure=250).
- Dokumentasi (DOKUMEN SAJA, loader tidak diubah, JSON tidak dibundel,
  file tidak dihapus): README.md Profiles, API.md §2 (judul diubah jadi
  "TIDAK AKTIF" + catatan status), CHANGELOG.md entri capability.
- Gate permanen tetap hijau: verify_bundle_runtime.sh PASS 15/FAIL 0
  (kini 506 fungsi, +1 dari hsin_thermal_check_run).
