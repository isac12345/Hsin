#!/system/bin/sh
# HSIN Thermal Monitor

[ -z "$HSIN_MODULE_PATH" ] && HSIN_MODULE_PATH="/data/adb/modules/hsin"
HSIN_DATA="${HSIN_DATA:-/data/adb/hsin}"

# Thermal thresholds (millidegrees).
# BUG FIX: same miscalibration already fixed once in engine/cpu/safety.sh
# and just now in engine/thermal/policy.sh - these were 40/45/50/60/70C,
# so hsin_thermal_classify()/hsin_thermal_performance_level() (used by
# hsin_thermal_engine_apply's status display and `hsin thermal-test`)
# were reporting "CRITICAL - aggressive reduction" / 50% perf at a
# perfectly ordinary 60-70C gaming temperature. Realigned to the same
# scale as extreme/thermal_override.sh (warn=80C/emergency=95C/
# panic=100C) with two extra intermediate steps for a smoother
# normal->warm->hot->critical->panic gradient.
HSIN_THERMAL_TEMP_NORMAL=50000
HSIN_THERMAL_TEMP_WARM=65000
HSIN_THERMAL_TEMP_HOT=80000
HSIN_THERMAL_TEMP_CRITICAL=95000
HSIN_THERMAL_TEMP_PANIC=100000

# Monitor interval
HSIN_THERMAL_MONITOR_INTERVAL=5

# Current thermal state
HSIN_THERMAL_STATE="normal"
HSIN_THERMAL_MAX_TEMP=0
HSIN_THERMAL_CPU_TEMP=0
HSIN_THERMAL_GPU_TEMP=0
HSIN_THERMAL_BATTERY_TEMP=0

# Read current temperatures
hsin_thermal_read() {
    HSIN_THERMAL_MAX_TEMP=0

    # CPU
    HSIN_THERMAL_CPU_TEMP=0
    for _zone in /sys/class/thermal/thermal_zone*/temp; do
        [ -f "$_zone" ] || continue
        _dir=$(dirname "$_zone")
        [ -f "$_dir/type" ] || continue
        _type=$(cat "$_dir/type" 2>/dev/null)
        case "$_type" in
            *cpu*|*CPU*)
                _t=$(cat "$_zone" 2>/dev/null)
                [ -n "$_t" ] && [ "$_t" -gt "$HSIN_THERMAL_CPU_TEMP" ] 2>/dev/null && HSIN_THERMAL_CPU_TEMP="$_t"
                ;;
        esac
    done

    # GPU
    HSIN_THERMAL_GPU_TEMP=0
    for _zone in /sys/class/thermal/thermal_zone*/temp; do
        [ -f "$_zone" ] || continue
        _dir=$(dirname "$_zone")
        [ -f "$_dir/type" ] || continue
        _type=$(cat "$_dir/type" 2>/dev/null)
        case "$_type" in
            *gpu*|*GPU*|*kgsl*)
                _t=$(cat "$_zone" 2>/dev/null)
                [ -n "$_t" ] && [ "$_t" -gt "$HSIN_THERMAL_GPU_TEMP" ] 2>/dev/null && HSIN_THERMAL_GPU_TEMP="$_t"
                ;;
        esac
    done

    # Battery
    HSIN_THERMAL_BATTERY_TEMP=0
    for _zone in /sys/class/thermal/thermal_zone*/temp; do
        [ -f "$_zone" ] || continue
        _dir=$(dirname "$_zone")
        [ -f "$_dir/type" ] || continue
        _type=$(cat "$_dir/type" 2>/dev/null)
        case "$_type" in
            *battery*|*batt*|*Battery*)
                _t=$(cat "$_zone" 2>/dev/null)
                [ -n "$_t" ] && [ "$_t" -gt "$HSIN_THERMAL_BATTERY_TEMP" ] 2>/dev/null && HSIN_THERMAL_BATTERY_TEMP="$_t"
                ;;
        esac
    done

    # Overall max
    [ "$HSIN_THERMAL_CPU_TEMP" -gt "$HSIN_THERMAL_MAX_TEMP" ] 2>/dev/null && HSIN_THERMAL_MAX_TEMP="$HSIN_THERMAL_CPU_TEMP"
    [ "$HSIN_THERMAL_GPU_TEMP" -gt "$HSIN_THERMAL_MAX_TEMP" ] 2>/dev/null && HSIN_THERMAL_MAX_TEMP="$HSIN_THERMAL_GPU_TEMP"
    [ "$HSIN_THERMAL_BATTERY_TEMP" -gt "$HSIN_THERMAL_MAX_TEMP" ] 2>/dev/null && HSIN_THERMAL_MAX_TEMP="$HSIN_THERMAL_BATTERY_TEMP"
}

