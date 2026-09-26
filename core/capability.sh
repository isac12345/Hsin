#!/system/bin/sh
# HSIN - Capability Scoring

HSIN_DATA="${HSIN_DATA:-/data/adb/hsin}"

[ -z "$HSIN_MODULE_PATH" ] && HSIN_MODULE_PATH="/data/adb/modules/hsin"
. "$HSIN_MODULE_PATH/core/sysfs.sh" 2>/dev/null
. "$HSIN_MODULE_PATH/core/logger.sh" 2>/dev/null
HSIN_DATA_DEVICE_TXT="$HSIN_DATA/device.txt"
HSIN_DATA_CAP="$HSIN_DATA/capability.json"

# Helper baca field dari device.txt
_dev_get() {
    grep "^$1=" "$HSIN_DATA_DEVICE_TXT" 2>/dev/null | head -1 | cut -d= -f2-
}

# Status: AVAILABLE=1, LIMITED=2, UNAVAILABLE=0
cap_set() {
    # $1=nama, $2=status (0/1/2), $3=detail
    echo "$1|$2|$3" >> "$HSIN_DATA_CAP.tmp"
}

cap_finalize() {
    {
        echo "{"
        echo "  \"timestamp\": \"$(date '+%Y-%m-%d %H:%M:%S')\","
        _first=1
        while IFS='|' read -r name status detail; do
            [ -z "$name" ] && continue
            [ $_first -eq 1 ] && _first=0 || echo ","
            _sname="UNAVAILABLE"
            [ "$status" = "1" ] && _sname="AVAILABLE"
            [ "$status" = "2" ] && _sname="LIMITED"
            _dn=$(echo "$detail" | tr -d '"\\' | head -c 200)
            printf '  "%s": {"status": "%s", "detail": "%s"}' "$name" "$_sname" "$_dn"
        done < "$HSIN_DATA_CAP.tmp"
        echo ""
        echo "}"
    } > "$HSIN_DATA_CAP"
    rm -f "$HSIN_DATA_CAP.tmp"
}

# --- Capability checks ---

cap_cpu_governor() {
    # Butuh scaling_governor writable + minimal 1 governor umum ada
    _govs=$(_dev_get "GOVS")
    _has=0
    for g in schedutil ondemand interactive performance; do
        case " $_govs " in
            *" $g "*) _has=1; break ;;
        esac
    done
    if [ "$_has" -eq 1 ]; then
        _w=0
        for p in /sys/devices/system/cpu/cpufreq/policy*; do
            [ -w "$p/scaling_governor" ] && _w=1
        done
        if [ "$_w" -eq 1 ]; then
            cap_set "cpu_governor" 1 "governors=$_govs"
        else
            cap_set "cpu_governor" 2 "no_writable (governors=$_govs)"
        fi
    else
        cap_set "cpu_governor" 0 "no_common_governor (have=$_govs)"
    fi
}

cap_cpu_freq_lock() {
    # Butuh scaling_min_freq & scaling_max_freq writable
    _w_min=0; _w_max=0; _has_avail=0
    for p in /sys/devices/system/cpu/cpufreq/policy*; do
        [ -d "$p" ] || continue
        [ -f "$p/scaling_available_frequencies" ] && _has_avail=1
        [ -w "$p/scaling_min_freq" ] && _w_min=$((_w_min + 1))
        [ -w "$p/scaling_max_freq" ] && _w_max=$((_w_max + 1))
    done
    if [ "$_has_avail" -eq 1 ] && [ "$_w_min" -gt 0 ] && [ "$_w_max" -gt 0 ]; then
        cap_set "cpu_freq_lock" 1 "writable_min=$_w_min max=$_w_max"
    elif [ "$_w_min" -gt 0 ] || [ "$_w_max" -gt 0 ]; then
        cap_set "cpu_freq_lock" 2 "partial_writable (min=$_w_min max=$_w_max)"
    else
        cap_set "cpu_freq_lock" 0 "no_writable_path"
    fi
}

