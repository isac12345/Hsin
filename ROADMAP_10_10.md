# HSIN Roadmap → 10/10 (Stabil, Multi-Device, Production-Ready)

## Ringkasan Strategi

**Target:** HSIN v5.0.0 release-ready dengan 0 error, stabil di semua device, siap publik.

**Durasi:** ~4-6 minggu development (dengan CI/CD automation).

**Prioritas tinggi:**
1. Device testing & validation (T615, Snapdragon, MediaTek, Exynos)
2. Error handling & recovery
3. StaticAnalysis & testing automation
4. Documentation & user guides
5. Performance & bootup optimization

---

## Fase 1: Testing & Device Validation (Week 1-2)

### 1.1 Establish Testing Environment

**Goal:** Test HSIN di minimal 4 device classes.

#### Devices target:
```
[ PRIMARY ]
- Unisoc T615 (ums9230) — sudah ada
  API 34, Android 14, Mali GPU
  
[ SECONDARY - Snapdragon ]
- SDM888 (Flagship 2021)
- SDM695 (Mid-range 2021)
- SDM680 (Budget 2021)

[ SECONDARY - MediaTek ]
- Dimensity 9200 (Flagship)
- Dimensity 7050 (Mid-range)
- Helio G99 (Budget)

[ SECONDARY - Exynos ]
- Exynos 1280 (Mid-range)
- Exynos 2100 (Flagship)

[ ALTERNATIVE ]
- PowerVR (jika ada, misal iPad)
- Xclipse (Samsung S24 series)
```

#### Test procedure per device:

**Step 1: Pre-Flash Baseline**
```bash
# Catat baseline sebelum install
getprop ro.product.model
getprop ro.build.version.sdk
getprop ro.soc.model
uname -r                          # Kernel version
cat /proc/cpuinfo                 # CPU info
cat /sys/class/thermal/*/temp     # Thermal baseline
dumpsys battery                   # Battery baseline
```

**Step 2: Install & Boot**
```bash
# Flash HSIN dev di Magisk Manager
# Reboot
# Tunggu ~3 menit boot complete

# Cek modul active
adb shell getprop | grep hsin
adb shell ls -la /data/adb/modules/hsin/

# Baca log boot
adb shell cat /data/adb/hsin/logs/hsin.log | head -100
```

**Step 3: Functional testing**
- ✅ Profil switching (battery → balanced → performance → extreme)
- ✅ Thermal check (`cat /sys/class/thermal/thermal_zone0/temp`)
- ✅ CPU freq (cat `/sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq`)
- ✅ GPU status (Adreno: `/sys/class/kgsl/kgsl-3d0/`, Mali: `/sys/class/devfreq/*mali*`)
- ✅ Game boost enable/disable
- ✅ Rollback function

**Step 4: Stability test (30 mins)**
- Launch game (e.g., Genshin, PUBG, Honkai)
- Monitor CPU/GPU/Thermal setiap 5 menit
- Cek log untuk warning/error

**Step 5: Post-test cleanup**
```bash
# Uninstall & boot
adb shell su -c "rm -rf /data/adb/modules/hsin"
adb reboot
# Verifikasi restored ke normal
```

#### Test report template (`tests/device_reports/{device_name}.md`):

```markdown
# Test Report: {DEVICE_MODEL}

**Device Info:**
- Model: ...
- API: ...
- Kernel: ...
- SoC: ...

**Pre-Install Baseline:**
- Boot time: ...
- Thermal: ...

**Installation Result:**
- ✅/❌ Install OK
- ✅/❌ Boot OK
- ✅/❌ Module active
- Log issues: ...

**Functional Tests:**
| Feature | Status | Notes |
|---|---|---|
| Profile battery | ✅ | ... |
| Profile balanced | ✅ | ... |
| Profile performance | ✅ | ... |
| Profile extreme | ✅ | Thermal OK |
| Game boost | ✅ | ... |
| Rollback | ✅ | ... |

**30-min Stability Test:**
- Game: Genshin
- CPU throttle: None
- Thermal peak: 45°C
- Errors: None

**Verdict:** ✅ PASS / ⚠️ PARTIAL / ❌ FAIL
```

### 1.2 CI Test Automation

**Goal:** Otomatis test shell scripts tanpa device.

#### Add to `.github/workflows/lint-and-test.yml`:

