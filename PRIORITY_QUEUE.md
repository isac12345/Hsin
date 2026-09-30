# PRIORITY_QUEUE.md — Step-by-Step AI Execution Queue (capability-first)

**Read this file** when executing next step. Each step is **atomic** and **independent**.

**Current Status:** Phase 1-4 DONE (Steps 1-21) + Step 23 DONE → Phase 5 tersisa Step 22 GATE RILIS (tunggu L2 HP nyata)
**Total Steps:** 22 (realign 2026-09-27: antrean lama 31 step dirombak —
Step 5 lama device-name-keyed DIREVERT, thermal JSON angka-tetap diganti
thermal_check.sh, migrasi 7 engine diringkas jadi 1 bukti pola, bump
version dipindah ke gate rilis Step 22)
**Format:** `## STEP [N] — [TITLE]`

**Aturan global tiap step:** capability-first (NOL key nama chipset),
write → read-back → verify (hasil APPLIED/SKIPPED/FALLBACK/FAILED),
node hilang = skip + log (bukan crash), shellcheck 0 + sh -n lolos + CI hijau.

---

## ⏸️ CURRENT PHASE

```
✅ PHASE 1: Testing Infrastructure (Steps 1-4) — DONE
✅ PHASE 2: Boot Guard & Safe Apply (Steps 5-8) — DONE
✅ PHASE 3: Capability Overrides (Steps 9-12) — DONE
✅ PHASE 4: Documentation (Steps 13-18) — DONE
⏳ PHASE 5: QA & Release (Steps 19-21 DONE, Step 22 GATE BELUM LOLOS — tunggu L2 HP)
```

---

# 🚀 EXECUTION QUEUE

## STEP 1: Create Testing Infrastructure (DONE)
**Status:** ✅ COMPLETE (merge 7e41841, 2026-09-27)
**No action needed — move to Step 5**

---

## STEP 2: Create lint-and-test CI (DONE)
**Status:** ✅ COMPLETE (merge 7e41841, 2026-09-27)
**No action needed — move to Step 5**

---

## STEP 3: Create validate_build.sh (DONE)
**Status:** ✅ COMPLETE (merge 7e41841, 2026-09-27)
**No action needed — move to Step 5**

---

## STEP 4: Enhance core/detector.sh — Comprehensive Detection (DONE)
**Status:** ✅ COMPLETE (commit 5b373ea, 2026-09-27)
**No action needed — move to Step 5**

---

## ⛔ STEP 5 LAMA — DIREVERT (JANGAN DIKERJAKAN ULANG)

`capability/device_overrides.json` keyed by nama chipset (`77b3a2b`)
direvert total via `36d2256` (2026-09-27). Alasan: pola
`DEVICE NAME → RANDOM TWEAK` melanggar capability-first. Pengganti resmi:
**STEP 9** (`capability/capability_overrides.json`, keyed by capability
signature). Siapa pun yang mengusulkan JSON keyed by nama chipset lagi
wajib membaca histori ini + PLAN.md dulu.

---

## STEP 5: Create core/boot_guard.sh — Boot Guard (DONE)
**Status:** ✅ COMPLETE (commit 5f3355c, 2026-09-27)
**No action needed — spec di bawah arsip historis.**

**Objective:**
Implement boot guard mechanism that tracks boot failures and auto-disables
tuning after consecutive failures. Reference pattern: `service.sh` repo
isac12345/Alpha (fail count + auto-disable + clear log when guard fires).

**Files to create:**
- `core/boot_guard.sh`

**Requirements:**
- [ ] Create `hsin_boot_guard_init()` function
  - Create `$HSIN_DATA/.boot_guard_state` file on first call
  - Format: `timestamp:count`
- [ ] Create `hsin_boot_guard_check()` function
  - Read current failure count
  - If count >= 2 and within 24h → return 1 (guard active, skip tuning)
  - If 24h elapsed → reset counter, return 0
  - Return 0 if count < 3
- [ ] Create `hsin_boot_guard_increment()` function
  - Increment failure counter + write timestamp
  - Log failure with reason
- [ ] Create `hsin_boot_guard_reset()` function
  - Clear state file; called on successful boot
