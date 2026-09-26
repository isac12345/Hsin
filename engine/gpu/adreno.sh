#!/system/bin/sh
# HSIN GPU Engine - Qualcomm Adreno (KGSL) Specific
# Credit: logic inspired by GTurbo (GPU governor control)

[ -z "$HSIN_MODULE_PATH" ] && HSIN_MODULE_PATH="/data/adb/modules/hsin"

# Apply Adreno KGSL tweaks
hsin_gpu_adreno_apply() {
    _profile="$1"

    # Load detector
    . "$HSIN_MODULE_PATH/engine/gpu/detector.sh" 2>/dev/null
    hsin_gpu_detect

    [ "$HSIN_GPU_VENDOR" = "adreno" ] || return 1
    [ -d "$HSIN_GPU_KGSL" ] || return 1
    _applied=0

    # Apply via devfreq if available
    if [ -n "$HSIN_GPU_DEVFREQ" ] && [ -d "$HSIN_GPU_DEVFREQ" ]; then
        . "$HSIN_MODULE_PATH/engine/gpu/generic.sh" 2>/dev/null
        hsin_gpu_generic_apply "$_profile" "$HSIN_GPU_DEVFREQ"
    fi

    # KGSL specific tweaks

    # default_pwrlevel (0=highest performance, max=num_pwrlevels-1)
    if [ -w "$HSIN_GPU_KGSL/default_pwrlevel" ] && [ -r "$HSIN_GPU_KGSL/num_pwrlevels" ]; then
        _np=$(cat "$HSIN_GPU_KGSL/num_pwrlevels" 2>/dev/null)
        _max_pwr=$((_np - 1))
        case "$_profile" in
            battery)     _pwr="$_max_pwr" ;;
            balanced)    _pwr=$((_np / 2)) ;;
            performance) _pwr="0" ;;
            extreme)     _pwr="0" ;;
        esac
        echo "$_pwr" > "$HSIN_GPU_KGSL/default_pwrlevel" 2>/dev/null && _applied=$((_applied + 1))
    fi

    # idle_timer (ms)
    if [ -w "$HSIN_GPU_KGSL/idle_timer" ]; then
        case "$_profile" in
            battery)     _idle="100" ;;
            balanced)    _idle="50" ;;
            performance) _idle="10" ;;
            extreme)     _idle="5" ;;
        esac
        echo "$_idle" > "$HSIN_GPU_KGSL/idle_timer" 2>/dev/null && _applied=$((_applied + 1))
    fi

    # force_clk_on (power vs performance)
    if [ -w "$HSIN_GPU_KGSL/force_clk_on" ]; then
        case "$_profile" in
            battery)     echo "0" > "$HSIN_GPU_KGSL/force_clk_on" 2>/dev/null ;;
            balanced)    echo "0" > "$HSIN_GPU_KGSL/force_clk_on" 2>/dev/null ;;
            performance) echo "1" > "$HSIN_GPU_KGSL/force_clk_on" 2>/dev/null && _applied=$((_applied + 1)) ;;
            extreme)     echo "1" > "$HSIN_GPU_KGSL/force_clk_on" 2>/dev/null && _applied=$((_applied + 1)) ;;
        esac
    fi

    # bus_split
    if [ -w "$HSIN_GPU_KGSL/bus_split" ]; then
        case "$_profile" in
            battery)     echo "1" > "$HSIN_GPU_KGSL/bus_split" 2>/dev/null ;;
            *)           echo "0" > "$HSIN_GPU_KGSL/bus_split" 2>/dev/null ;;
        esac
    fi

    echo "    Adreno (KGSL): applied=$_applied"
    return 0
}

# Get Adreno state
hsin_gpu_adreno_state() {
    . "$HSIN_MODULE_PATH/engine/gpu/detector.sh" 2>/dev/null
    hsin_gpu_detect

    [ "$HSIN_GPU_VENDOR" = "adreno" ] || return 1
    [ -d "$HSIN_GPU_KGSL" ] || return 1

    echo "  Adreno (KGSL) State:"
    [ -f "$HSIN_GPU_KGSL/default_pwrlevel" ] && {
        _pwr=$(cat "$HSIN_GPU_KGSL/default_pwrlevel" 2>/dev/null)
        printf "    default_pwrlevel: %s\n" "$_pwr"
    }
    [ -f "$HSIN_GPU_KGSL/num_pwrlevels" ] && {
        _np=$(cat "$HSIN_GPU_KGSL/num_pwrlevels" 2>/dev/null)
        printf "    num_pwrlevels:    %s\n" "$_np"
    }
    [ -f "$HSIN_GPU_KGSL/idle_timer" ] && {
        _idle=$(cat "$HSIN_GPU_KGSL/idle_timer" 2>/dev/null)
        printf "    idle_timer:       %s ms\n" "$_idle"
    }
    [ -f "$HSIN_GPU_KGSL/gpu_busy_percentage" ] && {
        _busy=$(cat "$HSIN_GPU_KGSL/gpu_busy_percentage" 2>/dev/null)
        printf "    gpu_busy:         %s%%\n" "$_busy"
    }
}

return 0 2>/dev/null || true