```yaml
name: Lint & Test

on:
  push:
    branches: [ main, develop ]
    paths:
      - 'core/**'
      - 'engine/**'
      - 'extreme/**'
  pull_request:

jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      - name: Install ShellCheck
        run: sudo apt-get install -y shellcheck
      
      - name: ShellCheck all scripts
        run: |
          find core engine extreme bin -name '*.sh' -exec shellcheck {} +
          shellcheck action.sh customize.sh service.sh post-fs-data.sh uninstall.sh
      
      - name: Validate shell syntax
        run: |
          find . -name '*.sh' -exec sh -n {} \;
      
      - name: Check file permissions
        run: |
          # service.sh, action.sh, bin/hsin harus 0755
          test -x action.sh && test -x service.sh && test -x post-fs-data.sh
  
  test-sandbox:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      - name: Setup test environment
        run: |
          mkdir -p /tmp/hsin_sandbox/{sys,proc,data}
      
      - name: Run detector.sh (sandbox)
        env:
          MODPATH: /tmp/hsin_sandbox
        run: |
          # Sandbox test — validate functions tanpa write /sys
          sh -c 'ALPHA_DRYRUN=1 . ./core/detector.sh 2>&1 | head -20'
      
      - name: Test backup/rollback logic
        run: |
          # Validate awk/sed patterns untuk backup/restore
          echo "node=/sys/test value=123" | awk -F= '{print $1, $2}'
  
  check-integrity:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      - name: Verify all mandatory files
        run: |
          FILES=(
            "module.prop"
            "service.sh"
            "customize.sh"
            "post-fs-data.sh"
            "uninstall.sh"
            "action.sh"
            "core/protect.sh"
            "core/backup.sh"
            "engine/cpu/apply.sh"
            "engine/gpu/apply.sh"
            "engine/thermal/apply.sh"
          )
          for f in "${FILES[@]}"; do
            [ -f "$f" ] || { echo "MISSING: $f"; exit 1; }
          done
      
      - name: Check module.prop format
        run: |
          grep -q '^id=hsin$' module.prop || exit 1
          grep -q '^name=' module.prop || exit 1
          grep -q '^version=' module.prop || exit 1
          grep -q '^versionCode=' module.prop || exit 1
      
      - name: Validate JSON configs
        run: |
          python3 -m json.tool capability/cpu/governor.json > /dev/null
          python3 -m json.tool capability/gpu/mali.json > /dev/null
          python3 -m json.tool capability/thermal/zones.json > /dev/null
```

---

## Fase 2: Improve Error Handling & Recovery (Week 2-3)

### 2.1 Enhanced Boot Guard (Alpha pattern + own twist)

Di `service.sh`, tambah lebih robust boot guard:

```bash
# ===== HSIN BOOT GUARD v2 =====
HSIN_BOOT_GUARD_FILE="$HSIN_DATA/.boot_guard_count"
HSIN_BOOT_GUARD_THRESHOLD=3
HSIN_BOOT_GUARD_COOLDOWN=86400  # 24 jam

# Jika boot fail 3x dalam 24 jam, disable untuk 24 jam
read_boot_guard() {
    if [ -f "$HSIN_BOOT_GUARD_FILE" ]; then
        IFS=: read -r _timestamp _count < "$HSIN_BOOT_GUARD_FILE"
        _now=$(date +%s)
        _age=$((_now - _timestamp))
        if [ "$_age" -lt "$HSIN_BOOT_GUARD_COOLDOWN" ]; then
            printf '%d\n' "$_count"
            return 0
        fi
    fi
    printf '0\n'
    return 0
}

increment_boot_guard() {
    _now=$(date +%s)
    _count=$(read_boot_guard)
    _count=$((_count + 1))
    printf '%s:%s\n' "$_now" "$_count" > "$HSIN_BOOT_GUARD_FILE"
    if [ "$_count" -ge "$HSIN_BOOT_GUARD_THRESHOLD" ]; then
        touch "$HSIN_MODULE_PATH/disable"
        hsin_log_error "main" "Boot guard: $_count failures dalam 24h — module DISABLED"
        return 1
    fi
    return 0
}

clear_boot_guard() {
    rm -f "$HSIN_BOOT_GUARD_FILE"
}

# Di awal service.sh:
if [ "$(getprop sys.boot_completed)" != "1" ]; then
    if ! increment_boot_guard; then
        hsin_log_error "main" "Boot guard threshold exceeded. Module will re-enable after 24h or manual reset."
        exit 1
    fi
    # ... tunggu boot
else
    clear_boot_guard  # Reset jika boot OK
fi
```

### 2.2 Safe Apply Mechanism

Tambah `core/safe_apply.sh` untuk prevent data loss:

