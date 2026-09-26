#!/system/bin/sh
# HSIN Policy Engine

[ -z "$HSIN_MODULE_PATH" ] && HSIN_MODULE_PATH="/data/adb/modules/hsin"
HSIN_DATA="${HSIN_DATA:-/data/adb/hsin}"

# Load priority config
HSIN_PRIORITY_FILE="$HSIN_MODULE_PATH/config/priority.json"

# Priority levels (from priority.json)
HSIN_PRIO_THERMAL=100
HSIN_PRIO_STABILITY=90
HSIN_PRIO_BATTERY=80
HSIN_PRIO_CPU=70
HSIN_PRIO_GPU=60
HSIN_PRIO_MEMORY=50
HSIN_PRIO_IO=40
HSIN_PRIO_NETWORK=30

# Current constraints
HSIN_POLICY_THERMAL_OVERRIDE="false"
HSIN_POLICY_BATTERY_SAVER="false"
HSIN_POLICY_STABILITY_BLOCK="false"
HSIN_POLICY_ACTIVE_PROFILE="balanced"
HSIN_POLICY_EXTERNAL_CHANGE="false"

# Initialize policy engine
hsin_policy_init() {
    HSIN_POLICY_THERMAL_OVERRIDE="false"
    HSIN_POLICY_BATTERY_SAVER="false"
    HSIN_POLICY_STABILITY_BLOCK="false"
    HSIN_POLICY_EXTERNAL_CHANGE="false"
    # BUG FIX: ACTIVE_PROFILE was never reset here, only ever assigned by
    # specific branches inside hsin_policy_check (thermal/stability). The
    # battery-saver branch below returns 1 WITHOUT assigning it, so a
    # caller reading HSIN_POLICY_ACTIVE_PROFILE after a battery-saver
    # block could get a stale value left over from a completely
    # different policy check earlier (e.g. a past thermal panic's
    # "battery"), instead of a sane default. Reset it every init.
    HSIN_POLICY_ACTIVE_PROFILE="balanced"

    # Check thermal
    hsin_policy_thermal_check

    # Check battery
    hsin_policy_battery_check

    # Check stability
    hsin_policy_stability_check

    # Check external changes
    hsin_policy_external_check
}

# Check thermal status
hsin_policy_thermal_check() {
    _max_temp=0
    for _zone in /sys/class/thermal/thermal_zone*/temp; do
        [ -f "$_zone" ] || continue
        _t=$(cat "$_zone" 2>/dev/null)
        [ -n "$_t" ] && [ "$_t" -gt "$_max_temp" ] 2>/dev/null && _max_temp="$_t"
    done

    # Thresholds (millidegrees)
    _thermal_warn=75000
    _thermal_critical=85000
    _thermal_panic=95000

    if [ "$_max_temp" -ge "$_thermal_panic" ] 2>/dev/null; then
        HSIN_POLICY_THERMAL_OVERRIDE="panic"
        HSIN_POLICY_STABILITY_BLOCK="true"
    elif [ "$_max_temp" -ge "$_thermal_critical" ] 2>/dev/null; then
        HSIN_POLICY_THERMAL_OVERRIDE="critical"
    elif [ "$_max_temp" -ge "$_thermal_warn" ] 2>/dev/null; then
        HSIN_POLICY_THERMAL_OVERRIDE="warn"
    else
        HSIN_POLICY_THERMAL_OVERRIDE="false"
    fi
}

# Check battery status
hsin_policy_battery_check() {
    _bat=""
    if [ -f /sys/class/power_supply/battery/capacity ]; then
        _bat=$(cat /sys/class/power_supply/battery/capacity 2>/dev/null)
    fi

    _charging="false"
    if [ -f /sys/class/power_supply/battery/status ]; then
        _status=$(cat /sys/class/power_supply/battery/status 2>/dev/null)
        case "$_status" in
            Charging|Full) _charging="true" ;;
        esac
    fi

    if [ "$_charging" = "false" ] && [ -n "$_bat" ] && [ "$_bat" -le 20 ] 2>/dev/null; then
        HSIN_POLICY_BATTERY_SAVER="true"
    else
        HSIN_POLICY_BATTERY_SAVER="false"
    fi
}

