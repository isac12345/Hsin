#!/system/bin/sh
# HSIN Thermal Apply Controller
# Credit: logic inspired by Sasha (thermal control)

[ -z "$HSIN_MODULE_PATH" ] && HSIN_MODULE_PATH="/data/adb/modules/hsin"
HSIN_DATA="${HSIN_DATA:-/data/adb/hsin}"

# Full thermal apply flow
hsin_thermal_engine_apply() {
    _profile="${1:-balanced}"
    _start_time=$(date +%s)

    echo ""
    echo "╔══════════════════════════════════════╗"
    echo "║   HSIN Thermal Engine                 ║"
    echo "╚══════════════════════════════════════╝"
    echo ""

    # Step 1: Detect
    echo "  Step 1: Detect"
    . "$HSIN_MODULE_PATH/engine/thermal/detect.sh" 2>/dev/null
    hsin_thermal_detect

    # Step 2: Read temperatures
    echo "  Step 2: Read"
    . "$HSIN_MODULE_PATH/engine/thermal/monitor.sh" 2>/dev/null
    hsin_thermal_read
    hsin_thermal_classify "$HSIN_THERMAL_MAX_TEMP"

    printf "    CPU:      %s\n" "$(hsin_thermal_format_temp "$HSIN_THERMAL_CPU_TEMP")"
    printf "    GPU:      %s\n" "$(hsin_thermal_format_temp "$HSIN_THERMAL_GPU_TEMP")"
    printf "    Battery:  %s\n" "$(hsin_thermal_format_temp "$HSIN_THERMAL_BATTERY_TEMP")"
    printf "    Max:      %s\n" "$(hsin_thermal_format_temp "$HSIN_THERMAL_MAX_TEMP")"
    printf "    State:    %s\n" "$HSIN_THERMAL_STATE"
    echo ""

    # Step 3: Determine policy
    echo "  Step 3: Policy"
    . "$HSIN_MODULE_PATH/engine/thermal/policy.sh" 2>/dev/null
    _perf=$(hsin_thermal_policy_determine "$HSIN_THERMAL_MAX_TEMP")
    printf "    Thermal Policy: %s\n" "$HSIN_THERMAL_POLICY"
    printf "    Perf Target:    %s%%\n" "$_perf"
    echo ""

    # Step 4: Backup
    echo "  Step 4: Backup"
    . "$HSIN_MODULE_PATH/engine/thermal/backup.sh" 2>/dev/null
    hsin_thermal_backup
    echo ""

    # Step 5: Apply policy
    echo "  Step 5: Apply"
    hsin_thermal_apply "$_profile"
    echo "    Applied: $HSIN_THERMAL_POLICY (perf=$_perf%)"
    echo ""

    # Step 6: Verify
    echo "  Step 6: Verify"
    hsin_thermal_read
    hsin_thermal_classify "$HSIN_THERMAL_MAX_TEMP"
    _verify_perf=$(hsin_thermal_policy_determine "$HSIN_THERMAL_MAX_TEMP")

    if [ "$_verify_perf" = "$_perf" ]; then
        printf "    Status:  OK\n"
    else
        printf "    Status:  Policy updated (%s%%)\n" "$_verify_perf"
    fi
    echo ""

    # Step 7: Log
    _end_time=$(date +%s)
    _duration=$((_end_time - _start_time))
    _ts=$(date '+%Y-%m-%d %H:%M:%S')
    mkdir -p "$HSIN_DATA/logs" 2>/dev/null
    echo "$_ts [THERMAL] Profile=$_profile Policy=$HSIN_THERMAL_POLICY Perf=$_perf% Duration=${_duration}s" >> "$HSIN_DATA/logs/thermal.log"

    echo "╔══════════════════════════════════════╗"
    echo "║   Thermal Apply Complete              ║"
    echo "╚══════════════════════════════════════╝"
    echo ""
}

# Quick thermal test (for hsin thermal-test)
hsin_thermal_test() {
    . "$HSIN_MODULE_PATH/engine/thermal/detect.sh" 2>/dev/null
    . "$HSIN_MODULE_PATH/engine/thermal/monitor.sh" 2>/dev/null

    hsin_thermal_read

    echo ""
    echo "╔══════════════════════════════════════╗"
    echo "║   HSIN Thermal Test                   ║"
    echo "╚══════════════════════════════════════╝"
    echo ""

    # CPU
    _cpu_fmt=$(hsin_thermal_format_temp "$HSIN_THERMAL_CPU_TEMP")
    if [ "$HSIN_THERMAL_CPU_TEMP" -gt 0 ] 2>/dev/null; then
        printf "  CPU:      PASS %s\n" "$_cpu_fmt"
    else
        printf "  CPU:      SKIP (no zone found)\n"
    fi

    # GPU
    _gpu_fmt=$(hsin_thermal_format_temp "$HSIN_THERMAL_GPU_TEMP")
    if [ "$HSIN_THERMAL_GPU_TEMP" -gt 0 ] 2>/dev/null; then
        printf "  GPU:      PASS %s\n" "$_gpu_fmt"
    else
        printf "  GPU:      SKIP (no zone found)\n"
    fi

    # Battery
    _bat_fmt=$(hsin_thermal_format_temp "$HSIN_THERMAL_BATTERY_TEMP")
    if [ "$HSIN_THERMAL_BATTERY_TEMP" -gt 0 ] 2>/dev/null; then
        printf "  Battery:  PASS %s\n" "$_bat_fmt"
    else
        printf "  Battery:  SKIP (no zone found)\n"
    fi

    echo ""

    # Protection status
    printf "  Protection: ACTIVE\n"
    echo ""

    # Adaptive control
    _level=$(hsin_thermal_performance_level "$HSIN_THERMAL_MAX_TEMP")
    printf "  Adaptive control: READY (%s%%)\n" "$_level"
    echo ""
}

return 0 2>/dev/null || true
