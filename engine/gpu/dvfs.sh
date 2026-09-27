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
# Dipakai untuk menghormati override eksplisit user (kandidat max_freq
# absolut) - cap persen profil tidak boleh menimpa pilihan user.
. "$HSIN_MODULE_PATH/core/user_knobs.sh" 2>/dev/null
. "$HSIN_MODULE_PATH/engine/cpu/frequency.sh" 2>/dev/null
# Daftar node devfreq GPU + daftar policy CPU dari cache scan (topologi
# statis), sama seperti engine/gpu/apply.sh: apply DVFS tidak perlu glob
# /sys/class/devfreq/* atau cpufreq/policy* sendiri. frequency.sh sudah
# menarik engine/cpu/detect.sh (hsin_cpu_policy_ids) kalau belum termuat.
. "$HSIN_MODULE_PATH/engine/gpu/detector.sh" 2>/dev/null
# Path sysfs dari core/scan_cache.sh, default sama dengan path yang
# sebelumnya ditulis langsung di file ini.
[ -n "$HSIN_SYSFS_CPU" ] || HSIN_SYSFS_CPU="${SYSFS_CPU_PREFIX:-/sys/devices/system/cpu}"
[ -n "$HSIN_SYSFS_DEVFREQ" ] || HSIN_SYSFS_DEVFREQ="${SYSFS_DEVFREQ_PREFIX:-/sys/class/devfreq}"
# Diisi hsin_cpu_policy_hwmax() (engine/cpu/detect.sh) dan
# hsin_gpu_opp_list() (engine/gpu/detector.sh).
_hcpw=""
_hgo_avail=""

_hsin_dvfs_log() {
    mkdir -p "$HSIN_DATA/logs" 2>/dev/null
    echo "$(date '+%Y-%m-%d %H:%M:%S') $1" >> "$HSIN_DATA/logs/dvfs.log" 2>/dev/null
}

# Catat satu node yang TIDAK jadi ter-clamp: _fail++ + WARN berisi alasannya
# (read-only / target ditolak kernel / target kosong). Dipanggil di dalam
# loop CPU & GPU, jadi _fail harus di-set 0 oleh pemanggil sebelum loop.
_hsin_dvfs_skip() {
    _fail=$((_fail + 1))
    _hsin_dvfs_log "WARN: $1"
}

