# STATUS.md — HSIN Real-Time Progress Tracker (capability-first)

**Last Updated:** 2026-09-27 (PQ Step 12 DONE; Phase 3 SELESAI 4/4; STOP sebelum Phase 4 — tunggu approve user)
**Overall Progress:** Phase 1 DONE → Phase 2 DONE → Phase 3 DONE → Phase 4 MENUNGGU APPROVE

---

## 🎯 Master Progress

```
[███████████░░░░░░░░░] 55% (12/22 steps DONE, penomoran PQ)

PHASE 1: Testing Infrastructure (Steps 1-4)    [██████████] 100% — DONE
PHASE 2: Boot Guard & Safe Apply (Steps 5-8)   [██████████] 100% — DONE
PHASE 3: Capability Overrides (PQ Steps 9-12)  [██████████] 100% — DONE (STOP: Phase 4 tunggu approve user)
PHASE 3: Capability Overrides (Steps 9-12)     [░░░░░░░░░░] 0% — BLOCKED (wait Phase 2)
PHASE 4: Documentation (Steps 13-18)           [░░░░░░░░░░] 0% — BLOCKED (wait Phase 3)
PHASE 5: QA & Release (Steps 19-22)            [░░░░░░░░░░] 0% — BLOCKED (wait Phase 4)
```

---

## 📋 PHASE 1: Testing Infrastructure (Steps 1-4) — DONE

- [x] **Step 1** — `tests/` testing framework + template device report —
  DONE 2026-09-27, merge `7e41841` (Merge work/phase1-tests).
- [x] **Step 2** — `.github/workflows/lint-and-test.yml` (shellcheck
  `-S error`, sh -n, validasi JSON, cek file wajib, format module.prop) —
  DONE 2026-09-27, merge `7e41841` (fix CI `532ff87` di dalamnya).
- [x] **Step 3** — `tests/validate_build.sh` (positif VALID exit 0, negatif
  ERROR exit 1) — DONE 2026-09-27, merge `7e41841`.
- [x] **Step 4** — `core/detector.sh` comprehensive (SoC/GPU/CPU-policy/
  thermal-zone + cache `detected.conf`) — DONE 2026-09-27, commit
  `5b373ea` (`refactor: comprehensive device detection (Phase 1.2, Step 4)`).

### ⛔ Step 5 LAMA — DIREVERT, DIGANTI (bukan bagian antrean)

- `capability/device_overrides.json` keyed by NAMA CHIPSET
  (`unisoc_t615`, `snapdragon_888`, …) — commit `77b3a2b`
  (`feat: device-specific override profiles (Phase 1.2, Step 5)`).
- DIREVERT total via `36d2256`
  (`Revert "feat: device-specific override profiles (Phase 1.2, Step 5)"`,
  2026-09-27, 62 deletions, file hilang dari tree).
- Alasan: pola `DEVICE NAME → RANDOM TWEAK` melanggar prinsip
  capability-first (skill alpha-hsin-engineering). Diganti Step 9 baru:
  `capability/capability_overrides.json` keyed by capability signature.

---

## 📋 PHASE 2: Boot Guard & Safe Apply (Steps 5-8) — NEXT

- [x] **Step 5** — `core/boot_guard.sh` — DONE 2026-09-27, commit `5f3355c`
  (`feat: boot guard with fail-count auto-disable (Phase 2, Step 5)`).
  Threshold >= 2x (perintah user, override PRIORITY_QUEUE yang tulis 3x —
  perlu sinkronisasi susulan, di luar scope Step 5). Bukti L1: sh -n 2/2,
  shellcheck -S error 0, sandbox 10/10 (fresh→applied, 1x→belum aktif,
  2x→AKTIF+skip tuning, counter persisten ts:count, log AKTIF+alasan,
  boot-ok→reset, korup→sanitasi, threshold-env override), jalur logger
  terverifikasi (WARN masuk boot.log). CI push: API GitHub tak terjangkau
  dari Termux (2x coba) — status CI BELUM terkonfirmasi, jujur menunggu.
