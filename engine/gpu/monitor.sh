#!/system/bin/sh
# HSIN GPU Engine - Monitor

[ -z "$HSIN_MODULE_PATH" ] && HSIN_MODULE_PATH="/data/adb/modules/hsin"
. "$HSIN_MODULE_PATH/core/sysfs.sh" 2>/dev/null

# Get current GPU frequency
hsin_gpu_monitor_freq() {
    # Try devfreq
    if [ -n "$HSIN_GPU_DEVFREQ" ] && [ -f "$HSIN_GPU_DEVFREQ/cur_freq" ]; then
        _freq=$(cat "$HSIN_GPU_DEVFREQ/cur_freq" 2>/dev/null)
        if [ -n "$_freq" ] && [ "$_freq" -gt 0 ] 2>/dev/null; then
            echo $((_freq / 1000000))
            return 0
        fi
    fi

    # Try Adreno KGSL
    if [ -f /sys/class/kgsl/kgsl-3d0/gpuclk ]; then
        _freq=$(cat /sys/class/kgsl/kgsl-3d0/gpuclk 2>/dev/null)
        if [ -n "$_freq" ] && [ "$_freq" -gt 0 ] 2>/dev/null; then
            echo $((_freq / 1000000))
            return 0
        fi
    fi

    # Try Mali
    if [ -f /sys/devices/platform/mali.0/devfreq/mali.0/cur_freq ]; then
        _freq=$(cat /sys/devices/platform/mali.0/devfreq/mali.0/cur_freq 2>/dev/null)
        if [ -n "$_freq" ] && [ "$_freq" -gt 0 ] 2>/dev/null; then
            echo $((_freq / 1000000))
            return 0
        fi
    fi

    echo "?"
    return 1
}

# Get GPU temperature (from thermal zones)
hsin_gpu_monitor_temp() {
    for _zone in /sys/class/thermal/thermal_zone*; do
        [ -d "$_zone" ] || continue
        _type=$(cat "$_zone/type" 2>/dev/null | tr '[:upper:]' '[:lower:]')
        case "$_type" in
            *gpu*)
                _temp=$(cat "$_zone/temp" 2>/dev/null)
                if [ -n "$_temp" ] && [ "$_temp" -gt 0 ] 2>/dev/null; then
                    echo $((_temp / 1000))
                    return 0
                fi
                ;;
        esac
    done
    echo "?"
    return 1
}

# Get GPU load (Adreno specific)
hsin_gpu_monitor_load() {
    if [ -f /sys/class/kgsl/kgsl-3d0/gpu_busy_percentage ]; then
        _load=$(cat /sys/class/kgsl/kgsl-3d0/gpu_busy_percentage 2>/dev/null)
        echo "$_load"
        return 0
    fi

    # Generic: try devfreq load
    if [ -n "$HSIN_GPU_DEVFREQ" ] && [ -f "$HSIN_GPU_DEVFREQ/load" ]; then
        _load=$(cat "$HSIN_GPU_DEVFREQ/load" 2>/dev/null)
        echo "$_load"
        return 0
    fi

    echo "?"
    return 1
}

# Get GPU status category
hsin_gpu_monitor_status() {
    _temp=$(hsin_gpu_monitor_temp)

    case "$_temp" in
        "?") echo "unknown"; return ;;
    esac

    # Guard: non-numeric temp ("?") would fail arithmetic compare.
    if [ -z "$_temp" ] || [ "$_temp" = "?" ]; then
        echo "unknown"
        return
    fi

    if [ "$_temp" -ge 80 ] 2>/dev/null; then
        echo "critical"
    elif [ "$_temp" -ge 65 ] 2>/dev/null; then
        echo "hot"
    elif [ "$_temp" -ge 50 ] 2>/dev/null; then
        echo "warm"
    else
        echo "normal"
    fi
}

# Print GPU monitor
hsin_gpu_monitor_print() {
    _freq=$(hsin_gpu_monitor_freq)
    _temp=$(hsin_gpu_monitor_temp)
    _load=$(hsin_gpu_monitor_load)
    _status=$(hsin_gpu_monitor_status)

    echo ""
    echo "╔══════════════════════════════════════╗"
    echo "║   GPU Monitor                        ║"
    echo "╚══════════════════════════════════════╝"
    echo ""
    printf "  Freq:   %s MHz\n" "$_freq"
    printf "  Temp:   %s°C\n" "$_temp"
    printf "  Load:   %s\n" "$_load"
    printf "  Status: %s\n" "$_status"
    echo ""
}

return 0 2>/dev/null || true
