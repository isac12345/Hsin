#!/system/bin/sh
# HSIN Extreme Restore

[ -z "$HSIN_MODULE_PATH" ] && HSIN_MODULE_PATH="/data/adb/modules/hsin"
HSIN_DATA="${HSIN_DATA:-/data/adb/hsin}"

# Full extreme restore
hsin_extreme_restore() {
    echo ""
    echo "╔══════════════════════════════════════╗"
    echo "║   HSIN Extreme Restore                ║"
    echo "╚══════════════════════════════════════╝"
    echo ""

    _restored=0

    # 1. Restore CPU frequencies
    echo "Restoring CPU frequencies..."
    . "$HSIN_MODULE_PATH/extreme/frequency_unlock.sh" 2>/dev/null
    hsin_extreme_freq_restore
    _restored=$((_restored + $?))
    echo ""

    # 2. Restore GPU
    echo "Restoring GPU settings..."
    . "$HSIN_MODULE_PATH/extreme/gpu_override.sh" 2>/dev/null
    hsin_extreme_gpu_restore
    _restored=$((_restored + $?))
    echo ""

    # 3. Restore thermal
    echo "Restoring thermal settings..."
    . "$HSIN_MODULE_PATH/extreme/thermal_override.sh" 2>/dev/null
    hsin_extreme_thermal_restore
    _restored=$((_restored + $?))
    echo ""

    # 4. Clear extreme state
    echo "Clearing extreme state..."
    rm -f "$HSIN_DATA/extreme_active" 2>/dev/null

    # 5. Log
    _ts=$(date '+%Y-%m-%d %H:%M:%S')
    mkdir -p "$HSIN_DATA/logs" 2>/dev/null
    echo "$_ts [EXTREME] RESTORE complete (restored=$_restored)" >> "$HSIN_DATA/logs/extreme.log"

    echo ""
    echo "╔══════════════════════════════════════╗"
    echo "║   Extreme Mode Disabled               ║"
    echo "╚══════════════════════════════════════╝"
    echo ""
    echo "  Status: Restored to safe defaults"
    echo "  Action: Restart recommended"
    echo ""
}

# Quick rollback (for emergency)
# BUG FIX (critical/safety): this used to set scaling_max_freq to
# cpuinfo_max_freq (CPU) and max_freq to the highest available frequency
# (GPU) - i.e. exactly what hsin_extreme_freq_apply/gpu_override already
# do to UNLOCK the chip. Called from safety_monitor.sh at PANIC (>=100C,
# imminent thermal-shutdown/hardware-risk territory), this meant the
# emergency handler was RE-APPLYING the extreme overclock instead of
# rolling it back - the CPU/GPU stayed pinned at max clock while already
# critically overheating. Fixed to clamp down to the lowest available
# frequency instead, so the device actually cools down immediately. The
# calmer EMERGENCY path (hsin_extreme_restore, a step below PANIC) still
# restores the real pre-extreme backup values via freq/gpu restore below.
hsin_extreme_quick_rollback() {
    echo "[EXTREME] Emergency rollback..."

    # Throttle CPU down to its lowest frequency (not the highest - see fix note above)
    for _policy in /sys/devices/system/cpu/cpufreq/policy*; do
        [ -d "$_policy" ] || continue
        [ -f "$_policy/cpuinfo_min_freq" ] || continue
        _hw_min=$(cat "$_policy/cpuinfo_min_freq" 2>/dev/null)
        [ -n "$_hw_min" ] && echo "$_hw_min" > "$_policy/scaling_max_freq" 2>/dev/null
        [ -n "$_hw_min" ] && echo "$_hw_min" > "$_policy/scaling_min_freq" 2>/dev/null
    done

    # Throttle GPU down to its lowest available frequency (not the highest)
    for _devfreq in /sys/class/devfreq/*; do
        [ -d "$_devfreq" ] || continue
        [ -f "$_devfreq/available_frequencies" ] || continue
        _min_avail=$(cat "$_devfreq/available_frequencies" 2>/dev/null | tr ' ' '\n' | sort -n | head -1)
        [ -n "$_min_avail" ] && echo "$_min_avail" > "$_devfreq/max_freq" 2>/dev/null
    done

    # Restore thermal trips
    [ -d "$HSIN_DATA/backups/thermal/extreme" ] && {
        for _trip_file in "$HSIN_DATA/backups/thermal/extreme"/*_trip; do
            [ -f "$_trip_file" ] || continue
            _zone_name=$(basename "$_trip_file" _trip)
            _target="/sys/class/thermal/$_zone_name/trip_point_0_temp"
            _val=$(cat "$_trip_file" 2>/dev/null)
            [ -f "$_target" ] && [ -n "$_val" ] && echo "$_val" > "$_target" 2>/dev/null
        done
    }

    rm -f "$HSIN_DATA/extreme_active" 2>/dev/null
    echo "[EXTREME] Quick rollback done"
}

return 0 2>/dev/null || true
