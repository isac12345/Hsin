#!/system/bin/sh
# HSIN Action Interface

[ -z "$HSIN_MODULE_PATH" ] && HSIN_MODULE_PATH="/data/adb/modules/hsin"
HSIN_DATA="${HSIN_DATA:-/data/adb/hsin}"

# ===== Hidden dev-only debug log =====
HSIN_DEBUG_LOG="$HSIN_DATA/logs/debug.log"
[ -d "$HSIN_DATA/logs" ] || mkdir -p "$HSIN_DATA/logs" 2>/dev/null
# Skip debug log write on the hot-path status command (called every ~3s)
# to avoid forking date on every WebUI poll.
case "${1:-info}" in
    status) ;;
    *) echo "----- $(date '+%Y-%m-%d %H:%M:%S') action.sh $* -----" >> "$HSIN_DEBUG_LOG" 2>/dev/null ;;
esac
exec 2>>"$HSIN_DEBUG_LOG"

# Load core modules
. "$HSIN_MODULE_PATH/core/logger.sh" 2>/dev/null
. "$HSIN_MODULE_PATH/core/backup.sh" 2>/dev/null
. "$HSIN_MODULE_PATH/core/validator.sh" 2>/dev/null
. "$HSIN_MODULE_PATH/core/profile_loader.sh" 2>/dev/null
. "$HSIN_MODULE_PATH/core/policy_engine.sh" 2>/dev/null
. "$HSIN_MODULE_PATH/core/state_manager.sh" 2>/dev/null
. "$HSIN_MODULE_PATH/core/protect.sh" 2>/dev/null
if ! command -v hsin_protect_watermark >/dev/null 2>&1; then
    echo "ERROR: core/protect.sh missing or tampered - refusing to run"
    exit 1
fi
hsin_protect_integrity || { echo "ERROR: Integrity check failed - refusing to run"; exit 1; }

HSIN_CONF="/sdcard/Android/hsin/hsin.conf"
HSIN_GAM_BOOST="false"
# Session-level opt-in: if the caller already exported ALLOW_EXTREME (e.g.
# the WebUI's confirm-dialog does `ALLOW_EXTREME=true action.sh apply
# extreme`), honor that for THIS invocation instead of letting the
# persisted conf file's ALLOW_EXTREME=false line silently clobber it below.
# Without this, the WebUI's one-time confirmation could never actually
# work - the file's saved value always won regardless of what was passed.
_allow_extreme_from_env="${ALLOW_EXTREME:-}"
ALLOW_EXTREME="${_allow_extreme_from_env:-false}"
if [ -f "$HSIN_CONF" ]; then
    while IFS='=' read -r _key _val || [ -n "$_key" ]; do
        case "$_key" in
            GAM_BOOST_ENABLED) HSIN_GAM_BOOST="${_val:-false}" ;;
            ALLOW_EXTREME)
                # Only take the file's value if the caller didn't already
                # opt in for this session.
                [ -z "$_allow_extreme_from_env" ] && ALLOW_EXTREME="${_val:-false}"
                ;;
        esac
    done < "$HSIN_CONF"
fi
# Extreme requires explicit opt-in from the caller or persistent config.

# Get device info as JSON
hsin_action_device_info() {
    _soc="unknown"
    _gpu="unknown"
    _kernel=$(uname -r 2>/dev/null)
    _ram="unknown"
    _devid=$(hsin_protect_device_fingerprint 2>/dev/null)

    # SoC
    if [ -f /proc/device-tree/compatible ]; then
        _soc=""
        read -r _soc < /proc/device-tree/compatible 2>/dev/null
        _soc="${_soc%% *}"  # take first word before any space/null
    fi

    # GPU: use the same universal detector as the apply engine. This handles
    # nodes such as 23100000.gpu that do not literally contain "mali".
    . "$HSIN_MODULE_PATH/engine/gpu/detector.sh" 2>/dev/null
    hsin_gpu_detect 2>/dev/null
    _gpu="${HSIN_GPU_DEVFREQ:-${HSIN_GPU_VENDOR:-unknown}}"
    [ -z "$_gpu" ] && _gpu="${HSIN_GPU_VENDOR:-unknown}"

    # RAM
    # FIX: /proc/meminfo values have leading whitespace after the colon
    # ("MemTotal:        8144936 kB"). `${_mv%% *}` was meant to cut
    # everything from the first space onward, but since _mv itself STARTS
    # with spaces, the whole value matched " *" and got stripped to "",
    # which is why RAM always showed N/A. Using `set --` lets normal word
    # splitting drop the leading/trailing whitespace before we take $1.
    if [ -f /proc/meminfo ]; then
        while IFS=: read -r _mk _mv; do
            case "$_mk" in
                MemTotal)
                    set -- $_mv
                    _ram="$1"
                    break
                    ;;
            esac
        done < /proc/meminfo
    fi

    # Single-line JSON: some WebUI exec bridges only pass through the last
    printf '{"soc":"%s","gpu":"%s","kernel":"%s","ram_kb":"%s","device_id":"%s"}\n' "$_soc" "$_gpu" "$_kernel" "$_ram" "$_devid"
}

# Get capability status as JSON
hsin_action_capabilities() {
    _cpu_tuning="false"
    _gpu_devfreq="false"
    _thermal_node="false"
    _fpsgo="false"
    _kgsl="false"
    _sched_lat="false"

    # CPU tuning
    [ -d /sys/devices/system/cpu/cpufreq/policy0 ] && _cpu_tuning="true"

    # GPU devfreq - match any vendor's devfreq node (Mali, PowerVR/IMG,
    # generic "gpu"); KGSL (Adreno/Qualcomm) is reported separately since
    # it has its own dedicated tuning knobs elsewhere in the engine.
    for _devfreq in /sys/class/devfreq/*; do
        [ -d "$_devfreq" ] || continue
        _name="${_devfreq##*/}"
        case "$_name" in
            *kgsl*) _kgsl="true" ;;
            *gpu*|*mali*|*pvr*|*img*) _gpu_devfreq="true" ;;
        esac
    done
    [ -d /sys/class/kgsl/kgsl-3d0 ] && _kgsl="true"

    # Thermal - any zone counts, not just zone0 (some devices start
    # numbering from a non-zero index or hide zone0 behind a vendor HAL).
    for _tz in /sys/class/thermal/thermal_zone*; do
        [ -d "$_tz" ] && { _thermal_node="true"; break; }
    done

    # FPSGO - MediaTek's frame-pacing governor lives under a couple of
    # different paths depending on kernel version; ged/hal is the classic
    # one, fpsgo/fbt is the newer common one.
    if [ -d /sys/kernel/ged/hal ] || [ -d /sys/kernel/fpsgo/fbt ] || [ -d /sys/module/mtk_fpsgo ]; then
        _fpsgo="true"
    fi

    # Scheduler latency tuning - checks both possible locations (see
    # engine/cpu/scheduler.sh): classic /proc/sys/kernel/ sysctl on older
    # kernels, or /sys/kernel/debug/sched/ on kernels where upstream moved
    # these behind debugfs (~5.13+). Sourcing scheduler.sh just for this
    # detection is intentional - keeps the "where does this node live"
    # logic in exactly one place instead of duplicating the path guesses
    # here and risking the two copies drifting apart later.
    . "$HSIN_MODULE_PATH/engine/cpu/scheduler.sh" 2>/dev/null
    if command -v _hsin_sched_lat_resolve_path >/dev/null 2>&1 && _hsin_sched_lat_resolve_path sched_latency_ns >/dev/null 2>&1; then
        _sched_lat="true"
    fi

    printf '{"cpu_tuning":%s,"gpu_devfreq":%s,"thermal_node":%s,"fpsgo":%s,"kgsl":%s,"sched_lat":%s}\n' \
        "$_cpu_tuning" "$_gpu_devfreq" "$_thermal_node" "$_fpsgo" "$_kgsl" "$_sched_lat"
}

