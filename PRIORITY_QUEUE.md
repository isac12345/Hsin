# PRIORITY_QUEUE.md — Step-by-Step AI Execution Queue

**Read this file** when executing next step. Each step is **atomic** and **independent**.

**Current Status:** Phase 1.2 ready (Device Detection)  
**Total Steps:** 31 (organized by phase)  
**Format:** `## STEP [N] — [TITLE]`

---

## ⏸️ CURRENT PHASE

```
✅ PHASE 1.1: Testing Infrastructure (Steps 1-3) — COMPLETE
⏳ PHASE 1.2: Device Detection (Steps 4-6) — NEXT
⏳ PHASE 1.3: Build Validation (Steps 7-8) — PENDING
```

---

# 🚀 EXECUTION QUEUE

## STEP 1: Create Testing Infrastructure (DONE)
**Status:** ✅ COMPLETE (commit 7e41841)  
**No action needed — move to Step 4**

---

## STEP 2: Create lint-and-test CI (DONE)
**Status:** ✅ COMPLETE (commit 7e41841)  
**No action needed — move to Step 4**

---

## STEP 3: Create validate_build.sh (DONE)
**Status:** ✅ COMPLETE (commit 7e41841)  
**No action needed — move to Step 4**

---

## STEP 4: Enhance core/detector.sh — Comprehensive SoC Detection

**Objective:**  
Add comprehensive SoC and GPU vendor detection to support Qualcomm, MediaTek, Exynos, Unisoc, Apple, and fallback detection. Cache results to `/data/adb/hsin/detected.conf`.

**Files to modify:**
- `core/detector.sh`

**Requirements:**
- [ ] Add `detect_qualcomm()` function
  - Check `ro.soc.model` contains `sm|sd|msm`
  - Check `ro.board.platform` contains `qcom`
  - Set `SOC_VENDOR="QUALCOMM"` and `GPU_VENDOR="ADRENO"`
  
- [ ] Add `detect_mediatek()` function
  - Check `ro.vendor.extension_library` contains `mtk|libmt`
  - Check `ro.vendor.mediatek.platform` exists
  - Set `SOC_VENDOR="MEDIATEK"` and `GPU_VENDOR="MALI"`

- [ ] Add `detect_exynos()` function
  - Check for Samsung fingerprint (e.g., `ro.vendor.fingerprint` contains `samsung`)
  - Set `SOC_VENDOR="EXYNOS"` and `GPU_VENDOR="MALI"` (or `XCLIPSE` if detected)

- [ ] Add `detect_unisoc()` function
  - Check `ro.board.platform` contains `ums|unisoc`
  - Set `SOC_VENDOR="UNISOC"` and `GPU_VENDOR="MALI"`

- [ ] Add `detect_apple()` function
  - Check `/proc/device-tree/compatible` contains `apple`
  - Set `SOC_VENDOR="APPLE"` and `GPU_VENDOR="APPLE"`

- [ ] Add `detect_gpu_vendor()` function (fallback)
  - If `/sys/class/kgsl/kgsl-3d0` exists → `GPU_VENDOR="ADRENO"`
  - If `/sys/class/devfreq/*mali*` exists → `GPU_VENDOR="MALI"`
  - If `/sys/devices/platform/*powervr*` exists → `GPU_VENDOR="POWERVR"`
  - If `/proc/device-tree/compatible` contains `xclipse` → `GPU_VENDOR="XCLIPSE"`

- [ ] Add `detect_cpu_policies()` function
  - List all `policy*` directories in `/sys/devices/system/cpu/cpufreq/`
  - Store as `CPU_POLICIES="policy0 policy1 ..."`
  - Fallback: `CPU_POLICIES="policy0"` if none found

- [ ] Add `detect_thermal_zones()` function
  - Scan `/sys/class/thermal/thermal_zone*` for GPU/CPU/SoC temp
  - Find first zone with type matching `*gpu*|*soc*|*tsens*|*cpu*`
  - Store path to `THERMAL_PATH="/sys/class/thermal/thermal_zone*/temp"`