```bash
#!/system/bin/sh
# HSIN Safe Apply — Atomic sysfs writes dengan rollback

BACKUP_DIR="${HSIN_DATA}/backup"
APPLY_TIMESTAMP=$(date +%s)
APPLY_LOG="${HSIN_DATA}/logs/apply_${APPLY_TIMESTAMP}.log"

safe_sysfs_write() {
    local sysfs_path="$1"
    local target_value="$2"
    local category="$3"
    
    # 1. Backup original value
    if [ -r "$sysfs_path" ]; then
        local original_value
        original_value=$(cat "$sysfs_path" 2>/dev/null)
        mkdir -p "$BACKUP_DIR"
        echo "$sysfs_path:$original_value" >> "$BACKUP_DIR/rollback_${APPLY_TIMESTAMP}.conf"
    fi
    
    # 2. Write with verification
    if [ -w "$sysfs_path" ]; then
        if echo "$target_value" > "$sysfs_path" 2>/dev/null; then
            local verify_value
            verify_value=$(cat "$sysfs_path" 2>/dev/null)
            if [ "$verify_value" = "$target_value" ]; then
                hsin_log_ok "safe_apply" "✓ $sysfs_path = $target_value"
                return 0
            else
                hsin_log_warn "safe_apply" "⚠ Write mismatch: wrote=$target_value, read=$verify_value"
                return 1
            fi
        else
            hsin_log_error "safe_apply" "✗ Write failed: $sysfs_path (permission denied)"
            return 1
        fi
    else
        chmod 644 "$sysfs_path" 2>/dev/null
        if echo "$target_value" > "$sysfs_path" 2>/dev/null; then
            hsin_log_ok "safe_apply" "✓ $sysfs_path = $target_value (chmod'd)"
            return 0
        else
            hsin_log_error "safe_apply" "✗ $sysfs_path not writable even after chmod"
            return 1
        fi
    fi
}

rollback_apply() {
    local timestamp="$1"
    local rollback_conf="$BACKUP_DIR/rollback_${timestamp}.conf"
    
    if [ ! -f "$rollback_conf" ]; then
        hsin_log_warn "rollback" "Rollback conf not found: $rollback_conf"
        return 1
    fi
    
    while IFS=: read -r path value; do
        if [ -n "$path" ] && [ -n "$value" ]; then
            echo "$value" > "$path" 2>/dev/null && \
                hsin_log_ok "rollback" "✓ Restored $path = $value"
        fi
    done < "$rollback_conf"
}
```

### 2.3 Graceful Degradation per Engine

Setiap engine (`engine/cpu/apply.sh`, `engine/gpu/apply.sh`, dll) harus:

1. **Isolate function** — if CPU engine fails, GPU/thermal tetap jalan
2. **Partial success OK** — jika 5/10 nodes applied, log "partial success"
3. **No crash on missing nodes** — skip dengan aman

Contoh `engine/cpu/apply.sh`:

```bash
#!/system/bin/sh
# CPU Engine — Graceful degradation

hsin_cpu_apply() {
    local profile="$1"
    local cpu_applied=0
    local cpu_failed=0
    
    hsin_log_section "CPU Engine Apply ($profile)"
    
    # 1. Detect CPU policies
    local cpu_policies=""
    if [ -d /sys/devices/system/cpu/cpufreq ]; then
        cpu_policies=$(ls -d /sys/devices/system/cpu/cpufreq/policy* 2>/dev/null | xargs -n1 basename)
    fi
    
    if [ -z "$cpu_policies" ]; then
        hsin_log_warn "cpu" "No CPU policies detected, CPU tuning skipped"
        return 0  # Not a failure — device just doesn't have it
    fi
    
    # 2. Per-profile governor selection
    case "$profile" in
        battery)
            cpu_gov_pref="powersave schedutil"
            cpu_freq_max=70
            ;;
        balanced)
            cpu_gov_pref="schedutil conservative"
            cpu_freq_max=100
            ;;
        performance)
            cpu_gov_pref="performance schedutil"
            cpu_freq_max=100
            ;;
        extreme)
            cpu_gov_pref="performance"
            cpu_freq_max=100
            ;;
        *)
            hsin_log_error "cpu" "Unknown profile: $profile"
            return 1
            ;;
    esac
    
    # 3. Apply governor per policy
    for pol in $cpu_policies; do
        local gov_node="/sys/devices/system/cpu/cpufreq/$pol/scaling_governor"
        local avail_file="/sys/devices/system/cpu/cpufreq/$pol/scaling_available_governors"
        
        if [ ! -f "$avail_file" ]; then
            hsin_log_skip "cpu" "Policy $pol: no available_governors file"
            cpu_failed=$((cpu_failed + 1))
            continue
        fi
        
        local avail_govs
        avail_govs=$(cat "$avail_file" 2>/dev/null)
        
        local selected_gov=""
        for candidate in $cpu_gov_pref; do
            case " $avail_govs " in
                *" $candidate "*)
                    selected_gov="$candidate"
                    break
                    ;;
            esac
        done
        
        if [ -z "$selected_gov" ]; then
            hsin_log_warn "cpu" "Policy $pol: no preferred governor available (available: $avail_govs)"
            cpu_failed=$((cpu_failed + 1))
            continue
        fi
        
        if safe_sysfs_write "$gov_node" "$selected_gov" "CPU_GOV"; then
            cpu_applied=$((cpu_applied + 1))
        else
            cpu_failed=$((cpu_failed + 1))
        fi
    done
    
    # 4. Apply frequency cap
    for pol in $cpu_policies; do
        local max_node="/sys/devices/system/cpu/cpufreq/$pol/scaling_max_freq"
        local cpuinfo_max="/sys/devices/system/cpu/cpufreq/$pol/cpuinfo_max_freq"
        local avail_file="/sys/devices/system/cpu/cpufreq/$pol/scaling_available_frequencies"
        
        if [ ! -f "$cpuinfo_max" ]; then
            continue
        fi
        
        local hw_max
        hw_max=$(cat "$cpuinfo_max" 2>/dev/null)
        local target_freq=$(( (hw_max / 100) * cpu_freq_max ))
        
        # Pick nearest available frequency
        if [ -f "$avail_file" ]; then
            local target_freq_nearest
            target_freq_nearest=$(cat "$avail_file" | tr ' ' '\n' | awk -v target="$target_freq" '$0 <= target {best=$0} END {print best}')
            [ -n "$target_freq_nearest" ] && target_freq="$target_freq_nearest"
        fi
        
        if safe_sysfs_write "$max_node" "$target_freq" "CPU_FREQ"; then
            cpu_applied=$((cpu_applied + 1))
        else
            cpu_failed=$((cpu_failed + 1))
        fi
    done
    
    hsin_log_info "cpu" "CPU engine: $cpu_applied applied, $cpu_failed partial/failed"
    
    # Return success if ANY applied
    [ "$cpu_applied" -gt 0 ] && return 0 || return 1
}

return 0 2>/dev/null || true
```