# Get live status as JSON
# Game auto-boost: called once per status poll, but only actually DOES
# anything on a transition (game just started, switched, or just closed) -
# not on every single poll, so it doesn't re-run the whole apply pipeline
# every 3 seconds while a game stays open.
hsin_action_game_boost_check() {
    # PATCH v4.0: jangan spam log tiap poll (dulu 1 baris tiap status poll
    # 5 detik = ~17rb baris/hari). Cuma tulis kalau nilai BERUBAH.
    _gb_log_file="$HSIN_DATA/.gam_boost_logged"
    _gb_logged=""
    read -r _gb_logged < "$_gb_log_file" 2>/dev/null
    if [ "$_gb_logged" != "$HSIN_GAM_BOOST" ]; then
        echo "GAMEBOOST: HSIN_GAM_BOOST=[$HSIN_GAM_BOOST]" >> "$HSIN_DEBUG_LOG" 2>/dev/null
        printf '%s' "$HSIN_GAM_BOOST" > "$_gb_log_file" 2>/dev/null
    fi
    [ "$HSIN_GAM_BOOST" = "true" ] || return 0

    . "$HSIN_MODULE_PATH/engine/game/detector.sh" 2>/dev/null
    . "$HSIN_MODULE_PATH/engine/game/game_manager.sh" 2>/dev/null

    # PATCH v4.2: monitor daemon = satu-satunya actor boost logic. Dua actor
    # tanpa lock = race revert/reapply. Status poll cukup baca state; kalau
    # daemon mati (mis. toggle fresh sebelum restart), action.sh tetap handle.
    if [ -f "$HSIN_DATA/monitor.pid" ]; then
        _hsin_mpid=""
        read -r _hsin_mpid < "$HSIN_DATA/monitor.pid" 2>/dev/null
        case "$_hsin_mpid" in ''|*[!0-9]*) _hsin_mpid="" ;; esac
        if [ -n "$_hsin_mpid" ] && kill -0 "$_hsin_mpid" 2>/dev/null; then
            return 0
        fi
    fi

    if ! command -v hsin_game_effective_profile >/dev/null 2>&1; then
        echo "GAMEBOOST: hsin_game_effective_profile not defined after sourcing - abort" >> "$HSIN_DEBUG_LOG" 2>/dev/null
        return 0
    fi

    _last_file="$HSIN_DATA/.last_game_pkg"
    _boost_file="$HSIN_DATA/.game_boost_state"
    _last_pkg=""
    [ -f "$_last_file" ] && read -r _last_pkg < "$_last_file" 2>/dev/null

    _cur_pkg=$(hsin_game_detect 2>/dev/null)
    # PATCH v4.0: log cuma kalau ada transisi/kandidat game (cur != last).
    # Pas stabil tiap poll nulis baris yang sama - spam log.
    if [ "$_cur_pkg" != "$_last_pkg" ]; then
        echo "GAMEBOOST: detected=[$_cur_pkg] last=[$_last_pkg]" >> "$HSIN_DEBUG_LOG" 2>/dev/null
    fi

    # Strip trailing whitespace/newlines from both - file contents can
    # pick up trailing newlines from `printf` overwriting a longer value.
    _last_pkg=$(printf '%s' "$_last_pkg" | tr -d '\r\n')
    _cur_pkg=$(printf '%s' "$_cur_pkg" | tr -d '\r\n')

    # Only treat _cur_pkg as "game" if it actually qualifies: listed in
    # games.conf OR has "game" in the package name (same check as
    # hsin_game_is_running in detector.sh).  Non-game foreground apps
    # are treated as empty so they never trigger notifications.
    if [ -n "$_cur_pkg" ]; then
        _hsin_is_game=1
        hsin_game_is_known "$_cur_pkg" 2>/dev/null && _hsin_is_game=0
        if [ "$_hsin_is_game" -ne 0 ]; then
            case "$_cur_pkg" in
                *game*|*Game*|*GAME*) _hsin_is_game=0 ;;
            esac
        fi
        if [ "$_hsin_is_game" -ne 0 ]; then
            _cur_pkg=""
        fi
    fi

    _grace_file="$HSIN_DATA/.game_boost_grace"
    _grace_seconds="${HSIN_GAME_BOOST_GRACE_SECONDS:-12}"

    if [ "$_cur_pkg" = "$_last_pkg" ]; then
        # Same as before, including "still nothing" (both empty). If a
        # grace timer happened to be running (e.g. the game reappeared in
        # foreground right as this poll landed), the game coming back IS
        # this branch - cur_pkg goes back to matching last_pkg without
        # last_pkg ever having been cleared during the wait (see the
        # empty-branch below). Clear any stale timer defensively.
        rm -f "$_grace_file" 2>/dev/null
        return 0
    fi

    # GRACE PERIOD (only on the "leaving" direction): a game leaving the
    # foreground doesn't necessarily mean it closed - pressing Home,
    # pulling down notifications, or switching to this very WebUI to check
    # something all do the same "foreground changed" thing a swipe-from-
    # recents does. Reverting instantly on every one of those was causing
    # profile flapping (revert -> reapply -> revert...) for anyone who so
    # much as glanced away for a second. Starting a NEW game still applies
    # immediately below (no reason to delay turning boost ON) - the delay
    # is only for turning it back OFF.
    if [ -z "$_cur_pkg" ] && [ -n "$_last_pkg" ]; then
        _now=$(date +%s 2>/dev/null)
        if [ ! -f "$_grace_file" ]; then
            echo "GAMEBOOST: $_last_pkg left foreground, starting ${_grace_seconds}s grace" >> "$HSIN_DEBUG_LOG" 2>/dev/null
            printf '%s' "$_now" > "$_grace_file" 2>/dev/null
            return 0
        fi
        _grace_started=""
        read -r _grace_started < "$_grace_file" 2>/dev/null
        case "$_grace_started" in ''|*[!0-9]*) _grace_started="$_now" ;; esac
        _elapsed=$(( _now - _grace_started ))
        if [ "$_elapsed" -lt "$_grace_seconds" ]; then
            return 0 ;# still within grace, keep waiting
        fi
        echo "GAMEBOOST: grace expired (${_elapsed}s), reverting for real" >> "$HSIN_DEBUG_LOG" 2>/dev/null
        rm -f "$_grace_file" 2>/dev/null
        # Falls through to the existing revert logic below, same as
        # before grace existed - _cur_pkg is still "" here.
    fi

    mkdir -p "$HSIN_DATA" 2>/dev/null
    printf '%s' "$_cur_pkg" > "$_last_file" 2>/dev/null
    rm -f "$_grace_file" 2>/dev/null
    echo "GAMEBOOST: transition detected, cur=[$_cur_pkg]" >> "$HSIN_DEBUG_LOG" 2>/dev/null

    if [ -n "$_cur_pkg" ]; then
        # Game just started/switched. Read the user's chosen base profile
        # from hsin.conf (the ONE they actively picked, not the one a
        # previous game-boost temporarily switched them to) - this is
        # what we want to RESTORE TO when the game closes.
        _base_profile="balanced"
        if [ -f "$HSIN_CONF" ]; then
            while IFS='=' read -r _ck _cv || [ -n "$_ck" ]; do
                [ "$_ck" = "PROFILE" ] && { _base_profile="${_cv:-balanced}"; break; }
            done < "$HSIN_CONF"
        fi
        case "$_base_profile" in
            battery|balanced|performance|extreme) ;;
            *) _base_profile="balanced" ;;
        esac

        # Make sure state.lock exists so the WebUI can read ACTIVE_PROFILE
        # back immediately. Without this, the very first boost after boot
        # would read "none" and the UI would show the wrong tile selected.
        hsin_state_init 2>/dev/null

        _eff_profile=$(hsin_game_effective_profile "$_base_profile" "$_cur_pkg")

        # FIX: never claim "extreme" here unless the user actually has
        # ALLOW_EXTREME=true. Previously state.lock/notify were set to
        # "extreme" optimistically BEFORE hsin_action_apply's own gate ran,
        # so the gate would silently reject the apply afterwards while the
        # UI/notification kept showing "extreme" as if it worked. Cap the
        # boost at "performance" instead when the opt-in isn't set.
        if [ "$_eff_profile" = "extreme" ] && [ "$ALLOW_EXTREME" != "true" ]; then
            echo "GAMEBOOST: extreme mapped but ALLOW_EXTREME!=true, capping at performance" >> "$HSIN_DEBUG_LOG" 2>/dev/null
            _eff_profile="performance"
        fi
        echo "GAMEBOOST: base=[$_base_profile] effective=[$_eff_profile]" >> "$HSIN_DEBUG_LOG" 2>/dev/null

        # Update state.lock NOW (synchronously) so the WebUI sees the
        # profile flip in the next 3s poll instead of having to wait for
        # the background apply to land. The apply is still async because
        # the actual sysfs writes take ~5-10s, but the visible state is
        # correct from the moment the game is detected.
        hsin_state_profile "$_eff_profile" 2>/dev/null
        hsin_state_update "APPLY_STATUS" "applying:$_eff_profile" 2>/dev/null

        if [ "$_eff_profile" != "$_base_profile" ]; then
            printf '%s' "$_base_profile" > "$_boost_file" 2>/dev/null
            hsin_notify "HSIN" "Game boost: $_cur_pkg -> $_eff_profile" 2>/dev/null
            hsin_action_apply "$_eff_profile" "boost" >/dev/null 2>&1
        else
            rm -f "$_boost_file" 2>/dev/null
        fi
    else
        # Game just closed.
        if [ -f "$_boost_file" ]; then
            _revert_profile=""
            read -r _revert_profile < "$_boost_file" 2>/dev/null
            _revert_profile=$(printf '%s' "$_revert_profile" | tr -d '\r\n')
            rm -f "$_boost_file" 2>/dev/null
            if [ -n "$_revert_profile" ]; then
                hsin_state_profile "$_revert_profile" 2>/dev/null
                hsin_state_update "APPLY_STATUS" "applying:$_revert_profile" 2>/dev/null
                hsin_notify "HSIN" "Game closed, back to $_revert_profile" 2>/dev/null
                hsin_action_apply "$_revert_profile" "boost" >/dev/null 2>&1
            fi
        fi
    fi
}