- [ ] Add `cache_detection()` function
  - Create `/data/adb/hsin/detected.conf` (or `$HSIN_DATA/detected.conf`)
  - Write key-value pairs:
    ```
    SOC_VENDOR=QUALCOMM
    SOC_MODEL=sm8350
    GPU_VENDOR=ADRENO
    CPU_POLICIES=policy0 policy1
    THERMAL_PATH=/sys/class/thermal/thermal_zone0/temp
    ```

- [ ] Add main `hsin_detect_all()` function
  - Call all detect_* functions in order
  - Call `cache_detection()` at end
  - Log results using `hsin_log_info()`

**Acceptance Criteria:**
- [ ] `detect_qualcomm()` works (tested via getprop mock)
- [ ] `detect_mediatek()` works
- [ ] `detect_exynos()` works
- [ ] `detect_unisoc()` works
- [ ] `detect_apple()` works
- [ ] `detect_gpu_vendor()` fallback works
- [ ] `detect_cpu_policies()` enumerates all policies
- [ ] `detect_thermal_zones()` finds correct thermal zone
- [ ] `hsin_detect_all()` caches to detected.conf
- [ ] ShellCheck: 0 errors
- [ ] sh -n: passes
- [ ] CI lint-and-test passes

**Expected Output:**
```bash
$ cat /data/adb/hsin/detected.conf
SOC_VENDOR=QUALCOMM
SOC_MODEL=sm8350
GPU_VENDOR=ADRENO
CPU_POLICIES=policy0 policy1 policy2 policy3
THERMAL_PATH=/sys/class/thermal/thermal_zone0/temp
```

**Commit Message:**
```
refactor: comprehensive device detection (Phase 1.2, Step 4)

- Add Qualcomm, MediaTek, Exynos, Unisoc, Apple SoC detection
- Add GPU vendor detection (Adreno, Mali, PowerVR, Xclipse, Apple)
- Add CPU policies enumeration
- Add thermal zone mapping
- Cache detection results to detected.conf
- Log results for debugging
- ShellCheck: 0 errors, sh -n: pass
```

**Go/No-Go Checklist:**
- [ ] All functions added
- [ ] CI passes
- [ ] detected.conf created with expected output
- [ ] No breaking changes to existing code
- [ ] README or docs not modified

**Estimated Effort:** 2-3 hours  
**Difficulty:** Medium

---

## STEP 5: Create capability/device_overrides.json

**Objective:**  
Create per-device tuning profiles for Unisoc T615, Snapdragon 888, MediaTek Dimensity 9200, and Exynos 1280. Include GPU freq caps per profile and thermal safety flags.

**Files to create:**
- `capability/device_overrides.json`

**Content Structure:**
```json
{
  "overrides": {
    "unisoc_t615": {
      "description": "Unisoc T615 (ums9230) — Mali GPU, conservative thermals",
      "cpu_governor_preference": ["schedutil", "powersave"],
      "gpu_freq_max_percent": {
        "battery": 60,
        "balanced": 85,
        "performance": 100,
        "extreme": 100
      },
      "thermal_safe_mode": true,
      "extreme_thermal_headroom_percent": 85
    },
    "snapdragon_888": {
      "description": "Snapdragon 888 — Adreno GPU, aggressive thermals possible",
      "cpu_governor_preference": ["performance", "schedutil"],
      "gpu_freq_max_percent": {
        "battery": 70,
        "balanced": 100,
        "performance": 100,
        "extreme": 100
      },
      "thermal_safe_mode": false,
      "extreme_thermal_headroom_percent": 80
    },
    "dimensity_9200": {
      "description": "MediaTek Dimensity 9200 — Mali GPU, modern architecture",
      "cpu_governor_preference": ["schedutil", "conservative"],
      "gpu_freq_max_percent": {
        "battery": 65,
        "balanced": 90,
        "performance": 100,
        "extreme": 100
      },
      "thermal_safe_mode": false,
      "extreme_thermal_headroom_percent": 75
    },
    "exynos_1280": {
      "description": "Exynos 1280 — Mali GPU, entry-level, strict thermal",
      "cpu_governor_preference": ["schedutil", "powersave"],
      "gpu_freq_max_percent": {
        "battery": 55,
        "balanced": 75,
        "performance": 95,
        "extreme": 95
      },
      "thermal_safe_mode": true,
      "extreme_thermal_headroom_percent": 80
    },
    "powervr": {
      "description": "PowerVR GPU — tuning limited, skip aggressive caps",
      "gpu_skip": true,
      "thermal_safe_mode": true
    },
    "xclipse": {
      "description": "Xclipse GPU (Samsung) — tuning limited",
      "gpu_skip": true,
      "thermal_safe_mode": true
    }
  }
}
```

