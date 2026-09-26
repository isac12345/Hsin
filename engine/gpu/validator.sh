#!/system/bin/sh
# HSIN GPU Engine - Validator

[ -z "$HSIN_MODULE_PATH" ] && HSIN_MODULE_PATH="/data/adb/modules/hsin"
HSIN_DATA="${HSIN_DATA:-/data/adb/hsin}"

# Scan GPU capabilities
hsin_gpu_cap_scan() {
    # Reset
    HSIN_GPU_CAP_DVFS="false"
    HSIN_GPU_CAP_GOVERNOR="false"
    HSIN_GPU_CAP_FREQ_CONTROL="false"
    HSIN_GPU_CAP_POWER_POLICY="false"
    HSIN_GPU_CAP_BOOST="false"
    HSIN_GPU_CAP_THERMAL_LINK="false"
    HSIN_GPU_CAP_CUR_FREQ="false"
    HSIN_GPU_CAP_MIN_FREQ="false"
    HSIN_GPU_CAP_MAX_FREQ="false"

    # Load detector
    . "$HSIN_MODULE_PATH/engine/gpu/detector.sh" 2>/dev/null
    hsin_gpu_detect

    case "$HSIN_GPU_VENDOR" in
        adreno)
            # KGSL capabilities
            [ -d "$HSIN_GPU_KGSL" ] || return 1

            # DVFS
            [ -f "$HSIN_GPU_KGSL/default_pwrlevel" ] && HSIN_GPU_CAP_DVFS="true"

            # Governor (via devfreq)
            if [ -n "$HSIN_GPU_DEVFREQ" ] && [ -f "$HSIN_GPU_DEVFREQ/available_governors" ]; then
                HSIN_GPU_CAP_GOVERNOR="true"
            fi

            # Freq control
            [ -f "$HSIN_GPU_KGSL/default_pwrlevel" ] && HSIN_GPU_CAP_FREQ_CONTROL="true"

            # Power policy
            [ -f "$HSIN_GPU_KGSL/force_clk_on" ] && HSIN_GPU_CAP_POWER_POLICY="true"

            # Boost
            [ -f "$HSIN_GPU_KGSL/devfreq/boost" ] && HSIN_GPU_CAP_BOOST="true"
            ;;

        mali)
            [ -n "$HSIN_GPU_DEVFREQ" ] || [ -n "$HSIN_GPU_MALI" ] || return 1

            # DVFS
            [ -f "$HSIN_GPU_DEVFREQ/available_frequencies" ] 2>/dev/null && HSIN_GPU_CAP_DVFS="true"

            # Governor
            if [ -f "$HSIN_GPU_DEVFREQ/available_governors" ]; then
                HSIN_GPU_CAP_GOVERNOR="true"
            fi

            # Freq control
            [ -f "$HSIN_GPU_DEVFREQ/min_freq" ] && [ -f "$HSIN_GPU_DEVFREQ/max_freq" ] && \
                HSIN_GPU_CAP_FREQ_CONTROL="true"

            # Power policy (Mali platform specific)
            if [ -n "$HSIN_GPU_MALI" ]; then
                [ -f "$HSIN_GPU_MALI/power_policy" ] && HSIN_GPU_CAP_POWER_POLICY="true"
            fi

            # Boost
            [ -f "$HSIN_GPU_DEVFREQ/boost" ] && HSIN_GPU_CAP_BOOST="true"
            ;;

        imgtec)
            # MediaTek GED
            [ -d "$HSIN_GPU_GED" ] || return 1

            # DVFS
            [ -f /proc/gpufreq/gpufreq_opp_dump ] && HSIN_GPU_CAP_DVFS="true"

            # Freq control
            [ -f /proc/gpufreq/gpufreq_power_limited ] && HSIN_GPU_CAP_FREQ_CONTROL="true"

            # Boost
            [ -f "$HSIN_GPU_GED/ged_dvfs_boost" ] && HSIN_GPU_CAP_BOOST="true"
            ;;

        generic)
            [ -n "$HSIN_GPU_DEVFREQ" ] || return 1

            # DVFS
            [ -f "$HSIN_GPU_DEVFREQ/available_frequencies" ] && HSIN_GPU_CAP_DVFS="true"

            # Governor
            [ -f "$HSIN_GPU_DEVFREQ/available_governors" ] && HSIN_GPU_CAP_GOVERNOR="true"

            # Freq control
            [ -f "$HSIN_GPU_DEVFREQ/min_freq" ] && [ -f "$HSIN_GPU_DEVFREQ/max_freq" ] && \
                HSIN_GPU_CAP_FREQ_CONTROL="true"
            ;;

        none)
            return 1
            ;;
    esac

    # Thermal link (common check)
    if [ -d /sys/class/thermal ]; then
        for _zone in /sys/class/thermal/thermal_zone*; do
            [ -d "$_zone" ] || continue
            _type=$(cat "$_zone/type" 2>/dev/null | tr '[:upper:]' '[:lower:]')
            case "$_type" in
                *gpu*) HSIN_GPU_CAP_THERMAL_LINK="true"; break ;;
            esac
        done
    fi

    return 0
}

# Generate capability JSON
hsin_gpu_cap_json() {
    [ -z "$HSIN_GPU_VENDOR" ] && hsin_gpu_cap_scan

    _out_dir="$HSIN_DATA/reports"
    mkdir -p "$_out_dir" 2>/dev/null

    {
        echo "{"
        echo "  \"vendor\": \"$HSIN_GPU_VENDOR\","
        echo "  \"devfreq\": $HSIN_GPU_CAP_DVFS,"
        echo "  \"governor\": $HSIN_GPU_CAP_GOVERNOR,"
        echo "  \"freq_control\": $HSIN_GPU_CAP_FREQ_CONTROL,"
        echo "  \"power_policy\": $HSIN_GPU_CAP_POWER_POLICY,"
        echo "  \"boost\": $HSIN_GPU_CAP_BOOST,"
        echo "  \"thermal_link\": $HSIN_GPU_CAP_THERMAL_LINK,"
        echo "  \"cur_freq\": $HSIN_GPU_CAP_CUR_FREQ,"
        echo "  \"min_freq\": $HSIN_GPU_CAP_MIN_FREQ,"
        echo "  \"max_freq\": $HSIN_GPU_CAP_MAX_FREQ"
        echo "}"
    } > "$_out_dir/gpu_cap.json"
}

# Print capability report
hsin_gpu_cap_print() {
    [ -z "$HSIN_GPU_VENDOR" ] && hsin_gpu_cap_scan

    echo ""
    echo "  GPU Capabilities:"
    printf "    DVFS:         %s\n" "$HSIN_GPU_CAP_DVFS"
    printf "    Governor:     %s\n" "$HSIN_GPU_CAP_GOVERNOR"
    printf "    Freq Control: %s\n" "$HSIN_GPU_CAP_FREQ_CONTROL"
    printf "    Power Policy: %s\n" "$HSIN_GPU_CAP_POWER_POLICY"
    printf "    Boost:        %s\n" "$HSIN_GPU_CAP_BOOST"
    printf "    Thermal Link: %s\n" "$HSIN_GPU_CAP_THERMAL_LINK"
    echo ""
}

return 0 2>/dev/null || true