hsin_action_live_status() {
    # CPU + GPU temp in ONE pass over thermal zones (was two full passes).
    # Also swapped `cat`/`dirname`/`basename` (each a forked process) for
    # shell builtins (`read`, parameter expansion) - on a lot of Unisoc
    # devices there are 20-40 thermal zones, so the old code could fork
    # 80-150+ processes just for this one status poll. That's almost
    # certainly where the multi-second delay was coming from, not the
    # integrity check (the profiling log showed that finishing in 0s).
    _cpu_temp="0"
    _gpu_temp="0"
    for _zone in /sys/class/thermal/thermal_zone*/temp; do
        [ -f "$_zone" ] || continue
        _dir="${_zone%/temp}"
        [ -f "$_dir/type" ] || continue
        _type=""
        read -r _type < "$_dir/type" 2>/dev/null
        case "$_type" in
            *cpu*|*CPU*)
                _t=""
                read -r _t < "$_zone" 2>/dev/null
                [ -n "$_t" ] && [ "$_t" -gt "$_cpu_temp" ] 2>/dev/null && _cpu_temp="$_t"
                ;;
            *gpu*|*GPU*)
                _t=""
                read -r _t < "$_zone" 2>/dev/null
                [ -n "$_t" ] && [ "$_t" -gt "$_gpu_temp" ] 2>/dev/null && _gpu_temp="$_t"
                ;;
        esac
    done

    # CPU freq (current + hardware max, so the WebUI can render a real
    # cur/max percentage instead of a hardcoded bar width). cpuinfo_max_freq
    # is the read-only hardware ceiling - same node every governor exposes
    # on every SoC vendor, so this is chipset-agnostic.
    #
    # "Current" freq is a core-count-weighted average across ALL cluster
    # policies (not the highest cluster). On big.LITTLE chips the busiest
    # cluster (usually big) would otherwise always win the max-of-all-
    # policies comparison, making the WebUI number look permanently
    # pinned near the top even while other clusters idle/fluctuate freely.
    # Weighting by core count keeps it a real "average clock speed", not
    # just an unweighted mean of 2-3 cluster numbers.
    # PERF: this used to be TWO separate loops over the same
    # /sys/devices/system/cpu/cpufreq/policy* directories - one for the
    # overall weighted average, one for the big/little breakdown - each
    # re-reading the same sysfs files and re-forking `wc -w` per policy.
    # Merged into one pass that reads each policy once and stashes
    # "freq:ncores:max" per policy in a plain string list; the big/little
    # split below just walks that in-memory list (zero file reads, zero
    # forks) instead of touching sysfs again.
    _cpu_freq="0"
    _cpu_max_khz="0"
    _cpu_freq_wsum=0
    _cpu_freq_wcnt=0
    _cpu_policy_data=""
    for _policy in /sys/devices/system/cpu/cpufreq/policy*; do
        [ -d "$_policy" ] || continue
        _f=""
        [ -f "$_policy/scaling_cur_freq" ] && read -r _f < "$_policy/scaling_cur_freq" 2>/dev/null
        _ncores=""
        [ -f "$_policy/related_cpus" ] && _ncores=$(wc -w < "$_policy/related_cpus" 2>/dev/null)
        [ -z "$_ncores" ] || [ "$_ncores" -le 0 ] 2>/dev/null && {
            [ -f "$_policy/cpus" ] && _ncores=$(wc -w < "$_policy/cpus" 2>/dev/null)
        }
        [ -z "$_ncores" ] || [ "$_ncores" -le 0 ] 2>/dev/null && _ncores=1
        _m=""
        [ -f "$_policy/cpuinfo_max_freq" ] && read -r _m < "$_policy/cpuinfo_max_freq" 2>/dev/null
        [ -z "$_m" ] && _m=0
        if [ -n "$_f" ] && [ "$_f" -gt 0 ] 2>/dev/null; then
            _cpu_freq_wsum=$((_cpu_freq_wsum + _f * _ncores))
            _cpu_freq_wcnt=$((_cpu_freq_wcnt + _ncores))
            _cpu_policy_data="$_cpu_policy_data $_f:$_ncores:$_m"
        fi
        [ -n "$_m" ] && [ "$_m" -gt "$_cpu_max_khz" ] 2>/dev/null && _cpu_max_khz="$_m"
    done
    [ "$_cpu_freq_wcnt" -gt 0 ] 2>/dev/null && _cpu_freq=$((_cpu_freq_wsum / _cpu_freq_wcnt))

    # Per-cluster breakdown (big vs LITTLE) so the WebUI can show them
    # separately instead of only the single blended average above - lets
    # you verify against per-cluster tools like DevCheck without needing
    # a second app. A policy counts as "big" if its hardware ceiling
    # equals the overall max found above; everything else is "little".
    # On a homogeneous/single-cluster CPU, _cpu_freq_little stays 0 and
    # the WebUI just hides the breakdown row.
    _cpu_freq_big=0
    _cpu_freq_little=0
    _wsum_big=0; _wcnt_big=0
    _wsum_little=0; _wcnt_little=0
    for _entry in $_cpu_policy_data; do
        _f="${_entry%%:*}"
        _rest="${_entry#*:}"
        _ncores="${_rest%%:*}"
        _m="${_rest#*:}"
        if [ "$_m" -ge "$_cpu_max_khz" ] 2>/dev/null; then
            _wsum_big=$((_wsum_big + _f * _ncores))
            _wcnt_big=$((_wcnt_big + _ncores))
        else
            _wsum_little=$((_wsum_little + _f * _ncores))
            _wcnt_little=$((_wcnt_little + _ncores))
        fi
    done
    [ "$_wcnt_big" -gt 0 ] 2>/dev/null && _cpu_freq_big=$((_wsum_big / _wcnt_big))
    [ "$_wcnt_little" -gt 0 ] 2>/dev/null && _cpu_freq_little=$((_wsum_little / _wcnt_little))

    # GPU freq (current + max). Devfreq is the generic Linux governor
    # framework used by Mali/Adreno/PowerVR/KGSL alike, so matching on the
    # node name (rather than a vendor-specific path) keeps this working
    # across Unisoc, MediaTek, Qualcomm and Exynos devices.
    _gpu_freq="0"
    _gpu_max_khz="0"
    for _devfreq in /sys/class/devfreq/*; do
        [ -d "$_devfreq" ] || continue
        _name="${_devfreq##*/}"
        case "$_name" in
            *gpu*|*mali*|*kgsl*|*adreno*|*pvr*|*img*)
                _f_hz=""
                [ -f "$_devfreq/cur_freq" ] && read -r _f_hz < "$_devfreq/cur_freq" 2>/dev/null
                # BUGFIX: this ran `$((_f_hz / 1000))` unconditionally, even
                # when cur_freq was empty/unreadable or (on some Unisoc
                # devfreq nodes) briefly held non-numeric content mid-update.
                # Arithmetic on a non-numeric operand doesn't reliably give 0
                # here - it's what produced the huge negative/garbled
                # cpu_freq/gpu_freq values (and the mangled text on the
                # Monitor tab, since the WebUI tweens toward whatever number
                # this prints). Guard exactly like every other numeric read
                # in this file already does before touching it.
                case "$_f_hz" in ''|*[!0-9]*) _f_hz="" ;; esac
                _f=0
                [ -n "$_f_hz" ] && _f=$((_f_hz / 1000))
                [ -n "$_f_hz" ] && [ "$_f" -gt "$_gpu_freq" ] 2>/dev/null && _gpu_freq="$_f"
                _m_hz=""
                [ -f "$_devfreq/max_freq" ] && read -r _m_hz < "$_devfreq/max_freq" 2>/dev/null
                case "$_m_hz" in ''|*[!0-9]*) _m_hz="" ;; esac
                _m=0
                [ -n "$_m_hz" ] && _m=$((_m_hz / 1000))
                [ -n "$_m_hz" ] && [ "$_m" -gt "$_gpu_max_khz" ] 2>/dev/null && _gpu_max_khz="$_m"
                ;;
        esac
    done

    # RAM used/total. MemAvailable (kernel's own "usable without swapping"
    # estimate) is a more honest "used" figure than MemFree, and both
    # fields exist on every modern Android kernel regardless of vendor.
    _ram_total_kb="0"
    _ram_avail_kb="0"
    if [ -f /proc/meminfo ]; then
        while IFS=: read -r _mk _mv; do
            case "$_mk" in
                MemTotal) set -- $_mv; _ram_total_kb="${1:-0}" ;;
                MemAvailable) set -- $_mv; _ram_avail_kb="${1:-0}" ;;
            esac
        done < /proc/meminfo
    fi
    _ram_used_kb="0"
    if [ "$_ram_total_kb" -gt 0 ] 2>/dev/null && [ "$_ram_avail_kb" -ge 0 ] 2>/dev/null; then
        _ram_used_kb=$((_ram_total_kb - _ram_avail_kb))
        [ "$_ram_used_kb" -lt 0 ] 2>/dev/null && _ram_used_kb=0
    fi

    # Zram usage %. Summed across every zram device (some SoCs/ROMs use
    # more than one) since /sys/block/zram* is the generic kernel path -
    # no vendor-specific node needed.
    _zram_used_bytes=0
    _zram_total_bytes=0
    for _zdev in /sys/block/zram*; do
        [ -d "$_zdev" ] || continue
        _zu=""
        [ -f "$_zdev/mem_used_total" ] && read -r _zu < "$_zdev/mem_used_total" 2>/dev/null
        _zt=""
        [ -f "$_zdev/disksize" ] && read -r _zt < "$_zdev/disksize" 2>/dev/null
        [ -n "$_zu" ] && [ "$_zu" -ge 0 ] 2>/dev/null && _zram_used_bytes=$((_zram_used_bytes + _zu))
        [ -n "$_zt" ] && [ "$_zt" -gt 0 ] 2>/dev/null && _zram_total_bytes=$((_zram_total_bytes + _zt))
    done
    _zram_pct=0
    [ "$_zram_total_bytes" -gt 0 ] 2>/dev/null && _zram_pct=$((_zram_used_bytes * 100 / _zram_total_bytes))

    # CPU load average (1-minute), x100 to keep it an integer over the
    # JSON wire (e.g. 235 = 2.35). /proc/loadavg is a plain kernel stat,
    # identical format on every Android build.
    _cpu_load_x100=0
    if [ -f /proc/loadavg ]; then
        _la1=""
        read -r _la1 _rest < /proc/loadavg 2>/dev/null
        case "$_la1" in
            *.*)
                _la_int="${_la1%%.*}"
                # Pad decimal part with trailing zeros then take exactly 2
                # digits, so "2.3" -> "30" and "2.35" -> "35" both work.
                _la_dec=$(printf '%s' "${_la1#*.}00" | cut -c1-2)
                case "$_la_int" in ''|*[!0-9]*) _la_int=0 ;; esac
                case "$_la_dec" in ''|*[!0-9]*) _la_dec=0 ;; esac
                _cpu_load_x100=$((_la_int * 100 + _la_dec))
                ;;
        esac
    fi

    # Battery. power_supply is a generic kernel class (not chipset-specific)
    # but the node name under it varies wildly by OEM/PMIC (battery, Battery,
    # bms, sprd-battery, sc27xx-battery, ...), so name-matching alone is
    # unreliable. Every node exposes a "type" file though - whichever one
    # says "Battery" is the real battery, regardless of what it's called.
    _battery_pct="-1"
    _battery_status="Unknown"
    _battery_temp_c="0"
    for _bp in /sys/class/power_supply/*; do
        [ -d "$_bp" ] || continue
        [ -f "$_bp/type" ] || continue
        _ptype=""
        read -r _ptype < "$_bp/type" 2>/dev/null
        case "$_ptype" in
            [Bb]attery)
                [ -f "$_bp/capacity" ] || continue
                read -r _battery_pct < "$_bp/capacity" 2>/dev/null
                [ -f "$_bp/status" ] && read -r _battery_status < "$_bp/status" 2>/dev/null
                # Battery temp node is reported in tenths of a degree C
                # (e.g. 350 = 35.0C) on every stock Android kernel.
                if [ -f "$_bp/temp" ]; then
                    _bt=""
                    read -r _bt < "$_bp/temp" 2>/dev/null
                    [ -n "$_bt" ] && [ "$_bt" -gt 0 ] 2>/dev/null && _battery_temp_c=$((_bt / 10))
                fi
                break
                ;;
        esac
    done
    # Fallback: name-based match, in case "type" itself is missing/blocked
    # on some vendor's node.
    if [ "$_battery_pct" = "-1" ]; then
        for _bp in /sys/class/power_supply/battery /sys/class/power_supply/Battery \
                   /sys/class/power_supply/bms /sys/class/power_supply/*battery* \
                   /sys/class/power_supply/*Battery*; do
            [ -d "$_bp" ] || continue
            [ -f "$_bp/capacity" ] || continue
            read -r _battery_pct < "$_bp/capacity" 2>/dev/null
            [ -f "$_bp/status" ] && read -r _battery_status < "$_bp/status" 2>/dev/null
            if [ -f "$_bp/temp" ]; then
                _bt=""
                read -r _bt < "$_bp/temp" 2>/dev/null
                [ -n "$_bt" ] && [ "$_bt" -gt 0 ] 2>/dev/null && _battery_temp_c=$((_bt / 10))
            fi
            break
        done
    fi
    case "$_battery_pct" in ''|*[!0-9]*) _battery_pct="-1" ;; esac

    # Display refresh rate, used as the "FPS" tile. True per-frame render
    # FPS needs a running SurfaceFlinger trace (expensive to poll every
    # ~1s and unreliable across vendors), so we report the panel's current
    # refresh rate instead - it's what most lightweight perf HUDs show and
    # is readable the same way on every chipset via `dumpsys display`.
    # Display refresh rate, used as the "Frame Rate" tile. renderFrameRate
    # is dumpsys display's own answer for "what's the panel doing right
    # now" (a single value), whereas the supportedModes list in the same
    # dump packs several fps= entries onto one line - matching that with a
    # greedy regex previously grabbed the LAST mode in the list instead of
    # the active one, so renderFrameRate is tried first on purpose.
    # PERF: dumpsys is a Binder IPC round-trip to system_server - genuinely
    # slow, and this was calling it (display, then SurfaceFlinger --list,
    # then SurfaceFlinger --latency, each piped through grep/awk) on EVERY
    # single poll, every ~2s, forever, regardless of which WebUI tab was
    # open. That's very likely the real source of the felt lag: three
    # expensive system calls competing for the CPU right when the user
    # taps something. Neither refresh rate nor game fps needs sub-2s
    # freshness, so both are now cached to a small file and only actually
    # re-queried every ~12s (one `date` fork to check the cache age is far
    # cheaper than three dumpsys calls).
    _now_ts=$(date +%s 2>/dev/null)
    case "$_now_ts" in ''|*[!0-9]*) _now_ts=0 ;; esac

    _refresh_hz="0"
    _rr_cache="$HSIN_DATA/.cache_refresh_hz"
    _rr_cache_ts=0
    if [ -f "$_rr_cache" ]; then
        read -r _rr_cache_ts _rr_cache_val < "$_rr_cache" 2>/dev/null
        case "$_rr_cache_ts" in ''|*[!0-9]*) _rr_cache_ts=0 ;; esac
    fi
    if [ "$_now_ts" -gt 0 ] 2>/dev/null && [ $((_now_ts - _rr_cache_ts)) -lt 12 ] 2>/dev/null; then
        _refresh_hz="${_rr_cache_val:-0}"
    else
        _dump="$(dumpsys display 2>/dev/null)"
        _r=$(printf '%s\n' "$_dump" | grep -o 'renderFrameRate [0-9.]*' | head -n 1 | awk '{print $2}' | cut -d. -f1)
        [ -n "$_r" ] && [ "$_r" -gt 0 ] 2>/dev/null && _refresh_hz="$_r"
        if [ "$_refresh_hz" = "0" ]; then
            _r=$(printf '%s\n' "$_dump" | grep -o 'refreshRateOverride [0-9.]*' | awk '{print $2}' | cut -d. -f1 | awk '$1>0{print;exit}')
            [ -n "$_r" ] && _refresh_hz="$_r"
        fi
        if [ "$_refresh_hz" = "0" ]; then
            _r=$(printf '%s\n' "$_dump" | grep -o 'fps=[0-9.]*' | head -n 1 | cut -d= -f2 | cut -d. -f1)
            [ -n "$_r" ] && _refresh_hz="$_r"
        fi
        case "$_refresh_hz" in ''|*[!0-9]*) _refresh_hz="0" ;; esac
        printf '%s %s\n' "$_now_ts" "$_refresh_hz" > "$_rr_cache" 2>/dev/null
    fi

    # Current profile + apply status (PATCH v4.0: APPLY_STATUS diekspose ke
    # status JSON supaya WebUI konfirmasi "done" hanya pas engine BENERAN
    # selesai - sebelumnya konfirmasi cuma dari ACTIVE_PROFILE yang ditulis
    # di awal apply, jadi WebUI bilang beres padahal engine masih jalan).
    _profile="none"
    _apply_status="unknown"
    if [ -f "$HSIN_DATA/state.lock" ]; then
        while IFS='=' read -r _k _v || [ -n "$_k" ]; do
            case "$_k" in
                ACTIVE_PROFILE) _profile="${_v:-none}" ;;
                APPLY_STATUS) _apply_status="${_v:-unknown}" ;;
            esac
        done < "$HSIN_DATA/state.lock"
    fi

    # System uptime (seconds since boot) - /proc/uptime is universal across
    # every Android kernel/chipset, used for the Device tab uptime display.
    _uptime_sec="0"
    if [ -f /proc/uptime ]; then
        read -r _uptime_sec _rest < /proc/uptime 2>/dev/null
        _uptime_sec="${_uptime_sec%%.*}"
    fi
    case "$_uptime_sec" in ''|*[!0-9]*) _uptime_sec="0" ;; esac

    # Real in-game rendered FPS (not the panel's refresh_hz above - that's
    # the display's rated Hz, this is how many frames the foreground game
    # actually presented). dumpsys gfxinfo/framestats only tracks HWUI
    # (Activity decor) frames, which is USELESS here: almost every game
    # renders through a SurfaceView/native Vulkan surface that's a
    # separate compositor layer HWUI never touches - gfxinfo would report
    # near-zero or garbage for exactly the apps this is meant to measure.
    # SurfaceFlinger itself sees every layer regardless of how it renders,
    # so --latency on the game's own layer is the only method that's
    # actually correct for both GLES and Vulkan games.
    # PERF: same issue as refresh_hz above but worse - TWO dumpsys
    # SurfaceFlinger calls (--list to find the layer, then --latency to
    # read its frame timestamps), piped through grep/awk, every single
    # poll, even when the last-known game package isn't actually in the
    # foreground (e.g. user just has the WebUI open tweaking settings).
    # PATCH v4: window dinaikin 4s -> 15s (was: shorter window than
    # enough to watch live FPS while actually gaming, but cuts this
    # expensive pair of calls roughly in half during normal browsing).
    _game_fps="0"
    _cur_game_pkg=""
    [ -f "$HSIN_DATA/.last_game_pkg" ] && read -r _cur_game_pkg < "$HSIN_DATA/.last_game_pkg" 2>/dev/null
    _cur_game_pkg=$(printf '%s' "$_cur_game_pkg" | tr -d '\r\n')
    if [ -n "$_cur_game_pkg" ]; then
        _fps_cache="$HSIN_DATA/.cache_game_fps"
        _fps_cache_ts=0
        if [ -f "$_fps_cache" ]; then
            read -r _fps_cache_ts _fps_cache_pkg _fps_cache_val < "$_fps_cache" 2>/dev/null
            case "$_fps_cache_ts" in ''|*[!0-9]*) _fps_cache_ts=0 ;; esac
        fi
        if [ "$_now_ts" -gt 0 ] 2>/dev/null && [ "$_fps_cache_pkg" = "$_cur_game_pkg" ] \
            && [ $((_now_ts - _fps_cache_ts)) -lt 15 ] 2>/dev/null; then
            _game_fps="${_fps_cache_val:-0}"
        else
            _layer=$(dumpsys SurfaceFlinger --list 2>/dev/null | grep -m1 "$_cur_game_pkg")
            if [ -n "$_layer" ]; then
                _game_fps=$(dumpsys SurfaceFlinger --latency "$_layer" 2>/dev/null | awk '
                    NR==1 { next }
                    { if ($2+0 > 0) { if (first=="") first=$2; last=$2; count++ } }
                    END {
                        if (count > 1 && last > first) {
                            fps = (count - 1) / ((last - first) / 1000000000)
                            printf "%.0f", fps
                        } else print 0
                    }')
                case "$_game_fps" in ''|*[!0-9]*) _game_fps="0" ;; esac
            fi
            printf '%s %s %s\n' "$_now_ts" "$_cur_game_pkg" "$_game_fps" > "$_fps_cache" 2>/dev/null
        fi
    fi

    # PATCH v4: 9 field profil (global_rr/dvfs/frame_limit/sf) cuma berubah
    # kalau ganti profil - jangan re-parse tiap poll. Cache dianggap valid
    # selama lebih baru dari profiles/<profil>.conf (test -nt = builtin,
    # nggak fork stat/ls sama sekali). Invalid juga kalau nama profil beda.
    _f_rr_enabled="false"; _f_rr_reduced="false"; _f_rr_peak="0"; _f_rr_min="0"
    _f_dvfs_enabled="false"; _f_dvfs_cpu="100"; _f_dvfs_gpu="100"
    _f_frl_disabled="false"; _f_sf_enabled="false"
    _pf_fields_cache="$HSIN_DATA/.cache_profile_fields"
    if [ "$_profile" != "none" ] && [ -f "$HSIN_MODULE_PATH/profiles/${_profile}.conf" ]; then
        if [ -f "$_pf_fields_cache" ] && [ "$_pf_fields_cache" -nt "$HSIN_MODULE_PATH/profiles/${_profile}.conf" ]; then
            read -r _cf_profile _f_rr_enabled _f_rr_reduced _f_rr_peak _f_rr_min \
                _f_dvfs_enabled _f_dvfs_cpu _f_dvfs_gpu _f_frl_disabled _f_sf_enabled \
                < "$_pf_fields_cache" 2>/dev/null
            [ "$_cf_profile" != "$_profile" ] && rm -f "$_pf_fields_cache" 2>/dev/null
        fi
        if [ ! -f "$_pf_fields_cache" ]; then
            . "$HSIN_MODULE_PATH/core/profile_loader.sh" 2>/dev/null
            if command -v hsin_profile_load >/dev/null 2>&1; then
                hsin_profile_load "$_profile" 2>/dev/null
                _f_rr_enabled="$(hsin_profile_get global_rr enabled)"
                _f_rr_reduced="$(hsin_profile_get global_rr reduced)"
                _f_rr_peak="$(hsin_profile_get global_rr peak_hz)"
                _f_rr_min="$(hsin_profile_get global_rr min_hz)"
                _f_dvfs_enabled="$(hsin_profile_get dvfs enabled)"
                _f_dvfs_cpu="$(hsin_profile_get dvfs cpu_limit)"
                _f_dvfs_gpu="$(hsin_profile_get dvfs gpu_limit)"
                _f_frl_disabled="$(hsin_profile_get frame_limit disabled)"
                _f_sf_enabled="$(hsin_profile_get surfaceflinger enabled)"
                [ -z "$_f_rr_enabled" ] && _f_rr_enabled="false"
                [ -z "$_f_rr_reduced" ] && _f_rr_reduced="false"
                [ -z "$_f_rr_peak" ] && _f_rr_peak="0"
                [ -z "$_f_rr_min" ] && _f_rr_min="0"
                [ -z "$_f_dvfs_enabled" ] && _f_dvfs_enabled="false"
                [ -z "$_f_dvfs_cpu" ] && _f_dvfs_cpu="100"
                [ -z "$_f_dvfs_gpu" ] && _f_dvfs_gpu="100"
                [ -z "$_f_frl_disabled" ] && _f_frl_disabled="false"
                [ -z "$_f_sf_enabled" ] && _f_sf_enabled="false"
                printf '%s %s %s %s %s %s %s %s %s %s\n' "$_profile" \
                    "$_f_rr_enabled" "$_f_rr_reduced" "$_f_rr_peak" "$_f_rr_min" \
                    "$_f_dvfs_enabled" "$_f_dvfs_cpu" "$_f_dvfs_gpu" \
                    "$_f_frl_disabled" "$_f_sf_enabled" > "$_pf_fields_cache" 2>/dev/null
            fi
        fi
    fi

    # Final sanity clamp before this hits the WebUI. Belt-and-suspenders on
    # top of the devfreq guard above: any of these ending up negative or
    # non-numeric (a bad sysfs read, a race mid device state-change, etc.)
    # used to get printed as-is and shown raw/garbled on the Monitor tab.
    # The WebUI already renders 0 as "N/A", so resetting to 0 here is a
    # safe, silent fallback instead of a broken-looking number.
    for _sanevar in _cpu_temp _gpu_temp _cpu_freq _cpu_freq_big _cpu_freq_little _gpu_freq _cpu_max_khz _gpu_max_khz; do
        eval "_saneval=\$$_sanevar"
        case "$_saneval" in ''|*[!0-9]*) eval "$_sanevar=0" ;; esac
    done

    printf '{"cpu_temp":%s,"gpu_temp":%s,"cpu_freq":%s,"cpu_freq_big":%s,"cpu_freq_little":%s,"gpu_freq":%s,"cpu_max_khz":%s,"gpu_max_khz":%s,"ram_used_kb":%s,"ram_total_kb":%s,"battery_pct":%s,"battery_status":"%s","battery_temp_c":%s,"refresh_hz":%s,"game_fps":%s,"uptime_sec":%s,"profile":"%s","apply_status":"%s","cpu_load_x100":%s,"zram_pct":%s,"global_rr_enabled":"%s","global_rr_reduced":"%s","global_rr_peak_hz":%s,"global_rr_min_hz":%s,"dvfs_enabled":"%s","dvfs_cpu_limit":%s,"dvfs_gpu_limit":%s,"frame_limit_disabled":"%s","surfaceflinger_enabled":"%s"}\n' \
        "$_cpu_temp" "$_gpu_temp" "$_cpu_freq" "$_cpu_freq_big" "$_cpu_freq_little" "$_gpu_freq" "$_cpu_max_khz" "$_gpu_max_khz" \
        "$_ram_used_kb" "$_ram_total_kb" "$_battery_pct" "$_battery_status" "$_battery_temp_c" "$_refresh_hz" "$_game_fps" "$_uptime_sec" "$_profile" "$_apply_status" \
        "$_cpu_load_x100" "$_zram_pct" \
        "$_f_rr_enabled" "$_f_rr_reduced" "$_f_rr_peak" "$_f_rr_min" \
        "$_f_dvfs_enabled" "$_f_dvfs_cpu" "$_f_dvfs_gpu" \
        "$_f_frl_disabled" "$_f_sf_enabled"
}

# Get log entries as JSON
hsin_action_logs() {
    _type="${1:-apply}"
    _lines="${2:-20}"

    _log="$HSIN_DATA/logs/${_type}.log"
    [ -f "$_log" ] || {
        echo "[]"
        return
    }

    # Build as a single-line JSON array (see note above re: multi-line output).
    _items=""
    while IFS= read -r _line; do
        [ -z "$_line" ] && continue
        _esc=$(printf '%s' "$_line" | sed 's/\\/\\\\/g; s/"/\\"/g')
        if [ -z "$_items" ]; then
            _items="\"$_esc\""
        else
            _items="$_items,\"$_esc\""
        fi
    done <<EOF_LOGLINES
$(tail -n "$_lines" "$_log" 2>/dev/null)
EOF_LOGLINES

    printf '[%s]\n' "$_items"
}

# Bundle every diagnostic source (boot/apply/rollback/error/debug logs,
hsin_action_export_debug() {
    _out="$HSIN_DATA/HSIN_DEBUG_REPORT.txt"
    _lines="${1:-100}"

    {
        echo "===== HSIN Debug Report ====="
        echo "Generated: $(date '+%Y-%m-%d %H:%M:%S')"
        echo ""

        echo "----- Device detection (device.txt) -----"
        cat "$HSIN_DATA/device.txt" 2>/dev/null || echo "(not found - detector may not have run yet)"
        echo ""

        echo "----- Capability scoring (capability.json) -----"
        cat "$HSIN_DATA/capability.json" 2>/dev/null || echo "(not found)"
        echo ""

        echo "----- Current state (state.lock) -----"
        cat "$HSIN_DATA/state.lock" 2>/dev/null || echo "(not found)"
        echo ""

        echo "----- boot.log (last $_lines lines) -----"
        tail -n "$_lines" "$HSIN_DATA/logs/boot.log" 2>/dev/null || echo "(empty/not found)"
        echo ""

        echo "----- apply.log (last $_lines lines) -----"
        tail -n "$_lines" "$HSIN_DATA/logs/apply.log" 2>/dev/null || echo "(empty/not found)"
        echo ""

        echo "----- rollback.log (last $_lines lines) -----"
        tail -n "$_lines" "$HSIN_DATA/logs/rollback.log" 2>/dev/null || echo "(empty/not found)"
        echo ""

        echo "----- error.log (last $_lines lines) -----"
        tail -n "$_lines" "$HSIN_DATA/logs/error.log" 2>/dev/null || echo "(empty/not found)"
        echo ""

        echo "----- debug.log: raw stderr, undefined functions, etc (last $_lines lines) -----"
        tail -n "$_lines" "$HSIN_DATA/logs/debug.log" 2>/dev/null || echo "(empty/not found)"
    } > "$_out" 2>/dev/null

    echo "OK: Debug report written to $_out"
}

# Apply profile (main action)
# $2 = source: "manual" (default, from WebUI/CLI apply button) or "boost"
# (called internally by the game-boost transition logic). Only a manual
# apply persists PROFILE= into hsin.conf - a boost/revert call must never
# overwrite the user's actual chosen base profile with a temporary value.
hsin_action_apply() {
    _profile="${1:-balanced}"
    _apply_source="${2:-manual}"

    # Validate profile exists
    [ -f "$HSIN_MODULE_PATH/profiles/${_profile}.conf" ] || {
        echo "ERROR: Profile not found: $_profile"
        return 1
    }

    # Check if extreme requires opt-in
    if [ "$_profile" = "extreme" ]; then
        [ "$ALLOW_EXTREME" = "true" ] || {
            echo "ERROR: Extreme mode requires ALLOW_EXTREME=true"
            return 1
        }
    fi

    # FIX: persist the user's manually chosen profile into hsin.conf's
    # PROFILE= line. Previously ONLY state.lock got updated here, so
    # hsin.conf's PROFILE stayed stuck at whatever customize.sh wrote at
    # install time ("balanced") forever. Every "restore base profile after
    # game closes" read (here and in monitor.sh) reads PROFILE from
    # hsin.conf, so without this fix the game-boost revert always fell
    # back to the install-time default instead of what you actually picked.
    # PATCH v4.2: boost aktif + apply manual -> update target revert supaya
    # game-close balik ke pilihan BARU user, bukan base lama.
    if [ "$_apply_source" = "manual" ] && [ -f "$HSIN_DATA/.game_boost_state" ]; then
        printf '%s' "$_profile" > "$HSIN_DATA/.game_boost_state" 2>/dev/null
    fi

    if [ "$_apply_source" = "manual" ] && [ -f "$HSIN_CONF" ]; then
        _pw_tmp="${HSIN_CONF}.tmp.$$"
        _pw_found=0
        : > "$_pw_tmp"
        while IFS= read -r _pw_line || [ -n "$_pw_line" ]; do
            case "$_pw_line" in
                PROFILE=*) printf 'PROFILE=%s\n' "$_profile" >> "$_pw_tmp"; _pw_found=1 ;;
                *) printf '%s\n' "$_pw_line" >> "$_pw_tmp" ;;
            esac
        done < "$HSIN_CONF"
        [ "$_pw_found" -eq 0 ] && printf 'PROFILE=%s\n' "$_profile" >> "$_pw_tmp"
        mv "$_pw_tmp" "$HSIN_CONF"
        chmod 0644 "$HSIN_CONF" 2>/dev/null
    fi

    # Policy check (fast, no sysfs writes)
    hsin_policy_init
    hsin_policy_check "engine" "$_profile" || {
        echo "WARNING: Policy override to $HSIN_POLICY_ACTIVE_PROFILE"
        _reason="policy limit"
        case "$HSIN_POLICY_THERMAL_OVERRIDE" in
            panic|critical) _reason="thermal ${HSIN_POLICY_THERMAL_OVERRIDE}" ;;
            warn) _reason="thermal warning" ;;
        esac
        [ "$HSIN_POLICY_BATTERY_SAVER" = "true" ] && _reason="battery saver"
        [ "$HSIN_POLICY_STABILITY_BLOCK" = "true" ] && _reason="stability protection"
        hsin_notify "HSIN" "Switched to $HSIN_POLICY_ACTIVE_PROFILE ($_reason)" 2>/dev/null
        _profile="$HSIN_POLICY_ACTIVE_PROFILE"
    }

    # Initialize state (fast)
    hsin_state_init
    hsin_state_save_before_apply

    # Capture the outgoing profile BEFORE we overwrite ACTIVE_PROFILE below.
    # Needed so the background job knows whether it must tear down Extreme
    # Mode's aggressive overrides (freq unlock / GPU override / thermal trip
    # override) when switching away from it.
    _prev_profile="none"
    [ -f "$HSIN_DATA/state.lock" ] && _prev_profile=$(grep "^ACTIVE_PROFILE=" "$HSIN_DATA/state.lock" 2>/dev/null | cut -d= -f2)
    [ -z "$_prev_profile" ] && _prev_profile="none"

    # Update state.lock FIRST, so the WebUI sees the profile flip
    # immediately (next 3s poll) rather than waiting for the bg apply
    # to land. Also makes sure game_boost_check's read of ACTIVE_PROFILE
    # always succeeds.
    hsin_state_profile "$_profile" 2>/dev/null
    hsin_state_update "APPLY_STATUS" "applying:$_profile" 2>/dev/null
    hsin_log_apply "ENGINE" "Profile applied (queued): $_profile"
    # FIX: fire an immediate "applying" notification here instead of only
    # notifying once the full background pipeline finishes (CPU+GPU+
    # thermal+memory+io+network, plus extra steps for extreme). That could
    # take 5-30s, making it look like nothing happened. This gives instant
    # feedback; the background job still sends its own completion
    # notification ("Profile: $_profile") once the real sysfs writes land.
    [ "$_apply_source" = "manual" ] && hsin_notify "HSIN" "Applying $_profile..." 2>/dev/null

    # Write the heavy work out to a standalone script file and launch it
    mkdir -p "$HSIN_DATA/tmp" 2>/dev/null
    _bgscript="$HSIN_DATA/tmp/apply_$$_$(date +%s).sh"

    cat > "$_bgscript" << BGEOF
#!/system/bin/sh
HSIN_MODULE_PATH="$HSIN_MODULE_PATH"
HSIN_DATA="$HSIN_DATA"
ALLOW_EXTREME="${ALLOW_EXTREME:-false}"
# Same hidden debug log as action.sh itself - this background job is a
HSIN_DEBUG_LOG="\$HSIN_DATA/logs/debug.log"
mkdir -p "\$HSIN_DATA/logs" 2>/dev/null
echo "----- \$(date '+%Y-%m-%d %H:%M:%S') apply-bg $_profile -----" >> "\$HSIN_DEBUG_LOG" 2>/dev/null
exec 2>>"\$HSIN_DEBUG_LOG"

. "\$HSIN_MODULE_PATH/core/logger.sh"
. "\$HSIN_MODULE_PATH/core/backup.sh"
. "\$HSIN_MODULE_PATH/core/state_manager.sh"

    # PATCH v4.3: pipeline unified - SEMUA engine (termasuk display/
    # render yang sebelumnya cuma jalan pas boot, plus DVFS + thermal)
    # lewat core/apply_engines.sh - sama persis dengan monitor.sh.
    . "\$HSIN_MODULE_PATH/core/apply_engines.sh"
    if hsin_apply_all_engines "$_profile" "$_prev_profile" "" "$_apply_source"; then
        hsin_state_profile "$_profile"
        hsin_state_update "APPLY_STATUS" "done:$_profile"
        hsin_log_apply "ENGINE" "Profile applied: $_profile"
        hsin_notify "HSIN" "Profile: $_profile" 2>/dev/null
    else
        hsin_state_update "APPLY_STATUS" "error:$_profile"
        hsin_log_error "main" "Profile apply failed: $_profile"
        hsin_notify "HSIN" "Profile failed: $_profile" 2>/dev/null
    fi


# Re-write state.lock in case the background job overwrote or stomped
# the "applying" marker we set synchronously above. Idempotent.
rm -f "\$0"
BGEOF
    chmod 755 "$_bgscript" 2>/dev/null

    if command -v setsid >/dev/null 2>&1; then
        setsid sh "$_bgscript" </dev/null >/dev/null 2>&1 &
    elif [ -x /data/adb/ksu/bin/busybox ]; then
        /data/adb/ksu/bin/busybox setsid sh "$_bgscript" </dev/null >/dev/null 2>&1 &
    else
        # Last-resort fallback: no setsid available anywhere. This can still
        sh "$_bgscript" </dev/null >/dev/null 2>&1 &
    fi

    echo "OK: Applying $_profile (running in background, check status in a moment)"
}

# Backup action
hsin_action_backup() {
    echo "Creating backup..."
    hsin_backup_all >/dev/null 2>&1
    hsin_log_apply "BACKUP" "Backup created"
    echo "OK: Backup created"
}

# Rollback action
hsin_action_rollback() {
    echo "Rolling back..."
    . "$HSIN_MODULE_PATH/core/rollback.sh" 2>/dev/null
    hsin_rollback_all
    hsin_log_rollback "Manual rollback triggered"
    echo "OK: Rollback complete"
}

# Get conflict status as JSON
# Read current values of the toggleable settings, as JSON
hsin_action_config_get() {
    _gam="false"
    _ext="false"
    _renderer="system"
    _downscale="false"
    _downscale_pct="30"
    _refresh_lock="false"
    _refresh_lock_hz="120"
    if [ -f "$HSIN_CONF" ]; then
        while IFS='=' read -r _key _val || [ -n "$_key" ]; do
            case "$_key" in
                GAM_BOOST_ENABLED) [ -n "$_val" ] && _gam="$_val" ;;
                ALLOW_EXTREME) [ -n "$_val" ] && _ext="$_val" ;;
                RENDERER) [ -n "$_val" ] && _renderer="$_val" ;;
                DOWNSCALE_ENABLED) [ -n "$_val" ] && _downscale="$_val" ;;
                DOWNSCALE_PERCENT) [ -n "$_val" ] && _downscale_pct="$_val" ;;
                REFRESH_LOCK_ENABLED) [ -n "$_val" ] && _refresh_lock="$_val" ;;
                REFRESH_LOCK_HZ) [ -n "$_val" ] && _refresh_lock_hz="$_val" ;;
            esac
        done < "$HSIN_CONF"
    fi
    echo "{\"gam_boost_enabled\":\"$_gam\",\"allow_extreme\":\"$_ext\",\"renderer\":\"$_renderer\",\"downscale_enabled\":\"$_downscale\",\"downscale_percent\":\"$_downscale_pct\",\"refresh_lock_enabled\":\"$_refresh_lock\",\"refresh_lock_hz\":\"$_refresh_lock_hz\"}"
}

# Toggle one of the allowed settings in hsin.conf - $1=key $2=true|false.
# Only these two keys are settable this way on purpose, so the WebUI can't
# be used to inject arbitrary config lines.
hsin_action_config_set() {
    _key="$1"
    _val="$2"
    case "$_key" in
        GAM_BOOST_ENABLED|ALLOW_EXTREME|DOWNSCALE_ENABLED|REFRESH_LOCK_ENABLED) : ;;
        RENDERER) : ;;
        DOWNSCALE_PERCENT|REFRESH_LOCK_HZ) : ;;
        *) echo "ERROR: unknown setting: $_key"; return 1 ;;
    esac
    case "$_key" in
        RENDERER)
            case "$_val" in
                skiagl|skiavk|system) : ;;
                *) echo "ERROR: RENDERER must be skiagl, skiavk, or system"; return 1 ;;
            esac
            ;;
        DOWNSCALE_PERCENT)
            case "$_val" in
                ''|*[!0-9]*) echo "ERROR: DOWNSCALE_PERCENT must be a number 1-99"; return 1 ;;
            esac
            if [ "$_val" -lt 1 ] || [ "$_val" -gt 99 ]; then
                echo "ERROR: DOWNSCALE_PERCENT must be 1-99"
                return 1
            fi
            ;;
        REFRESH_LOCK_HZ)
            case "$_val" in
                ''|*[!0-9]*) echo "ERROR: REFRESH_LOCK_HZ must be a number"; return 1 ;;
            esac
            ;;
        *)
            case "$_val" in
                true|false) : ;;
                *) echo "ERROR: value must be true or false"; return 1 ;;
            esac
            ;;
    esac

    [ -f "$HSIN_CONF" ] || { echo "ERROR: config not found: $HSIN_CONF"; return 1; }

    _tmp="${HSIN_CONF}.tmp.$$"
    _found=0
    : > "$_tmp"
    while IFS= read -r _line || [ -n "$_line" ]; do
        case "$_line" in
            ${_key}=*) printf '%s=%s\n' "$_key" "$_val" >> "$_tmp"; _found=1 ;;
            *) printf '%s\n' "$_line" >> "$_tmp" ;;
        esac
    done < "$HSIN_CONF"
    [ "$_found" -eq 0 ] && printf '%s=%s\n' "$_key" "$_val" >> "$_tmp"
    mv "$_tmp" "$HSIN_CONF"
    chmod 0644 "$HSIN_CONF" 2>/dev/null

    # If GAM_BOOST_ENABLED was turned on, make sure the monitor loop is
    # running so game detection actually fires. No-op if already running.
    if [ "$_key" = "GAM_BOOST_ENABLED" ] && [ "$_val" = "true" ]; then
        . "$HSIN_MODULE_PATH/core/monitor.sh" 2>/dev/null
        _mpid=""
        [ -f "$HSIN_DATA/monitor.pid" ] && read -r _mpid < "$HSIN_DATA/monitor.pid" 2>/dev/null
        if [ -n "$_mpid" ] && kill -0 "$_mpid" 2>/dev/null; then
            : # monitor already alive
        else
            rm -f "$HSIN_DATA/.monitor.stop" 2>/dev/null
            hsin_monitor_start
            hsin_log_info "config" "Monitor started for game boost (toggle-on)"
        fi
    fi

    echo "OK: $_key=$_val"
}

hsin_action_conflicts() {
    _conflicts=""
    _count=0

    # Check for other modules
    for _dir in /data/adb/modules/*/; do
        [ -d "$_dir" ] || continue
        _name=$(basename "$_dir")
        case "$_name" in
            hsin*) continue ;;
        esac

        case "$_name" in
            *UPerf*|*uperf*)
                _conflicts="${_conflicts}{\"name\":\"UPerf\",\"path\":\"$_dir\",\"conflict\":\"CPU frequency control\",\"status\":\"active\"},"
                _count=$((_count + 1))
                ;;
            *GTurbo*|*gturbo*)
                _conflicts="${_conflicts}{\"name\":\"GTurbo\",\"path\":\"$_dir\",\"conflict\":\"GPU governor control\",\"status\":\"active\"},"
                _count=$((_count + 1))
                ;;
            *FAS*|*fas*)
                _conflicts="${_conflicts}{\"name\":\"FAS-RS\",\"path\":\"$_dir\",\"conflict\":\"FPS management\",\"status\":\"active\"},"
                _count=$((_count + 1))
                ;;
            *Sasha*|*sasha*)
                _conflicts="${_conflicts}{\"name\":\"Sasha\",\"path\":\"$_dir\",\"conflict\":\"Thermal control\",\"status\":\"active\"},"
                _count=$((_count + 1))
                ;;
            *Rairin*|*rairin*)
                _conflicts="${_conflicts}{\"name\":\"Rairin\",\"path\":\"$_dir\",\"conflict\":\"Performance engine\",\"status\":\"active\"},"
                _count=$((_count + 1))
                ;;
        esac
    done

    # Remove trailing comma
    _conflicts="${_conflicts%,}"

    printf '{"count":%s,"conflicts":[%s]}\n' "$_count" "$_conflicts"
}

