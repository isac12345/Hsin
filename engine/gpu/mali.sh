#!/system/bin/sh
# HSIN GPU Engine - ARM Mali Specific
# Credit: logic inspired by GTurbo (GPU governor control)

[ -z "$HSIN_MODULE_PATH" ] && HSIN_MODULE_PATH="/data/adb/modules/hsin"

# Apply Mali tweaks
hsin_gpu_mali_apply() {
    _profile="$1"

    # Load detector
    . "$HSIN_MODULE_PATH/engine/gpu/detector.sh" 2>/dev/null
    hsin_gpu_detect

    [ "$HSIN_GPU_VENDOR" = "mali" ] || return 1
    _applied=0

    # Apply via devfreq if available
    if [ -n "$HSIN_GPU_DEVFREQ" ] && [ -d "$HSIN_GPU_DEVFREQ" ]; then
        . "$HSIN_MODULE_PATH/engine/gpu/generic.sh" 2>/dev/null
        hsin_gpu_generic_apply "$_profile" "$HSIN_GPU_DEVFREQ"
        _applied=$?
    fi

    # Apply Mali platform specific (if available)
    if [ -n "$HSIN_GPU_MALI" ] && [ -d "$HSIN_GPU_MALI" ]; then
        # power_policy: always_on vs coarse_demand
        if [ -w "$HSIN_GPU_MALI/power_policy" ]; then
            case "$_profile" in
                battery)     _pp="coarse_demand" ;;
                balanced)    _pp="always_on" ;;
                performance) _pp="always_on" ;;
                extreme)     _pp="always_on" ;;
            esac
            echo "$_pp" > "$HSIN_GPU_MALI/power_policy" 2>/dev/null && _applied=$((_applied + 1))
        fi

        # dvfs_governor: 0=coarse_demand, 1=ondemand, 2=performance
        if [ -w "$HSIN_GPU_MALI/dvfs_governor" ]; then
            case "$_profile" in
                battery)     _dg="1" ;;
                balanced)    _dg="1" ;;
                performance) _dg="2" ;;
                extreme)     _dg="2" ;;
            esac
            echo "$_dg" > "$HSIN_GPU_MALI/dvfs_governor" 2>/dev/null && _applied=$((_applied + 1))
        fi

        # js_scheduling_period
        if [ -w "$HSIN_GPU_MALI/js_scheduling_period" ]; then
            case "$_profile" in
                battery)     _jsp="3" ;;
                balanced)    _jsp="2" ;;
                performance) _jsp="1" ;;
                extreme)     _jsp="1" ;;
            esac
            echo "$_jsp" > "$HSIN_GPU_MALI/js_scheduling_period" 2>/dev/null && _applied=$((_applied + 1))
        fi
    fi

    # Apply Mali KBase parameters (if available)
    if [ -n "$HSIN_GPU_KBASE" ] && [ -d "$HSIN_GPU_KBASE" ]; then
        # gpu_boost_level2: 0=off, 1=on (boost GPU performance)
        if [ -w "$HSIN_GPU_KBASE/gpu_boost_level2" ]; then
            case "$_profile" in
                battery)     _bl="0" ;;
                balanced)    _bl="0" ;;
                performance) _bl="1" ;;
                extreme)     _bl="1" ;;
            esac
            echo "$_bl" > "$HSIN_GPU_KBASE/gpu_boost_level2" 2>/dev/null && _applied=$((_applied + 1))
        fi

        # gpu_pollingtime: lower=more responsive, higher=more battery
        if [ -w "$HSIN_GPU_KBASE/gpu_pollingtime" ]; then
            case "$_profile" in
                battery)     _pt="8" ;;
                balanced)    _pt="4" ;;
                performance) _pt="4" ;;
                extreme)     _pt="1" ;;
            esac
            echo "$_pt" > "$HSIN_GPU_KBASE/gpu_pollingtime" 2>/dev/null && _applied=$((_applied + 1))
        fi

        # gpu_upthreshold: lower=GPU ramps faster, higher=more battery
        if [ -w "$HSIN_GPU_KBASE/gpu_upthreshold" ]; then
            case "$_profile" in
                battery)     _ut="88" ;;
                balanced)    _ut="72" ;;
                performance) _ut="55" ;;
                extreme)     _ut="30" ;;
            esac
            echo "$_ut" > "$HSIN_GPU_KBASE/gpu_upthreshold" 2>/dev/null && _applied=$((_applied + 1))
        fi
    fi

    echo "    Mali: applied=$_applied"
    return 0
}

# Get Mali state
hsin_gpu_mali_state() {
    . "$HSIN_MODULE_PATH/engine/gpu/detector.sh" 2>/dev/null
    hsin_gpu_detect

    [ "$HSIN_GPU_VENDOR" = "mali" ] || return 1

    echo "  Mali State:"
    if [ -n "$HSIN_GPU_DEVFREQ" ] && [ -d "$HSIN_GPU_DEVFREQ" ]; then
        . "$HSIN_MODULE_PATH/engine/gpu/generic.sh" 2>/dev/null
        hsin_gpu_generic_state "$HSIN_GPU_DEVFREQ"
    fi

    if [ -n "$HSIN_GPU_MALI" ] && [ -d "$HSIN_GPU_MALI" ]; then
        [ -f "$HSIN_GPU_MALI/power_policy" ] && {
            _pp=$(cat "$HSIN_GPU_MALI/power_policy" 2>/dev/null)
            printf "    power_policy:      %s\n" "$_pp"
        }
        [ -f "$HSIN_GPU_MALI/dvfs_governor" ] && {
            _dg=$(cat "$HSIN_GPU_MALI/dvfs_governor" 2>/dev/null)
            printf "    dvfs_governor:     %s\n" "$_dg"
        }
    fi

    if [ -n "$HSIN_GPU_KBASE" ] && [ -d "$HSIN_GPU_KBASE" ]; then
        [ -f "$HSIN_GPU_KBASE/gpu_boost_level2" ] && {
            _bl=$(cat "$HSIN_GPU_KBASE/gpu_boost_level2" 2>/dev/null)
            printf "    boost_level2:      %s\n" "$_bl"
        }
        [ -f "$HSIN_GPU_KBASE/gpu_pollingtime" ] && {
            _pt=$(cat "$HSIN_GPU_KBASE/gpu_pollingtime" 2>/dev/null)
            printf "    pollingtime:       %s\n" "$_pt"
        }
        [ -f "$HSIN_GPU_KBASE/gpu_upthreshold" ] && {
            _ut=$(cat "$HSIN_GPU_KBASE/gpu_upthreshold" 2>/dev/null)
            printf "    upthreshold:       %s\n" "$_ut"
        }
    fi
}

return 0 2>/dev/null || true
