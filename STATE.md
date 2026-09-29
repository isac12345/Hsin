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

- SESI 2026-09-27/28 (leader langsung, penomoran PQ): PQ Step 9
  overrides (b79763d), Step 10/11 thermal_check + verifikasi ulang
  trip_point + return-or-exit (2a56064, 546f9a5), harmonisasi spec
  Step 11 (912b3bf), Step 12 engine_guard degradasi (7ae4573), fix
  bundle thermal_check (ee5f85b, red-green via build release),
  Phase 4 docs Step 13-18 (a9e4e03, 50bf8e6, ce4dfbd, 1f362e7,
  b37b0f2, 3c46f66), Phase 5 Step 19-21 + extreme hard-limit
  (ed5e34e, a7e90e5, 1734654, 15d5770), gate Step 22 BELUM LOLOS
  (d84bb49), Step 23 knob visibility (05191f1). HEAD main 05191f1,
  push + CI success semua, repo bersih. STOP: tunggu user (siang).

- APP-M1 (2026-09-28, leader + dev-modul work/m1-manual): TERIMA L1 + merge
  cef5f46 ke main, push DONE. Manual murni: hanya override user ditulis,
  sisanya SKIPPED. 8 koreksi leader atas diff pekerja. Bukti: statis 0,
  sandbox lama 60/60 identik baseline, snapshot 8/8, ZIP staging /tmp OK.
  module.prop tetap v5.0.0-beta1/5001. APP_PLAN M1 [x]. L2: validasi HP.
- APP-K1-K3 (2026-09-28): dokumen K1/K2/K3 disisipkan APP_PLAN.md (baris
  258/271/282, tabel 126-128) — belum dieksekusi; hanya rencana.
  Antrean: M2 guard-status (butuh approve user? tidak — M2 sudah di plan).
- APP-M1B (2026-09-28, leader + dev-modul work/m1b-purity, 2 putaran):
  TERIMA L1 + merge ca429a2 ke main. Safety remap dilewati di manual
  (intervensi kritis hanya thermal cap), cap di-restore saat dingin
  (cool/normal, CPU+GPU, terverifikasi), boost skip di manual + log
  persis, cpu_restore readback ketat. Bukti: (a) 96C hanya 3 node cap,
  (b) batt 10% nol tulis, (c) restore 1800000/800M, (d) boost manual nol
  tulis (balanced tetap performance), (e) 8 suite sandbox lama hijau,
  profil lama md5 identik; sh -n + shellcheck -S error 0; tanpa runtime
  baru. Koreksi NOTES M1 (catatan restore keliru) + bagian M1b.
   APP_PLAN M1b [x]. L2: validasi HP. STOP.
- APP-M2 (2026-09-29, leader + dev-modul work/m2-guard): TERIMA L1 + merge
  dafeb7d ke main. guard-status read-only (5 baris key=value + JSON
  terakhir, rc 0; hilang/rusak -> "tidak ada state"). Koreksi leader
  d547271: auto-exec saat source + preamble tulis + harness path.
  Bukti: harness 20/20, regresi hijau semua, snapshot nol tulis.
  APP_PLAN M2 [x]. L2: validasi HP. STOP.
- APP-K1 (2026-09-29, leader investigasi pra-kode, STOP): live-read 5 knob
  GAGAL semua dari Termux (Permission denied, su dilarang tanpa izin).
  Batas di-tree dicatat (vm.sh HSIN_VM_SAFE, profil) tapi BELUM dikunci.
  readahead + backlog tanpa batas di-tree -> butuh angka user (Q1-Q5).
  Penilaian 16-19: DVFS bersyarat-aman, RR bersyarat, frame-limit kurang
  cocok, SF tidak aman live. NOL kode diubah, K1 tetap [ ]. Menunggu user.
- APP-K1 (2026-09-29, leader langsung; 2 delegasi dev-modul GAGAL/cancel):
  TERIMA L1, batas dikunci user (vfs 0-1000, ratio 1-90, bg 1-50 +
  validasi bg<ratio, readahead preset 7 nilai, backlog 128-16384).
  5 knob baru: vfs_cache_pressure, dirty_ratio,
  dirty_background_ratio, backlog, io_block_*_readahead. 7 file
  +393/-70 tanpa file runtime baru. 3 koreksi leader (kategori hasil saat
  tulis gagal; backup io sandboxable; BUG runtime ZIP asal M2 ditemukan
  lewat rekonstruksi runtime + diperbaiki). Bukti: harness K1 36/36,
  suite lama 8/8, runtime sh -n OK, dispatcher end-to-end. Baris 16-19
  dikeluarkan dari K1 (dicatat NOTES sebagai kandidat step terpisah).
  APP_PLAN K1 [x]. L2: validasi HP. STOP.