# Human-readable summary for the Manager app's "Action" button, which runs
hsin_action_info() {
    _profile="none"
    if [ -f "$HSIN_DATA/state.lock" ]; then
        while IFS='=' read -r _k _v || [ -n "$_k" ]; do
            [ "$_k" = "ACTIVE_PROFILE" ] && { _profile="${_v:-none}"; break; }
        done < "$HSIN_DATA/state.lock"
    fi

    _status_json=$(hsin_action_live_status)
    _cpu_freq=0; _gpu_freq=0; _cpu_temp=0; _gpu_temp=0
    # Parse simple key:value JSON in one pass - strip braces, replace
    # commas with newlines, then read each k:v pair with builtins only.
    _sj="${_status_json#\{}"; _sj="${_sj%\}}"
    _kv_tmp="$HSIN_DATA/.action_info_kv.$$"
    printf '%s' "$_sj" | tr ',' '\n' > "$_kv_tmp" 2>/dev/null
    while IFS=: read -r _pk _pv; do
        _pk="${_pk#\"}"; _pk="${_pk%\"}"; _pk="${_pk## }"
        _pv="${_pv#\"}"; _pv="${_pv%\"}"
        case "$_pk" in
            cpu_freq) _cpu_freq="${_pv:-0}" ;;
            gpu_freq) _gpu_freq="${_pv:-0}" ;;
            cpu_temp) _cpu_temp="${_pv:-0}" ;;
            gpu_temp) _gpu_temp="${_pv:-0}" ;;
        esac
    done < "$_kv_tmp"
    rm -f "$_kv_tmp" 2>/dev/null

    echo "HSIN Universal Engine"
    echo "Profile aktif: $_profile"
    echo ""
    [ -n "$_cpu_freq" ] && [ "$_cpu_freq" -gt 0 ] 2>/dev/null && \
        echo "CPU: $((_cpu_freq / 1000)) MHz, $((_cpu_temp / 1000))°C"
    [ -n "$_gpu_freq" ] && [ "$_gpu_freq" -gt 0 ] 2>/dev/null && \
        echo "GPU: $((_gpu_freq / 1000)) MHz, $((_gpu_temp / 1000))°C"
    echo ""
    echo "Buka WebUI module ini buat kontrol lengkap."
}

