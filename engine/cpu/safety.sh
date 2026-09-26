#!/system/bin/sh
# HSIN CPU Engine - Safety Engine

[ -z "$HSIN_MODULE_PATH" ] && HSIN_MODULE_PATH="/data/adb/modules/hsin"

# Temperature thresholds (millidegrees).
# FIX: previous values (40/45/50/60C) were miscalibrated - 50C is normal
# operating temp for a phone SoC under light load, not a "limit" state.
# Realigned to match the scale used everywhere else in HSIN
# (policy_engine.sh: warn=75C/critical=85C/panic=95C, extreme.conf trip=95C,
# performance.conf trip=85C, gpu monitor.sh: 50/65/80C) so CPU safety no
# longer silently downgrades performance/extreme to balanced/battery under
# completely normal gaming temperatures.
HSIN_TEMP_NORMAL=60000
HSIN_TEMP_REDUCE=75000
HSIN_TEMP_LIMIT=85000
HSIN_TEMP_CRITICAL=95000

# Battery thresholds (percentage)
HSIN_BAT_LOW=15
HSIN_BAT_MEDIUM=30

# Get current temperature (max across all zones)
hsin_cpu_safety_temp() {
    _max=0
    for _zone in /sys/class/thermal/thermal_zone*/temp; do
        [ -f "$_zone" ] || continue
        _t=$(cat "$_zone" 2>/dev/null)
        [ -n "$_t" ] && [ "$_t" -gt "$_max" ] 2>/dev/null && _max="$_t"
    done
    echo "$_max"
}

# Get temperature status
hsin_cpu_safety_temp_status() {
    _temp=$(hsin_cpu_safety_temp)

    if [ "$_temp" -ge "$HSIN_TEMP_CRITICAL" ] 2>/dev/null; then
        echo "critical"
    elif [ "$_temp" -ge "$HSIN_TEMP_LIMIT" ] 2>/dev/null; then
        echo "limit"
    elif [ "$_temp" -ge "$HSIN_TEMP_REDUCE" ] 2>/dev/null; then
        echo "reduce"
    else
        echo "normal"
    fi
}

# Get battery level
hsin_cpu_safety_battery() {
    if [ -f /sys/class/power_supply/battery/capacity ]; then
        cat /sys/class/power_supply/battery/capacity 2>/dev/null
    else
        echo "100"  # Default: assume full if no battery info
    fi
}

# Get charging status
hsin_cpu_safety_charging() {
    if [ -f /sys/class/power_supply/battery/status ]; then
        _status=$(cat /sys/class/power_supply/battery/status 2>/dev/null)
        case "$_status" in
            Charging|Full) echo "true"; return 0 ;;
        esac
    fi
    echo "false"
}

# Check if boost is allowed
hsin_cpu_safety_can_boost() {
    # Check temperature
    _temp_status=$(hsin_cpu_safety_temp_status)
    case "$_temp_status" in
        critical|limit) return 1 ;;
    esac

    # Check battery (only when not charging)
    _charging=$(hsin_cpu_safety_charging)
    if [ "$_charging" = "false" ]; then
        _bat=$(hsin_cpu_safety_battery)
        [ -n "$_bat" ] && [ "$_bat" -lt "$HSIN_BAT_LOW" ] 2>/dev/null && return 1
    fi

    return 0
}

# Get effective profile based on safety checks
hsin_cpu_safety_effective() {
    _requested="$1"

    _temp_status=$(hsin_cpu_safety_temp_status)
    _charging=$(hsin_cpu_safety_charging)
    _bat=$(hsin_cpu_safety_battery)

    # Temperature-based reduction
    case "$_temp_status" in
        critical)
            echo "battery"
            return 0
            ;;
        limit)
            case "$_requested" in
                extreme|performance)
                    echo "balanced"
                    return 0
                    ;;
            esac
            ;;
        reduce)
            case "$_requested" in
                extreme)
                    echo "performance"
                    return 0
                    ;;
            esac
            ;;
    esac

    # Battery-based reduction (only when not charging)
    if [ "$_charging" = "false" ]; then
        if [ -n "$_bat" ] && [ "$_bat" -lt "$HSIN_BAT_LOW" ] 2>/dev/null; then
            echo "battery"
            return 0
        fi
        if [ -n "$_bat" ] && [ "$_bat" -lt "$HSIN_BAT_MEDIUM" ] 2>/dev/null; then
            case "$_requested" in
                extreme)
                    echo "performance"
                    return 0
                    ;;
            esac
        fi
    fi

    echo "$_requested"
}

# Print safety status
hsin_cpu_safety_print() {
    _temp=$(hsin_cpu_safety_temp)
    # Guard: temp is in millidegrees; dividing 0 by 1000 still gives 0
    # but an empty string would fail. Default to 0.
    _temp_c=0
    [ -n "$_temp" ] && _temp_c=$((_temp / 1000))
    _temp_status=$(hsin_cpu_safety_temp_status)
    _bat=$(hsin_cpu_safety_battery)
    _charging=$(hsin_cpu_safety_charging)

    echo ""
    echo "  Safety Status:"
    printf "    Temperature: %s°C (%s)\n" "$_temp_c" "$_temp_status"
    printf "    Battery:     %s%%\n" "${_bat:-?}"
    printf "    Charging:    %s\n" "$_charging"
    echo ""
}

return 0 2>/dev/null || true
