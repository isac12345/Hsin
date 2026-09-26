#!/system/bin/sh
# HSIN Advanced DVFS Limiter
#
# Stellar-style "advanced_dvfs": cpu_limit / gpu_limit as a plain percentage
# cap (0-100) applied on top of whatever governor is already active - it
# only pulls scaling_max_freq / devfreq max_freq down to a percentage of
# hardware max, it does NOT touch the governor itself. This lets a profile
# say "schedutil governor, but never let CPU go above 80% of its max clock"
# for thermal/battery headroom without switching to a fixed-freq governor.
#
# Independent from engine/cpu/governor.sh and engine/gpu/*.sh on purpose -
# those pick WHICH governor/policy runs, this just clamps the ceiling
# after that choice is made. Safe no-op at 100 (== hardware default, no
# clamp applied at all).

[ -z "$HSIN_MODULE_PATH" ] && HSIN_MODULE_PATH="/data/adb/modules/hsin"
HSIN_DATA="${HSIN_DATA:-/data/adb/hsin}"

. "$HSIN_MODULE_PATH/core/sysfs.sh" 2>/dev/null
. "$HSIN_MODULE_PATH/engine/cpu/frequency.sh" 2>/dev/null

_hsin_dvfs_log() {
    mkdir -p "$HSIN_DATA/logs" 2>/dev/null
    echo "$(date '+%Y-%m-%d %H:%M:%S') $1" >> "$HSIN_DATA/logs/dvfs.log" 2>/dev/null
}

# --- CPU side: clamp scaling_max_freq per policy to a % of that policy's
# own cpuinfo_max_freq. Restores to cpuinfo_max_freq (i.e. unclamped) at 100.
hsin_dvfs_cpu_apply() {
    _pct="${1:-100}"
    case "$_pct" in ''|*[!0-9]*) echo "ERROR: cpu_limit must be 0-100" >&2; return 1 ;; esac
    [ "$_pct" -gt 100 ] 2>/dev/null && _pct=100

    _applied=0
    for _p in /sys/devices/system/cpu/cpufreq/policy*; do
        [ -d "$_p" ] || continue
        [ -w "$_p/scaling_max_freq" ] || continue
        _hw_max=$(cat "$_p/cpuinfo_max_freq" 2>/dev/null)
        [ -z "$_hw_max" ] && continue

        if [ "$_pct" -eq 100 ]; then
            _target="$_hw_max"
        else
            _avail=$(cat "$_p/scaling_available_frequencies" 2>/dev/null)
            if [ -n "$_avail" ]; then
                _target=$(hsin_cpu_freq_pick "cap:$_pct" "$_avail")
            else
                _target=$((_hw_max * _pct / 100))
            fi
        fi
        [ -z "$_target" ] && continue

        echo "$_target" > "$_p/scaling_max_freq" 2>/dev/null && _applied=$((_applied + 1))
    done

    _hsin_dvfs_log "cpu_limit=$_pct% applied to $_applied policy node(s)"
    echo "OK: cpu_limit=$_pct% applied ($_applied policies)"
    return 0
}