### 2.4 Per-Device Profile Overrides

Tambah `capability/device_overrides.json`:

```json
{
  "overrides": {
    "unisoc_t615": {
      "description": "Unisoc T615 (ums9230) — Mali GPU, conservative thermals",
      "cpu_governor_preference": ["schedutil", "powersave"],
      "gpu_freq_max_percent_battery": 60,
      "gpu_freq_max_percent_balanced": 85,
      "gpu_freq_max_percent_performance": 100,
      "thermal_safe_mode": true,
      "extreme_thermal_headroom_percent": 85
    },
    "snapdragon_888": {
      "description": "Snapdragon 888 — Adreno GPU, aggressive thermals possible",
      "cpu_governor_preference": ["performance", "schedutil"],
      "gpu_freq_max_percent_battery": 70,
      "gpu_freq_max_percent_performance": 100,
      "thermal_safe_mode": false,
      "extreme_thermal_headroom_percent": 80
    },
    "dimensity_9200": {
      "description": "MediaTek Dimensity 9200",
      "cpu_governor_preference": ["schedutil", "conservative"],
      "thermal_safe_mode": false
    },
    "exynos_1280": {
      "description": "Exynos 1280 — Mali GPU",
      "thermal_safe_mode": true
    },
    "powervr": {
      "description": "PowerVR GPU — tuning belum supported",
      "gpu_skip": true
    },
    "xclipse": {
      "description": "Xclipse GPU (Samsung) — tuning belum supported",
      "gpu_skip": true
    }
  }
}
```

Dan di `core/detector.sh`, load overrides:

```bash
load_device_overrides() {
    local override_file="$HSIN_MODULE_PATH/capability/device_overrides.json"
    [ -f "$override_file" ] || return 0
    
    # Parse JSON untuk SOC yang terdeteksi
    local device_key=$(echo "$SOC_VENDOR" | tr '[:upper:]' '[:lower:]')
    # ... parse JSON dan export override variables
}
```

---

## Fase 3: Multi-Device Compatibility (Week 3)

### 3.1 Comprehensive Chipset Detection

Perbarui `core/detector.sh` untuk cover semua major chipsets:

```bash
#!/system/bin/sh
# HSIN Device Detector — Support 99% Android devices

detect_soc() {
    local soc_vendor="UNKNOWN"
    local soc_model="UNKNOWN"
    local gpu_vendor="UNKNOWN"
    
    # 1. Cek Qualcomm
    if getprop ro.soc.model | grep -q "sm\|sd\|msm" 2>/dev/null; then
        soc_vendor="QUALCOMM"
        soc_model=$(getprop ro.soc.model 2>/dev/null || getprop ro.board.platform 2>/dev/null)
        gpu_vendor="ADRENO"
    fi
    
    # 2. Cek MediaTek
    if getprop ro.vendor.extension_library | grep -q "mtk\|libmt" 2>/dev/null; then
        soc_vendor="MEDIATEK"
        soc_model=$(getprop ro.vendor.mediatek.platform 2>/dev/null || getprop ro.soc.model)
        gpu_vendor="MALI"
    fi
    
    # 3. Cek Samsung Exynos
    if [ -f /sys/devices/virtual/dmi/id/system_vendor ] && \
       grep -q "samsung" /sys/devices/virtual/dmi/id/system_vendor 2>/dev/null; then
        soc_vendor="EXYNOS"
        soc_model=$(getprop ro.soc.model)
        # Exynos pake Mali mostly, tapi ada juga Xclipse
        if [ -f /sys/class/kgsl/kgsl-3d0 ]; then
            gpu_vendor="ADRENO"
        elif [ -d /sys/devices/platform/13b40000.gpu ] || grep -q "xclipse" /proc/device-tree/compatible 2>/dev/null; then
            gpu_vendor="XCLIPSE"
        else
            gpu_vendor="MALI"
        fi
    fi
    
    # 4. Cek Apple (jika bootloader membolehkan)
    if grep -q "apple" /proc/device-tree/compatible 2>/dev/null; then
        soc_vendor="APPLE"
        soc_model=$(getprop ro.soc.model || echo "Apple-SoC")
        gpu_vendor="APPLE"
    fi
    
    # 5. Cek Unisoc (T615, T618, dll)
    if getprop ro.board.platform | grep -q "ums\|unisoc" 2>/dev/null; then
        soc_vendor="UNISOC"
        soc_model=$(getprop ro.board.platform)
        gpu_vendor="MALI"
    fi
    
    # 6. Fallback: cek GPU presence
    if [ -f /sys/class/kgsl/kgsl-3d0 ]; then
        [ "$gpu_vendor" = "UNKNOWN" ] && gpu_vendor="ADRENO"
    elif ls /sys/class/devfreq/*mali* >/dev/null 2>&1; then
        [ "$gpu_vendor" = "UNKNOWN" ] && gpu_vendor="MALI"
    elif ls /sys/devices/platform/*powervr* >/dev/null 2>&1 || \
         grep -q "powervr" /proc/device-tree/compatible 2>/dev/null; then
        gpu_vendor="POWERVR"
    fi
    
    export SOC_VENDOR="$soc_vendor"
    export SOC_MODEL="$soc_model"
    export GPU_VENDOR="$gpu_vendor"
    
    hsin_log_info "detect" "SoC=$soc_vendor Model=$soc_model GPU=$gpu_vendor"
}

detect_cpu_policies() {
    local policies=""
    if [ -d /sys/devices/system/cpu/cpufreq ]; then
        policies=$(ls -d /sys/devices/system/cpu/cpufreq/policy* 2>/dev/null | xargs -n1 basename | sort)
    fi
    [ -z "$policies" ] && {
        hsin_log_warn "detect" "No CPU policies found (CPU tuning unavailable)"
        return 1
    }
    export CPU_POLICIES="$policies"
    hsin_log_info "detect" "CPU Policies: $policies"
}

detect_gpu_paths() {
    case "$GPU_VENDOR" in
        ADRENO)
            export GPU_SYSFS_PREFIX="/sys"
            export GPU_DEVFREQ_PATH="/sys/class/devfreq/qcom,kgsl-3d0"
            ;;
        MALI)
            # Mali devfreq bisa di berbagai path
            for path in /sys/class/devfreq/*mali* /sys/devices/platform/*mali*/devfreq/*; do
                if [ -d "$path" ]; then
                    export GPU_DEVFREQ_PATH="$path"
                    break
                fi
            done
            ;;
        POWERVR)
            hsin_log_info "detect" "PowerVR GPU detected — tuning limited"
            ;;
        XCLIPSE)
            hsin_log_info "detect" "Xclipse GPU detected — tuning limited"
            ;;
        *)
            hsin_log_warn "detect" "GPU vendor unknown"
            ;;
    esac
}

detect_storage_devices() {
    local devices=""
    if [ -d /sys/block ]; then
        devices=$(ls -d /sys/block/mmcblk* /sys/block/sda* 2>/dev/null | xargs -n1 basename | sort -u)
    fi
    [ -z "$devices" ] && devices="mmcblk0"  # Fallback
    export STORAGE_DEVICES="$devices"
    hsin_log_info "detect" "Storage devices: $devices"
}

detect_thermal_zones() {
    # Find main thermal zone (biasanya GPU atau SoC temp)
    local thermal_path=""
    for tz in /sys/class/thermal/thermal_zone*; do
        [ -d "$tz" ] || continue
        local type
        type=$(cat "$tz/type" 2>/dev/null)
        case "$type" in
            *gpu*|*soc*|*tsens*) thermal_path="$tz/temp"; break ;;
        esac
    done
    [ -n "$thermal_path" ] && export THERMAL_PATH="$thermal_path"
    export THERMAL_SUPPORTED=1
}

# Main
hsin_detect_all() {
    detect_soc
    detect_cpu_policies
    detect_gpu_paths
    detect_storage_devices
    detect_thermal_zones
    
    # Cache hasil detection
    mkdir -p "$HSIN_DATA"
    {
        echo "SOC_VENDOR=$SOC_VENDOR"
        echo "SOC_MODEL=$SOC_MODEL"
        echo "GPU_VENDOR=$GPU_VENDOR"
        echo "CPU_POLICIES=$CPU_POLICIES"
        echo "GPU_DEVFREQ_PATH=${GPU_DEVFREQ_PATH:-}"
        echo "THERMAL_PATH=${THERMAL_PATH:-}"
    } > "$HSIN_DATA/detected.conf"
    
    hsin_log_ok "detect" "Device detection complete"
}
```

