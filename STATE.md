# STATE.md — HSIN manual

- INIT (2026-09-26, leader): repo isac12345/Hsin (private, diubah
  dari public atas perintah user) dibuat via
  `gh repo create`, clone kosong ke ~/Hsin, kerangka AGENTS.md +
  NOTES.md + PLAN.md + STATE.md ditulis. Konsep dikunci: HSIN manual/
  bebas setting (Alpha adaptif). Fokus modul dulu, APK belakangan,
  tanpa build. Sumber /sdcard/hsin (6 zip + hsin-dev v5-beta1).
  BELUM: audit varian + impor basis + commit awal. Branch: master
  (baru, 0 commit, belum push).

- AUDIT-VARIAN (2026-09-26, leader + dev-modul): audit read-only DONE,
  TERIMA (verifikasi leader cocok: grep kontaminasi per zip + hsin-dev
  bersih + extreme/ lengkap 5 file + git clean). Basis = hsin-dev
  v5-beta1. Branch main sinkron origin (2524226). Lanjut: impor basis
  ke repo (tanpa build), lalu fix isi per file. Tanpa flash/zip.

- IMPOR-BASIS (2026-09-26, leader, perintah user "yes"): hsin-dev
  v5-beta1 diimpor apa adanya ke main (commit c6e6957, 110 file,
  build/ dikecualikan, secret-scan bersih, .devmode kosong ikut).
  Push DONE, main sinkron origin. BELUM diubah isinya sama sekali.
  Lanjut: audit timing apply + peta scan.

- AUDIT-TIMING (2026-09-26, leader + dev-modul): DONE TERIMA
  (verifikasi leader 6 klaim cocok). Biang >15s = scan ulang tiap
  apply + backup full + binder. Desain cache disetujui.

- CACHE-LANGKAH1 (2026-09-26, leader + dev-modul work/scan-cache):
  TERIMA + merge ab92aa3 ke main, push DONE, worktree/branch
  dibersihkan. Thermal kini cache-first (fallback aman). Antrean:
  fix policy-subshell (throttle no-op) + backup.sh glob + engine
  lain ke cache. L2: butuh flash + APPLY-TIME HP.

- BACKUP-CACHE-2B (2026-09-26, leader + dev-modul work/backup-cache):
  TERIMA + merge 5e80e74, push DONE, worktree/branch bersih.
  Backup thermal cache-first, 1 snapshot/apply. Antrean: engine
  cpu/gpu/mem/io ke cache + error per tweak.

- CPU-CACHE-2C (2026-09-26, leader + dev-modul work/cpu-cache):
  TERIMA + merge f58d2ed, push DONE, worktree/branch bersih.
  CPU cache-first (tuning identik), safety 1 pass. Antrean:
  gpu/mem/io ke cache + error per tweak.

- GPU-CACHE-2D (2026-09-26, leader + dev-modul work/gpu-cache):
  TERIMA + merge c223501, push DONE, worktree/branch bersih.
  GPU cache-first + OPP cache (tuning identik). Antrean:
  mem/io ke cache + dvfs.sh glob + error per tweak.

- MEMIO-CACHE-2E (2026-09-26, leader + dev-modul work/memio-cache):
  TERIMA + merge 8adc31d, push DONE, worktree/branch bersih.
  Mem/IO/dvfs cache-first (tuning identik). Antrean: bug zram
  (apply tanpa detect) + error per tweak + L2 HP.

- AUDIT-ERROR-2F (2026-09-26, leader + dev-modul): DONE TERIMA
  (harness t1-t11, repo bersih, verifikasi leader: OOM-proteksi
  mati BENAR + dvfs-bohong BENAR). 14 temuan, antrean 10 fix.

- FIX1-OOM (2026-09-26, leader langsung, ≤20 baris): proteksi daemon
  jadi satu baris spasi (7070f13, +3/-15). Bukti: bash-n OK,
  shellcheck 0, uji fungsi 12/12 cocok + non-proteksi lolos. Push
  DONE.

- FIX2-ZRAM (2026-09-26, leader + dev-modul work/zram-fix): TERIMA +
  merge 8bcca04, push DONE, worktree/branch bersih. zram detect→
  apply tersambung + guard tulis (algo utuh). Antrean: #3 dvfs.

- FIX3-DVFS (2026-09-26, leader + dev-modul work/dvfs-verify): TERIMA
  + merge 319238a, push DONE, worktree/branch bersih. Tulis DVFS
  diverifikasi, lapor jujur. Antrean: #4 oom-verify + sisa.

- FIX4-OOM (2026-09-26, leader + dev-modul work/oom-verify): TERIMA +
  merge ea9325a, push DONE, worktree/branch bersih. Release via
  verify, hitung jujur, proteksi utuh. Antrean: #5 zram-readback.