- [x] **Step 6 (dokumen)** — integrasi boot guard ke `service.sh` — DONE
  2026-09-27, commit `62ee738` (= STEP 7 versi perintah user; penomoran
  kini sinkron kembali). Check di seksi 1 SEBELUM tuning apa pun (bounded
  wait 120s ganti infinite loop; timeout = fail → skip SEMUA + exit 0);
  reset via `on_boot_ok` di seksi 11b setelah `.applied` + service-ready
  (selesai tanpa crash, bukan cuma start). NOL counter duplikat di
  service.sh (hanya panggil fungsi). Bukti L1: sh -n + shellcheck
  `-S error` 0, sandbox 8/8 (wiring statis baris 25/57/59/457 + emulasi
  skip-total/pulih).
- [x] **Step 7** — `core/safe_apply.sh` — DONE 2026-09-27, commit `6ea5619`
  (`feat: safe sysfs write gateway with 5 result categories` = "Step 6"
  versi perintah user). Gateway 5 kategori (APPLIED=0 / SKIPPED=2 /
  UNAVAILABLE=3 / FALLBACK=4 / FAILED=1), referensi `apply_tweak()` Alpha
  (common/engine.sh) TANPA chmod paksa (read-only = SKIPPED beralasan).
  Write+verify inti REUSE `hsin_node_write_verify()` existing
  (core/sysfs.sh, tanpa duplikasi). Bukti L1: sh -n + shellcheck
  `-S error` 0, sandbox 11/11 (hilang/read-only/ditolak/ngawur
  ±alternatif/sukses/log/counter/engine-palsu/logger).
- [x] **Step 8** — migrasi 1 engine sebagai bukti pola — DONE 2026-09-27,
  commit `6ea5619` (sama). Dipilih `engine/io/readahead.sh` (risiko
  terkecil: 71 baris, 1 write site, non-kritis) BUKAN engine/cpu
  (backup/restore path = risiko lebih tinggi; cpu menyusul setelah pola
  approved). A/B tanpa override IDENTIK (512=512). Plus 1 baris
  build_release.sh: safe_apply.sh + boot_guard.sh masuk daftar runtime
  (tanpanya hilang di ZIP release — kelas bug scan_cache dulu; boot_guard
  ikut diperbaiki karena celah yang sama dari Step 5).

---

## 📋 PHASE 3: Capability-Driven Overrides & Thermal Safety (Steps 9-12) — BLOCKED

- [x] **Step 9** — `capability/capability_overrides.json` + `core/load_overrides.sh`
  — DONE 2026-09-27, commit `b79763d` (= STEP 9 versi perintah user).
  JSON keyed by capability signature (3 signatures + default_fallback),
  NOL nama chipset/vendor (grep = 0), valid via `json.tool`. Match fields
  HANYA dari output detector.sh yang beneran ada (device.txt:
  CPU_POLICIES/GOVS/THERMAL + cek devfreq-writable live); SOC/VENDOR/GPU
  tidak pernah dibaca; detector.sh UTUH (git status bersih).
  Loader: match pertama menang → export hints; no-match/cacat/hilang →
  default_fallback + log WAJIB "no signature match, using default
  fallback"; TIDAK PERNAH tulis sysfs (statis + checksum runtime).
  Hints logis (persen + gov preference + thermal_class), mapping OPP di
  apply layer. Bukti L1: sh -n + shellcheck `-S error` 0, sandbox 9/9
  (match/no-match+log/cacat/hilang+log/no-write/detector-utuh).
  Plus 1 baris build_release.sh: load_overrides.sh masuk daftar runtime.
- [x] **Step 10** — `core/thermal_check.sh` — thermal guardrail
  (NORMAL/HIGH/VERY HIGH/CRITICAL + UNKNOWN) di atas THERMAL/THERMAL_PATH/
  zone detector.sh; threshold dari trip_point kernel terdeteksi (relatif
  device, fallback konservatif tercatat; NOL nama vendor/chipset); hanya
  CRITICAL intervensi via hsin_safe_apply (scaling_max_freq->min, kategori
  APPLIED terverifikasi + node benar turun); HIGH/VERY HIGH log-only;
  hilang -> UNKNOWN rc=4 no-crash; return (bukan exit) agar service.sh
  tidak mati; integrasi service.sh pasca-boot-guard. Bukti L1: sh -n +
  shellcheck `-S error` 0, sandbox 6/6 lewat jalur file asli (NORMAL utuh,
  HIGH/VERY HIGH utuh+log, CRITICAL APPLIED+rc3, relativitas 85C beda
  device, UNKNOWN).   Revisi `546f9a5` (2026-09-27, perbaiki test
  tautologi + bug rc/exit/duplikat). CI lint-and-test success.
  `detected.conf` + writability live, pilih entry cocok, fallback
  `default` + log bila tidak cocok.