- APP-K2 (2026-09-29, leader langsung): TERIMA L1, commit 6a0ac2a. 6 knob
  tier-1: io_block_{add_random,iostats,nomerges} (0/1), stat_interval
  (1-60), page_cluster (0-9), cpu_policy_*_rate_limit_us (0-100000 us,
  gate governor==schedutil + node ada). Live HP: 5 node ada writable;
  rate_limit_us TIDAK ADA (governor aktif uscfreq) -> UNAVAILABLE di
  device ini, sesuai gate K2; batas 0-100000 = batas UI (kernel kstrtouint
  tanpa clamp, diverifikasi ke source kernel v6.6), belum terverifikasi
  live. File baru engine/io/queue_tuning.sh terdaftar di build_release.sh.
  Koreksi leader: page-cluster (hypen) vs kunci page_cluster -> pemetaan
  di vm.sh. Bukti: harness K2 42/42, suite lama 8/8, runtime ZIP sh -n OK
  + 0 blok if kosong, dispatcher 6/6. Catatan: nomerges live 2 tidak
  bisa dipilih (opsi 0/1 sesuai keputusan user). APP_PLAN K2 [x].
  L2: validasi HP. STOP.

- APP-K3 (2026-09-29, leader langsung): TERIMA L1, commit faf7261. 12 knob
  tier-2 capability-gated: sched_child_runs_first (0/1), uclamp_min/max
  (0-1024), gpu_node_*_{polling_interval,up_threshold,down_differential},
  mali_{boost_level2,pollingtime,upthreshold}, sched_*_pct (10-200 persen).
  Live HP: 3 sysctl sched TIDAK ADA; up_threshold/down_differential TIDAK
  ADA (governor simple_ondemand); polling_interval=50; uclamp format
  vendor ("0.00"/"max"); kbase 0/8/88. Semua UNAVAILABLE = Supported false,
  bukan error. Batas dari dokumentasi kernel (devfreq ABI, SCHED_
  CAPACITY_SCALE) atau relatif terhadap nilai live + set engine (3 param
  kbase, perlu uji tulis L2). 3 koreksi leader (uclamp manual early-return,
  kbase bergantung detector, JSON tanpa object wrapper). Bukti: harness K3
  48/48, suite lama 10/10, runtime ZIP sh -n OK + 0 blok if kosong.
  APP_PLAN K3 [x]. L2: validasi HP. STOP.
- APP-K3-FIX (2026-09-29, leader langsung, atas klarifikasi user): 2 bug
  diperbaiki. (1) hsin_gpu_kbase_knobs_apply baca $_profile bukan
  $_mk_profile -> nilai KOSONG ditulis ke node kbase saat dipanggil tanpa
  pemanggil; fix + guard profil tak dikenal. (2) BLOKIRER PRODUKSI: validasi
  nilai 3 kunci devfreq (polling_interval/up_threshold/down_differential)
  tersisip di _uk_class (klasifikasi key) bukan hsin_uk_val_ok -> knob-set
  DITOLAK di proses bersih, jadi 3 dari 12 knob K3 mati di HP; fix dipindah
  ke fungsi yang benar. Bukti red-green (kode lama vs baru tanpa $_profile:
  node kosong vs 0/4/72 benar) + uji proses bersih (3 kunci rc=0) +
  end-to-end dua proses (50->100 APPLIED). Harness K3 diperketat: fungsi
  _isolate() membatalkan semua variabel global engine per skenario
  (termasuk guard cache deteksi) TANPA menyentuh variabel konfigurasi
  (_uk_file, HSIN_SANDBOX_DIR) + 3 skenario regresi fungsi mandiri.
  Harness 48/48 -> 51/51; seluruh 11 suite regresi hijau. Scan pola serupa
  (poin c): 0 fungsi lain dengan pola salah-nama-variabel; 11 temuan
  scanner = false positive, diperiksa manual. KOREKSI LAPORAN K3:
  sched_child_runs_first ADA (live 0, writable) dan knob-nya berfungsi;
  yang absen hanya 3 sysctl latency. STOP.