cap_gpu_devfreq() {
    # Scan /sys/class/devfreq/* untuk GPU (silent jika tidak ada)
    _found=0; _writable=0
    for d in /sys/class/devfreq/*; do
        [ -d "$d" ] || continue
        _name=$(basename "$d" | tr '[:upper:]' '[:lower:]')
        case "$_name" in
            *gpu*|*gfx*|*mali*) _found=$((_found + 1)) ;;
        esac
        case "$_name" in
            *gpu*|*gfx*|*mali*)
                [ -w "$d/governor" ] && _writable=$((_writable + 1))
                ;;
        esac
    done 2>/dev/null
    if [ "$_found" -gt 0 ] && [ "$_writable" -gt 0 ]; then
        cap_set "gpu_devfreq" 1 "found=$_found writable=$_writable"
    elif [ "$_found" -gt 0 ]; then
        cap_set "gpu_devfreq" 2 "found=$_found no_writable"
    else
        cap_set "gpu_devfreq" 0 "no_devfreq_gpu"
    fi
}

cap_gpu_kgsl() {
    # Qualcomm-specific (KGSL Adreno)
    if [ -d /sys/class/kgsl/kgsl-3d0 ]; then
        if [ -w /sys/class/kgsl/kgsl-3d0/num_pwrlevels ] || [ -w /sys/class/kgsl/kgsl-3d0/default_pwrlevel ]; then
            cap_set "gpu_kgsl" 1 "kgsl-3d0 writable"
        else
            cap_set "gpu_kgsl" 2 "kgsl-3d0 present not writable"
        fi
    else
        cap_set "gpu_kgsl" 0 "no_kgsl (not_qcom_or_disabled)"
    fi
}

cap_gpu_mali_platform() {
    # Mali via /sys/devices/platform/*.mali
    _found=0; _writable=0
    for m in /sys/devices/platform/*.mali; do
        [ -d "$m" ] || continue
        _found=$((_found + 1))
        if [ -w "$m/power_policy" ] || [ -w "$m/dvfs_governor" ]; then
            _writable=$((_writable + 1))
        fi
    done
    if [ "$_found" -gt 0 ] && [ "$_writable" -gt 0 ]; then
        cap_set "gpu_mali_platform" 1 "found=$_found writable=$_writable"
    elif [ "$_found" -gt 0 ]; then
        cap_set "gpu_mali_platform" 2 "found=$_found no_writable"
    else
        cap_set "gpu_mali_platform" 0 "no_mali_platform_node"
    fi
}

cap_gpu_fpsgo() {
    # MTK FPSGO
    if [ -d /sys/kernel/fpsgo ] || [ -d /sys/module/mtk_fpsgo ]; then
        cap_set "gpu_fpsgo" 1 "fpsgo present (mtk)"
    else
        cap_set "gpu_fpsgo" 0 "no_fpsgo"
    fi
}

cap_thermal_zones() {
    _count=$(_dev_get "THERMAL")
    [ -z "$_count" ] && _count=0
    _w=$(_dev_get "THERMAL_W")
    [ -z "$_w" ] && _w=0
    if [ "$_count" -gt 0 ] && [ "$_w" -gt 0 ]; then
        cap_set "thermal_zones" 1 "zones=$_count writable=$_w"
    elif [ "$_count" -gt 0 ]; then
        cap_set "thermal_zones" 2 "zones=$_count no_writable"
    else
        cap_set "thermal_zones" 0 "no_thermal_zones"
    fi
}

cap_cpuset() {
    if [ -d /dev/cpuset ]; then
        _w=0
        for g in top-app foreground background system-background; do
            [ -d "/dev/cpuset/$g" ] && [ -w "/dev/cpuset/$g/cpus" ] && _w=$((_w + 1))
        done
        if [ "$_w" -gt 0 ]; then
            cap_set "cpuset" 1 "groups=$_w writable"
        else
            cap_set "cpuset" 2 "no_writable_groups"
        fi
    else
        cap_set "cpuset" 0 "no_cpuset"
    fi
}

cap_io_scheduler() {
    _found=0; _w=0
    for b in /sys/block/*; do
        [ -d "$b" ] || continue
        _name=$(basename "$b")
        case "$_name" in loop*|ram*|zram*|dm-*) continue ;; esac
        _found=$((_found + 1))
        [ -w "$b/queue/scheduler" ] && _w=$((_w + 1))
    done 2>/dev/null
    if [ "$_found" -gt 0 ] && [ "$_w" -gt 0 ]; then
        cap_set "io_scheduler" 1 "devices=$_found writable=$_w"
    elif [ "$_found" -gt 0 ]; then
        cap_set "io_scheduler" 2 "no_writable_scheduler"
    else
        cap_set "io_scheduler" 0 "no_block_devices"
    fi
}

cap_io_readahead() {
    _found=0; _w=0
    for b in /sys/block/*; do
        [ -d "$b" ] || continue
        _name=$(basename "$b")
        case "$_name" in loop*|ram*|zram*|dm-*) continue ;; esac
        [ -f "$b/queue/read_ahead_kb" ] && _found=$((_found + 1))
        [ -w "$b/queue/read_ahead_kb" ] && _w=$((_w + 1))
    done 2>/dev/null
    if [ "$_found" -gt 0 ] && [ "$_w" -gt 0 ]; then
        cap_set "io_readahead" 1 "devices=$_found"
    else
        cap_set "io_readahead" 0 "no_readahead_node"
    fi
}

cap_zram() {
    _zram=$(_dev_get "ZRAM")
    if [ "$_zram" = "available" ]; then
        cap_set "zram" 1 "zram0 present"
    else
        cap_set "zram" 0 "no_zram"
    fi
}

cap_vm_swappiness() {
    if [ -f /proc/sys/vm/swappiness ] && [ -w /proc/sys/vm/swappiness ]; then
        cap_set "vm_swappiness" 1 "writable"
    elif [ -f /proc/sys/vm/swappiness ]; then
        cap_set "vm_swappiness" 2 "readable_not_writable"
    else
        cap_set "vm_swappiness" 0 "no_swappiness"
    fi
}

cap_network_tcp() {
    _cur=$(_dev_get "TCP_CUR")
    if [ -w /proc/sys/net/ipv4/tcp_congestion_control ]; then
        cap_set "network_tcp" 1 "current=$_cur"
    else
        cap_set "network_tcp" 0 "no_writable_tcp"
    fi
}

cap_network_sysctl() {
    _w=0
    for p in /proc/sys/net/ipv4/tcp_fastopen \
             /proc/sys/net/ipv4/tcp_ecn \
             /proc/sys/net/core/netdev_max_backlog; do
        [ -w "$p" ] && _w=$((_w + 1))
    done
    if [ "$_w" -gt 0 ]; then
        cap_set "network_sysctl" 1 "writable=$_w"
    else
        cap_set "network_sysctl" 0 "no_writable_sysctl"
    fi
}

cap_input_boost() {
    # Touch boost via /sys/class/input/input*/poll_rate (vendor-agnostic scan)
    _found=0
    for i in /sys/class/input/input*; do
        [ -d "$i" ] || continue
        [ -f "$i/poll_rate" ] && _found=$((_found + 1))
    done 2>/dev/null
    if [ "$_found" -gt 0 ]; then
        cap_set "input_boost" 1 "input_devices=$_found"
    else
        cap_set "input_boost" 0 "no_poll_rate_node"
    fi
}