# --- CPU side: clamp scaling_max_freq per policy to a % of that policy's
# own cpuinfo_max_freq. Restores to cpuinfo_max_freq (i.e. unclamped) at 100.
hsin_dvfs_cpu_apply() {
    _pct="${1:-100}"
    case "$_pct" in ''|*[!0-9]*) echo "ERROR: cpu_limit must be 0-100" >&2; return 1 ;; esac
    [ "$_pct" -gt 100 ] 2>/dev/null && _pct=100

    _applied=0
    _fail=0
    hsin_cpu_policy_ids
    for _pid in $HSIN_CPU_POLICY_IDS; do
        _p="$HSIN_SYSFS_CPU/cpufreq/policy$_pid"
        [ -d "$_p" ] || { _hsin_dvfs_log "cpu policy$_pid hilang sejak scan (skip)"; _fail=$((_fail + 1)); continue; }
        # Override eksplisit user (kandidat max_freq absolut) menang atas cap
        # persen profil. Tanpa ini, tahap DVFS - yang jalan PALING AKHIR di
        # pipeline - menimpa hasil engine CPU sekaligus pilihan user, jadi
        # "HSIN manual" berakhir sama saja. Log agar jelas node ini dilewati
        # karena atas permintaan user, bukan karena gagal.
        _uk_abs=$(hsin_uk_cpu_field "$_pid" max_khz 2>/dev/null)
        if [ -n "$_uk_abs" ]; then
            _hsin_dvfs_log "cpu policy$_pid dilewati: override user max_khz=$_uk_abs (kirim cpu_limit=100 untuk mengoverride override)"
            continue
        fi
        [ -w "$_p/scaling_max_freq" ] || { _hsin_dvfs_skip "cpu policy$_pid scaling_max_freq read-only (skip)"; continue; }
        hsin_cpu_policy_hwmax "$_pid"; _hw_max="$_hcpw"
        [ -z "$_hw_max" ] && { _hsin_dvfs_skip "cpu policy$_pid cpuinfo_max_freq kosong (skip)"; continue; }

        if [ "$_pct" -eq 100 ]; then
            _target="$_hw_max"
        else
            # available_frequencies = topologi statis -> cache dulu; nilai
            # scaling_max_freq yang HSIN tulis sendiri tetap live di atas.
            _avail=$(hsin_cpu_freq_available "$_p")
            if [ -n "$_avail" ]; then
                _target=$(hsin_cpu_freq_pick "cap:$_pct" "$_avail")
            else
                _target=$((_hw_max * _pct / 100))
            fi
        fi
        [ -z "$_target" ] && { _hsin_dvfs_skip "cpu policy$_pid tidak punya target clamp (skip)"; continue; }

        # Redirect sukses != clamp dipakai: kernel bisa tolak diam-diam.
        # Tulis + readback, baru dihitung OK.
        if hsin_node_write_verify "$_p/scaling_max_freq" "$_target"; then
            _applied=$((_applied + 1))
        else
            _cur=$(hsin_node_read "$_p/scaling_max_freq" 2>/dev/null)
            [ -n "$_cur" ] || _cur="tidak terbaca"
            _hsin_dvfs_skip "cpu policy$_pid scaling_max_freq tetap $_cur (target $_target ditolak kernel)"
        fi
    done

    _hsin_dvfs_log "cpu_limit=$_pct% -> OK $_applied / SKIP $_fail policy node(s) src=$HSIN_CPU_POLICY_SOURCE"
    if [ "$_applied" -gt 0 ]; then
        echo "OK: cpu_limit=$_pct% applied ($_applied policies) SKIP $_fail"
    else
        echo "SKIP: cpu_limit=$_pct% tidak ter-clamp di policy mana pun (SKIP $_fail)"
    fi
    [ "$_fail" -gt 0 ] && [ "$_applied" -eq 0 ] && return 1
    return 0
}

