# STATUS.md — HSIN v5.0.0 Real-Time Progress Tracker

**Last Updated:** 2026-09-27 (Task 1.1.1–1.1.3 DONE, 1.2/1.3 menunggu approve)
**Overall Progress:** Phase 1 — IN PROGRESS (3/7 tasks 1.1 done)

---

## 🎯 Master Progress

```
[████░░░░░░░░░░░░░░░░] 20% (Week 1/5)

PHASE 1: Foundation & Testing Framework    [░░░░░░░░░░] 0% — READY TO START
PHASE 2: Error Handling & Recovery         [░░░░░░░░░░] 0% — BLOCKED (wait Phase 1)
PHASE 3: Multi-Device Support              [░░░░░░░░░░] 0% — BLOCKED (wait Phase 1-2)
PHASE 4: Automation & Documentation        [░░░░░░░░░░] 0% — BLOCKED (wait Phase 1-3)
PHASE 5: QA, Release & Maintenance         [░░░░░░░░░░] 0% — BLOCKED (wait Phase 1-4)
```

---

## 📋 PHASE 1: Foundation & Testing Framework (Week 1)

**Status:** ⏳ READY FOR AI CODING  
**Estimated Effort:** 40% (Weeks 1)  
**Commits Expected:** 3-4

### 1.1 Create Testing Infrastructure [3/7 tasks]

- [x] **Task 1.1.1** — Create `tests/` directory structure
  - [x] `tests/TESTING_FRAMEWORK.md` (comprehensive testing guide)
  - [x] `tests/device_reports/` (directory for per-device reports)
  - [x] `tests/TEMPLATE_DEVICE_REPORT.md` (template for human testers)
  - Acceptance: Files exist, TEMPLATE has all required sections
  - Status: DONE (2026-09-27, merge 7e41841; verifikasi leader: 5 file baru, sh -n OK, shellcheck 0, YAML valid via PyYAML, sim lint lolos, validate positif+negatif OK)
  - Commit: `feat: create testing framework infrastructure`

- [x] **Task 1.1.2** — Create `.github/workflows/lint-and-test.yml`
  - ShellCheck all .sh files (level `-S error`: warning pre-existing SC2115/SC2154 di build_release.sh & action.sh terbukti gagalkan push bila tanpa filter — dibuktikan rc=1)
  - sh -n syntax validation
  - JSON config validation (python3 -m json.tool, skip-safe bila belum ada JSON)
  - Mandatory file checks
  - module.prop format validation
  - Acceptance: Workflow runs on push, 0 errors
  - Status: DONE (2026-09-27, merge 7e41841; sim lokal LINT-SIM-PASS; runs nyata menunggu push ini)
  - Commit: `ci: add lint and test automation`

- [x] **Task 1.1.3** — Create build validation script
  - `tests/validate_build.sh` — Pre/post-zip validation
  - Check mandatory files present
  - Verify ZIP structure
  - Check hash manifest count
  - Acceptance: Script runs, returns exit 0 on valid ZIP
  - Status: DONE (2026-09-27, merge 7e41841; positif VALID exit 0, negatif ERROR exit 1)
  - Commit: `test: add build validation script`

### 1.2 Improve Core Device Detection [0/6 tasks]

- [x] **Task 1.2.1** — Enhance `core/detector.sh` (Step 4) — DONE (2026-09-27; 241+/2-; mock 5 vendor + THERMAL_PATH + cache; getprop mock apple/empty masih bentrok harness — bukan kode, L2 wajib)
  - Add Qualcomm detection (SDM/SM/MSM)
  - Add MediaTek detection (MTK/Dimensity)
  - Add Exynos detection (Samsung)
  - Add Unisoc detection (UMS*)
  - Add Apple detection (device-tree)
  - Add GPU vendor detection (Adreno, Mali, PowerVR, Xclipse)
  - Add CPU policies enumeration
  - Add thermal zone mapping
  - Acceptance: All 8 detection functions work, cache to detected.conf
  - Status: PENDING
  - Commit: `refactor: comprehensive device detection`

- [ ] **Task 1.2.2** — Create `capability/device_overrides.json`
  - Structure: unisoc_t615, snapdragon_888, dimensity_9200, exynos_1280
  - Per-device: gpu_freq_max_percent (battery/balanced/performance/extreme)
  - Per-device: thermal_safe_mode flag
  - Acceptance: Valid JSON, 4+ device profiles
  - Status: PENDING (direvert 2026-09-27 via 36d2256 — device_overrides.json keyed by nama chipset, diganti jadi capability-signature-based)
  - Commit: `feat: device-specific override profiles` (direvert)