### 3.2 Thermal Safety Matrix

Buat `capability/thermal_safety.json`:

```json
{
  "thermal_zones": {
    "gpu": {
      "critical_temp_c": 100,
      "warn_temp_c": 75,
      "battery_mode_cap_temp_c": 50,
      "balanced_mode_cap_temp_c": 65,
      "performance_mode_cap_temp_c": 80,
      "extreme_mode_cap_temp_c": 85
    },
    "cpu": {
      "critical_temp_c": 110,
      "warn_temp_c": 85,
      "battery_mode_cap_temp_c": 55,
      "balanced_mode_cap_temp_c": 70,
      "performance_mode_cap_temp_c": 85,
      "extreme_mode_cap_temp_c": 95
    },
    "soc": {
      "critical_temp_c": 120,
      "warn_temp_c": 90
    }
  },
  "throttle_response": {
    "cpu_freq_reduce_on_critical": 50,
    "gpu_freq_reduce_on_critical": 40,
    "watchdog_check_interval_ms": 5000,
    "recovery_delay_after_cool_ms": 30000
  }
}
```

---

## Fase 4: Automation & Documentation (Week 3-4)

### 4.1 README.md yang Comprehensive

```markdown
# HSIN v5.0.0 — Universal Adaptive Performance Engine

## Quick Start

**Requirements:**
- Android 11+ (API 30+)
- Magisk 20.4+
- ARM64 architecture
- 100MB free space

**Installation:**
1. Download HSIN-v5.0.0-release.zip
2. Flash via Magisk Manager
3. Reboot
4. Open companion app or check `/data/adb/hsin/logs/hsin.log`

## Supported Devices

| Chipset | Support Level | Status |
|---|---|---|
| Snapdragon 888+ | ✅ Tested | Stable |
| Snapdragon 765/768/778 | ✅ Tested | Stable |
| MediaTek Dimensity 9200 | ✅ Tested | Stable |
| MediaTek Helio G99 | ✅ Tested | Stable |
| Exynos 1280/1380 | ✅ Tested | Stable |
| Unisoc T615/T618 | ✅ Tested | Stable |
| Apple A-series | ⚠️ Partial | Tuning limited |
| PowerVR | ⚠️ Partial | Tuning limited |
| Xclipse | ⚠️ Partial | Tuning limited |

## Profiles

### Battery
- CPU: Powersave/Schedutil governor, 70% freq cap
- GPU: 60% freq cap
- Thermal: Strict 50°C limit
- Use: Light browsing, chat, reading

### Balanced
- CPU: Schedutil governor, 100% freq
- GPU: 85% freq cap
- Thermal: Normal 65°C threshold
- Use: Everyday mix of apps

### Performance
- CPU: Performance governor, 100% freq
- GPU: 100% freq cap
- Thermal: 80°C threshold, allows sustained boost
- Use: Gaming, heavy apps

### Extreme
- CPU: Performance, 100% freq
- GPU: 100% freq, aggressive polling (10ms)
- Thermal: 85°C headroom
- ⚠️ Higher temperature, higher power draw
- Use: Sustained intense gaming only
- Recovery: Automatic rollback if thermal >100°C

## Uninstall

**Safe removal:**
```bash
# Via Magisk Manager: toggle off, then uninstall
# Manual:
su -c "rm -rf /data/adb/modules/hsin /data/adb/hsin"
# Reboot
```

**Rollback:**
If settings corrupted, HSIN auto-detects and rolls back to pre-apply state.

## Advanced

### Manual Config Override

Edit `/sdcard/Android/hsin/hsin.conf`:

```ini
# Profile: battery | balanced | performance | extreme
PROFILE=balanced

