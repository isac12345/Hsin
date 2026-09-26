#!/system/bin/sh
# HSIN Thermal Policy
# Credit: logic inspired by Sasha (thermal control)

[ -z "$HSIN_MODULE_PATH" ] && HSIN_MODULE_PATH="/data/adb/modules/hsin"
HSIN_DATA="${HSIN_DATA:-/data/adb/hsin}"
# shellcheck disable=SC1091
. "$HSIN_MODULE_PATH/core/sysfs.sh" 2>/dev/null
# shellcheck disable=SC1091
. "$HSIN_MODULE_PATH/core/scan_cache.sh" 2>/dev/null
# Diisi hsin_scan_lookup() (core/scan_cache.sh) tiap lookup field.
_sc_f=""

# Policy thresholds (millidegrees).
# BUG FIX: these were still the same miscalibrated values already fixed
# once in engine/cpu/safety.sh (40/45/50/60C) - 50C is a completely
# normal SoC temp under load, not a "hot, start throttling" state. This
# file was apparently missed when that fix went in elsewhere, so every
# apply of battery/balanced (via hsin_thermal_apply_cpu/_gpu below) was
# STILL silently capping CPU to 70% max freq and GPU to 80% max freq
# under totally ordinary gaming/load temperatures, and even
# performance/extreme could get force-throttled to 50% starting at just
# 60C. Realigned to the same scale now used everywhere else in HSIN
# (cpu/safety.sh: normal=60C/reduce=75C/limit=85C/critical=95C;
# policy_engine.sh: warn=75C/critical=85C/panic=95C; extreme.conf
# trip=95C) so this engine doesn't independently throttle under normal
# conditions anymore.
HSIN_THERMAL_POL_NORMAL=60000
HSIN_THERMAL_POL_WARM=75000
HSIN_THERMAL_POL_HOT=85000
HSIN_THERMAL_POL_CRITICAL=95000

# Current policy state
HSIN_THERMAL_POLICY=""
HSIN_THERMAL_PERF_TARGET="100"

# Determine policy based on temperature
hsin_thermal_policy_determine() {
    _temp="$1"

    if [ "$_temp" -ge "$HSIN_THERMAL_POL_CRITICAL" ] 2>/dev/null; then
        HSIN_THERMAL_POLICY="critical"
        HSIN_THERMAL_PERF_TARGET="50"
    elif [ "$_temp" -ge "$HSIN_THERMAL_POL_HOT" ] 2>/dev/null; then
        HSIN_THERMAL_POLICY="hot"
        HSIN_THERMAL_PERF_TARGET="70"
    elif [ "$_temp" -ge "$HSIN_THERMAL_POL_WARM" ] 2>/dev/null; then
        HSIN_THERMAL_POLICY="warm"
        HSIN_THERMAL_PERF_TARGET="85"
    elif [ "$_temp" -ge "$HSIN_THERMAL_POL_NORMAL" ] 2>/dev/null; then
        HSIN_THERMAL_POLICY="normal"
        HSIN_THERMAL_PERF_TARGET="95"
    else
        HSIN_THERMAL_POLICY="cool"
        HSIN_THERMAL_PERF_TARGET="100"
    fi

    echo "$HSIN_THERMAL_PERF_TARGET"
}

# Apply thermal policy to CPU frequency
# Daftar policy + cpuinfo_max_freq + tabel OPP diambil dari cache scan
# (core/scan_cache.sh), jadi tidak ada glob cpufreq/policy* dan tidak ada
# cat cpuinfo_max_freq per apply. Tinggal satu test [ -w ] tanpa fork tepat
# sebelum tulis; nilai max_freq yang di-cache hanya untuk picking OPP.
hsin_thermal_apply_cpu() {
    _policy="$1"
    _base_max="$2"

    # Note: $_base_max is currently unused; kept in the signature so the
    # call sites in hsin_thermal_engine_apply / hsin_thermal_apply don't
    # have to change. Logged for debugging.
    [ -n "$_base_max" ] && [ "$_base_max" -gt 0 ] 2>/dev/null || _base_max=""

    # Calculate reduced max
    _reduced=$(( _base_max * HSIN_THERMAL_PERF_TARGET / 100 ))
    [ -z "$_reduced" ] && _reduced=0

    hsin_scan_cpu_get
    for _id in $HSIN_SCAN_CPU_POLICIES; do
        hsin_scan_lookup "$HSIN_SCAN_CPU_POLICY_LINES" "$_id" 5
        _hw_max="$_sc_f"
        # Guard: kosong/non-numeric akan error di arithmetic.
        case "$_hw_max" in ''|*[!0-9]*) continue ;; esac
        [ "$_hw_max" -le 0 ] 2>/dev/null && continue

        _dir="$HSIN_SYSFS_CPU/cpufreq/policy$_id"
        _new_max=$(( _hw_max * HSIN_THERMAL_PERF_TARGET / 100 ))
        hsin_scan_lookup "$HSIN_SCAN_CPU_POLICY_LINES" "$_id" 7
        _opp_csv="$_sc_f"
        if [ -n "$_opp_csv" ]; then
            _avail=$(printf '%s' "$_opp_csv" | tr ',' ' ')
            _new_max=$(hsin_opp_cap_pick "$_new_max" "$_avail")
        fi
        [ -n "$_new_max" ] && [ -w "$_dir/scaling_max_freq" ] && \
            printf '%s\n' "$_new_max" > "$_dir/scaling_max_freq" 2>/dev/null
    done
}