# Main dispatcher
_main() {
    _cmd="${1:-info}"
    [ "$#" -gt 0 ] && shift

    case "$_cmd" in
        info)
            hsin_action_info
            ;;
        device)
            hsin_action_device_info
            ;;
        capabilities)
            hsin_action_capabilities
            ;;
        status)
            hsin_action_game_boost_check
            hsin_action_live_status
            ;;
        logs)
            hsin_action_logs "$@"
            ;;
        apply)
            hsin_action_apply "$1" "manual"
            ;;
        backup)
            hsin_action_backup
            ;;
        rollback)
            hsin_action_rollback
            ;;
        conflicts)
            hsin_action_conflicts
            ;;
        config-get)
            hsin_action_config_get
            ;;
        config-set)
            hsin_action_config_set "$1" "$2"
            ;;
        renderer-apply)
            . "$HSIN_MODULE_PATH/engine/render/renderer.sh" 2>/dev/null
            if hsin_render_apply_live "$1"; then
                # Persist so post-fs-data.sh re-applies this automatically
                # at next boot without the user having to tap Apply again.
                hsin_action_config_set "RENDERER" "$1" >/dev/null 2>&1
            fi
            ;;
        renderer-state)
            . "$HSIN_MODULE_PATH/engine/render/renderer.sh" 2>/dev/null
            hsin_render_state
            ;;
        downscale-enable)
            . "$HSIN_MODULE_PATH/engine/display/downscale.sh" 2>/dev/null
            _ds_pct="${1:-30}"
            case "$_ds_pct" in
                ''|*[!0-9]*) echo "ERROR: percent must be a number 1-99"; exit 1 ;;
            esac
            if [ "$_ds_pct" -lt 1 ] || [ "$_ds_pct" -gt 99 ]; then
                echo "ERROR: percent must be 1-99"
                exit 1
            fi
            hsin_downscale_capture_native
            if hsin_downscale_apply "$_ds_pct"; then
                hsin_action_config_set "DOWNSCALE_ENABLED" "true" >/dev/null 2>&1
                hsin_action_config_set "DOWNSCALE_PERCENT" "$_ds_pct" >/dev/null 2>&1
                echo "OK: downscale applied ($(hsin_downscale_calc_target "$_ds_pct" 2>/dev/null) @ $(hsin_downscale_calc_density "$_ds_pct" 2>/dev/null)dpi, ${_ds_pct}%)"
            else
                echo "ERROR: could not apply downscale (native resolution not detected yet)"
                exit 1
            fi
            ;;
        downscale-disable)
            . "$HSIN_MODULE_PATH/engine/display/downscale.sh" 2>/dev/null
            hsin_downscale_reset
            hsin_action_config_set "DOWNSCALE_ENABLED" "false" >/dev/null 2>&1
            echo "OK: downscale disabled, restored native resolution and density"
            ;;
        downscale-status)
            . "$HSIN_MODULE_PATH/engine/display/downscale.sh" 2>/dev/null
            _ds_enabled="false"
            _ds_saved_pct="30"
            if [ -f "$HSIN_CONF" ]; then
                while IFS='=' read -r _dk _dv || [ -n "$_dk" ]; do
                    case "$_dk" in
                        DOWNSCALE_ENABLED) [ -n "$_dv" ] && _ds_enabled="$_dv" ;;
                        DOWNSCALE_PERCENT) [ -n "$_dv" ] && _ds_saved_pct="$_dv" ;;
                    esac
                done < "$HSIN_CONF"
            fi
            hsin_downscale_status "$_ds_enabled" "$_ds_saved_pct"
            ;;
        list-apps)
            . "$HSIN_MODULE_PATH/engine/game/detector.sh" 2>/dev/null
            . "$HSIN_MODULE_PATH/engine/game/game_manager.sh" 2>/dev/null
            hsin_game_list_installed
            ;;
        game-list|game_list)
            . "$HSIN_MODULE_PATH/engine/game/detector.sh" 2>/dev/null
            . "$HSIN_MODULE_PATH/engine/game/game_manager.sh" 2>/dev/null
            hsin_game_list_conf
            ;;
        game-add|game_add)
            . "$HSIN_MODULE_PATH/engine/game/detector.sh" 2>/dev/null
            . "$HSIN_MODULE_PATH/engine/game/game_manager.sh" 2>/dev/null
            hsin_game_add "$1" "$2"
            ;;
        game-remove|game_remove)
            . "$HSIN_MODULE_PATH/engine/game/detector.sh" 2>/dev/null
            . "$HSIN_MODULE_PATH/engine/game/game_manager.sh" 2>/dev/null
            hsin_game_remove "$1"
            ;;
        refresh-lock-enable)
            . "$HSIN_MODULE_PATH/engine/display/refresh_rate.sh" 2>/dev/null
            _rr_hz="${1:-120}"
            case "$_rr_hz" in
                ''|*[!0-9]*) echo "ERROR: hz must be a number"; exit 1 ;;
            esac
            _rr_applied=$(hsin_refresh_lock "$_rr_hz")
            if [ -n "$_rr_applied" ]; then
                hsin_action_config_set "REFRESH_LOCK_ENABLED" "true" >/dev/null 2>&1
                hsin_action_config_set "REFRESH_LOCK_HZ" "$_rr_applied" >/dev/null 2>&1
                echo "OK: refresh rate locked at ${_rr_applied}Hz"
            else
                echo "ERROR: could not lock refresh rate (no settings/cmd binary?)"
                exit 1
            fi
            ;;
        refresh-lock-disable)
            . "$HSIN_MODULE_PATH/engine/display/refresh_rate.sh" 2>/dev/null
            hsin_refresh_unlock
            hsin_action_config_set "REFRESH_LOCK_ENABLED" "false" >/dev/null 2>&1
            echo "OK: refresh rate lock disabled, restored auto/adaptive"
            ;;
        refresh-lock-status)
            . "$HSIN_MODULE_PATH/engine/display/refresh_rate.sh" 2>/dev/null
            _rr_enabled="false"
            _rr_saved_hz="120"
            if [ -f "$HSIN_CONF" ]; then
                while IFS='=' read -r _rk _rv || [ -n "$_rk" ]; do
                    case "$_rk" in
                        REFRESH_LOCK_ENABLED) [ -n "$_rv" ] && _rr_enabled="$_rv" ;;
                        REFRESH_LOCK_HZ) [ -n "$_rv" ] && _rr_saved_hz="$_rv" ;;
                    esac
                done < "$HSIN_CONF"
            fi
            hsin_refresh_status "$_rr_enabled" "$_rr_saved_hz"
            ;;
        export-debug)
            hsin_action_export_debug "$1"
            ;;
        export)
            hsin_action_export_debug "$1"
            ;;
        *)
            echo "Usage: action.sh [info|device|capabilities|status|logs|apply|backup|rollback|conflicts|export|renderer-apply|renderer-state|downscale-enable|downscale-disable|downscale-status|refresh-lock-enable|refresh-lock-disable|refresh-lock-status|export-debug|list-apps|game-list|game-add|game-remove]"
            ;;
    esac

    hsin_protect_harden_data
}

_main "$@"