# Check stability (crash count)
hsin_policy_stability_check() {
    if [ -f "$HSIN_DATA/crash_count" ]; then
        _crashes=$(cat "$HSIN_DATA/crash_count" 2>/dev/null)
        [ "$_crashes" -ge 3 ] 2>/dev/null && HSIN_POLICY_STABILITY_BLOCK="true"
    fi
}

# Check for external governor/frequency changes
hsin_policy_external_check() {
    [ -f "$HSIN_DATA/state.lock" ] || return 0

    # Check if CPU governor was changed externally
    _lock_gov=$(grep "^CPU_GOVERNOR=" "$HSIN_DATA/state.lock" 2>/dev/null | cut -d= -f2)
    if [ -n "$_lock_gov" ]; then
        for _policy in /sys/devices/system/cpu/cpufreq/policy*; do
            [ -d "$_policy" ] || continue
            [ -f "$_policy/scaling_governor" ] || continue
            _cur=$(cat "$_policy/scaling_governor" 2>/dev/null)
            if [ "$_cur" != "$_lock_gov" ]; then
                HSIN_POLICY_EXTERNAL_CHANGE="true"
                echo "[POLICY] WARNING: External governor change detected ($_lock_gov -> $_cur)"
                break
            fi
        done
    fi
}

# Check if an engine can apply a profile
hsin_policy_check() {
    _engine="$1"
    _profile="$2"

    # Refresh policy state
    hsin_policy_init

    # Extreme is an explicit rooted-user performance choice. Do not silently
    # downgrade it for warnings, charging/battery-saver, or historical crash
    # counters. A true panic is still a hard safety event and is handled by
    # the extreme safety monitor as well as this policy layer.
    if [ "$HSIN_POLICY_THERMAL_OVERRIDE" = "panic" ]; then
        case "$_profile" in
            performance|extreme)
                echo "[POLICY] Thermal panic: forcing battery"
                HSIN_POLICY_ACTIVE_PROFILE="battery"
                return 1
                ;;
        esac
    fi
    if [ "$_profile" != "extreme" ] && [ "$HSIN_POLICY_BATTERY_SAVER" = "true" ]; then
        case "$_profile" in
            performance) HSIN_POLICY_ACTIVE_PROFILE="balanced"; return 1;;
        esac
    fi
    if [ "$_profile" != "extreme" ] && [ "$HSIN_POLICY_STABILITY_BLOCK" = "true" ]; then
        case "$_profile" in
            performance|balanced) HSIN_POLICY_ACTIVE_PROFILE="battery"; return 1;;
        esac
    fi

    # External change detected: warn but allow
    if [ "$HSIN_POLICY_EXTERNAL_CHANGE" = "true" ]; then
        echo "[POLICY] WARNING: External changes detected, proceeding with caution"
    fi

    return 0
}

# Get effective profile after policy constraints
hsin_policy_effective() {
    _engine="$1"
    _profile="$2"

    hsin_policy_check "$_engine" "$_profile" && {
        echo "$_profile"
        return 0
    }

    echo "$HSIN_POLICY_ACTIVE_PROFILE"
}

# Print policy status
hsin_policy_status() {
    hsin_policy_init

    echo ""
    echo "╔══════════════════════════════════════╗"
    echo "║   Policy Engine Status               ║"
    echo "╚══════════════════════════════════════╝"
    echo ""
    printf "  Thermal Override:   %s\n" "${HSIN_POLICY_THERMAL_OVERRIDE:-false}"
    printf "  Battery Saver:     %s\n" "${HSIN_POLICY_BATTERY_SAVER:-false}"
    printf "  Stability Block:   %s\n" "${HSIN_POLICY_STABILITY_BLOCK:-false}"
    printf "  External Change:   %s\n" "${HSIN_POLICY_EXTERNAL_CHANGE:-false}"
    printf "  Active Profile:    %s\n" "${HSIN_POLICY_ACTIVE_PROFILE:-balanced}"
    echo ""
}

return 0 2>/dev/null || true