# Apply thermal policy to GPU
# Sama seperti CPU: node devfreq + available_frequencies dari cache, satu
# test [ -w ] sebelum tulis, max_freq tetap dibaca live karena itu nilai
# yang berubah tiap apply.
hsin_thermal_apply_gpu() {
    _policy="$1"

    hsin_scan_devfreq_get
    for _node in $HSIN_SCAN_DEVFREQ_NODES; do
        _dir="$HSIN_SYSFS_DEVFREQ/$_node"
        [ -f "$_dir/max_freq" ] || continue

        hsin_scan_lookup "$HSIN_SCAN_DEVFREQ_LINES" "$_node" 1
        _opp_csv="$_sc_f"
        _avail=$(printf '%s' "$_opp_csv" | tr ',' ' ')
        [ -n "$_avail" ] || continue

        case "$_policy" in
            critical|hot)
                # Use an actual OPP, never an arbitrary value such as 1200
                # MHz on a 384/768/1500 MHz GPU table.
                _max_avail=$(hsin_opp_max "$_avail")
                [ -n "$_max_avail" ] || continue
                _target=$(hsin_opp_cap_pick "$(( _max_avail * 80 / 100 ))" "$_avail")
                ;;
            *)
                # Let DVFS handle it
                _max_avail=$(hsin_opp_max "$_avail")
                [ -n "$_max_avail" ] || continue
                _target="$_max_avail"
                ;;
        esac

        [ -n "$_target" ] && [ -w "$_dir/max_freq" ] && \
            printf '%s\n' "$_target" > "$_dir/max_freq" 2>/dev/null
    done
}

# Apply thermal policy to scheduling
hsin_thermal_apply_sched() {
    _policy="$1"

    case "$_policy" in
        critical)
            # Reduce uclamp for all tasks
            for _task in /proc/*/sched; do
                [ -f "$_task" ] || continue
                # Only adjust uclamp_max for background tasks
            done
            ;;
        hot)
            # Moderate reduction
            ;;
        *)
            # No adjustment needed
            ;;
    esac
}

# Full thermal policy application
hsin_thermal_apply() {
    _profile="$1"

    # Read current temps
    . "$HSIN_MODULE_PATH/engine/thermal/monitor.sh" 2>/dev/null
    hsin_thermal_read

    # Determine policy
    _perf=$(hsin_thermal_policy_determine "$HSIN_THERMAL_MAX_TEMP")

    # Apply based on profile
    case "$_profile" in
        battery|balanced)
            # Apply thermal policy
            hsin_thermal_apply_cpu "$HSIN_THERMAL_POLICY" ""
            hsin_thermal_apply_gpu "$HSIN_THERMAL_POLICY"
            ;;
        performance)
            # Less aggressive thermal management
            if [ "$HSIN_THERMAL_POLICY" = "critical" ]; then
                hsin_thermal_apply_cpu "$HSIN_THERMAL_POLICY" ""
                hsin_thermal_apply_gpu "$HSIN_THERMAL_POLICY"
            fi
            ;;
        extreme)
            # Extreme owns the hardware ceiling. Do not add a software clock
            # cap here; the dedicated extreme safety monitor handles an
            # emergency and OEM/kernel thermal protection remains active.
            ;;
    esac

    # Log
    _ts=$(date '+%Y-%m-%d %H:%M:%S')
    echo "$_ts [THERMAL] Policy=$HSIN_THERMAL_POLICY Perf=$_perf% MaxTemp=$HSIN_THERMAL_MAX_TEMP" >> "$HSIN_DATA/logs/thermal.log"
}

# Print policy status
hsin_thermal_policy_print() {
    . "$HSIN_MODULE_PATH/engine/thermal/monitor.sh" 2>/dev/null
    hsin_thermal_read
    _perf=$(hsin_thermal_policy_determine "$HSIN_THERMAL_MAX_TEMP")

    echo ""
    echo "╔══════════════════════════════════════╗"
    echo "║   HSIN Thermal Policy                ║"
    echo "╚══════════════════════════════════════╝"
    echo ""
    printf "  Max Temp:     %s\n" "$(hsin_thermal_format_temp "$HSIN_THERMAL_MAX_TEMP")"
    printf "  Policy:       %s\n" "${HSIN_THERMAL_POLICY:-unknown}"
    printf "  Perf Target:  %s%%\n" "$_perf"
    echo ""
    echo "  Rules:"
    printf "    cool     (<60C):     100%%\n"
    printf "    normal   (60-75C):   95%%\n"
    printf "    warm     (75-85C):   85%%\n"
    printf "    hot      (85-95C):   70%%\n"
    printf "    critical (>95C):     50%%\n"
    echo ""
}

return 0 2>/dev/null || true