# --- GPU side: clamp devfreq max_freq (generic, any devfreq-based GPU:
# Mali/PowerVR/Adreno-on-devfreq) to a % of the device's own reported max.
hsin_dvfs_gpu_apply() {
    _pct="${1:-100}"
    case "$_pct" in ''|*[!0-9]*) echo "ERROR: gpu_limit must be 0-100" >&2; return 1 ;; esac
    [ "$_pct" -gt 100 ] 2>/dev/null && _pct=100

    _applied=0
    _fail=0
    hsin_gpu_devfreq_candidates
    for _d in $HSIN_GPU_DEVFRES; do
        [ -d "$_d" ] || { _hsin_dvfs_log "gpu node ${_d##*/} hilang sejak scan (skip)"; _fail=$((_fail + 1)); continue; }
        # Sama seperti CPU: override user menang atas cap persen profil.
        _uk_gabs=$(hsin_uk_gpu_field "${_d##*/}" max_khz 2>/dev/null)
        if [ -n "$_uk_gabs" ]; then
            _hsin_dvfs_log "gpu node ${_d##*/} dilewati: override user max_khz=$_uk_gabs (kirim gpu_limit=100 untuk mengoverride override)"
            continue
        fi
        [ -w "$_d/max_freq" ] || { _hsin_dvfs_skip "gpu node ${_d##*/} max_freq read-only (skip)"; continue; }

        # available_frequencies = topologi statis -> cache dulu (dengan
        # fallback baca file), jadi rantai tr|grep|sort|tail per node hilang.
        hsin_gpu_opp_list "$_d"; _avail="$_hgo_avail"
        _hw_max=""
        [ -n "$_avail" ] && _hw_max=$(hsin_opp_max "$_avail")
        [ -z "$_hw_max" ] && _hw_max=$(cat "$_d/max_freq" 2>/dev/null)
        [ -z "$_hw_max" ] && { _hsin_dvfs_skip "gpu node ${_d##*/} tidak punya max_freq terbaca (skip)"; continue; }

        if [ "$_pct" -eq 100 ]; then
            _target="$_hw_max"
        else
            _target=$((_hw_max * _pct / 100))
            if [ -n "$_avail" ]; then
                _best=$(hsin_opp_cap_pick "$_target" "$_avail")
                [ -n "$_best" ] && _target="$_best"
            fi
        fi
        [ -z "$_target" ] && { _hsin_dvfs_skip "gpu node ${_d##*/} tidak punya target clamp (skip)"; continue; }

        if hsin_node_write_verify "$_d/max_freq" "$_target"; then
            _applied=$((_applied + 1))
        else
            _cur=$(hsin_node_read "$_d/max_freq" 2>/dev/null)
            [ -n "$_cur" ] || _cur="tidak terbaca"
            _hsin_dvfs_skip "gpu node ${_d##*/} max_freq tetap $_cur (target $_target ditolak kernel)"
        fi
    done

    _hsin_dvfs_log "gpu_limit=$_pct% -> OK $_applied / SKIP $_fail devfreq node(s) src=$HSIN_GPU_NODE_SOURCE"
    if [ "$_applied" -gt 0 ]; then
        echo "OK: gpu_limit=$_pct% applied ($_applied devfreq nodes) SKIP $_fail"
    else
        echo "SKIP: gpu_limit=$_pct% tidak ter-clamp di devfreq node mana pun (SKIP $_fail)"
    fi
    [ "$_fail" -gt 0 ] && [ "$_applied" -eq 0 ] && return 1
    return 0
}

# Apply both from two explicit args.
hsin_dvfs_apply() {
    _cpu_pct="${1:-100}"
    _gpu_pct="${2:-100}"
    _rc=0
    hsin_dvfs_cpu_apply "$_cpu_pct" || _rc=1
    hsin_dvfs_gpu_apply "$_gpu_pct" || _rc=1
    return $_rc
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
    _rc=0
    hsin_dvfs_cpu_apply 100 || _rc=1
    hsin_dvfs_gpu_apply 100 || _rc=1
    if [ "$_rc" -eq 0 ]; then
        echo "OK: DVFS limiter restored to hardware default (100%)"
    else
        echo "PARTIAL: DVFS restore diminta (100%) tapi ada node yang tidak ter-clamp - cek OK/SKIP di atas"
    fi
    return $_rc
}

hsin_dvfs_status() {
    echo "  DVFS Limiter State:"
    hsin_cpu_policy_ids
    for _pid in $HSIN_CPU_POLICY_IDS; do
        _p="$HSIN_SYSFS_CPU/cpufreq/policy$_pid"
        [ -d "$_p" ] || continue
        _cur=$(cat "$_p/scaling_max_freq" 2>/dev/null)
        hsin_cpu_policy_hwmax "$_pid"; _hw="$_hcpw"
        [ -n "$_cur" ] && [ -n "$_hw" ] && [ "$_hw" -gt 0 ] 2>/dev/null && \
            printf "    %s: max=%s (%d%% of hw max %s)\n" "policy$_pid" "$_cur" "$((_cur * 100 / _hw))" "$_hw"
    done
    hsin_gpu_devfreq_candidates
    for _d in $HSIN_GPU_DEVFRES; do
        [ -d "$_d" ] || continue
        _cur=$(cat "$_d/max_freq" 2>/dev/null)
        [ -n "$_cur" ] && printf "    %s: max_freq=%s\n" "${_d##*/}" "$_cur"
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
