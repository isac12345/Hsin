#!/system/bin/sh
# HSIN Capability Scanner (Dual Mode)

[ -z "$HSIN_MODULE_PATH" ] && HSIN_MODULE_PATH="/data/adb/modules/hsin"
. "$HSIN_MODULE_PATH/core/sysfs.sh" 2>/dev/null
HSIN_DATA="${HSIN_DATA:-/data/adb/hsin}"
HSIN_CAP_DIR="$HSIN_MODULE_PATH/capability"
HSIN_REPORT_DIR="$HSIN_DATA/reports"
HSIN_CAP_REPORT="$HSIN_REPORT_DIR/capability_report.json"

mkdir -p "$HSIN_REPORT_DIR" 2>/dev/null

# Load dependencies
. "$HSIN_MODULE_PATH/core/logger.sh" 2>/dev/null
. "$HSIN_MODULE_PATH/core/root_check.sh" 2>/dev/null
. "$HSIN_MODULE_PATH/core/hardware.sh" 2>/dev/null

# --- Detection helpers ---

# Check if any path matching glob exists
_scan_glob() {
    _count=0
    for _p in $1; do
        [ -e "$_p" ] && _count=$((_count + 1))
    done
    echo "$_count"
}

# Check if a node exists and is readable
_scan_readable() {
    [ -f "$1" ] && [ -r "$1" ] && echo "true" || echo "false"
}

# Check if a node exists, is readable, and writable
_scan_writable() {
    [ -f "$1" ] && [ -r "$1" ] && [ -w "$1" ] && echo "true" || echo "false"
}

# Check if any node in a list is writable
_scan_any_writable() {
    for _n in "$@"; do
        [ -f "$_n" ] && [ -w "$_n" ] && { echo "true"; return; }
    done
    echo "false"
}

# Check writability via root (su -c)
_scan_writable_root() {
    _path="$1"
    [ -e "$_path" ] || { echo "false"; return; }
    # If already writable, skip root
    [ -w "$_path" ] && { echo "true"; return; }
    # Try with root
    su -c "[ -w '$_path' ]" 2>/dev/null && echo "true" || echo "false"
}

# --- Per-category scanners ---

_scan_cpu() {
    _cpufreq_exists="false"
    _governor_exists="false"
    _schedutil_exists="false"
    _cpuset_exists="false"

    # cpufreq: check if any policy directory exists
    _count=$(_scan_glob "/sys/devices/system/cpu/cpufreq/policy*")
    [ "$_count" -gt 0 ] && _cpufreq_exists="true"

    # governor: check if scaling_governor is readable anywhere
    if [ "$_cpufreq_exists" = "true" ]; then
        for _p in /sys/devices/system/cpu/cpufreq/policy*; do
            [ -f "$_p/scaling_governor" ] && [ -r "$_p/scaling_governor" ] && {
                _governor_exists="true"
                _cur_gov=$(cat "$_p/scaling_governor" 2>/dev/null)
                [ "$_cur_gov" = "schedutil" ] && _schedutil_exists="true"
                break
            }
        done
    fi

    # cpuset: check /dev/cpuset
    [ -d "/dev/cpuset" ] && _cpuset_exists="true"

    # Write support (root-aware)
    _cpufreq_writable="false"
    _governor_writable="false"
    _cpuset_writable="false"

    if [ "$_cpufreq_exists" = "true" ]; then
        for _p in /sys/devices/system/cpu/cpufreq/policy*; do
            [ -w "$_p/scaling_min_freq" ] && _cpufreq_writable="true" && break
        done
    fi
    if [ "$_governor_exists" = "true" ]; then
        for _p in /sys/devices/system/cpu/cpufreq/policy*; do
            [ -w "$_p/scaling_governor" ] && _governor_writable="true" && break
        done
    fi
    if [ "$_cpuset_exists" = "true" ]; then
        [ -w "/dev/cpuset/top-app/cpus" ] && _cpuset_writable="true"
    fi

    # Score
    _total=0; _avail=0
    for _v in "$_cpufreq_exists" "$_governor_exists" "$_cpuset_exists"; do
        _total=$((_total + 1))
        [ "$_v" = "true" ] && _avail=$((_avail + 1))
    done
    [ "$_total" -gt 0 ] && _score=$((100 * _avail / _total)) || _score=0

    echo "  \"cpu\": {"
    echo "    \"cpufreq\": $_cpufreq_exists,"
    echo "    \"cpufreq_writable\": $_cpufreq_writable,"
    echo "    \"governor\": $_governor_exists,"
    echo "    \"governor_writable\": $_governor_writable,"
    echo "    \"schedutil\": $_schedutil_exists,"
    echo "    \"cpuset\": $_cpuset_exists,"
    echo "    \"cpuset_writable\": $_cpuset_writable,"
    echo "    \"score\": $_score"
    echo "  }"
}