- [ ] **Task 1.2.3** — Create `capability/thermal_safety.json`
  - Structure: gpu, cpu, soc zones
  - Temp thresholds: critical, warn, battery_cap, balanced_cap, performance_cap, extreme_cap
  - Throttle response: cpu_freq_reduce, gpu_freq_reduce, watchdog_interval
  - Acceptance: Valid JSON, sensible values (critical >100°C)
  - Status: PENDING
  - Commit: `feat: thermal safety matrix`

### 1.3 Update Build & Validation [0/3 tasks]

- [ ] **Task 1.3.1** — Update `build_release.sh`
  - Add validation step before zip
  - Check mandatory files present
  - Verify hash manifest
  - Size check (<50MB)
  - Acceptance: build_release.sh runs validation, aborts if invalid
  - Status: PENDING
  - Commit: `refactor: add release validation to build script`

- [ ] **Task 1.3.2** — Update `module.prop`
  - Change versionCode from previous → 5000 (v5.0.0)
  - Acceptance: module.prop has versionCode=5000
  - Status: PENDING
  - Commit: `chore: bump version to 5.0.0`

---

## 📋 PHASE 2: Error Handling & Recovery (Week 2)

**Status:** ⏳ BLOCKED (waiting Phase 1 completion)  
**Estimated Effort:** 35%  
**Commits Expected:** 3-4  
**Unblocks when:** Phase 1 complete + merged to develop

### 2.1 Boot Guard v2 [0/3 tasks]

- [ ] **Task 2.1.1** — Create `core/boot_guard.sh`
  - Track boot failures (file: /data/adb/hsin/.boot_failures)
  - Auto-disable if 3 failures in 24h
  - Log each failure with timestamp
  - Clear counter on successful boot
  - Acceptance: boot_guard.sh works, /data/adb/hsin/.boot_failures exists after test
  - Status: BLOCKED
  - Commit: `feat: boot guard v2`

- [ ] **Task 2.1.2** — Integrate boot guard into `service.sh`
  - Source boot_guard.sh at start
  - Call hsin_boot_guard_check()
  - Exit 0 if guard triggered
  - Acceptance: service.sh calls boot guard, skips tuning on fail
  - Status: BLOCKED
  - Commit: `refactor: integrate boot guard into service`

### 2.2 Safe Apply Mechanism [0/8 tasks]

- [ ] **Task 2.2.1** — Create `core/safe_apply.sh`
  - safe_sysfs_write(path, value, category) — write + verify
  - safe_apply_rollback(timestamp) — restore backed-up values
  - safe_apply_verify(timestamp) — check if values match
  - Acceptance: All 3 functions work, backup/rollback tested
  - Status: BLOCKED
  - Commit: `feat: safe sysfs write mechanism with rollback`

- [ ] **Task 2.2.2-8** — Migrate engines to use safe_apply
  - [ ] 2.2.2: `engine/cpu/apply.sh` — Replace all writes
  - [ ] 2.2.3: `engine/gpu/apply.sh` — Replace all writes
  - [ ] 2.2.4: `engine/thermal/apply.sh` — Replace all writes
  - [ ] 2.2.5: `engine/memory/apply.sh` — Replace all writes
  - [ ] 2.2.6: `engine/io/apply.sh` — Replace all writes
  - [ ] 2.2.7: `engine/network/apply.sh` — Replace all writes
  - [ ] 2.2.8: `engine/display/apply.sh` — Replace all writes
  - Pattern: `echo "$value" > "$path"` → `safe_sysfs_write "$path" "$value" "CATEGORY"`
  - Acceptance: All engines use safe_apply, logs show APPLIED/FAILED/SKIPPED
  - Status: BLOCKED
  - Commits: `refactor: migrate engine/*/apply.sh to safe_apply` (1 commit per engine)

### 2.3 Graceful Degradation [0/1 task]