cap_refresh_rate() {
    # SurfaceFlinger refresh control via settings (works on most A11+)
    if [ -f /system/bin/cmd ] || command -v cmd >/dev/null 2>&1; then
        cap_set "refresh_rate" 1 "cmd_settings available"
    else
        cap_set "refresh_rate" 0 "no_cmd_tool"
    fi
}

cap_surfaceflinger_props() {
    # Capability: resetprop tersedia + beberapa property SF valid
    if command -v resetprop >/dev/null 2>&1; then
        cap_set "sf_props" 1 "resetprop_available"
    else
        cap_set "sf_props" 0 "no_resetprop"
    fi
}

# Main: jalankan semua capability check
hsin_capability_run() {
    hsin_log_section "HSIN Capability Scoring"

    [ -f "$HSIN_DATA_DEVICE_TXT" ] || {
        hsin_log_warn "capability" "device.txt missing, running detector..."
        . "${HSIN_MODULE_PATH:-/data/adb/modules/hsin}/core/detector.sh" 2>/dev/null
        hsin_detect_all 2>/dev/null
    }

    rm -f "$HSIN_DATA_CAP.tmp"

    # Load blacklist into memory for fast checking
    . "${HSIN_MODULE_PATH:-/data/adb/modules/hsin}/core/validator.sh" 2>/dev/null

    cap_cpu_governor
    cap_cpu_freq_lock
    cap_gpu_devfreq
    cap_gpu_kgsl
    cap_gpu_mali_platform
    cap_gpu_fpsgo
    cap_thermal_zones
    cap_cpuset
    cap_io_scheduler
    cap_io_readahead
    cap_zram
    cap_vm_swappiness
    cap_network_tcp
    cap_network_sysctl
    cap_input_boost
    cap_refresh_rate
    cap_surfaceflinger_props

    cap_finalize
    cap_print_report
    hsin_log_ok "capability" "capability.json written: $HSIN_DATA_CAP"
}