- [ ] **Step 11** — `core/thermal_check.sh` — threshold NORMAL / HIGH /
  VERY HIGH / CRITICAL dari thermal_zone TERDETEKSI. Tanpa zone →
  no-op + log (bukan crash, bukan throttle buta).
- [x] **PQ Step 12** — graceful degradation formal (`core/engine_guard.sh`
  + wiring `service.sh`) — DONE 2026-09-27. Wrapper `hsin_engine_run`
  (snapshot counter safe_apply -> panggil langsung -> delta per-engine;
  APPLIED+FALLBACK=applied, FAILED=failed, SKIPPED+UNAVAIL=skipped;
  rc 0 bila applied>0 else 1; kategori lama tanpa kategori baru).
  6 engine service.sh via wrapper (gagal -> WARN lanjut, tidak abort) +
  `hsin_engine_summary` di status report + runtime list. Bukti L1: sh -n +
  shellcheck `-S error` 0 (sweep semua .sh), sandbox 8/8 kondisi nyata
  (tanpa preset counter: 1 gagal lanjut, semua gagal sampai END, partial
  1 engine rc=0, FALLBACK applied, skip beralasan, wiring).

---

## 📋 PHASE 4: Documentation (Steps 13-18) — BLOCKED

- [x] **PQ Step 13** — README.md — DONE 2026-09-27. Quick start,
  requirements, profil, safety features (boot guard, safe apply,
  thermal guardrail, degradasi per-engine), 1 device tervalidasi +
  lainnya graceful degrade eksplisit (tanpa matriks chipset), log
  locations, status boot guard, uninstall, support.
- [x] **PQ Step 14** — TESTING.md — DONE 2026-09-27. Prosedur
  baseline→install→functional→stability→cleanup; functional mencakup
  guard on/off, 5 kategori safe apply, thermal 4 state, degradasi
  per-engine; stability wajib reboot 3x di HP fisik; template laporan
  berbasis capability (tanpa matriks nama chipset).
- [x] **PQ Step 15** — TROUBLESHOOTING.md — DONE 2026-09-27. 6 item
  (slow boot, guard aktif + cek/baca/reset, thermal UNKNOWN vs
  CRITICAL, GPU skip = fallback disengaja, rollback/restore,
  summary degraded); semua perintah + string log diverifikasi silang
  ke kode (1 koreksi: CLI `restore` bukan `rollback`).
- [x] **PQ Step 16** — DEVICE_COMPATIBILITY.md — DONE 2026-09-27.
  Tabel TERVALIDASI (1 device + bukti jujur: report L2 menyusul,
  dir report masih kosong) vs GRACEFUL DEGRADE (mekanisme fallback,
  tanpa daftar chipset); tanpa klaim %/optimis (hanya yang tertelusur
  ke kode).
- [x] **PQ Step 17** — API.md — DONE 2026-09-27. Panduan modder:
  tambah tweak (pola safe_apply, tanpa echo mentah), tambah signature
  (4 kunci match capability, larang keyed-chipset), extend detection
  (prefix + sandbox dulu), Safety Warning (no-raise, no-bypass guard,
  daftar runtime); 24 fungsi + 7 env var terverifikasi ke kode.
- [x] **PQ Step 18** — CHANGELOG.md — DONE 2026-09-27. Format Keep a
  Changelog, section `## [Unreleased]` (bukan rilis resmi; version
  bump menunggu Phase 5): Added/Changed/Fixed/Reverted
  capability-first Step 1–18; `module.prop` tidak tersentuh.

---

## 📋 PHASE 5: QA & Release (Steps 19-22) — BLOCKED

- [x] **PQ Step 19** — QA_CHECKLIST.md — DONE 2026-09-27. Checklist
  berverifikasi (code/build/device/stability/edge/uninstall +
  anti-klaim-publik); status 1 device eksplisit + item device kedua
  BELUM (blocker multi-device); stability dinyatakan device-spesifik.
- [x] **PQ Step 20** — RELEASE_NOTES.md — DONE 2026-09-27. Draft
  dengan baris status BELUM DIRILIS di paling atas; fitur Phase 2–3
  + keterbatasan jujur (1 device, butuh L2 + device kedua); tanpa
  kata stable/production-ready; pesan commit dikoreksi tanpa versi
  (aturan Step 18).