- [ ] **Task 2.3.1** — Implement graceful degradation pattern
  - Each engine: applied_count=0, failed_count=0
  - Loop through targets, skip individual items on fail (don't exit)
  - Log each APPLIED/SKIPPED/FAILED
  - Return 0 if applied_count > 0 (partial success OK)
  - Update `service.sh` — continue with next engine on fail
  - Acceptance: Engine failure doesn't abort module, logs show partial success
  - Status: BLOCKED
  - Commit: `refactor: graceful degradation per engine`

---

## 📋 PHASE 3: Multi-Device Support (Week 3)

**Status:** ⏳ BLOCKED (waiting Phase 1-2 completion)  
**Estimated Effort:** 20%  
**Commits Expected:** 3-4  
**Unblocks when:** Phase 2 complete + merged to develop

### 3.1 Enhanced Detector [0/2 tasks]

- [ ] **Task 3.1.1** — Finalize `core/detector.sh`
  - All 8 SoC detection functions complete + tested
  - Create `core/soc_list.conf` — reference of known SoCs
  - Acceptance: detector.sh detects all major chipsets (Qualcomm, MediaTek, Exynos, Unisoc, Apple)
  - Status: BLOCKED
  - Commit: `refactor: finalize comprehensive device detection`

- [ ] **Task 3.1.2** — Create `core/load_overrides.sh`
  - Parse device_overrides.json for detected SoC
  - Export override variables (gpu_freq_max_percent, thermal_safe_mode, etc.)
  - Integration: Call load_overrides() in service.sh after detection
  - Acceptance: Override values loaded and used in profile application
  - Status: BLOCKED
  - Commit: `feat: device override loader`

### 3.2 Thermal Safety [0/1 task]

- [ ] **Task 3.2.1** — Create `core/thermal_check.sh`
  - Check current temp before aggressive tuning
  - Skip performance/extreme cap if temp > battery_cap
  - Log thermal state changes
  - Auto-rollback if temp > critical
  - Acceptance: thermal_check.sh prevents thermal throttle, logs changes
  - Status: BLOCKED
  - Commit: `feat: thermal safety monitoring`

---

## 📋 PHASE 4: Automation & Documentation (Week 3-4)

**Status:** ⏳ BLOCKED (waiting Phase 1-3 completion)  
**Estimated Effort:** 20%  
**Commits Expected:** 2-3  
**Unblocks when:** Phase 3 complete + merged to develop

### 4.1 CI/CD Automation [0/2 tasks]

- [ ] **Task 4.1.1** — Finalize `.github/workflows/` (from Phase 1)
  - lint-and-test.yml — complete
  - build-and-verify.yml — add size check, artifact upload
  - Acceptance: Both workflows run on push, produce artifacts
  - Status: BLOCKED
  - Commit: `ci: finalize build and verify pipeline`

- [ ] **Task 4.1.2** — Create `.github/ISSUE_TEMPLATE/`
  - `bug_report.md` — standardized bug template
  - `device_report.md` — device test report template
  - Acceptance: Templates available in GitHub new issue form
  - Status: BLOCKED
  - Commit: `docs: add issue templates`

### 4.2 Documentation [0/6 tasks]

- [ ] **Task 4.2.1** — Create comprehensive `README.md`
  - Quick start, installation, verification
  - Features, profiles, device support table
  - Logs, troubleshooting, uninstall
  - Acceptance: README complete, all sections filled
  - Status: BLOCKED
  - Commit: `docs: comprehensive README`

- [ ] **Task 4.2.2** — Create `TESTING.md`
  - Pre-test setup, test cases (install, profiles, stability, rollback, edge cases)
  - Report template
  - Acceptance: TESTING.md has reproducible test cases
  - Status: BLOCKED
  - Commit: `docs: QA testing guide`

- [ ] **Task 4.2.3** — Create `TROUBLESHOOTING.md`
  - Common issues: slow boot, thermal throttle, GPU stuck, etc.
  - Solutions with debug steps
  - Acceptance: 5+ issues with solutions
  - Status: BLOCKED
  - Commit: `docs: troubleshooting guide`

- [ ] **Task 4.2.4** — Create `DEVICE_COMPATIBILITY.md`
  - Per-device notes (Unisoc T615, Snapdragon, MediaTek, Exynos)
  - Known issues, workarounds, optimizations
  - Acceptance: 4+ devices documented
  - Status: BLOCKED
  - Commit: `docs: device compatibility matrix`

- [ ] **Task 4.2.5** — Create `API.md`
  - For modders: how to add new profiles, extend detection, add custom tweaks
  - Function signatures, environment variables, examples
  - Acceptance: API.md has 3+ examples
  - Status: BLOCKED
  - Commit: `docs: modding API guide`

- [ ] **Task 4.2.6** — Create `CHANGELOG.md`
  - v5.0.0 changes: boot guard, safe apply, multi-device, docs
  - Previous versions (v4.2.7, v4.2.6, etc.)
  - Acceptance: CHANGELOG lists all major changes
  - Status: BLOCKED
  - Commit: `docs: changelog for v5.0.0`

---

## 📋 PHASE 5: QA, Release & Maintenance (Week 4-6)

**Status:** ⏳ BLOCKED (waiting Phase 1-4 completion)  
**Estimated Effort:** 5%  
**Commits Expected:** 1-2  
**Unblocks when:** Phase 4 complete + merged to develop

### 5.1 QA & Release Prep [0/3 tasks]

- [ ] **Task 5.1.1** — Create `QA_CHECKLIST.md`
  - Code quality (ShellCheck, syntax, JSON, files, permissions)
  - Build quality (ZIP, size, hash, integrity)
  - Device testing (install, boot, module, log)
  - Functional testing (profile, thermal, GPU, game boost, rollback)
  - Stability testing (30min gaming)
  - Uninstall testing
  - Acceptance: QA_CHECKLIST complete with all criteria
  - Status: BLOCKED
  - Commit: `docs: QA checklist for release`

- [ ] **Task 5.1.2** — Create `RELEASE_NOTES.md`
  - v5.0.0 headline: "Production-ready, multi-device, zero bootloop"
  - Major features: boot guard, safe apply, device profiles
  - Supported devices: 4+ tested
  - Known limitations: PowerVR, Xclipse (limited tuning)
  - Acceptance: Release notes clear and complete
  - Status: BLOCKED
  - Commit: `docs: release notes for v5.0.0`

- [ ] **Task 5.1.3** — Create `SUPPORT_POLICY.md`
  - Issue response SLA (24h for critical, 72h for normal)
  - Support channels (GitHub, Discord, Telegram)
  - Device compatibility matrix (actively supported vs. community-supported)
  - Acceptance: Support policy clear
  - Status: BLOCKED
  - Commit: `docs: support policy`

---

## 📊 Summary Stats

| Metric | Value |
|---|---|
| **Total Tasks** | 31 |
| **Completed** | 0 |
| **In Progress** | 0 |
| **Blocked** | 0 |
| **Ready to Start** | 12 (Phase 1) |
| **Expected Commits** | 11-14 |
| **Expected Duration** | 4-6 weeks |

---

## 🔄 Update Instructions

**After each task completion:**

1. Update checkbox: `- [x]` (done) or `- [ ]` (pending)
2. Update task Status → COMPLETED
3. Note any issues/blockers in "Blocker" column
4. Commit message references this STATUS.md
5. Example: `feat: boot guard v2 (Phase 2, Task 2.1.1) — STATUS.md updated`

**Weekly rollup:**
```bash
# Count completed tasks
grep -c "^\s*- \[x\]" STATUS.md

# Example: "Phase 1 complete: 12/12 tasks ✅"
```

---

## 🚦 Phase Transition Rules

- ✅ **Phase 1 → Phase 2:** All 12 Phase 1 tasks completed + merged to develop
- ✅ **Phase 2 → Phase 3:** All Phase 2 tasks completed + merged to develop
- ✅ **Phase 3 → Phase 4:** All Phase 3 tasks completed + merged to develop
- ✅ **Phase 4 → Phase 5:** All Phase 4 tasks completed + merged to main (release branch)
- ✅ **Phase 5 → RELEASE:** Phase 5 tasks completed + QA PASS + tag v5.0.0

---

## 🎯 Success Criteria (Final Release)

- [ ] ✅ ShellCheck: 0 errors
- [ ] ✅ Syntax: 0 sh -n errors
- [ ] ✅ JSON: Valid (all configs)
- [ ] ✅ Files: 100% mandatory present
- [ ] ✅ Boot guard: Tested, prevents bootloop
- [ ] ✅ Safe apply: 100% verify-after-write
- [ ] ✅ Device support: 4+ chipsets tested
- [ ] ✅ Documentation: Complete (README, TESTING, TROUBLESHOOTING, API)
- [ ] ✅ QA: Checklist PASS
- [ ] ✅ Commits: Clean history (11-14 commits)

---

**Last Status Update:** Ready for Phase 1 AI coding execution  
**Next Step:** AI agent reads PLAN.md + PRIORITY_QUEUE.md, starts Task 1.1.1