**Requirements:**
- [ ] Valid JSON (python3 -m json.tool passes)
- [ ] At least 4 device profiles (unisoc_t615, snapdragon_888, dimensity_9200, exynos_1280)
- [ ] Each device has `gpu_freq_max_percent` with all 4 profiles
- [ ] Each device has `thermal_safe_mode` flag (boolean)
- [ ] Each device has `extreme_thermal_headroom_percent` (integer, 70-95)
- [ ] Fallback entries for unsupported GPUs (powervr, xclipse)

**Acceptance Criteria:**
- [ ] File created at `capability/device_overrides.json`
- [ ] Valid JSON
- [ ] 4+ device profiles
- [ ] All required fields present
- [ ] CI passes

**Commit Message:**
```
feat: device-specific override profiles (Phase 1.2, Step 5)

- Add Unisoc T615 profile (conservative, safe thermals)
- Add Snapdragon 888 profile (aggressive)
- Add MediaTek Dimensity 9200 profile
- Add Exynos 1280 profile (entry-level)
- Add fallback profiles for PowerVR/Xclipse (tuning limited)
- Each device has gpu_freq_max_percent per profile
- Each device has thermal_safe_mode and thermal_headroom_percent
```

**Go/No-Go Checklist:**
- [ ] JSON valid
- [ ] 4+ profiles
- [ ] All fields present
- [ ] CI passes
- [ ] No code changes

**Estimated Effort:** 30 minutes  
**Difficulty:** Easy

---

## STEP 6: Create capability/thermal_safety.json

**Objective:**  
Define thermal safety thresholds and throttle response for GPU, CPU, and SoC. Include temperature limits per profile and watchdog parameters.

**Files to create:**
- `capability/thermal_safety.json`

**Content Structure:**
```json
{
  "thermal_zones": {
    "gpu": {
      "critical_temp_c": 100,
      "warn_temp_c": 75,
      "temp_limits_per_profile": {
        "battery": 50,
        "balanced": 65,
        "performance": 80,
        "extreme": 85
      }
    },
    "cpu": {
      "critical_temp_c": 110,
      "warn_temp_c": 85,
      "temp_limits_per_profile": {
        "battery": 55,
        "balanced": 70,
        "performance": 85,
        "extreme": 95
      }
    },
    "soc": {
      "critical_temp_c": 120,
      "warn_temp_c": 90
    }
  },
  "throttle_response": {
    "cpu_freq_reduce_on_critical_percent": 50,
    "gpu_freq_reduce_on_critical_percent": 40,
    "watchdog_check_interval_ms": 5000,
    "recovery_delay_after_cool_ms": 30000
  }
}
```

**Requirements:**
- [ ] Valid JSON
- [ ] GPU section with critical, warn, and per-profile limits
- [ ] CPU section with critical, warn, and per-profile limits
- [ ] SoC section with critical and warn only
- [ ] throttle_response section with timing parameters
- [ ] Critical temps > 100°C for GPU, > 110°C for CPU
- [ ] Profile limits: battery < balanced < performance < extreme