- APP-A4 (2026-09-29, leader + dev-apk work/app-a4): TERIMA L1 + merge
  7606df3 ke main. Scaffold Kotlin+Compose satu modul: version catalog
  (AGP 8.6.0, Kotlin 2.0.20, plugin compose 2.0.20 = versi Kotlin sesuai
  dokumen resmi, BOM 2024.10.00, activity-compose 1.9.3, lifecycle 2.8.7,
  coroutines 1.8.1), applicationId com.hsin, minSdk 26/targetSdk 34,
  keystore debug sementara, manifest NOL permission + tanpa
  service/receiver/provider, tanpa .java/NDK/Navigation/serialization.
  Workflow build-apk manual tanpa step NDK. Koreksi leader d2a6b35:
  MainActivity pakai material3 TANPA dependensi (pasti gagal compile) ->
  tulis ulang foundation-only; hapus composeOptions ganda (plugin yang
  mengatur) + testInstrumentationRunner mati + compose-foundation
  (build CI #1 gagal Unresolved foundation, build CI #2 run 36537576407
  SUCCESS, APK 6.856.887 byte). Catatan proses: pekerja checkout cabang
  di repo utama (langgar AGENTS.md butir 7) -> leader kembalikan ke main
  setelah merge. APP_PLAN A4 [x]. L2: pasang + tes rasa di HP.
- APP-A5 (2026-09-29, leader rewrite penuh atas hasil dev-apk): TERIMA L1
  + merge a419b63. Token 11 warna + Shadow di ui/theme/Color.kt (SATU-SATUNYA
  tempat hex), Dimens (TouchMin 44/OutlineThick 1.5/ShadowOffset 3/Radius 4/
  Gap 8/Pad 16), Type (mono HANYA angka+log), Theme (darkColorScheme semua
  slot terisi, dark-only, tanpa dynamic color). 8 komponen + 8 @Preview:
  HCard (shadow keras Box hitam offset 3dp, tanpa elevation), HBadge
  (outline-only, enum HStatus 9 status), HButton (primer fill accent/sekunder
  outline), HSlider, HSelectRow, TopBar, BottomNav (4 tab state-based tanpa
  library nav), ScreenScaffold (bukan Scaffold M3 agar token tidak bocor).
  Dep: +material3 dari BOM. Bukti: 0 hex di luar Color.kt, 0
  MaterialTheme.colorScheme di komponen, 0 shadowElevation/gradient/blur,
  semua import terpetakan ke katalog. Koreksi leader: hasil dev-apk tidak
  bisa compile (import com.hsin.ui.theme.44.dp di 4 file, modifier
  chaining salah, signature ScreenScaffold tidak cocok, semua teks mono) ->
  leader menulis ulang 8 komponen + theme. APP_PLAN A5 [x]. L2: build CI.
- M3 (2026-09-29, leader): docs/APP_CONTRACT.md diperbarui post M1/M2.
  §3.9 batasan (Usage rc=0 + capabilities tak sandboxable), §3.10
  guard-status output nyata (aktif & tidak aktif), §3.11 knob-list mode
  manual (2 APPLIED + 31 SKIPPED, 33 key= terverifikasi hitungan),
  §4 inventaris knob post K1/K2/K3 (termasuk nomerges=2, preset
  readahead, rate_limit_us butuh governor schedutil), gap D1+D2 ditutup
  ("SUDAH PUTUS"), D3+D4 diperbarui. README (default profile manual),
  TROUBLESHOOTING (guard-status), TESTING (4 suite baru) dikoreksi.
  Bukti sandbox nyata diambil ulang, bukan dari ingatan. Commit 4e19506,
  CI lint 36576990605 success. APP_PLAN M3 [x].
- APP-A6 (2026-09-29): 2 ronde dev-apk + takeover leader (lihat NOTES).
  Merge 77ddff7, unit test 32 test (16+16) hijau lokal DAN CI.
  CI main: lint-and-test 36583327074 success, build-apk 36583327112
  success. APP_PLAN A6 [x]. L2: belum.
- Koreksi leader: 3 compile error ditemukan (ByteArrayOutputStream
  .outputStream(), private const val di class body, StringWriter(StringBuilder))
  - semuanya dari kode dev-apk yang belum pernah dikompilasi.
