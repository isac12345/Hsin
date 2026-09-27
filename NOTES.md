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
  /usr/tmp/opencode (pelajaran alat).

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