**Acceptance Criteria:**
- [ ] File created at `capability/thermal_safety.json`
- [ ] Valid JSON
- [ ] All sections present
- [ ] Sensible temperature values
- [ ] CI passes

**Commit Message:**
```
feat: thermal safety matrix (Phase 1.2, Step 6)

- Define thermal zones: GPU, CPU, SoC
- Set critical/warn temperature thresholds
- Set per-profile temperature limits (battery/balanced/performance/extreme)
- Define throttle response (freq reduction percentages, watchdog interval, recovery delay)
- Critical temps: GPU 100°C, CPU 110°C, SoC 120°C
- Watchdog check every 5s, recovery delay 30s after cool
```

**Go/No-Go Checklist:**
- [ ] JSON valid
- [ ] All sections present
- [ ] Sensible values
- [ ] CI passes
- [ ] No code changes

**Estimated Effort:** 30 minutes  
**Difficulty:** Easy

---

## STEP 7: Update build_release.sh — Add Validation

**Objective:**  
Integrate build validation into `build_release.sh` so that pre-built ZIP is validated before upload/release.

**Files to modify:**
- `build_release.sh`

**Requirements:**
- [ ] After ZIP is created, call `sh tests/validate_build.sh "$ZIP"`
- [ ] Check exit code: 0 = valid, 1 = invalid
- [ ] If invalid, abort with error message
- [ ] If valid, log "Build validation PASSED"
- [ ] Continue with upload/artifact step

**Acceptance Criteria:**
- [ ] `build_release.sh` calls validate_build.sh
- [ ] Aborts on validation failure
- [ ] CI still passes
- [ ] No other functionality broken

**Commit Message:**
```
refactor: add release validation to build script (Phase 1.3, Step 7)

- Call tests/validate_build.sh after ZIP creation
- Abort build if validation fails
- Log validation results
- Prevent invalid ZIPs from being uploaded
```

**Go/No-Go Checklist:**
- [ ] build_release.sh modified
- [ ] Calls validate_build.sh
- [ ] Exit code checked
- [ ] Error handling works
- [ ] CI passes

**Estimated Effort:** 1 hour  
**Difficulty:** Easy

---

## STEP 8: Update module.prop — Bump Version to 5.0.0

**Objective:**  
Update `module.prop` to reflect v5.0.0 and versionCode 5000, marking the start of 10/10 stability initiative.

**Files to modify:**
- `module.prop`

**Changes:**
- [ ] Set `version=5.0.0` (currently v4.2.7 or similar)
- [ ] Set `versionCode=5000`
- [ ] Update `description` to mention "v5.0.0 — Production-ready, multi-device"

**Acceptance Criteria:**
- [ ] module.prop has `version=5.0.0`
- [ ] module.prop has `versionCode=5000`
- [ ] CI passes (mandatory file check, module.prop format check)

**Commit Message:**
```
chore: bump version to 5.0.0 (Phase 1.3, Step 8)

- Set version=5.0.0 (production-ready, multi-device initiative)
- Set versionCode=5000
- Update description to reflect v5.0.0 features
```

**Go/No-Go Checklist:**
- [ ] module.prop updated
- [ ] version and versionCode correct
- [ ] CI passes
- [ ] No code logic changes

**Estimated Effort:** 15 minutes  
**Difficulty:** Trivial

---

## PHASE 1 COMPLETE ✅

After **STEP 8**, Phase 1 is complete.  
Next: Phase 2 (Error Handling & Recovery)

---

## STEP 9: Create core/boot_guard.sh — Boot Guard v2

**Objective:**  
Implement boot guard mechanism that tracks boot failures and auto-disables module after 3 failures in 24 hours.

**Files to create:**
- `core/boot_guard.sh`

**Requirements:**
- [ ] Create `hsin_boot_guard_init()` function
  - Create `/data/adb/hsin/.boot_guard_state` file on first call
  - Format: `timestamp:count:reason`