- [x] **PQ Step 21** — SUPPORT_POLICY.md — DONE 2026-09-27. SLA
  best-effort tanpa angka; kanal hanya GitHub Issues repo privat
  (terverifikasi, tanpa karangan); kompatibilitas rujuk Step 16;
  section TIDAK didukung (extreme, device lain, mod bypass) +
  cara melapor.
- [ ] **Step 22** — final status update + GATE RILIS: versionCode baru HANYA
  bila Phase 2-3 selesai DAN tervalidasi di HP nyata (L2). Tanpa L2 = tanpa
  rilis stabil.

---

## 📋 PHASE 5+: Tambahan di luar 22 step (PQ Step 23)

- [x] **PQ Step 23** — visibilitas hasil knob — DONE 2026-09-27.
  Recorder `hsin_uk_result` + reset per siklus di `user_knobs.sh`
  (sudah di-bundle, tanpa file runtime baru); 1-baris record di
  titik keputusan 7 engine (dipakai/snap/ditolak/profil, kategori
  safe_apply saja); `knob-list` = baris key=value + JSON lama
  terakhir (APK aman); sandbox 9/9 file asli; README +
  TROUBLESHOOTING didokumentasikan.

---

## 🔭 Known Follow-ups (bukan blocker rilis)

- PQ Step 11 FOLLOW-UP: threshold thermal boleh di-override via capability
  entry `thermal_class: managed` (bukan via nama device). Status: BELUM
  dikerjakan — implementasi aktual pakai max `trip_point_*_temp` kernel
  semua zona + fallback konservatif tercatat di
  `HSIN_THERMAL_CHECK_BASIS`. Bukan blocker Phase 3.

---

## 🚦 GATE RILIS (PQ Step 22 — evaluasi 2026-09-27, TANPA bump versi)

Spec gate (`PRIORITY_QUEUE.md` Step 22): 22/22 steps + L2 HP nyata PASS
(boot guard path + safe apply + signature match, bukti log HP) +
sandbox capability-hilang PASS → BARU BOLEH bump `version`/
`versionCode`. Evaluasi per syarat (bukti konkret):

1. Phase 2–3 selesai — **SUDAH**. STATUS ([x] Steps 5–8, PQ 9–12) +
   commit `5f3355c`, `62ee738`, `6ea5619`, `b79763d`, `2a56064`/
   `546f9a5`, `912b3bf`, `7ae4573`.
2. L2 HP nyata (log HP, bukan klaim) — **BELUM**.
   `tests/device_reports/` masih kosong kecuali `.gitkeep`
   (terverifikasi `ls -la`); QA_CHECKLIST 0/25 `[x]`.
3. Sandbox capability-hilang PASS — **SUDAH**
   (`sandbox_degrade.sh` 8/8, `thermal_sandbox` UNKNOWN no-crash,
   `sandbox_overrides.sh` fallback + log).
4. Blocker tercatat — device kedua BELUM; profil `extreme` belum
   pernah jalan di HP fisik sama sekali (KETERBATASAN KERAS).

**GATE RILIS: BELUM LOLOS.** `module.prop` tetap `v5.0.0-beta1` /
`versionCode=5001`, tidak disentuh. Pesan commit spec Step 22
("(gate passed)") TIDAK dipakai — gate tidak lolos.

Langkah berikutnya yang konkret:

1. Jalankan `TESTING.md` tahap 1–5 di HP fisik (baseline → install →
   functional → stability 3x reboot → cleanup).
2. Isi report L2 pertama di `tests/device_reports/` (template
   capability, bukan nama chipset).
3. Centang `QA_CHECKLIST.md` dengan HASIL (angka/log), bukan klaim.
4. Setelah 1–3 hijau di device developer + device kedua ada →
   evaluasi ulang gate ini.

---

## ✅ Fixed Issues (dulu Known Issues — sudah diperbaiki)