- [ ] Log JELAS kapan guard aktif ("Boot guard ACTIVE: tuning skipped,
  N failures in 24h") — user harus tahu dari log, bukan menebak

**Acceptance Criteria:**
- [ ] All 4 functions work (sandbox: 2x increment → check returns 1;
  reset → check returns 0; stale timestamp >24h → auto-reset)
- [ ] State file created/tracked correctly
- [ ] ShellCheck: 0 errors, sh -n: passes, CI lint-and-test passes

**Expected Output:**
```bash
$ cat /data/adb/hsin/.boot_fail_count
1758976800:1
$ hsin_boot_guard_check; echo $?   # 0 (masih di bawah threshold 2)
```

**Commit Message:**
```
feat: boot guard with fail-count auto-disable (Phase 2, Step 5)

- Track boot failures with timestamp (format timestamp:count)
- Auto-disable tuning after >= 2x consecutive failures (Alpha-proven)
- Clear log line when guard fires; reset on successful boot
- Reference pattern: service.sh repo isac12345/Alpha
- ShellCheck: 0 errors, sh -n: pass
```

**Go/No-Go Checklist:**
- [ ] All functions created
- [ ] Sandbox red-green (fail-path + reset-path) PASS
- [ ] ShellCheck passes, CI passes
- [ ] No code outside core/boot_guard.sh touched

**Estimated Effort:** 2 hours
**Difficulty:** Medium

---

## STEP 6: Integrate boot_guard.sh into service.sh (DONE)
**Status:** ✅ COMPLETE (commit 62ee738, 2026-09-27)
**No action needed — spec di bawah arsip historis.**

**Objective:**
Call boot guard at service.sh startup. If guard is active, skip all tuning
and exit cleanly (return 0 path, bukan error boot).

**Files to modify:**
- `service.sh`

**Requirements:**
- [ ] At start of service.sh, source `core/boot_guard.sh`
- [ ] Call `hsin_boot_guard_check()`
- [ ] If returns 1 (guard active):
  - Log: "Boot guard ACTIVE: module tuning skipped"
  - Exit 0 (no error, but skip everything)
- [ ] If returns 0 (safe to proceed):
  - Continue with normal boot sequence
  - Call `hsin_boot_guard_reset()` after successful boot

**Acceptance Criteria:**
- [ ] Guard integrated; guard-active path skips tuning + exit 0
- [ ] Normal path unchanged (regression: boot sukses → reset terpanggil)
- [ ] Logging works; CI passes

**Commit Message:**
```
refactor: integrate boot guard into service (Phase 2, Step 6)

- Source core/boot_guard.sh at startup
- Check guard before proceeding with tuning
- Exit cleanly (0) if guard is active
- Reset guard on successful boot
```

**Go/No-Go Checklist:**
- [ ] boot_guard sourced, check before tuning
- [ ] Both paths (active/inactive) sandbox-tested
- [ ] Exit codes correct, CI passes

**Estimated Effort:** 1 hour
**Difficulty:** Easy

---

## STEP 7: Create core/safe_apply.sh — Safe Write with Verify (DONE)
**Status:** ✅ COMPLETE (commit 6ea5619, 2026-09-27)
**No action needed — spec di bawah arsip historis.**

**Objective:**
Single choke point for ALL sysfs/proc writes: check node exist + writable,
write, read-back, verify, categorize result. Reference: `apply_tweak()`
repo isac12345/Alpha. NO claim of success without verify.

**Files to create:**
- `core/safe_apply.sh`

**Requirements:**
- [ ] Create `hsin_node_write_verify(path, value, category)` function
  - Node tidak ada → return 2 + log `SKIPPED (node missing)`
  - Node ada tapi tidak writable → return 2 + log `SKIPPED (read-only)`
  - Write → read-back → cocok → return 0 + log `APPLIED`
  - Write → read-back → beda → return 1 + log `FAILED (mismatch)`
  - JANGAN `chmod` node untuk memaksa writable (baca skill: node
    read-only = skip, bukan paksa)
- [ ] Result categories used EVERYWHERE downstream:
  `APPLIED / SKIPPED / FALLBACK / FAILED` (FALLBACK dicatat pemanggil
  saat pakai nilai pengganti)
- [ ] Counters per apply session: `_ok` / `_skip` / `_fail` + 1 baris
  ringkasan ke log

**Acceptance Criteria:**
- [ ] Sandbox sysfs palsu 4 kasus: tulis-ok → APPLIED; node hilang →
  SKIPPED; read-only → SKIPPED; read-back beda → FAILED
- [ ] Tanpa verify tidak ada klaim sukses di output mana pun
- [ ] ShellCheck: 0 errors, sh -n: passes, CI passes

**Commit Message:**
```
feat: safe sysfs write with read-back verify (Phase 2, Step 7)

- hsin_node_write_verify(): exist+writable check, write, read-back
- Result categories APPLIED/SKIPPED/FALLBACK/FAILED, no fake success
- Session counters + 1-line summary to log
- Reference: apply_tweak() repo isac12345/Alpha
- ShellCheck: 0 errors, sh -n: pass
```

**Go/No-Go Checklist:**
- [ ] 4-case sandbox matrix PASS
- [ ] No chmod-force path
- [ ] ShellCheck passes, CI passes

**Estimated Effort:** 2 hours
**Difficulty:** Medium

---

## STEP 8: Migrate engine/cpu to safe_apply.sh (proof of pattern) (DONE)
**Status:** ✅ COMPLETE (commit 6ea5619, 2026-09-27 — bukti pola = `engine/io/readahead.sh`, risiko terkecil, bukan engine/cpu)
**No action needed — spec di bawah arsip historis.**

**Objective:**
Migrate MINIMAL ONE engine (`engine/cpu`) to `safe_apply.sh` as proof the
pattern is used. Other engines follow only after this pattern proves clean.

**Files to modify:**
- Engine CPU apply path (`engine/cpu/*.sh` yang menulis node)

**Requirements:**
- [ ] Every direct `echo "$v" > "$node"` in CPU path → via
  `hsin_node_write_verify()` with category `CPU_*`
- [ ] Governor pick: pilih dari `scaling_available_governors` live
  (fallback berurutan + log FALLBACK bila preferensi utama tak ada)
- [ ] Frequency target: snap ke OPP/available_frequencies terdekat
  (≤ target), bukan `max * persen` mentah
- [ ] TANPA override aktif: hasil apply IDENTIK vs sebelum migrasi
  (A/B diff node kosong — regresi nihil)

**Acceptance Criteria:**
- [ ] All CPU writes go through verify helper
- [ ] A/B no-override sandbox: identical results pre/post migration
- [ ] APPLIED/SKIPPED/FAILED visible in log; CI passes

**Commit Message:**
```
refactor: migrate engine/cpu to safe_apply (Phase 2, Step 8)

- All CPU node writes via hsin_node_write_verify()
- Governor pick from live available_governors + FALLBACK log
- Frequency snapped to nearest valid OPP (no raw max*percent)
- A/B no-override: identical results (zero regression)
```

**Go/No-Go Checklist:**
- [ ] Writes replaced, logging shows categories
- [ ] A/B identical, ShellCheck passes, CI passes

**Estimated Effort:** 1-2 hours
**Difficulty:** Easy-Medium

---

## PHASE 2 COMPLETE ✅

After **STEP 8**, Phase 2 is complete.
Next: Phase 3 (Capability-Driven Overrides)

---

## STEP 9: Create capability/capability_overrides.json (capability-signature-keyed) (DONE)
**Status:** ✅ COMPLETE (commit b79763d, 2026-09-27 — JSON + loader `core/load_overrides.sh`)
**No action needed — spec di bawah arsip historis.**

**Objective:**
Per-capability tuning defaults keyed by CAPABILITY SIGNATURE — NEVER by
chipset name. This REPLACES the reverted Step 5 lama. Devices matching no
signature → `default` entry (safe fallback), never total skip, never
unvalidated override.

**Files to create:**
- `capability/capability_overrides.json`

**Signature format (canonical, computed by Step 10):**
```
cpu{1|2+} _ gpu{devfreq|kgsl|none} _ thermal{0|1|2+}
```
Examples: `cpu2+_gpu-devfreq_thermal2+`, `cpu1_gpu-none_thermal0`, `default`.

**Content Structure:**
```json
{
  "version": 1,
  "signatures": {
    "cpu2+_gpu-devfreq_thermal2+": {
      "description": "Multi-policy CPU + writable GPU devfreq + 2+ thermal zones",
      "cpu_gov_preference": ["schedutil", "powersave"],
      "gpu_max_percent": {"battery": 60, "balanced": 85, "performance": 100},
      "thermal_class": "managed"
    },
    "cpu1_gpu-none_thermal0": {
      "description": "Minimal capability — light touch only",
      "cpu_gov_preference": ["schedutil"],
      "gpu_max_percent": {"battery": 60, "balanced": 70, "performance": 85},
      "thermal_class": "unmanaged"
    },
    "default": {
      "description": "Safe fallback for unmatched signatures",
      "cpu_gov_preference": ["schedutil"],
      "gpu_max_percent": {"battery": 60, "balanced": 70, "performance": 85},
      "thermal_class": "unmanaged"
    }
  }
}
```

**Requirements:**
- [ ] Valid JSON (`python3 -m json.tool` passes)
- [ ] NOL key nama chipset (`unisoc|snapdragon|dimensity|exynos` grep = 0)
- [ ] Minimal 2 signature entries + 1 `default` entry
- [ ] Tiap entry: gov preference + gpu_max_percent (battery/balanced/
  performance) + thermal_class (managed/unmanaged)
- [ ] Nilai persen = intent logis (mapping ke OPP di engine, bukan frekuensi
  mentah)

**Acceptance Criteria:**
- [ ] File created, JSON valid, zero chipset-name keys
- [ ] `default` entry present; CI passes

**Commit Message:**
```
feat: capability-signature-keyed overrides (Phase 3, Step 9)

- Keyed by capability signature (cpu/gpu/thermal classes), NOT chipset names
- Replaces reverted device-name-keyed Step 5 lama (36d2256)
- Includes safe 'default' fallback for unmatched devices
- Percents are logical intent (OPP mapping happens in engine)
```

**Go/No-Go Checklist:**
- [ ] JSON valid, chipset-name grep = 0
- [ ] default present, CI passes, no code changes

**Estimated Effort:** 1 hour
**Difficulty:** Easy

---

## STEP 10: Create core/load_overrides.sh — Signature Match + Fallback (DONE, dieksekusi sebagai thermal guardrail)
**Status:** ✅ COMPLETE (commit 2a56064 + revisi 546f9a5, 2026-09-27 — loader ikut Step 9 `b79763d`; slot Step 10 dipakai `core/thermal_check.sh`)
**No action needed — spec di bawah arsip historis.**

**Objective:**
Compute device capability signature from `detected.conf` + live writability
checks, select matching entry from `capability_overrides.json`, fall back
to `default` with logged reason when nothing matches.

**Files to create:**
- `core/load_overrides.sh`

**Requirements:**
- [ ] Create `hsin_signature_compute()` function
  - cpu class: hitung policy dari `detected.conf` (`1` vs `2+`)
  - gpu class: `devfreq` bila node GPU writable ditemukan, `kgsl` bila
    node kgsl writable, selain itu `none` (cek live `[ -w ]`, bukan asumsi)
  - thermal class: hitung thermal zone (`0` / `1` / `2+`)
  - Output: string kanonis `cpuX_gpuY_thermalZ`
- [ ] Create `hsin_override_load()` function
  - Parse JSON entry sesuai signature (tanpa jq bila tidak ada di
    recovery shell — pakai awk/sed pola sederhana + fallback aman)
  - Signature tak cocok → pakai `default` + log
    `FALLBACK (signature <sig> unmatched → default)`
  - Export variabel override untuk engine
- [ ] Distinguish in log: APPLIED (entry cocok) vs FALLBACK (default)

**Acceptance Criteria:**
- [ ] Sandbox 3 kasus: signature cocok → entry dipakai; signature asing →
  default + FALLBACK log; detected.conf hilang → default + log
- [ ] ShellCheck: 0 errors, CI passes

**Commit Message:**
```
feat: capability signature match + default fallback (Phase 3, Step 10)

- Compute canonical signature from detected.conf + live writability
- Match capability_overrides.json entry, FALLBACK to default + log
- APPLIED vs FALLBACK clearly distinguished in log
```

**Go/No-Go Checklist:**
- [ ] 3-case sandbox PASS, ShellCheck passes, CI passes

**Estimated Effort:** 2 hours
**Difficulty:** Medium

---

## STEP 11: Create core/thermal_check.sh — Zone-Based Thermal Classes (DONE)
**Status:** ✅ COMPLETE (harmonisasi spec 912b3bf, 2026-09-27 — implementasi = Step 10; cap-only `cf20708`)
**No action needed — spec di bawah arsip historis (checkbox [x] di dalam = terverifikasi, sisanya tertutup fix cap-only).**

**Objective:**
Thermal classification NORMAL / HIGH / VERY HIGH / CRITICAL derived from
DETECTED thermal zone data — NOT fixed numbers per chipset. No zones →
thermal features degrade to no-op + log (never crash, never blind throttle).

**Files to create:**
- `core/thermal_check.sh`

**Requirements:**
- [x] Klasifikasi via fungsi internal `_read_thermal_max()` +
  `_read_thermal_basis()` + `_classify_thermal()` di
  `core/thermal_check.sh` — file di-source LANGSUNG (panggil langsung
  lalu baca global `HSIN_THERMAL_CHECK_STATE` / `THERMAL_MAX_TEMP` /
  `HSIN_THERMAL_CHECK_RC` — JANGAN dalam `$( )`; fix dari bug #7 yang
  ditemukan saat testing: subshell menghilangkan assignment global)
  - Baca suhu live dari semua thermal zone terdeteksi, ambil max
  - Klasifikasi: NORMAL (full profile) / HIGH (monitor) /
    VERY HIGH (monitor + limited intervention bila beralasan) /
    CRITICAL (emergency intervention, satu-satunya yang boleh
    intervensi via `hsin_safe_apply`)
  - Threshold dari max `trip_point_*_temp` kernel semua zona yang
    terdeteksi (basis device-specific, bukan tuning per-chipset);
    tanpa trip data → fallback konservatif + TERCATAT di
    `HSIN_THERMAL_CHECK_BASIS`
  - FOLLOW-UP (belum dikerjakan, bukan blocker): threshold boleh
    di-override via capability entry `thermal_class: managed`
    (bukan via nama device) — lihat STATUS.md "Known Follow-ups"
- [x] Zona tidak ada → return UNKNOWN + log unmanaged (tidak block tuning,
  tapi tidak diam-diam klaim NORMAL) — fitur thermal jadi no-op yang jujur
- [ ] Thermal TIDAK BOLEH menaikkan limit di atas profil/override user
  (hanya boleh menahan — pelajaran bug policy.sh: thermal menaikkan =
  membatalkan cap profil)

**Acceptance Criteria:**
- [x] Sandbox: tiap kelas terpicu pada rentang yang benar; tanpa zone →
  UNKNOWN + log unmanaged; panggilan langsung (bukan subshell) STATE benar
- [ ] Tidak ada penulisan yang menaikkan limit profil; CI passes

**Commit Message:**
```
feat: zone-based thermal classification (Phase 3, Step 11)

- NORMAL/HIGH/VERY HIGH/CRITICAL from detected thermal zones
- No zones → honest no-op + log (no crash, no blind throttle)
- Thermal never raises profile/user caps (cap-only)
- Direct call + global read (no subshell state loss)
```

**Go/No-Go Checklist:**
- [ ] Classification matrix PASS, no-zone case PASS
- [ ] Cap-only verified, ShellCheck passes, CI passes

**Estimated Effort:** 2 hours
**Difficulty:** Medium

---

## STEP 12: Formalize Graceful Degradation (engine fail != module fail) (DONE)
**Status:** ✅ COMPLETE (commit 7ae4573, 2026-09-27 — `core/engine_guard.sh` + wiring service.sh)
**No action needed — spec di bawah arsip historis.**

**Objective:**
Make graceful degradation explicit contract: per-engine applied/failed
counters, partial success = return 0, service continues to next engine.

**Files to modify:**
- Engine apply paths migrated so far + `service.sh` engine-call logic

**Requirements:**
- [ ] Each migrated engine tracks `applied_count` / `failed_count`
  (dari counter safe_apply Step 7)
- [ ] Return 0 bila `applied_count > 0` (partial success OK);
  return 1 hanya bila nol applied
- [ ] `service.sh`: engine return 1 → log warning, lanjut engine berikut
  (module tidak abort)
- [ ] Tiap skip mencantumkan ALASAN (node missing / read-only / mismatch /
  signature fallback) — skip diam-diam = bug

**Acceptance Criteria:**
- [ ] Sandbox: 1 engine total-gagal → module tetap jalan + warning;
  partial → return 0 + counts di log
- [ ] CI passes

**Commit Message:**
```
refactor: graceful degradation contract per engine (Phase 3, Step 12)

- applied/failed counters per engine; partial success = return 0
- service.sh continues on engine failure (module never aborts)
- Every skip carries a reason (no silent skips)
```

**Go/No-Go Checklist:**
- [ ] Fail-isolation sandbox PASS, CI passes

**Estimated Effort:** 2 hours
**Difficulty:** Medium

---

## PHASE 3 COMPLETE ✅

After **STEP 12**, Phase 3 is complete.
Next: Phase 4 (Documentation)

---

## STEPS 13-18: Documentation Creation (DONE)
**Status:** ✅ COMPLETE 2026-09-27 (README `a9e4e03`, TESTING `50bf8e6`, TROUBLESHOOTING `ce4dfbd`, DEVICE_COMPATIBILITY `1f362e7`, API `b37b0f2`, CHANGELOG `3c46f66`)
**No action needed — spec di bawah arsip historis.**

**Objective:**
Create honest documentation: validated claims vs graceful-degrade claims
kept strictly separate.

### STEP 13: Create README.md
- Quick start, requirements, profiles, log locations, uninstall, support
- Klaim device: HANYA yang tervalidasi; sisanya "graceful degrade"
- Commit: `docs: comprehensive README (Phase 4, Step 13)`
- **Estimated Effort:** 2-3 hours

### STEP 14: Create TESTING.md
- Test procedure (baseline → install → functional → stability → cleanup)
  + report template (ikuti pola ROADMAP lama Fase 1, tanpa matriks
  device-name sebagai janji)
- Commit: `docs: QA testing guide (Phase 4, Step 14)`
- **Estimated Effort:** 2 hours

### STEP 15: Create TROUBLESHOOTING.md
- 5+ masalah umum + langkah debug (slow boot, guard aktif, thermal
  unmanaged, GPU skip, rollback)
- Commit: `docs: troubleshooting guide (Phase 4, Step 15)`
- **Estimated Effort:** 1-2 hours

### STEP 16: Create DEVICE_COMPATIBILITY.md
- Dua tabel terpisah: TERVALIDASI (device + bukti: log/tanggal/tester —
  saat ini Unisoc/Mali milik user) vs GRACEFUL DEGRADE (semua device lain,
  menunggu bukti nyata). Jangan klaim rata.
- Commit: `docs: device compatibility matrix (Phase 4, Step 16)`
- **Estimated Effort:** 1-2 hours

### STEP 17: Create API.md
- Untuk modder: tambah signature entry, extend detection, tambah tweak;
  signature fungsi + env var + contoh
- Commit: `docs: modding API guide (Phase 4, Step 17)`
- **Estimated Effort:** 1-2 hours

### STEP 18: Create CHANGELOG.md
- v5.0.0 changes (termasuk: Step 5 lama direvert → capability-first),
  versi sebelumnya
- Commit: `docs: changelog for v5.0.0 (Phase 4, Step 18)`
- **Estimated Effort:** 1 hour

**Go/No-Go (each doc step):** markdown rapi, klaim device jujur
(validated vs degrade), tanpa nama chipset sebagai janji support.

---

## PHASE 4 COMPLETE ✅

After **STEP 18**, Phase 4 is complete.
Next: Phase 5 (QA & Release)

---

## STEPS 19-21: QA & Release Prep (DONE)
**Status:** ✅ COMPLETE 2026-09-27 (QA_CHECKLIST `ed5e34e`, RELEASE_NOTES `a7e90e5`, SUPPORT_POLICY `1734654`)
**No action needed — spec di bawah arsip historis.**

### STEP 19: Create QA_CHECKLIST.md
- Code quality (shellcheck, sh -n, JSON valid, file wajib, module.prop)
- Build quality (ZIP valid via tests/validate_build.sh pola Step 7 lama,
  size <50MB, integrity)
- Device testing (install, boot, guard-path, profile switch, rollback)
- Stability (30min gaming), edge cases (reboot saat apply, config korup),
  uninstall bersih
- Commit: `docs: QA checklist for release (Phase 5, Step 19)`
- **Estimated Effort:** 1 hour

### STEP 20: Create RELEASE_NOTES.md
- Headline, fitur Phase 2-3, keterbatasan JUJUR (device tervalidasi vs
  degrade, butuh L2 HP)
- Commit: `docs: release notes for v5.0.0 (Phase 5, Step 20)`
- **Estimated Effort:** 1 hour

### STEP 21: Create SUPPORT_POLICY.md
- SLA respons, kanal support, matriks kompatibilitas (rujuk Step 16)
- Commit: `docs: support policy (Phase 5, Step 21)`
- **Estimated Effort:** 30 minutes

---

## STEP 22: Final Status Update + Release Gate (⏳ GATE BELUM LOLOS — tunggu L2 HP)
**Status:** dievaluasi `d84bb49` 2026-09-27: Phase 2-3 selesai ✅, sandbox degrade ✅, L2 HP ❌ (device_reports kosong, QA 0/25), device kedua + extreme ❌. `module.prop` tetap v5.0.0-beta1/5001. JANGAN bump versi sebelum L2.

**Objective:**
Mark all phases complete and enforce the release gate: NO stable
versionCode bump before Phase 2-3 DONE **AND** validated on real hardware
(L2). This step REPLACES version-bump-awal Step 8 lama.

**Requirements:**
- [ ] Mark all 22 steps complete in STATUS.md, progress 100%
- [ ] L2 HP nyata PASS: boot guard path + safe apply + signature match di
  device tervalidasi (bukti: log HP, bukan klaim)
- [ ] Sandbox capability-hilang PASS (graceful degrade terbukti)
- [ ] BARU BOLEH: bump `version`/`versionCode` di `module.prop` ke rilis
  stabil dalam commit ini
- [ ] Commit: `docs: Phase 5 complete — ready for release (gate passed)`

**Go/No-Go Checklist:**
- [ ] 22/22 steps, L2 evidence attached, degrade sandbox PASS
- [ ] versionCode bumped ONLY here (grep: no earlier bump commit)

---

## STEP 23: Knob Result Visibility (tambahan, di luar 22 step awal) (DONE)
**Status:** ✅ COMPLETE (commit 05191f1, 2026-09-27)

**Objective:**
Jejak diminta X → diterapkan Y → alasan Z jangan hanya di log:
catat per knob ke SATU state file tiap siklus apply, tampilkan di
`hsin knob-list` dalam baris key=value (APK akan membacanya nanti).

**Files to modify:**
- `core/user_knobs.sh` (recorder + reset + output knob-list)
- Titik keputusan override 7 engine (1 baris record per titik, tanpa
  ubah jalur apply) + reset di `service.sh` §7 dan
  `hsin_apply_all_engines`

**Requirements:**
- [ ] State file `$HSIN_DATA/knob_results.env`, tulis atomik tmp+mv,
  reset tiap siklus apply; hilang → "belum ada hasil apply"
- [ ] Record dari titik yang sama dengan `hsin_uk_used` / WARN yang
  sudah ada; kategori HANYA set safe_apply (tanpa kategori baru)
- [ ] `knob-list`: baris `key=… requested=… applied=… category=…
  reason="…"` dulu, JSON lama byte-identik TERAKHIR (parser APK
  lastJsonLine tidak terganggu)
- [ ] Tanpa override → tampil nilai profil; tanpa file runtime baru
  (recorder di `user_knobs.sh` yang sudah di-bundle)

**Acceptance Criteria:**
- [ ] Sandbox file asli: valid APPLIED, snap FALLBACK + alasan,
  gov ditolak FALLBACK + alasan, OPP kosong tanpa klaim palsu,
  state hilang jujur, reset per siklus, profil-only tampil
- [ ] ShellCheck 0 errors, sh -n pass, CI passes

**Commit Message:**
```
feat: knob result visibility per apply cycle (PQ Step 23)
```

**Go/No-Go Checklist:**
- [ ] knob sandbox PASS, APK parser unaffected, CI passes

**Estimated Effort:** 2 hours
**Difficulty:** Medium

---

## 🎯 EXECUTION SUMMARY

```
PHASE 1: Testing Infrastructure (Steps 1-4) — DONE
├─ Step 1: Testing framework ✅ (7e41841)
├─ Step 2: lint-and-test CI ✅ (7e41841)
├─ Step 3: validate_build.sh ✅ (7e41841)
└─ Step 4: core/detector.sh ✅ (5b373ea)

PHASE 2: Boot Guard & Safe Apply (Steps 5-8) — DONE
├─ Step 5: core/boot_guard.sh ✅ (5f3355c)
├─ Step 6: integrate service.sh ✅ (62ee738)
├─ Step 7: core/safe_apply.sh ✅ (6ea5619)
└─ Step 8: proof of pattern (io/readahead) ✅ (6ea5619)

PHASE 3: Capability Overrides (Steps 9-12) — DONE
├─ Step 9: capability_overrides.json + loader ✅ (b79763d)
├─ Step 10: thermal_check.sh guardrail ✅ (2a56064/546f9a5)
├─ Step 11: harmonisasi spec ✅ (912b3bf)
└─ Step 12: graceful degradation contract ✅ (7ae4573)

PHASE 4: Documentation (Steps 13-18) — DONE
├─ README ✅ (a9e4e03), TESTING ✅ (50bf8e6), TROUBLESHOOTING ✅ (ce4dfbd)
├─ DEVICE_COMPATIBILITY ✅ (1f362e7), API ✅ (b37b0f2), CHANGELOG ✅ (3c46f66)

PHASE 5: QA & Release (Steps 19-22) — 19-21 DONE, 22 GATE BELUM LOLOS
├─ QA_CHECKLIST ✅ (ed5e34e), RELEASE_NOTES ✅ (a7e90e5), SUPPORT_POLICY ✅ (1734654)
├─ Step 22: gate BELUM LOLOS (d84bb49, tunggu L2 HP)
└─ Step 23: knob visibility ✅ (05191f1)
```

**Dropped/merged from old 31-step queue (explicit, not silent):**
- Old Step 5 (device-name JSON) → REVERTED (36d2256), replaced by new Step 9
- Old Step 6 (fixed thermal JSON) → replaced by new Step 11 (zone-based)
- Old Step 7 (build validation hook) → folded into Step 19 QA checklist
- Old Step 8 (early version bump 5000) → moved to Step 22 release gate
- Old Steps 12-18 (7-engine migration) → collapsed to new Step 8 (cpu proof);
  remaining engines migrate after pattern approval
- Old Step 20 (device-name loader) → replaced by new Step 10

---

## 📝 HOW TO USE THIS FILE

1. **AI Agent:** Read current step section (+ PLAN.md histori + skill
   alpha-hsin-engineering before writing any code)
2. **Execute:** Follow all requirements and acceptance criteria
3. **Commit:** Push with exact message format (1 step = 1 commit, no force)
4. **Notify:** Update STATUS.md checkbox + hash + progress bar + summary
5. **Repeat:** Move to next step (need user approval before Phase jumps)

Example:
```
Human: "Execute Step 5"
AI: Reads STEP 5, creates core/boot_guard.sh, sandbox-tests, commits
AI: Pushes to GitHub, CI runs
AI: Updates STATUS.md: Step 5 [x] + hash + progress 5/22
Human: "Execute Step 6"
...
```

---

**Last Updated:** 2026-09-30 (sinkron status: Steps 5-21 + 23 DONE + hash; Step 22 gate belum lolos)
**Total Steps:** 22 (+ Step 23 tambahan; Steps 1-21 + 23 DONE, Step 22 GATE tunggu L2 HP)
**Phase 2 Progress:** 4/4 DONE
**Next:** STEP 22 GATE RILIS — TESTING.md di HP fisik + report L2 + QA (tanpa L2 = tanpa bump versi)