- [ ] Create `hsin_boot_guard_check()` function
  - Read current boot failure count
  - If count >= 3 and within 24h → return 1 (guard active)
  - If 24h elapsed → reset counter, return 0
  - Return 0 if count < 3

- [ ] Create `hsin_boot_guard_increment()` function
  - Increment failure counter
  - Write timestamp + count to state file
  - Log failure with reason

- [ ] Create `hsin_boot_guard_reset()` function
  - Clear state file
  - Called on successful boot

**Acceptance Criteria:**
- [ ] boot_guard.sh created
- [ ] All 4 functions work
- [ ] State file created/tracked correctly
- [ ] 24h cooldown logic works
- [ ] ShellCheck: 0 errors

**Commit Message:**
```
feat: boot guard v2 (Phase 2.1, Step 9)

- Track boot failures with timestamp
- Auto-disable after 3 failures in 24h
- 24h cooldown before re-enabling
- Log each failure and reset
```

**Go/No-Go Checklist:**
- [ ] All functions created
- [ ] State file logic works
- [ ] 24h cooldown implemented
- [ ] ShellCheck passes
- [ ] CI passes

**Estimated Effort:** 2 hours  
**Difficulty:** Medium

---

## STEP 10: Integrate boot_guard.sh into service.sh

**Objective:**  
Call boot guard at service.sh startup. If guard is active (3+ failures), skip all tuning and exit cleanly.

**Files to modify:**
- `service.sh`

**Requirements:**
- [ ] At start of service.sh, source `core/boot_guard.sh`
- [ ] Call `hsin_boot_guard_check()`
- [ ] If returns 1 (guard active):
  - Log: "Boot guard active: module tuning skipped"
  - Exit 0 (no error, but skip everything)
- [ ] If returns 0 (safe to proceed):
  - Continue with normal boot sequence
  - Call `hsin_boot_guard_reset()` after successful boot

**Acceptance Criteria:**
- [ ] boot_guard integrated into service.sh
- [ ] Proper exit behavior
- [ ] Logging works
- [ ] No breakage of normal flow
- [ ] CI passes

**Commit Message:**
```
refactor: integrate boot guard into service (Phase 2.1, Step 10)

- Source core/boot_guard.sh at startup
- Check guard before proceeding with tuning
- Exit cleanly if guard is active
- Reset guard on successful boot
```

**Go/No-Go Checklist:**
- [ ] boot_guard sourced
- [ ] Check performed before tuning
- [ ] Guard logic works
- [ ] Exit codes correct
- [ ] CI passes

**Estimated Effort:** 1 hour  
**Difficulty:** Easy

---

## STEP 11: Create core/safe_apply.sh — Safe Sysfs Write Mechanism

**Objective:**  
Implement atomic sysfs writes with backup, verification, and rollback capability.

**Files to create:**
- `core/safe_apply.sh`

**Requirements:**
- [ ] Create `safe_sysfs_write(path, value, category)` function
  - Backup original value to `/data/adb/hsin/backup/applied_${timestamp}.conf`
  - Write value to sysfs path
  - Verify written value matches target
  - Log result (APPLIED/FAILED/SKIPPED)
  - Return 0 on success, 1 on failure

- [ ] Create `safe_apply_rollback(timestamp)` function
  - Find backup file for timestamp
  - Read and restore all original values in reverse order
  - Log restoration for each value

- [ ] Create `safe_apply_verify(timestamp)` function
  - Compare current sysfs values with expected values
  - Report mismatches
  - Return 0 if all match, 1 if any mismatch

**Acceptance Criteria:**
- [ ] All 3 functions created
- [ ] Backup created before writes
- [ ] Verification works
- [ ] Rollback restores original values
- [ ] ShellCheck: 0 errors

**Commit Message:**
```
feat: safe sysfs write mechanism with rollback (Phase 2.2, Step 11)

- Atomic sysfs writes with backup before modification
- Verify written values match target
- Rollback capability to restore original values
- Full logging of all operations
- ShellCheck: 0 errors
```