# --- GPU side: clamp devfreq max_freq (generic, any devfreq-based GPU:
# Mali/PowerVR/Adreno-on-devfreq) to a % of the device's own reported max.
hsin_dvfs_gpu_apply() {
    _pct="${1:-100}"
    case "$_pct" in ''|*[!0-9]*) echo "ERROR: gpu_limit must be 0-100" >&2; return 1 ;; esac
    [ "$_pct" -gt 100 ] 2>/dev/null && _pct=100

    _applied=0
    for _d in /sys/class/devfreq/*; do
        [ -d "$_d" ] || continue
        hsin_devfreq_gpu_candidate "$_d" || continue
        [ -w "$_d/max_freq" ] || continue

        _hw_max=""
        if [ -f "$_d/available_frequencies" ]; then
            _hw_max=$(tr ' ' '\n' < "$_d/available_frequencies" 2>/dev/null | grep -v '^$' | sort -n | tail -1)
        fi
        [ -z "$_hw_max" ] && _hw_max=$(cat "$_d/max_freq" 2>/dev/null)
        [ -z "$_hw_max" ] && continue

        if [ "$_pct" -eq 100 ]; then
            _target="$_hw_max"
        else
            _target=$((_hw_max * _pct / 100))
            if [ -f "$_d/available_frequencies" ]; then
                _best=$(hsin_opp_cap_pick "$_target" "$(cat "$_d/available_frequencies" 2>/dev/null)")
                [ -n "$_best" ] && _target="$_best"
            fi
        fi
        [ -z "$_target" ] && continue

        echo "$_target" > "$_d/max_freq" 2>/dev/null && _applied=$((_applied + 1))
    done

    _hsin_dvfs_log "gpu_limit=$_pct% applied to $_applied devfreq node(s)"
    echo "OK: gpu_limit=$_pct% applied ($_applied devfreq nodes)"
    return 0
}

# Apply both from two explicit args.
hsin_dvfs_apply() {
    _cpu_pct="${1:-100}"
    _gpu_pct="${2:-100}"
    hsin_dvfs_cpu_apply "$_cpu_pct"
    hsin_dvfs_gpu_apply "$_gpu_pct"
}

# Read ADVANCED_DVFS_CPU_LIMIT / ADVANCED_DVFS_GPU_LIMIT from a profile
# .conf (or hsin.conf) and apply. No-op if the keys aren't present at all
# (profile didn't opt into DVFS limiting) rather than defaulting to 100
# and doing needless writes.
hsin_dvfs_apply_from_conf() {
    _conf="${1:-$HSIN_MODULE_PATH/config/hsin.conf}"
    [ -f "$_conf" ] || return 0

    _cpu_pct=""; _gpu_pct=""; _enabled=false
    while IFS='=' read -r _k _v || [ -n "$_k" ]; do
        case "$_k" in
            ADVANCED_DVFS_ENABLED) _enabled="$_v" ;;
            ADVANCED_DVFS_CPU_LIMIT|cpu_limit) _cpu_pct="$_v" ;;
            ADVANCED_DVFS_GPU_LIMIT|gpu_limit) _gpu_pct="$_v" ;;
        esac
    done < "$_conf"

    [ "$_enabled" = "true" ] || return 0
    [ -n "$_cpu_pct" ] && hsin_dvfs_cpu_apply "$_cpu_pct"
    [ -n "$_gpu_pct" ] && hsin_dvfs_gpu_apply "$_gpu_pct"
    return 0
}

# Restore both to 100% (unclamped / hardware default).
hsin_dvfs_restore() {
    hsin_dvfs_cpu_apply 100
    hsin_dvfs_gpu_apply 100
    echo "OK: DVFS limiter restored to hardware default (100%)"
}

hsin_dvfs_status() {
    echo "  DVFS Limiter State:"
    for _p in /sys/devices/system/cpu/cpufreq/policy*; do
        [ -d "$_p" ] || continue
        _cur=$(cat "$_p/scaling_max_freq" 2>/dev/null)
        _hw=$(cat "$_p/cpuinfo_max_freq" 2>/dev/null)
        [ -n "$_cur" ] && [ -n "$_hw" ] && [ "$_hw" -gt 0 ] 2>/dev/null && \
            printf "    %s: max=%s (%d%% of hw max %s)\n" "$(basename "$_p")" "$_cur" "$((_cur * 100 / _hw))" "$_hw"
    done
    for _d in /sys/class/devfreq/*; do
        [ -d "$_d" ] || continue
        hsin_devfreq_gpu_candidate "$_d" || continue
        _cur=$(cat "$_d/max_freq" 2>/dev/null)
        [ -n "$_cur" ] && printf "    %s: max_freq=%s\n" "$(basename "$_d")" "$_cur"
    done
}

# CLI interface
hsin_dvfs_main() {
    _action="${1:-status}"
    case "$_action" in
        apply) hsin_dvfs_apply "${2:-100}" "${3:-100}" ;;
        cpu) hsin_dvfs_cpu_apply "${2:-100}" ;;
        gpu) hsin_dvfs_gpu_apply "${2:-100}" ;;
        restore) hsin_dvfs_restore ;;
        status) hsin_dvfs_status ;;
        *)
            echo "Usage: hsin dvfs <apply|cpu|gpu|restore|status> [cpu_pct] [gpu_pct]"
            ;;
    esac
}

return 0 2>/dev/null || true