# Thermal safety — 0=default, 1=strict
THERMAL_SAFE_MODE=0

# Log level: 1-4 (4=verbose)
LOG_LEVEL=3
```

### Logs

Check `/data/adb/hsin/logs/`:
- `hsin.log` — main boot/apply log
- `monitor.log` — real-time monitoring
- `thermal.log` — temperature tracking
- `error.log` — warnings/failures

### Troubleshooting

**Device boots slow after install:**
1. Uninstall HSIN
2. Reboot normally
3. If normal boot, issue is HSIN
4. Check log: `/data/adb/hsin/logs/hsin.log`

**Extreme mode thermal throttle:**
1. Use Performance profile instead
2. Reduce extreme_thermal_headroom in config

**GPU still capped at low freq:**
1. Check `/data/adb/hsin/detected.conf`
2. Verify GPU_VENDOR is correct
3. If unsupported GPU, try disabling GPU tuning

## Support

- **Issue tracker:** GitHub issues
- **Discussion:** GitHub discussions
- **Discord:** [Link]
- **Telegram:** [Link]

## Credits

- **HSIN core:** Somwan
- **Reference implementations:** Alpha, Uperf, UPerf community
- **Beta testers:** [Contributors]
```

### 4.2 Build Release Script

Perbarui `build_release.sh`:

```bash
#!/system/bin/sh
# ... existing build_release.sh logic ...

# Add final validation step
_validate_release_zip() {
    local zipfile="$1"
    echo "[validate] Checking $zipfile integrity..."
    
    # 1. Check mandatory files
    local mandatory=(
        "module.prop"
        "service.sh"
        "customize.sh"
        "post-fs-data.sh"
        "uninstall.sh"
        "action.sh"
        "core/protect.sh"
        "core/backup.sh"
        "engine/cpu/apply.sh"
        "engine/gpu/apply.sh"
        "engine/thermal/apply.sh"
        "core/runtime.sh"  # After compact
    )
    
    for f in "${mandatory[@]}"; do
        unzip -l "$zipfile" | grep -q " $f$" || {
            echo "  [FAIL] Missing: $f"
            return 1
        }
    done
    echo "  [OK] All mandatory files present"
    
    # 2. Check manifest integrity
    local manifest_ok=1
    unzip -p "$zipfile" core/.integrity.manifest | wc -l | grep -q "[1-9]" || manifest_ok=0
    [ "$manifest_ok" = "1" ] && echo "  [OK] Integrity manifest present" || echo "  [WARN] Manifest missing (dev build?)"
    
    # 3. Check max size
    local size_mb=$(du -m "$zipfile" | awk '{print $1}')
    if [ "$size_mb" -gt 50 ]; then
        echo "  [WARN] Large ZIP: ${size_mb}MB (expected <50MB)"
    else
        echo "  [OK] Size OK: ${size_mb}MB"
    fi
    
    echo "[validate] $zipfile validation PASSED"
    return 0
}

# Call sebelum upload
_validate_release_zip "$OUT_DIR/HSIN-${VERSION}.zip" || exit 1
```

---

## Fase 5: Testing Checklist & Release (Week 4-6)

### 5.1 QA Checklist

```markdown
# HSIN v5.0.0 Release QA Checklist

## Pre-Release (Internal)

- [ ] All mandatory files present
- [ ] ShellCheck: 0 errors
- [ ] Shell syntax: Valid (sh -n)
- [ ] JSON configs: Valid (python3 json.tool)
- [ ] Module.prop: Correct format
- [ ] Integrity manifest: Present & correct hash count
- [ ] Build log: 0 warnings
- [ ] ZIP size: <50MB
- [ ] Artifact: Signed/verified

## Device Testing (per device)

### Installation
- [ ] Flash OK via Magisk Manager
- [ ] Reboot OK, device boots normally
- [ ] Module active in Magisk
- [ ] `/data/adb/hsin/logs/hsin.log` exists, readable

### Functionality
- [ ] Profile switch battery → balanced → performance OK
- [ ] Profile switch performance → battery OK (reverse)
- [ ] Extreme mode applies without thermal exceeding 100°C
- [ ] App companion (AlphaBubble) installs
- [ ] Notifications working
- [ ] Game boost detects game launch
- [ ] Rollback restores previous config

### Stability
- [ ] 30min gaming (Genshin) without crash
- [ ] Battery drain acceptable (<5% in 30min idle)
- [ ] Thermal stays within limits per profile
- [ ] No bootloop after 5 consecutive reboots
- [ ] Log has no [ERROR] entries (only [WARN] OK)

### Edge Cases
- [ ] Reboot during apply (simulate: trigger apply, reboot immediately)
- [ ] Power off during apply (simulate: trigger apply, power down)
- [ ] Manual config corrupt (corrupt hsin.conf, reboot — auto-recovery expected)

### Uninstall
- [ ] Uninstall via Magisk OK
- [ ] Reboot after uninstall normal
- [ ] Device restored to pre-install state
- [ ] No residual files in `/data/adb/hsin/` after manual cleanup

## Post-Release (Community)

- [ ] Track reported issues (GitHub issues)
- [ ] Respond to first 10 reports within 24h
- [ ] Publish hotfix if critical bug found
- [ ] Update compatibility matrix based on reports
```

