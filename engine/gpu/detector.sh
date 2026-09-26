#!/system/bin/sh
# HSIN GPU Engine - Universal Detector
[ -z "$HSIN_MODULE_PATH" ] && HSIN_MODULE_PATH="/data/adb/modules/hsin"
. "$HSIN_MODULE_PATH/core/sysfs.sh" 2>/dev/null

hsin_gpu_detect() {
    HSIN_GPU_VENDOR="none"; HSIN_GPU_NODES=""; HSIN_GPU_DEVFREQ=""; HSIN_GPU_DEVFREQS=""; HSIN_GPU_PLATFORM=""; HSIN_GPU_KGSL=""; HSIN_GPU_MALI=""; HSIN_GPU_KBASE=""; HSIN_GPU_GED=""
    HSIN_GPU_GOV_WRITABLE="false"; HSIN_GPU_FREQ_WRITABLE="false"

    # Prefer KGSL when present: this is the native Adreno path.
    if [ -d /sys/class/kgsl/kgsl-3d0 ]; then
        HSIN_GPU_VENDOR="adreno"
        HSIN_GPU_KGSL="/sys/class/kgsl/kgsl-3d0"
        HSIN_GPU_NODES="$HSIN_GPU_KGSL"
    fi

    # Universal devfreq scan. Vendor-specific names are only a hint; an OF
    # compatible/device modalias is also inspected so nodes such as 23100000.gpu
    # on Unisoc are correctly classified as GPU.
    for _d in /sys/class/devfreq/*; do
        [ -d "$_d" ] || continue
        hsin_devfreq_gpu_candidate "$_d" || continue
        [ -z "$HSIN_GPU_DEVFREQ" ] && HSIN_GPU_DEVFREQ="$_d"
        HSIN_GPU_DEVFREQS="$HSIN_GPU_DEVFREQS $_d"
        case "$HSIN_GPU_VENDOR" in
            none)
                _meta=$(cat "$_d/device/of_node/compatible" 2>/dev/null | tr '\0' ' ' | tr '[:upper:]' '[:lower:]')
                _name=$(basename "$_d" | tr '[:upper:]' '[:lower:]')
                case "$_meta $_name" in
                    *adreno*|*kgsl*) HSIN_GPU_VENDOR="adreno" ;;
                    *mali*) HSIN_GPU_VENDOR="mali" ;;
                    *powervr*|*pvr*|*imgtec*|*img*) HSIN_GPU_VENDOR="powervr" ;;
                    *) HSIN_GPU_VENDOR="generic" ;;
                esac
                ;;
        esac
    done

    # Fallback metadata for Mali KBase / classic platform paths.
    if [ "$HSIN_GPU_VENDOR" = "none" ]; then
        for _m in /sys/devices/platform/*.mali /sys/devices/platform/*mali*; do
            [ -d "$_m" ] || continue
            HSIN_GPU_VENDOR="mali"; HSIN_GPU_MALI="$_m"; HSIN_GPU_NODES="$_m"; break
        done
    fi
    [ -d /sys/module/mali_kbase/parameters ] && HSIN_GPU_KBASE="/sys/module/mali_kbase/parameters"
    [ -d /sys/kernel/ged ] && HSIN_GPU_GED="/sys/kernel/ged"
    [ -d /sys/class/kgsl/kgsl-3d0 ] && HSIN_GPU_VENDOR="adreno"

    [ -n "$HSIN_GPU_DEVFREQ" ] && HSIN_GPU_NODES="$HSIN_GPU_DEVFREQ"
    if [ -n "$HSIN_GPU_DEVFREQ" ]; then
        [ -w "$HSIN_GPU_DEVFREQ/governor" ] && HSIN_GPU_GOV_WRITABLE="true"
        [ -w "$HSIN_GPU_DEVFREQ/max_freq" ] && HSIN_GPU_FREQ_WRITABLE="true"
    fi
    [ -n "$HSIN_GPU_KGSL" ] && [ -w "$HSIN_GPU_KGSL/default_pwrlevel" ] && HSIN_GPU_FREQ_WRITABLE="true"
}

hsin_gpu_print() {
    hsin_gpu_detect
    echo ""
    echo "HSIN GPU Detection"
    printf "  Vendor: %s\n" "$HSIN_GPU_VENDOR"
    printf "  Devfreq: %s\n" "${HSIN_GPU_DEVFREQ:-none}"
    printf "  KGSL: %s\n" "${HSIN_GPU_KGSL:-none}"
    printf "  Writable governor: %s\n" "$HSIN_GPU_GOV_WRITABLE"
    printf "  Writable max_freq: %s\n" "$HSIN_GPU_FREQ_WRITABLE"
    if [ -n "$HSIN_GPU_DEVFREQ" ]; then
        [ -f "$HSIN_GPU_DEVFREQ/available_governors" ] && printf "  Governors: %s\n" "$(cat "$HSIN_GPU_DEVFREQ/available_governors" 2>/dev/null)"
        [ -f "$HSIN_GPU_DEVFREQ/available_frequencies" ] && printf "  Frequencies: %s\n" "$(cat "$HSIN_GPU_DEVFREQ/available_frequencies" 2>/dev/null)"
    fi
}

return 0 2>/dev/null || true