**Go/No-Go Checklist:**
- [ ] All functions created
- [ ] Backup logic works
- [ ] Verification logic works
- [ ] Rollback restores values
- [ ] ShellCheck passes
- [ ] CI passes

**Estimated Effort:** 2-3 hours  
**Difficulty:** Medium-Hard

---

## STEPS 12-18: Migrate Engines to safe_apply

**Objective:**  
Update all engine apply scripts to use `safe_sysfs_write()` instead of direct `echo` writes.

**Pattern:**
Replace all instances of:
```bash
echo "$value" > "$path" 2>/dev/null
```

With:
```bash
safe_sysfs_write "$path" "$value" "CATEGORY"
```

**Files to modify (one step each):**
- STEP 12: `engine/cpu/apply.sh`
- STEP 13: `engine/gpu/apply.sh`
- STEP 14: `engine/thermal/apply.sh`
- STEP 15: `engine/memory/apply.sh`
- STEP 16: `engine/io/apply.sh`
- STEP 17: `engine/network/apply.sh`
- STEP 18: `engine/display/apply.sh`

**For each step:**
- [ ] Replace all direct writes with safe_sysfs_write
- [ ] Add category labels (CPU, GPU, THERMAL, MEMORY, IO, NETWORK, DISPLAY)
- [ ] Update logging to show APPLIED/FAILED/SKIPPED
- [ ] ShellCheck passes
- [ ] CI passes

**Acceptance Criteria (per step):**
- [ ] All writes use safe_sysfs_write
- [ ] Logging shows results
- [ ] CI passes
- [ ] No functional breakage

**Commit Messages:**
```
refactor: migrate engine/cpu/apply.sh to safe_apply (Phase 2.2, Step 12)
refactor: migrate engine/gpu/apply.sh to safe_apply (Phase 2.2, Step 13)
... (etc)
```

**Go/No-Go Checklist (each step):**
- [ ] Writes replaced
- [ ] Logging updated
- [ ] ShellCheck passes
- [ ] CI passes

**Estimated Effort (per step):** 1-2 hours  
**Difficulty (per step):** Easy-Medium

---

## STEP 19: Implement Graceful Degradation Pattern

**Objective:**  
Ensure engine failures don't abort module. Each engine returns partial success if any writes succeeded.

**Files to modify:**
- All `engine/*/apply.sh` files
- `service.sh` (update engine call logic)

