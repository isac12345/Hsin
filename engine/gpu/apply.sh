#!/system/bin/sh
# HSIN GPU Engine - Universal Apply Controller
[ -z "$HSIN_MODULE_PATH" ] && HSIN_MODULE_PATH="/data/adb/modules/hsin"
HSIN_DATA="${HSIN_DATA:-/data/adb/hsin}"
. "$HSIN_MODULE_PATH/core/logger.sh" 2>/dev/null
. "$HSIN_MODULE_PATH/core/sysfs.sh" 2>/dev/null
. "$HSIN_MODULE_PATH/engine/gpu/detector.sh" 2>/dev/null
. "$HSIN_MODULE_PATH/engine/gpu/generic.sh" 2>/dev/null
. "$HSIN_MODULE_PATH/engine/gpu/devfreq_tuning.sh" 2>/dev/null
. "$HSIN_MODULE_PATH/engine/gpu/mali.sh" 2>/dev/null

hsin_gpu_backup() {
    _d="$HSIN_DATA/backups/gpu_native"
    mkdir -p "$_d" 2>/dev/null
    hsin_gpu_detect
    for _n in $HSIN_GPU_DEVFREQS; do
        [ -d "$_n" ] || { hsin_report_skip "backup GPU: node ${_n##*/} tidak ada"; continue; }
        _id=$(basename "$_n")
        mkdir -p "$_d/$_id" 2>/dev/null
        for _f in governor min_freq max_freq; do
            [ -f "$_n/$_f" ] && hsin_node_read "$_n/$_f" > "$_d/$_id/$_f" 2>/dev/null
        done
    done
    if [ -n "$HSIN_GPU_KGSL" ] && [ -d "$HSIN_GPU_KGSL" ]; then
        mkdir -p "$_d/kgsl" 2>/dev/null
        for _f in default_pwrlevel idle_timer force_clk_on; do
            [ -f "$HSIN_GPU_KGSL/$_f" ] && hsin_node_read "$HSIN_GPU_KGSL/$_f" > "$_d/kgsl/$_f" 2>/dev/null
        done
    fi
    printf '%s\n' "$_d"
}

hsin_gpu_restore() {
    _d="$1"; [ -d "$_d" ] || return 1
    hsin_gpu_detect
    for _n in $HSIN_GPU_DEVFREQS; do
        [ -d "$_n" ] || { hsin_report_skip "restore GPU: node ${_n##*/} tidak ada"; continue; }
        _id=$(basename "$_n")
        for _f in governor max_freq min_freq; do
            [ -f "$_d/$_id/$_f" ] && [ -w "$_n/$_f" ] && printf '%s\n' "$(cat "$_d/$_id/$_f" 2>/dev/null)" > "$_n/$_f" 2>/dev/null
        done
    done
    if [ -n "$HSIN_GPU_KGSL" ] && [ -d "$_d/kgsl" ]; then
        for _f in default_pwrlevel idle_timer force_clk_on; do
            [ -f "$_d/kgsl/$_f" ] && [ -w "$HSIN_GPU_KGSL/$_f" ] && printf '%s\n' "$(cat "$_d/kgsl/$_f" 2>/dev/null)" > "$HSIN_GPU_KGSL/$_f" 2>/dev/null
        done
    fi
    return 0
}

hsin_gpu_adreno_kgsl_apply() {
    _profile="$1"
    [ -n "$HSIN_GPU_KGSL" ] && [ -d "$HSIN_GPU_KGSL" ] || return 0
    case "$_profile" in
        extreme) _pwr=0 ;;
        performance) _pwr=0 ;;
        *) return 0 ;;
    esac
    if [ -w "$HSIN_GPU_KGSL/default_pwrlevel" ]; then
        if hsin_node_write_verify "$HSIN_GPU_KGSL/default_pwrlevel" "$_pwr"; then
            echo "    Adreno KGSL: default_pwrlevel=$_pwr (verified)"
        else
            echo "    Adreno KGSL: default_pwrlevel skip (rejected/read-only)"
        fi
    fi
}

hsin_gpu_apply() {
    _profile="$1"
    hsin_gpu_detect
    echo "    GPU backend: vendor=${HSIN_GPU_VENDOR} devfreq=${HSIN_GPU_DEVFREQ:-none} (nodes=${HSIN_GPU_NODE_SOURCE:-scan})"
    if [ -n "$HSIN_GPU_DEVFREQS" ]; then
        for _d in $HSIN_GPU_DEVFREQS; do
            [ -d "$_d" ] || continue
            hsin_gpu_generic_apply "$_profile" "$_d"
        done
    else
        echo "    GPU devfreq: unsupported/unavailable (skip)"
    fi
    # K3: tunable devfreq (polling_interval/up_threshold/
    # down_differential). Hanya berlaku bila override user ada; tanpa
    # override tidak ada yang ditulis.
    if command -v hsin_gpu_devfreq_tunables_apply >/dev/null 2>&1; then
        hsin_gpu_devfreq_tunables_apply "$_profile"
    fi
    # K3: knob parameter Mali KBase. Gate = node kbase ADA (bukan nama
    # vendor), jadi jalan di device yang kbase-nya ada apa pun hasil
    # deteksi vendor.
    if command -v hsin_gpu_kbase_knobs_apply >/dev/null 2>&1; then
        hsin_gpu_kbase_knobs_apply "$_profile"
    fi
    case "$HSIN_GPU_VENDOR" in
        adreno) hsin_gpu_adreno_kgsl_apply "$_profile" ;;
    esac
    return 0
}

return 0 2>/dev/null || true
