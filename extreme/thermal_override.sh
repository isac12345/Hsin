#!/system/bin/sh
# HSIN Extreme Thermal Policy
# Extreme does NOT disable or raise vendor thermal trip points. It only reports
# the native limits; CPU/GPU performance can run at the hardware ceiling while
# Android/kernel thermal protection remains authoritative.
[ -z "$HSIN_MODULE_PATH" ] && HSIN_MODULE_PATH="/data/adb/modules/hsin"
HSIN_DATA="${HSIN_DATA:-/data/adb/hsin}"

HSIN_EXTREME_TEMP_WARN=80000
HSIN_EXTREME_TEMP_EMERGENCY=95000
HSIN_EXTREME_TEMP_PANIC=100000

hsin_extreme_thermal_detect() {
    _found=0
    for _z in /sys/class/thermal/thermal_zone*; do
        [ -d "$_z" ] || continue
        _type=$(cat "$_z/type" 2>/dev/null)
        _temp=$(cat "$_z/temp" 2>/dev/null)
        _trip=$(cat "$_z/trip_point_0_temp" 2>/dev/null)
        [ -z "$_type" ] && continue
        _fmt="N/A"; [ -n "$_temp" ] && [ "$_temp" -gt 1000 ] 2>/dev/null && _fmt="$((_temp/1000))C"
        _tcf="native"; [ -n "$_trip" ] && [ "$_trip" -gt 1000 ] 2>/dev/null && _tcf="$((_trip/1000))C"
        printf '  %s: temp=%s native_trip=%s\n' "$_type" "$_fmt" "$_tcf"
        _found=$((_found+1))
    done
    [ "$_found" -gt 0 ] || echo '  No thermal zones detected'
}

hsin_extreme_thermal_max() {
    _max=0
    for _z in /sys/class/thermal/thermal_zone*/temp; do
        [ -f "$_z" ] || continue
        _t=$(cat "$_z" 2>/dev/null)
        [ -n "$_t" ] && [ "$_t" -gt "$_max" ] 2>/dev/null && _max="$_t"
    done
    echo "$_max"
}

hsin_extreme_thermal_check() {
    _max=$(hsin_extreme_thermal_max)
    if [ "$_max" -ge "$HSIN_EXTREME_TEMP_PANIC" ] 2>/dev/null; then echo PANIC; return 3
    elif [ "$_max" -ge "$HSIN_EXTREME_TEMP_EMERGENCY" ] 2>/dev/null; then echo EMERGENCY; return 2
    elif [ "$_max" -ge "$HSIN_EXTREME_TEMP_WARN" ] 2>/dev/null; then echo WARNING; return 1
    fi
    echo OK; return 0
}

hsin_extreme_thermal_apply() {
    echo 'Extreme thermal: native kernel/OEM thermal protection preserved (no trip-point override)'
    return 0
}

hsin_extreme_thermal_restore() {
    echo 'Extreme thermal restore: no trip-point modifications were made'
    return 0
}

hsin_extreme_thermal_monitor() {
    while true; do
        _s=$(hsin_extreme_thermal_check); _m=$(hsin_extreme_thermal_max)
        _c='N/A'; [ "$_m" -gt 1000 ] 2>/dev/null && _c="$((_m/1000))C"
        echo "[$(date +%H:%M:%S)] $_c - $_s"
        case "$_s" in EMERGENCY|PANIC) return 1;; esac
        sleep 5
    done
}

return 0 2>/dev/null || true