**Requirements:**
- [ ] Each engine function tracks `applied_count` and `failed_count`
- [ ] Loop through targets (policies, nodes, etc.)
- [ ] On individual item failure: log SKIPPED, continue (don't exit)
- [ ] After loop: log "Applied=$applied_count Failed=$failed_count"
- [ ] Return 0 if `applied_count > 0` (partial success OK)
- [ ] Return 1 only if `applied_count = 0` (total failure)

- [ ] In service.sh: catch engine exit codes
  - If engine returns 1 (fail): log warning, continue with next engine
  - If engine returns 0 (ok or partial): continue normally

**Acceptance Criteria:**
- [ ] Each engine has applied/failed counters
- [ ] Partial success = return 0
- [ ] Total failure = return 1
- [ ] service.sh doesn't abort on engine fail
- [ ] Logging shows partial success details
- [ ] CI passes

**Commit Message:**
```
refactor: graceful degradation per engine (Phase 2.3, Step 19)

- Track applied_count and failed_count per engine
- Skip individual items on failure, continue with others
- Return 0 if any items applied (partial success OK)
- Return 1 only if zero items applied (total fail)
- Update service.sh to continue on engine failures
- Log detailed results for debugging
```

**Go/No-Go Checklist:**
- [ ] Counters implemented
- [ ] Skip logic works
- [ ] Return codes correct
- [ ] service.sh updated
- [ ] Logging detailed
- [ ] CI passes

**Estimated Effort:** 2 hours  
**Difficulty:** Medium

---

## PHASE 2 COMPLETE ✅

After **STEP 19**, Phase 2 is complete.  
Next: Phase 3 (Multi-Device Support)

---

## STEP 20: Enhance core/detector.sh — Load Device Overrides

**Objective:**  
Create `load_device_overrides()` function that reads `device_overrides.json` and exports detected device's override variables.

**Files to modify:**
- `core/detector.sh`

**Requirements:**
- [ ] Create `load_device_overrides()` function
  - Determine device key from `$SOC_VENDOR` (normalize to lowercase)
  - Parse `capability/device_overrides.json` (use jq or awk/sed)
  - Extract override values for detected device
  - Export as environment variables:
    - `DEVICE_GPU_FREQ_BATTERY`, `DEVICE_GPU_FREQ_BALANCED`, etc.
    - `DEVICE_THERMAL_SAFE_MODE`
    - `DEVICE_THERMAL_HEADROOM`
  - Log loaded values

- [ ] Integrate into `hsin_detect_all()`
  - Call `load_device_overrides()` after SoC/GPU detection
  - Cache overrides to detected.conf

**Acceptance Criteria:**
- [ ] load_device_overrides() works
- [ ] Reads device_overrides.json
- [ ] Exports correct variables
- [ ] Logs values for debugging
- [ ] ShellCheck: 0 errors

**Commit Message:**
```
feat: device override loader (Phase 3.1, Step 20)

- Parse device_overrides.json for detected SoC
- Export per-device GPU freq caps and thermal settings
- Cache overrides to detected.conf
- Log loaded values for verification
```

**Go/No-Go Checklist:**
- [ ] load_device_overrides() created
- [ ] JSON parsing works
- [ ] Variables exported
- [ ] Logging works
- [ ] ShellCheck passes
- [ ] CI passes

**Estimated Effort:** 1-2 hours  
**Difficulty:** Medium

---

## STEP 21: Create core/thermal_check.sh — Runtime Thermal Monitoring

**Objective:**  
Implement thermal pre-check before aggressive tuning. Skip performance/extreme caps if device is already hot.

**Files to create:**
- `core/thermal_check.sh`

**Requirements:**
- [ ] Create `thermal_get_current_temp()` function
  - Read current temp from `$THERMAL_PATH` (set by detector)
  - Handle multiple thermal zones (fallback logic)
  - Return temp in Celsius

- [ ] Create `thermal_is_safe(profile)` function
  - Get current temp
  - Look up allowed max from `capability/thermal_safety.json`
  - Return 0 if current <= allowed, 1 if hot

- [ ] Create `thermal_auto_rollback(timestamp)` function
  - Monitor temp while tuning active
  - If exceeds critical (>100°C): call rollback
  - Log thermal emergency

**Acceptance Criteria:**
- [ ] Thermal checks work
- [ ] Reads correct temperature
- [ ] Compares against limits
- [ ] Rollback triggered on critical
- [ ] ShellCheck: 0 errors

**Commit Message:**
```
feat: thermal safety monitoring (Phase 3.2, Step 21)

- Read current temperature before tuning
- Check if current temp exceeds profile limit
- Skip aggressive tuning if device is hot
- Auto-rollback if temp exceeds critical (>100°C)
- Full logging of thermal state
```

**Go/No-Go Checklist:**
- [ ] Thermal functions created
- [ ] Temp reading works
- [ ] Safety checks work
- [ ] Auto-rollback works
- [ ] ShellCheck passes
- [ ] CI passes

**Estimated Effort:** 2 hours  
**Difficulty:** Medium

---

## STEPS 22-27: Documentation Creation

**Objective:**  
Create comprehensive documentation for users, developers, and QA.

### STEP 22: Create README.md
- Installation, features, profiles, supported devices
- Logs location, troubleshooting, uninstall
- **Estimated Effort:** 2-3 hours

### STEP 23: Create TESTING.md
- Testing framework, test cases, report template
- Pre-flash baseline, functional tests, stability tests
- **Estimated Effort:** 2 hours

### STEP 24: Create TROUBLESHOOTING.md
- Common issues: slow boot, thermal throttle, GPU stuck
- Debug steps for each issue
- **Estimated Effort:** 1-2 hours

### STEP 25: Create DEVICE_COMPATIBILITY.md
- Per-device notes (T615, Snapdragon, MediaTek, Exynos)
- Known issues, workarounds, optimizations
- **Estimated Effort:** 1-2 hours

### STEP 26: Create API.md
- For modders: extending profiles, detection, tweaks
- Function signatures, env variables, examples
- **Estimated Effort:** 1-2 hours

### STEP 27: Create CHANGELOG.md
- v5.0.0 changes, previous versions
- Feature highlights, bug fixes
- **Estimated Effort:** 1 hour

---

## PHASE 3 & 4 COMPLETE ✅

After **STEP 27**, Phase 3-4 (multi-device & docs) complete.  
Next: Phase 5 (QA & Release)

---

## STEPS 28-30: QA & Release Prep

### STEP 28: Create QA_CHECKLIST.md
- Code quality, build quality, device testing
- Functional testing, stability testing
- **Estimated Effort:** 1 hour

### STEP 29: Create RELEASE_NOTES.md
- v5.0.0 headline, major features, device support
- Known limitations
- **Estimated Effort:** 1 hour

### STEP 30: Create SUPPORT_POLICY.md
- Response SLA, support channels
- Compatibility matrix
- **Estimated Effort:** 30 minutes

---

## STEP 31: Final Status Update

**Objective:**  
Update STATUS.md to mark all phases complete and set release tag.

- [ ] Mark all 31 tasks complete
- [ ] Update progress bar to 100%
- [ ] Note: "Ready for v5.0.0 release"
- [ ] Commit: "docs: Phase 5 complete — ready for release"

---

## 🎯 EXECUTION SUMMARY

```
PHASE 1: Testing Infrastructure (Steps 1-8) — Ready to execute
├─ 1.1 Testing Framework (Steps 1-3) ✅ DONE
├─ 1.2 Device Detection (Steps 4-6) ⏳ NEXT
└─ 1.3 Build Validation (Steps 7-8) ⏳ PENDING

PHASE 2: Error Handling (Steps 9-19) — BLOCKED (wait Phase 1)
├─ 2.1 Boot Guard (Steps 9-10)
├─ 2.2 Safe Apply (Steps 11-18)
└─ 2.3 Graceful Degradation (Step 19)

PHASE 3: Multi-Device (Steps 20-21) — BLOCKED (wait Phase 2)
├─ 3.1 Device Overrides (Step 20)
└─ 3.2 Thermal Monitoring (Step 21)

PHASE 4: Documentation (Steps 22-27) — BLOCKED (wait Phase 3)
├─ README, TESTING, TROUBLESHOOTING
├─ DEVICE_COMPATIBILITY, API, CHANGELOG

PHASE 5: QA & Release (Steps 28-31) — BLOCKED (wait Phase 4)
├─ QA_CHECKLIST, RELEASE_NOTES, SUPPORT_POLICY
└─ Final status update
```

---

## 📝 HOW TO USE THIS FILE

1. **AI Agent:** Read current step section
2. **Execute:** Follow all requirements and acceptance criteria
3. **Commit:** Push with exact message format
4. **Notify:** Update STATUS.md checkbox and step status
5. **Repeat:** Move to next step

Example:
```
Human: "Execute Step 4"
AI: Reads STEP 4, modifies core/detector.sh, tests, commits
AI: Pushes to GitHub, CI runs
AI: Updates STATUS.md with [x] Task 1.2.1 DONE
Human: "Execute Step 5"
...
```

---

**Last Updated:** 2026-09-27  
**Total Steps:** 31  
**Phase 1 Progress:** 3/8 complete  
**Next:** STEP 4 — Enhance core/detector.sh