- `core/thermal_check.sh` hilang dari bundle rilis — DITEMUKAN +
  DIFIX 2026-09-27 (leader, saat verifikasi PQ Step 12; commit
  `ee5f85b`, 1 baris daftar runtime `build_release.sh`). Sejak Step 10
  file tidak ada di daftar bundle → di ZIP rilis source-nya di-rewrite
  jadi `core/runtime.sh` sehingga guard thermal diam-diam tidak jalan
  (tanpa crash). Bukti red-green dari build `release` sungguhan di
  salinan repo: pra-fix 0 marker thermal di `core/runtime.sh` rilis;
  pasca-fix 19 marker + `service.sh` ZIP me-source runtime +
  `runtime.sh` rilis di-source di sandbox → CRITICAL + intervensi via
  safe_apply jalan (maxfreq 1800000→300000, rc=3). Audit gap bundle:
  27 `core/*.sh` vs daftar — satu-satunya gap lain
  `core/_bootstrap.sh` (tidak di-source siapa pun = benign, tidak
  dibundle).

- `core/scan_cache.sh:47` (guard prefix) — FIXED 2026-09-27, commit
  `000c83a` (= STEP 8 versi perintah user). Keenam prefix sysfs
  (CPU/THERMAL/DEVFREQ/GPU/BLOCK/PROC) kini pakai guard `[ -n ... ] ||`
  (pola scheduler.sh:13 + Step 4); di device vars unset → default identik,
  perilaku sama persis. Bukti L1: sh -n + shellcheck `-S error` 0,
  `tests/sandbox_scan_prefix.sh` 5/5 (prefix selamat pasca-source
  scan_cache + scheduler, discovery IO murni prefix palsu sda+sdb tanpa
  seed manual, tanpa bocor /sys/block, default tetap /sys/block),
  regresi hijau semua (safe_apply 11/11, boot_guard 10/10,
  service_guard 8/8). Item ini Keluar dari antrean Known Issues —
  `engine/io/` aman dikerjakan lagi.

---

## 📊 Summary Stats (konsisten dengan checkbox di atas — hitung ulang tiap update)

| Metric | Value |
|---|---|
| **Total Steps** | 22 |
| **Completed** | 8 (Steps 1-8 dokumen; penomoran user↔dokumen sinkron kembali) |
| **Next** | STEP 8 (fix Known Issue scan_cache:47), lalu Phase 3 butuh approve |
| **Reverted** | 1 (Step 5 lama, `36d2256`) |
| **Pending** | 14 (Steps 9-22) |
| **Expected Commits** | ~18 (1 per step, tanpa force push) |

---

## 🔄 Update Instructions

**After each step completion:**

1. Update checkbox step (tandai done bila selesai, pending bila belum).
2. Tulis tanggal + hash commit asli (dari `git log`, jangan dikarang).
3. Update Master Progress bar + Summary Stats di atas (WAJIB sama dengan
   hitungan checkbox — bug lama: progress 0% padahal task sudah checklist).
4. Pastikan nomor step sama di PLAN.md, STATUS.md, PRIORITY_QUEUE.md,
   ROADMAP_10_10.md. Bila beda, update file yang tertinggal.

---

## 🚦 Phase Transition Rules

- ✅ **Phase 1 → Phase 2:** Steps 1-4 DONE (terpenuhi 2026-09-27).
- ✅ **Phase 2 → Phase 3:** Steps 5-8 DONE + CI hijau.
- ✅ **Phase 3 → Phase 4:** Steps 9-12 DONE + sandbox capability-hilang PASS.
- ✅ **Phase 4 → Phase 5:** Steps 13-18 DONE.
- ✅ **Phase 5 → RELEASE:** Steps 19-22 DONE + L2 HP nyata PASS + gate
  versionCode lolos (Phase 2-3 tervalidasi HP).

---

## 🎯 Success Criteria (Final Release = definisi 10/10 baru)

- [ ] Capability detection akurat (signature cocok di device tervalidasi).
- [ ] Boot guard + safe apply terbukti jalan (sandbox + HP nyata).
- [ ] Tervalidasi nyata di minimal 1 device fisik (Unisoc/Mali user).
- [ ] Graceful degrade terbukti di kondisi capability hilang (sandbox test).
- [ ] ShellCheck 0 errors, sh -n 0 errors, JSON valid semua.
- [ ] Klaim device jujur: "tervalidasi" vs "graceful degrade".

---

**Next Step:** STEP 9 (PQ Step 9) — `capability/capability_overrides.json` keyed by capability signature — STOP, TUNGGU APPROVE USER. Jangan mulai sebelum approve.