- FIX5-ZRAMRB (2026-09-26, leader + dev-modul work/zram-readback):
  TERIMA + merge bcb09f0, push DONE, worktree/branch bersih.
  Readback algo, ok jujur, mapping utuh. Antrean: pre-check [siku].

- FIX6-PRECHECK (2026-09-26, leader langsung, task cancel → ≤20
  baris): pre-check + probe balanced lepas [siku] (78742cc, +8/-2).
  Bukti: bash-n OK, shellcheck 0, uji 5 kasus (readback ketat utuh,
  balanced `[zstd]`→zstd). Push DONE. Antrean: #7 thermal-status.

- FIX7-THERMALSTATUS (2026-09-27, leader langsung, ≤20 baris):
  status kosong di thermal_manager.sh 2 site (e20a351, +4/-2,
  `_status=$(classify)` → panggil + baca $HSIN_THERMAL_STATE).
  Bukti: bash-n OK, shellcheck 0, red-green (lama kosong+basi,
  baru hot/normal/panic benar). Worktree/branch basi
  work/zram-precheck dibersihkan. Antrean: #8 scheduler-log.

- FIX8-SCHEDLOG (2026-09-27, leader langsung, 1 baris): log cpuset
  BIG pakai $HSIN_CPU_BIG bukan $_cpus basi (3034cf4, 1+-1-).
  Bukti: bash-n OK, shellcheck 0, demo red-green. IO scheduler
  bersih. Antrean: #9 dead-code/no-op.

- FIX9-DEADCODE (2026-09-27, leader langsung): HAPUS devfreq.sh
  (0 pemanggil, diganti generic.sh) + stub hsin_thermal_apply_sched
  no-op (e8864a1, -158/+1). Bukti: bash-n OK, grep sisa 0,
  SC2115 pre-existing di luar scope. Susulan 157be9a: hapusan
  devfreq.sh lepas dari e8864a1 (staging lepas habis stash-pop),
  ter-commit susulan, push DONE. Antrean: #10 generic-msg.

- FIX10-GENERICMSG (2026-09-27, leader langsung, pesan saja):
  generic.sh tanpa OPP klaim governor prematur + max kosong
  (14bd9fe, 2+-2-, nol perilaku). Bukti: bash-n OK, shellcheck 0,
  sandbox 3 kasus (A/B/C, C regresi nihil). Antrean: sisa kosmetik
  (DEVFRES/safety-while/disksize) + /proc→$HSIN_PROC bertahap.

- SISA-2F (2026-09-27, leader langsung): DEVFRES/|while benign
  terkonfirmasi (tanpa fix); disksize-komentar + safety-export-mati
  (aa719a7); proc langkah-1 network via $HSIN_PROC (f4ac85c, tuning
  utuh). Bukti: bash-n, shellcheck 0, sandbox (bbr/tfo/sysctl/state),
  /proc 95→73. Antrean: proc batch-2 per area + L2 HP.

- PROC-2 (2026-09-27, leader langsung): core/detector.sh via
  $HSIN_PROC (a620ea5, deteksi utuh). Bukti: bash-n OK, shellcheck
  0, sandbox 5 fungsi. /proc 73→55. Antrean: proc batch-3 + L2 HP.

- PROC-3 (2026-09-27, leader langsung): core/* 6 file via $HSIN_PROC
  (f891245, probe utuh). Bukti: bash-n 6/6, shellcheck 0, sandbox
  (hardware/root_check/backup/capability_scan). /proc 55→32.
  Antrean: proc batch-4 (action.sh + engine/*) + L2 HP.

- PROC-4 + #14 SELESAI (2026-09-27, leader langsung): action.sh +
  engine/{imgtec,validator,scheduler,governor} via $HSIN_PROC (f174dcc).
  Bukti: bash-n 5/5, shellcheck 0 baru, sandbox end-to-end (status JSON
  ram/uptime/load dari prefix palsu, device_info soc, sched-latency
  tuning identik). /proc 95→0 eksekutable (sisa 9 komentar). Antrean:
  L2 HP (flash + APPLY-TIME).

- KNOBS-API + 3 BUG (2026-09-27, dev-modul + review leader): aksi
  `knobs` JSON untuk app (bb50517, read-only; review: 18 fungsi eksternal
  semua ada, escaper benar, sandbox 2 skenario valid, 0 regresi). Review
  menemukan 3 bug: f319da0 scan_cache hilang dari runtime release (cache
  scan mati di ZIP release), 6f494f6 refresh_hz salah baca bentuk `=`,
  30c1fbb cache KOSONG diterima sah -> thermal/safety buta (paling serius).
  Semua push DONE. Antrean: L2 HP + rencana app (Tahap 3).
