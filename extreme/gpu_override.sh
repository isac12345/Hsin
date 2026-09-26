#!/system/bin/sh
# HSIN Extreme GPU Override - universal devfreq backend
[ -z "$HSIN_MODULE_PATH" ] && HSIN_MODULE_PATH="/data/adb/modules/hsin"
HSIN_DATA="${HSIN_DATA:-/data/adb/hsin}"
. "$HSIN_MODULE_PATH/core/sysfs.sh" 2>/dev/null

HSIN_GPU_DVFS_LOCK_SUPPORTED="false"

hsin_extreme_gpu_detect() {
    _found=0
    for _d in /sys/class/devfreq/*; do
        [ -d "$_d" ] || continue
        hsin_devfreq_gpu_candidate "$_d" || continue
        _found=$((_found+1))
        _avail=$(cat "$_d/available_frequencies" 2>/dev/null)
        _max=$(hsin_opp_max "$_avail")
        _cur=$(cat "$_d/cur_freq" 2>/dev/null)
        printf '  %s: max=%s cur=%s writable=%s\n' "$(basename "$_d")" "${_max:-N/A}" "${_cur:-N/A}" "$( [ -w "$_d/max_freq" ] && echo yes || echo no )"
        [ -w "$_d/max_freq" ] && HSIN_GPU_DVFS_LOCK_SUPPORTED="true"
    done
    [ "$_found" -gt 0 ] || echo '  No supported GPU devfreq node found'
}

hsin_extreme_gpu_backup() {
    if [ -f "$HSIN_DATA/extreme_active" ] && [ -f "$HSIN_DATA/gpu_backup_latest" ]; then
        _e=$(cat "$HSIN_DATA/gpu_backup_latest" 2>/dev/null); [ -d "$_e" ] && { echo "$_e"; return 0; }
    fi
    _dir="$HSIN_DATA/backups/gpu_extreme_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$_dir" 2>/dev/null
    for _d in /sys/class/devfreq/*; do
        [ -d "$_d" ] || continue
        hsin_devfreq_gpu_candidate "$_d" || continue
        _n=$(basename "$_d"); mkdir -p "$_dir/$_n" 2>/dev/null
        for _f in governor min_freq max_freq; do [ -f "$_d/$_f" ] && cat "$_d/$_f" > "$_dir/$_n/$_f" 2>/dev/null; done
    done
    echo "$_dir" > "$HSIN_DATA/gpu_backup_latest" 2>/dev/null
    echo "$_dir"
}

hsin_extreme_gpu_apply() {
    hsin_extreme_gpu_detect >/dev/null
    _ok=0; _skip=0; _fail=0
    for _d in /sys/class/devfreq/*; do
        [ -d "$_d" ] || continue
        hsin_devfreq_gpu_candidate "$_d" || continue
        _avail=$(cat "$_d/available_frequencies" 2>/dev/null)
        _max=$(hsin_opp_max "$_avail")
        [ -n "$_max" ] || { _skip=$((_skip+1)); continue; }
        if [ -w "$_d/max_freq" ] && hsin_node_write_verify "$_d/max_freq" "$_max"; then _ok=$((_ok+1)); else _fail=$((_fail+1)); fi
        # Extreme is the only profile allowed to request a performance GPU
        # governor. We still only write governors the node advertises.
        if [ -f "$_d/available_governors" ] && [ -w "$_d/governor" ]; then
            _gov=$(cat "$_d/available_governors" 2>/dev/null)
            case " $_gov " in
                *' performance '*) hsin_node_write_verify "$_d/governor" performance >/dev/null 2>&1 || : ;;
            esac
        fi
    done
    echo "GPU extreme: ok=$_ok skip=$_skip fail=$_fail"
    return 0
}

hsin_extreme_gpu_restore() {
    [ -f "$HSIN_DATA/gpu_backup_latest" ] || return 0
    _dir=$(cat "$HSIN_DATA/gpu_backup_latest" 2>/dev/null)
    [ -d "$_dir" ] || return 0
    for _n in "$_dir"/*; do
        [ -d "$_n" ] || continue
        _d="/sys/class/devfreq/$(basename "$_n")"; [ -d "$_d" ] || continue
        for _f in governor max_freq min_freq; do
            [ -f "$_n/$_f" ] && [ -w "$_d/$_f" ] && printf '%s\n' "$(cat "$_n/$_f" 2>/dev/null)" > "$_d/$_f" 2>/dev/null
        done
    done
    return 0
}
return 0 2>/dev/null || true
