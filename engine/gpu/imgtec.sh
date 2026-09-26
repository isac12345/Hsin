#!/system/bin/sh
# HSIN GPU Engine - MediaTek GED Specific
# Credit: logic inspired by GTurbo (GPU governor control)

[ -z "$HSIN_MODULE_PATH" ] && HSIN_MODULE_PATH="/data/adb/modules/hsin"

# Apply MediaTek GED tweaks
hsin_gpu_imgtec_apply() {
    _profile="$1"

    # Load detector
    . "$HSIN_MODULE_PATH/engine/gpu/detector.sh" 2>/dev/null
    hsin_gpu_detect

    [ "$HSIN_GPU_VENDOR" = "imgtec" ] || return 1
    _applied=0

    # GED boost
    if [ -d "$HSIN_GPU_GED" ]; then
        # ged_dvfs_boost
        if [ -w "$HSIN_GPU_GED/ged_dvfs_boost" ]; then
            case "$_profile" in
                battery)     echo "0" > "$HSIN_GPU_GED/ged_dvfs_boost" 2>/dev/null ;;
                balanced)    echo "0" > "$HSIN_GPU_GED/ged_dvfs_boost" 2>/dev/null ;;
                performance) echo "1" > "$HSIN_GPU_GED/ged_dvfs_boost" 2>/dev/null && _applied=$((_applied + 1)) ;;
                extreme)     echo "1" > "$HSIN_GPU_GED/ged_dvfs_boost" 2>/dev/null && _applied=$((_applied + 1)) ;;
            esac
        fi

        # ged_dvfs_force_up
        if [ -w "$HSIN_GPU_GED/ged_dvfs_force_up" ]; then
            case "$_profile" in
                performance|extreme)
                    echo "1" > "$HSIN_GPU_GED/ged_dvfs_force_up" 2>/dev/null && _applied=$((_applied + 1))
                    ;;
                *)
                    echo "0" > "$HSIN_GPU_GED/ged_dvfs_force_up" 2>/dev/null
                    ;;
            esac
        fi
    fi

    # gpufreq interface (if available)
    if [ -f /proc/gpufreq/gpufreq_power_limited ]; then
        case "$_profile" in
            battery)
                # Limit max frequency
                _max_freq=$(cat /proc/gpufreq/gpufreq_opp_dump 2>/dev/null | head -1 | awk '{print $1}')
                [ -n "$_max_freq" ] && {
                    echo "0 $_max_freq" > /proc/gpufreq/gpufreq_power_limited 2>/dev/null && _applied=$((_applied + 1))
                }
                ;;
            balanced|performance|extreme)
                # Allow full frequency
                echo "0 0" > /proc/gpufreq/gpufreq_power_limited 2>/dev/null && _applied=$((_applied + 1))
                ;;
        esac
    fi

    # FPSGO (if available)
    if [ -d /sys/module/mtk_fpsgo/parameters ]; then
        case "$_profile" in
            battery)
                echo "0" > /sys/module/mtk_fpsgo/parameters/boost_affinity 2>/dev/null
                ;;
            balanced|performance|extreme)
                echo "1" > /sys/module/mtk_fpsgo/parameters/boost_affinity 2>/dev/null && _applied=$((_applied + 1))
                ;;
        esac
    fi

    echo "    MediaTek GED: applied=$_applied"
    return 0
}

# Get MediaTek GED state
hsin_gpu_imgtec_state() {
    . "$HSIN_MODULE_PATH/engine/gpu/detector.sh" 2>/dev/null
    hsin_gpu_detect

    [ "$HSIN_GPU_VENDOR" = "imgtec" ] || return 1

    echo "  MediaTek GED State:"
    if [ -d "$HSIN_GPU_GED" ]; then
        [ -f "$HSIN_GPU_GED/ged_dvfs_boost" ] && {
            _boost=$(cat "$HSIN_GPU_GED/ged_dvfs_boost" 2>/dev/null)
            printf "    ged_dvfs_boost: %s\n" "$_boost"
        }
    fi
    if [ -f /proc/gpufreq/gpufreq_opp_dump ]; then
        _opp=$(cat /proc/gpufreq/gpufreq_opp_dump 2>/dev/null | head -3)
        printf "    gpufreq_opp:\n%s\n" "$_opp"
    fi
}

return 0 2>/dev/null || true