_scan_gpu() {
    _mali="false"
    _adreno="false"
    _generic="false"

    # Mali: /sys/class/devfreq/*mali* or /sys/devices/platform/*mali*
    _mali_count=$(_scan_glob "/sys/class/devfreq/*mali*")
    _mali_plat=$(_scan_glob "/sys/devices/platform/*mali*")
    [ "$_mali_count" -gt 0 ] || [ "$_mali_plat" -gt 0 ] && _mali="true"

    # Adreno: /sys/class/kgsl/kgsl-3d0
    [ -d "/sys/class/kgsl/kgsl-3d0" ] && _adreno="true"

    # Generic: /sys/class/devfreq/*gpu*
    _generic_count=0
    for _d in /sys/class/devfreq/*; do
        [ -d "$_d" ] || continue
        hsin_devfreq_gpu_candidate "$_d" && _generic_count=$((_generic_count + 1))
    done
    [ "$_generic_count" -gt 0 ] && _generic="true"

    # Write support
    _mali_w="false"; _adreno_w="false"; _generic_w="false"
    if [ "$_mali" = "true" ]; then
        for _d in /sys/class/devfreq/*mali*; do
            [ -w "$_d/max_freq" ] && _mali_w="true" && break
        done 2>/dev/null
    fi
    if [ "$_adreno" = "true" ]; then
        [ -w "/sys/class/kgsl/kgsl-3d0/devfreq/max_freq" ] && _adreno_w="true"
    fi
    if [ "$_generic" = "true" ]; then
        for _d in /sys/class/devfreq/*gpu*; do
            [ -w "$_d/max_freq" ] && _generic_w="true" && break
        done 2>/dev/null
    fi

    # Score
    _score=0
    [ "$_mali" = "true" ] && _score=70
    [ "$_adreno" = "true" ] && _score=80
    [ "$_generic" = "true" ] && [ "$_score" -eq 0 ] && _score=50
    [ "$_mali_w" = "true" ] || [ "$_adreno_w" = "true" ] || [ "$_generic_w" = "true" ] && _score=$((_score + 20))
    [ "$_score" -gt 100 ] && _score=100

    echo "  \"gpu\": {"
    echo "    \"mali\": $_mali,"
    echo "    \"mali_writable\": $_mali_w,"
    echo "    \"adreno\": $_adreno,"
    echo "    \"adreno_writable\": $_adreno_w,"
    echo "    \"generic_devfreq\": $_generic,"
    echo "    \"generic_writable\": $_generic_w,"
    echo "    \"score\": $_score"
    echo "  }"
}

_scan_thermal() {
    _zones="false"
    _hal="false"
    _safe="false"

    # Thermal zones
    _zone_count=$(_scan_glob "/sys/class/thermal/thermal_zone*")
    [ "$_zone_count" -gt 0 ] && _zones="true"

    # Thermal HAL / vendor specific
    [ -d "/sys/devices/virtual/thermal/thermal_message" ] && _hal="true"
    [ -d "/sys/kernel/eara_thermal" ] && _hal="true"
    [ -d "/proc/mtk_batoc_throttling" ] && _hal="true"

    # Safe policy (trip points readable)
    if [ "$_zones" = "true" ]; then
        for _z in /sys/class/thermal/thermal_zone*; do
            [ -f "$_z/trip_point_0_temp" ] && [ -r "$_z/trip_point_0_temp" ] && {
                _safe="true"
                break
            }
        done 2>/dev/null
    fi

    # Score
    _total=0; _avail=0
    for _v in "$_zones" "$_hal" "$_safe"; do
        _total=$((_total + 1))
        [ "$_v" = "true" ] && _avail=$((_avail + 1))
    done
    [ "$_total" -gt 0 ] && _score=$((100 * _avail / _total)) || _score=0

    echo "  \"thermal\": {"
    echo "    \"zones\": $_zones,"
    echo "    \"hal\": $_hal,"
    echo "    \"safe_policy\": $_safe,"
    echo "    \"score\": $_score"
    echo "  }"
}

_scan_memory() {
    _zram="false"
    _vm="false"

    # ZRAM
    [ -b "/dev/block/zram0" ] || [ -d "/sys/block/zram0" ] && _zram="true"

    # VM tunables
    [ -f "/proc/sys/vm/swappiness" ] && _vm="true"

    # Write support
    _vm_w="false"
    [ -w "/proc/sys/vm/swappiness" ] && _vm_w="true"

    _score=0
    [ "$_zram" = "true" ] && _score=$((_score + 50))
    [ "$_vm" = "true" ] && _score=$((_score + 30))
    [ "$_vm_w" = "true" ] && _score=$((_score + 20))
    [ "$_score" -gt 100 ] && _score=100

    echo "  \"memory\": {"
    echo "    \"zram\": $_zram,"
    echo "    \"vm\": $_vm,"
    echo "    \"vm_writable\": $_vm_w,"
    echo "    \"score\": $_score"
    echo "  }"
}

_scan_io() {
    _scheduler="false"
    _block="false"

    # Find real block devices (skip loop, ram, zram, dm)
    _real_devs=0
    for _b in /sys/block/*; do
        [ -d "$_b" ] || continue
        _name=$(basename "$_b")
        case "$_name" in
            loop*|ram*|zram*|dm-*) continue ;;
        esac
        _real_devs=$((_real_devs + 1))
        [ -f "$_b/queue/scheduler" ] && _scheduler="true"
        _block="true"
    done 2>/dev/null

    # Write support
    _scheduler_w="false"
    for _b in /sys/block/*; do
        [ -d "$_b" ] || continue
        _name=$(basename "$_b")
        case "$_name" in
            loop*|ram*|zram*|dm-*) continue ;;
        esac
        [ -w "$_b/queue/scheduler" ] && _scheduler_w="true" && break
    done 2>/dev/null

    _score=0
    [ "$_scheduler" = "true" ] && _score=$((_score + 50))
    [ "$_block" = "true" ] && _score=$((_score + 30))
    [ "$_scheduler_w" = "true" ] && _score=$((_score + 20))
    [ "$_score" -gt 100 ] && _score=100

    echo "  \"io\": {"
    echo "    \"scheduler\": $_scheduler,"
    echo "    \"scheduler_writable\": $_scheduler_w,"
    echo "    \"block\": $_block,"
    echo "    \"real_devices\": $_real_devs,"
    echo "    \"score\": $_score"
    echo "  }"
}

_scan_network() {
    _tcp="false"
    _sysctl="false"

    # TCP congestion control
    [ -f "/proc/sys/net/ipv4/tcp_congestion_control" ] && _tcp="true"

    # Available congestion algorithms
    _avail_tcp=""
    [ -f "/proc/sys/net/ipv4/tcp_available_congestion_control" ] && \
        _avail_tcp=$(cat "/proc/sys/net/ipv4/tcp_available_congestion_control" 2>/dev/null)

    # sysctl network tunables
    [ -f "/proc/sys/net/ipv4/tcp_fastopen" ] && _sysctl="true"

    # Write support
    _tcp_w="false"
    [ -w "/proc/sys/net/ipv4/tcp_congestion_control" ] && _tcp_w="true"

    _score=0
    [ "$_tcp" = "true" ] && _score=$((_score + 50))
    [ "$_sysctl" = "true" ] && _score=$((_score + 30))
    [ "$_tcp_w" = "true" ] && _score=$((_score + 20))
    [ "$_score" -gt 100 ] && _score=100

    echo "  \"network\": {"
    echo "    \"tcp\": $_tcp,"
    echo "    \"tcp_writable\": $_tcp_w,"
    echo "    \"tcp_available\": \"$_avail_tcp\","
    echo "    \"sysctl\": $_sysctl,"
    echo "    \"score\": $_score"
    echo "  }"
}

# --- Root-aware scanners (Mode B) ---

_scan_cpu_root() {
    _cpufreq_exists="false"
    _governor_exists="false"
    _schedutil_exists="false"
    _cpuset_exists="false"
    _cpufreq_writable="false"
    _governor_writable="false"
    _cpuset_writable="false"

    # cpufreq
    _count=$(_scan_glob "/sys/devices/system/cpu/cpufreq/policy*")
    [ "$_count" -gt 0 ] && _cpufreq_exists="true"

    # governor
    if [ "$_cpufreq_exists" = "true" ]; then
        for _p in /sys/devices/system/cpu/cpufreq/policy*; do
            [ -f "$_p/scaling_governor" ] && [ -r "$_p/scaling_governor" ] && {
                _governor_exists="true"
                _cur_gov=$(cat "$_p/scaling_governor" 2>/dev/null)
                [ "$_cur_gov" = "schedutil" ] && _schedutil_exists="true"
                break
            }
        done
    fi

    # cpuset
    [ -d "/dev/cpuset" ] && _cpuset_exists="true"

    # Root-aware write checks
    if [ "$_cpufreq_exists" = "true" ]; then
        for _p in /sys/devices/system/cpu/cpufreq/policy*; do
            _scan_writable_root "$_p/scaling_min_freq" | grep -q "true" && _cpufreq_writable="true" && break
        done
    fi
    if [ "$_governor_exists" = "true" ]; then
        for _p in /sys/devices/system/cpu/cpufreq/policy*; do
            _scan_writable_root "$_p/scaling_governor" | grep -q "true" && _governor_writable="true" && break
        done
    fi
    if [ "$_cpuset_exists" = "true" ]; then
        _scan_writable_root "/dev/cpuset/top-app/cpus" | grep -q "true" && _cpuset_writable="true"
    fi

    # Score
    _total=0; _avail=0
    for _v in "$_cpufreq_exists" "$_governor_exists" "$_cpuset_exists"; do
        _total=$((_total + 1))
        [ "$_v" = "true" ] && _avail=$((_avail + 1))
    done
    [ "$_total" -gt 0 ] && _score=$((100 * _avail / _total)) || _score=0

    echo "  \"cpu\": {"
    echo "    \"cpufreq\": $_cpufreq_exists,"
    echo "    \"cpufreq_writable\": $_cpufreq_writable,"
    echo "    \"governor\": $_governor_exists,"
    echo "    \"governor_writable\": $_governor_writable,"
    echo "    \"schedutil\": $_schedutil_exists,"
    echo "    \"cpuset\": $_cpuset_exists,"
    echo "    \"cpuset_writable\": $_cpuset_writable,"
    echo "    \"score\": $_score"
    echo "  }"
}

# --- Main scanner ---

# Mode A: User Scan (no root) - Hardware information only
hsin_scan_user() {
    echo ""
    echo "╔══════════════════════════════════════╗"
    echo "║   HSIN User Scan (No Root)           ║"
    echo "╚══════════════════════════════════════╝"
    echo ""
    echo "  Mode: Hardware Information Only"
    echo "  Root: NOT AVAILABLE"
    echo "  Engine: NOT ENABLED"
    echo ""
    echo "  For full capability scan, run:"
    echo "    su -c hsin scan"
    echo ""

    # Hardware info (no root needed)
    hsin_hardware_info
    hsin_hardware_write 2>/dev/null

    # Basic capability detection (read-only)
    echo "Basic capability detection (read-only)..."
    echo ""

    {
        echo "{"
        echo "  \"timestamp\": \"$(date '+%Y-%m-%d %H:%M:%S')\","
        echo "  \"mode\": \"user\","
        echo "  \"root\": false,"
        echo "  \"engine_enabled\": false,"

        # CPU
        _scan_cpu
        echo ","
        # GPU
        _scan_gpu
        echo ","
        # Thermal
        _scan_thermal
        echo ","
        # Memory
        _scan_memory
        echo ","
        # IO
        _scan_io
        echo ","
        # Network
        _scan_network

        echo "}"
    } > "$HSIN_CAP_REPORT"

    echo "  Report: $HSIN_CAP_REPORT"
    echo ""
    echo "  NOTE: This is hardware info only."
    echo "  Engine tweaks require root access."
    echo ""
}

# Mode B: Root Scan - Full capability with writable checks
hsin_scan_root() {
    hsin_root_init
    if [ "$HSIN_ROOT_AVAILABLE" != "true" ]; then
        echo "[ERROR] Root access required for full capability scan"
        echo "  Run: su -c hsin scan"
        return 1
    fi

    echo ""
    echo "╔══════════════════════════════════════╗"
    echo "║   HSIN Root Capability Scan          ║"
    echo "╚══════════════════════════════════════╝"
    echo ""
    echo "  Mode: Full Capability Scan"
    echo "  Root: AVAILABLE ($HSIN_ROOT_METHOD)"
    echo "  Engine: ENABLED"
    echo ""

    # Hardware info first
    hsin_hardware_info
    hsin_hardware_write 2>/dev/null

    # Full capability scan with root-aware write checks
    echo "Checking permissions..."
    echo ""

    {
        echo "{"
        echo "  \"timestamp\": \"$(date '+%Y-%m-%d %H:%M:%S')\","
        echo "  \"mode\": \"root\","
        echo "  \"root\": true,"
        echo "  \"root_method\": \"$HSIN_ROOT_METHOD\","
        echo "  \"engine_enabled\": true,"

        # CPU (root-aware)
        _scan_cpu_root
        echo ","
        # GPU
        _scan_gpu
        echo ","
        # Thermal
        _scan_thermal
        echo ","
        # Memory
        _scan_memory
        echo ","
        # IO
        _scan_io
        echo ","
        # Network
        _scan_network

        echo "}"
    } > "$HSIN_CAP_REPORT"

    # Extract scores
    _cpu_s=$(grep '"score"' "$HSIN_CAP_REPORT" | head -1 | grep -o '[0-9]*')
    _gpu_s=$(grep '"score"' "$HSIN_CAP_REPORT" | sed -n '2p' | grep -o '[0-9]*')
    _thrm_s=$(grep '"score"' "$HSIN_CAP_REPORT" | sed -n '3p' | grep -o '[0-9]*')
    _mem_s=$(grep '"score"' "$HSIN_CAP_REPORT" | sed -n '4p' | grep -o '[0-9]*')
    _io_s=$(grep '"score"' "$HSIN_CAP_REPORT" | sed -n '5p' | grep -o '[0-9]*')
    _net_s=$(grep '"score"' "$HSIN_CAP_REPORT" | sed -n '6p' | grep -o '[0-9]*')

    [ -z "$_cpu_s" ] && _cpu_s=0
    [ -z "$_gpu_s" ] && _gpu_s=0
    [ -z "$_thrm_s" ] && _thrm_s=0
    [ -z "$_mem_s" ] && _mem_s=0
    [ -z "$_io_s" ] && _io_s=0
    [ -z "$_net_s" ] && _net_s=0

    _overall=$(((_cpu_s + _gpu_s + _thrm_s + _mem_s + _io_s + _net_s) / 6))

    # Print report
    echo ""
    echo "╔══════════════════════════════════════╗"
    echo "║   HSIN Capability Scan Report        ║"
    echo "╚══════════════════════════════════════╝"
    echo ""
    printf "  CPU      %3d%%\n" "$_cpu_s"
    printf "  GPU      %3d%%\n" "$_gpu_s"
    printf "  THERMAL  %3d%%\n" "$_thrm_s"
    printf "  MEMORY   %3d%%\n" "$_mem_s"
    printf "  IO       %3d%%\n" "$_io_s"
    printf "  NETWORK  %3d%%\n" "$_net_s"
    echo "  ──────────────────────────────"
    printf "  OVERALL  %3d%%\n" "$_overall"
    echo ""
    echo "  Report: $HSIN_CAP_REPORT"
    echo ""
}

# Auto-detect mode and run appropriate scan
hsin_scan() {
    hsin_root_init
    if [ "$HSIN_ROOT_AVAILABLE" = "true" ]; then
        hsin_scan_root
    else
        hsin_scan_user
    fi
}

# Query helper: is a capability enabled?
hsin_cap_enabled() {
    # $1=category (cpu/gpu/thermal/memory/io/network), $2=subkey
    [ -f "$HSIN_CAP_REPORT" ] || return 1
    grep -q "\"$2\": true" "$HSIN_CAP_REPORT" 2>/dev/null
}

# Query helper: get capability score
hsin_cap_score() {
    # $1=category (cpu/gpu/thermal/memory/io/network)
    [ -f "$HSIN_CAP_REPORT" ] || { echo "0"; return; }
    grep "\"$1\":" "$HSIN_CAP_REPORT" 2>/dev/null | grep '"score"' | grep -o '[0-9]*' | head -1
}

return 0 2>/dev/null || true