### 5.2 Multi-Device Testing Matrix

```yaml
# .github/workflows/multi-device-matrix.yml (manual trigger)
name: Multi-Device Testing Matrix

on:
  workflow_dispatch:
    inputs:
      device_list:
        description: "Comma-separated device names to test"
        required: true
        default: "T615,SD888,Dimensity9200"

jobs:
  test:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        device: ["T615", "SD888", "Dimensity9200", "Exynos1280"]
    steps:
      - uses: actions/checkout@v4
      
      - name: Generate test report for ${{ matrix.device }}
        run: |
          cat > tests/device_reports/${{ matrix.device }}-result.md << 'EOF'
          # Test Report: ${{ matrix.device }}
          
          **Status:** Awaiting tester
          **Tester:** [Link to manual test job]
          
          - [ ] Installation OK
          - [ ] Boot OK
          - [ ] Profile switching OK
          - [ ] Stability 30min OK
          - [ ] Uninstall OK
          EOF
      
      - name: Upload report
        uses: actions/upload-artifact@v4
        with:
          name: test-report-${{ matrix.device }}
          path: tests/device_reports/${{ matrix.device }}-result.md
```

---

## Fase 6: Post-Launch Maintenance (Ongoing)

### 6.1 Version Update Flow

```
v5.0.0 (Release)
    ↓
v5.0.1 (Hotfixes: critical bugs, Samsung OneUI fix, etc.)
    ↓
v5.1.0 (Feature: new device profile, new tuning option)
    ↓
v5.2.0 (Enhancement: WebUI, CLI tool)
    ↓
v6.0.0 (Major: merge with HSIN-specific features like extreme mode refinement)
```

### 6.2 Monitoring & Analytics

Track:
- Install count (via ModuleDB/Telegram bot)
- Error rate (via GitHub issue labels)
- Device compatibility (build matrix)
- Response time to user reports

```bash
# Monthly report:
echo "HSIN Monthly Report:"
echo "- Installs: $(curl -s api.magiskmodule.com/hsin/stats | jq .installs)"
echo "- Issues this month: $(gh issue list --repo isac12345/Hsin --created '>2026-09-01' --json number | jq length)"
echo "- Top issue: $(gh issue list --repo isac12345/Hsin --json title,reactions --sort reactions | head -1)"
```

---

## Summary Table: Jalan Menuju 10/10

| Fase | Fokus | Durasi | Hasil |
|---|---|---|---|
| **1** | Device Testing & CI | 2w | ✅ 4+ device tested, 0 lint errors |
| **2** | Error Handling | 1.5w | ✅ Boot guard, safe apply, graceful degradation |
| **3** | Multi-Device Support | 1w | ✅ 99% device coverage, override per-device |
| **4** | Automation & Docs | 1w | ✅ Full README, testing matrix, build validation |
| **5** | QA Release | 0.5w | ✅ Checklist passed, release ready |
| **6** | Maintenance | ∞ | ✅ Monthly updates, community support |
| | **TOTAL** | **4-6w** | **HSIN 10/10 ✅** |

---

## Implementasi Priority

### MUST (Minggu 1-2):
1. ✅ Device testing framework
2. ✅ Boot guard v2
3. ✅ Multi-chipset detection
4. ✅ ShellCheck CI

### SHOULD (Minggu 2-3):
5. ✅ Safe apply + rollback
6. ✅ Per-device overrides
7. ✅ Thermal matrix
8. ✅ Graceful degradation

### NICE-TO-HAVE (Minggu 4+):
9. ✅ WebUI/CLI tool
10. ✅ Advanced monitoring
11. ✅ Custom ROM support
12. ✅ Per-app profiles

---

## Kesimpulan

**HSIN bisa jadi 10/10** dengan fokus pada:
- **Device compatibility** (testing real hardware)
- **Error handling** (boot guard, graceful degradation)
- **Automation** (CI/CD testing)
- **Documentation** (user guides, troubleshooting)

Bukan tentang menambah fitur, tapi tentang **stability, reliability, dan universal support**.

Estimate: **4-6 minggu** untuk produksi-ready v5.0.0.

**Good luck! 🚀**