# Determine thermal state from temperature
hsin_thermal_classify() {
    _temp="$1"

    if [ "$_temp" -ge "$HSIN_THERMAL_TEMP_PANIC" ] 2>/dev/null; then
        HSIN_THERMAL_STATE="panic"
    elif [ "$_temp" -ge "$HSIN_THERMAL_TEMP_CRITICAL" ] 2>/dev/null; then
        HSIN_THERMAL_STATE="critical"
    elif [ "$_temp" -ge "$HSIN_THERMAL_TEMP_HOT" ] 2>/dev/null; then
        HSIN_THERMAL_STATE="hot"
    elif [ "$_temp" -ge "$HSIN_THERMAL_TEMP_WARM" ] 2>/dev/null; then
        HSIN_THERMAL_STATE="warm"
    else
        HSIN_THERMAL_STATE="normal"
    fi
}

# Get performance level based on thermal state
hsin_thermal_performance_level() {
    _temp="$1"

    if [ "$_temp" -ge "$HSIN_THERMAL_TEMP_PANIC" ] 2>/dev/null; then
        echo "30"
    elif [ "$_temp" -ge "$HSIN_THERMAL_TEMP_CRITICAL" ] 2>/dev/null; then
        echo "50"
    elif [ "$_temp" -ge "$HSIN_THERMAL_TEMP_HOT" ] 2>/dev/null; then
        echo "70"
    elif [ "$_temp" -ge "$HSIN_THERMAL_TEMP_WARM" ] 2>/dev/null; then
        echo "85"
    elif [ "$_temp" -ge "$HSIN_THERMAL_TEMP_NORMAL" ] 2>/dev/null; then
        echo "95"
    else
        echo "100"
    fi
}

# Format temperature for display
hsin_thermal_format_temp() {
    _t="$1"
    if [ -z "$_t" ] || [ "$_t" = "0" ]; then
        echo "N/A"
    elif [ "$_t" -gt 1000 ] 2>/dev/null; then
        echo "$(( _t / 1000 ))C"
    elif [ "$_t" -gt 200 ] 2>/dev/null; then
        echo "$(( _t / 10 ))C"
    else
        echo "${_t}C"
    fi
}

# Print monitor status
hsin_thermal_monitor_print() {
    hsin_thermal_read
    hsin_thermal_classify "$HSIN_THERMAL_MAX_TEMP"

    _cpu_fmt=$(hsin_thermal_format_temp "$HSIN_THERMAL_CPU_TEMP")
    _gpu_fmt=$(hsin_thermal_format_temp "$HSIN_THERMAL_GPU_TEMP")
    _bat_fmt=$(hsin_thermal_format_temp "$HSIN_THERMAL_BATTERY_TEMP")
    _max_fmt=$(hsin_thermal_format_temp "$HSIN_THERMAL_MAX_TEMP")
    _level=$(hsin_thermal_performance_level "$HSIN_THERMAL_MAX_TEMP")

    echo ""
    echo "╔══════════════════════════════════════╗"
    echo "║   HSIN Thermal Monitor               ║"
    echo "╚══════════════════════════════════════╝"
    echo ""
    printf "  CPU:      %s\n" "$_cpu_fmt"
    printf "  GPU:      %s\n" "$_gpu_fmt"
    printf "  Battery:  %s\n" "$_bat_fmt"
    printf "  Max:      %s\n" "$_max_fmt"
    echo ""
    printf "  State:    %s\n" "$HSIN_THERMAL_STATE"
    printf "  Perf:     %s%%\n" "$_level"
    echo ""

    case "$HSIN_THERMAL_STATE" in
        normal)  printf "  Status:   NORMAL\n" ;;
        warm)    printf "  Status:   WARM - monitoring\n" ;;
        hot)     printf "  Status:   HOT - reducing performance\n" ;;
        critical)printf "  Status:   CRITICAL - aggressive reduction\n" ;;
        panic)   printf "  Status:   PANIC - minimum performance\n" ;;
    esac
    echo ""
}

# Monitor loop (runs in background)
hsin_thermal_monitor_loop() {
    _interval="${1:-$HSIN_THERMAL_MONITOR_INTERVAL}"

    while true; do
        hsin_thermal_read
        hsin_thermal_classify "$HSIN_THERMAL_MAX_TEMP"

        # Log state change
        _state_file="$HSIN_DATA/thermal_state"
        _old_state=""
        [ -f "$_state_file" ] && _old_state=$(cat "$_state_file" 2>/dev/null)
        echo "$HSIN_THERMAL_STATE" > "$_state_file"

        if [ "$HSIN_THERMAL_STATE" != "$_old_state" ] && [ -n "$_old_state" ]; then
            _ts=$(date '+%Y-%m-%d %H:%M:%S')
            echo "[$_ts] [THERMAL] State: $_old_state -> $HSIN_THERMAL_STATE" >> "$HSIN_DATA/logs/thermal.log"
        fi

        sleep "$_interval"
    done
}

return 0 2>/dev/null || true