# Print human-readable hardware report with scores
cap_print_report() {
    [ -f "$HSIN_DATA_CAP" ] || return

    echo ""
    echo "╔══════════════════════════════════════╗"
    echo "║   HSIN Hardware Capability Report    ║"
    echo "╚══════════════════════════════════════╝"
    echo ""

    _cpu_avail=0; _cpu_total=0
    _gpu_avail=0; _gpu_total=0
    _thermal_avail=0; _thermal_total=0
    _mem_avail=0; _mem_total=0
    _io_avail=0; _io_total=0
    _net_avail=0; _net_total=0
    _other_avail=0; _other_total=0

    # Parse capability.json (simple grep-based, no jq needed)
    while IFS= read -r _line; do
        # Skip structural JSON lines (opening/closing braces, timestamp)
        case "$_line" in
            '{'|'}'|*'timestamp'*) continue ;;
        esac
        # Must contain a key with status
        case "$_line" in
            *'"status"'*) ;;
            *) continue ;;
        esac
        # Extract key: first quoted string on the line
        _name=$(echo "$_line" | grep -o '"[^"]*"' | head -1 | tr -d '"')
        [ -z "$_name" ] && continue
        # Check status: UNAVAILABLE before AVAILABLE (UNAVAILABLE contains AVAILABLE substring)
        case "$_line" in
            *"UNAVAILABLE"*) _status="0"; _sname="UNAVAILABLE"; _icon="✗" ;;
            *"LIMITED"*) _status="2"; _sname="LIMITED"; _icon="~" ;;
            *"AVAILABLE"*) _status="1"; _sname="AVAILABLE"; _icon="✓" ;;
            *) continue ;;
        esac

        # Categorize and count
        case "$_name" in
            cpu_*|cpuset)
                _cpu_total=$((_cpu_total + 1))
                [ "$_status" != "0" ] && _cpu_avail=$((_cpu_avail + 1))
                printf "  CPU   %s %-20s %s\n" "$_icon" "$_name" "$_sname"
                ;;
            gpu_*)
                _gpu_total=$((_gpu_total + 1))
                [ "$_status" != "0" ] && _gpu_avail=$((_gpu_avail + 1))
                printf "  GPU   %s %-20s %s\n" "$_icon" "$_name" "$_sname"
                ;;
            thermal_*)
                _thermal_total=$((_thermal_total + 1))
                [ "$_status" != "0" ] && _thermal_avail=$((_thermal_avail + 1))
                printf "  THRM  %s %-20s %s\n" "$_icon" "$_name" "$_sname"
                ;;
            vm_*|zram*)
                _mem_total=$((_mem_total + 1))
                [ "$_status" != "0" ] && _mem_avail=$((_mem_avail + 1))
                printf "  MEM   %s %-20s %s\n" "$_icon" "$_name" "$_sname"
                ;;
            io_*)
                _io_total=$((_io_total + 1))
                [ "$_status" != "0" ] && _io_avail=$((_io_avail + 1))
                printf "  IO    %s %-20s %s\n" "$_icon" "$_name" "$_sname"
                ;;
            network_*|net_*)
                _net_total=$((_net_total + 1))
                [ "$_status" != "0" ] && _net_avail=$((_net_avail + 1))
                printf "  NET   %s %-20s %s\n" "$_icon" "$_name" "$_sname"
                ;;
            *)
                _other_total=$((_other_total + 1))
                [ "$_status" != "0" ] && _other_avail=$((_other_avail + 1))
                printf "  OTHER %s %-20s %s\n" "$_icon" "$_name" "$_sname"
                ;;
        esac
    done < "$HSIN_DATA_CAP"

    # Calculate totals
    _total=$((_cpu_total + _gpu_total + _thermal_total + _mem_total + _io_total + _net_total + _other_total))
    _avail=$((_cpu_avail + _gpu_avail + _thermal_avail + _mem_avail + _io_avail + _net_avail + _other_avail))

    echo ""
    echo "──────────────────────────────────────"

    # Category scores
    _pct_cpu=0; _pct_gpu=0; _pct_thrm=0; _pct_mem=0; _pct_io=0; _pct_net=0
    [ "$_cpu_total" -gt 0 ] && _pct_cpu=$((100 * _cpu_avail / _cpu_total))
    [ "$_gpu_total" -gt 0 ] && _pct_gpu=$((100 * _gpu_avail / _gpu_total))
    [ "$_thermal_total" -gt 0 ] && _pct_thrm=$((100 * _thermal_avail / _thermal_total))
    [ "$_mem_total" -gt 0 ] && _pct_mem=$((100 * _mem_avail / _mem_total))
    [ "$_io_total" -gt 0 ] && _pct_io=$((100 * _io_avail / _io_total))
    [ "$_net_total" -gt 0 ] && _pct_net=$((100 * _net_avail / _net_total))

    printf "  CPU      %3d%%\n" "$_pct_cpu"
    printf "  GPU      %3d%%\n" "$_pct_gpu"
    printf "  THERMAL  %3d%%\n" "$_pct_thrm"
    printf "  MEMORY   %3d%%\n" "$_pct_mem"
    printf "  IO       %3d%%\n" "$_pct_io"
    printf "  NETWORK  %3d%%\n" "$_pct_net"

    echo "──────────────────────────────────────"
    [ "$_total" -gt 0 ] && _overall=$((100 * _avail / _total)) || _overall=0
    printf "  OVERALL  %3d%%\n" "$_overall"
    echo ""
}

# Query helper: apakah fitur tersedia?
hsin_cap_has() {
    # $1=nama fitur, return 0 jika AVAILABLE, 1 jika LIMITED, 2 jika UNAVAILABLE
    [ -f "$HSIN_DATA_CAP" ] || return 2
    _line=$(grep "\"$1\":" "$HSIN_DATA_CAP" 2>/dev/null | head -1)
    case "$_line" in
        *AVAILABLE*) return 0 ;;
        *LIMITED*) return 1 ;;
        *) return 2 ;;
    esac
}

return 0 2>/dev/null || true
