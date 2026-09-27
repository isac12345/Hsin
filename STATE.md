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

- APP-SCAFFOLD (2026-09-27, leader inline): app/ Gradle+Kotlin scaffold
  (7a0402a, 52 file). RootExec (su -c + stdout capture + timeout + safe
  quoting), HsinRepository (knobs/status/device/apply/config-set/logs),
  MainActivity 3-tab (Status/Knobs/Logs), KnobsFragment (dynamic
  RecyclerView dari `action.sh knobs` + draft + Apply), StatusFragment
  (pull-to-refresh live status + device info), LogsFragment (spinner
  log type). Material 3 theme, viewBinding, kotlinx.serialization, icon
  dari branding/logo.png. Push DONE. Antrean: Extreme opt-in UI + game
  list UI + Backup/Restore UI + polish + L2 HP.

- USER-KNOBS (2026-09-27, dev-modul + review leader): aksi
  knob-set/knob-reset/knob-list (aaa7a9c) simpan override knob ke
  $HSIN_DATA/user_knobs.env (atomic + readback, maks 64 key, tervalidasi).
  Review leader: 10 uji injeksi DITOLAK semua, file berisi 4 baris persis,
  7 aksi lama rc=0, jalur apply TIDAK tersentuh. Push DONE.
  PENTING: override belum dipakai apply -> pilihan user BELUM berefek.

- APP-FIX + CI (2026-09-27, leader inline): scaffold 7a0402a diperbaiki -
  adapter RecyclerView ditulis ulang jadi model baris datar (versi lama
  campur tipe baris = runtime crash), 10x ArrayAdapter signature salah,
  import decodeFromString hilang, fragment akses mainViewModel private,
  manifest menunjuk class terhapus, layout disinkronkan, 0 TODO/placeholder,
  wrapper Gradle palsu (stub) dihapus. Apply jadi nyata: knob-set* +
  config-set* lalu satu apply. Fitur tanpa jalur tulis (DVFS/global-RR/
  frame-limit/SF) ditampilkan read-only, bukan switch palsu (9c8aac3).
  Workflow .github/workflows/{build-apk,build-modul}.yml MANUAL
  (workflow_dispatch, tidak auto-build saat push).
  CATATAN JUJUR: Kotlin BELUM PERNAH dikompilasi (tanpa JDK di Termux);
  semua R.id/R.layout/@string/@style/@color sudah dicek resolve, tapi
  error compile baru terlihat setelah CI dijalankan. Push DONE.

- DOKUMEN (2026-09-27, leader): PLAN.md ditulis ulang agar akurat (Tahap 1
  kode selesai nunggu L2; Tahap 3 app jalan tapi belum terverifikasi
  compile; build hanya via GitHub Actions). Tidak ada perubahan kode.

- CI-BUILD-PASS (2026-09-27, leader):
  * APK build & compile sukses via GitHub Actions (run #36296279179,
    artifact: `hsin-debug-apk`). 5 error compile diperbaiki: path
    AndroidManifest, duplikat warna, attr Material 3, Kotlin scope/model,
    dan path artifact.
  * Modul ZIP build sukses via GitHub Actions (run #36296491773,
    artifact: `hsin-modul-dev`). Verifikasi `core/runtime.sh` lolos.
  * Siap untuk pengujian HP (L2).

- FIX-RUNTIME-GUARD-P1 (2026-09-27, leader + dev-modul work/guard-runtime):
  TERIMA L1 + merge b5cbf73, push pending. Guard idempotent di generated
  runtime.sh via build_release.sh (+3). Verifikasi leader: sh -n OK,
  shellcheck 0 baru, sim fungsi-ada + re-source murah. L2: flash+reboot.

- AUDIT-BLANK-P2 (2026-09-27, leader + dev-modul work/p2-shell + dev-apk
  read-only): 2c 3/3 fix ADA (bukan penyebab); 2d komentar diluruskan
  (merge bbf27ee, push pending); 2e KSU-compat aman (tanpa fix); 2f rantai
  error app terbukti tampil pesan (timeout→throw→Snackbar/toast), jadi
  blank-tanpa-error tak terbukti statis → pemisah = Task 2a di HP oleh
  user. L2: user tes shell manual + konfirmasi berat/blank.

- SWEEP-SANDBOX-KONTRAK (2026-09-27, leader + dev-modul work/sweep-shell
  + dev-apk read-only + fix work/knobs-empty): TERIMA + merge 3ed645e
  (komentar stale + 2 prefix sandbox) + f5a0e9f (toast scan-kosong Knobs),
  push DONE. Verifikasi leader: sh -n OK, shellcheck 0 baru (SC2154
  false-positive via eval, SC2115 pre-existing), sandbox sendiri (status
  0.3s JSON-29-key valid + suhu mengalir, knobs 2 policies, pohon kosong
  rc=0, 1 baris `{`), kontrak COCOK kecuali status-asimetris-aman
  (ignoreUnknownKeys). CI: modul #36301125635 + apk #36301127388 success.
  L2: flash + reboot + tes HP oleh user.


- STEP4-STEP5 (2026-09-27): Step 4 detector (5b373ea) + Step 5 overrides
  (77b3a2b) + STATUS.md DONE (a65f32c, 3cb91cf). CI hijau semua. STOP.
