#!/system/bin/sh
# HSIN CPU Engine - Governor Engine
# Credit: logic inspired by UPerf (CPU frequency control)

[ -z "$HSIN_MODULE_PATH" ] && HSIN_MODULE_PATH="/data/adb/modules/hsin"
# Daftar policy datang dari hsin_cpu_policy_ids() (cache scan-sekali-simpan,
# fallback glob) - sumbernya sama dengan detect.sh, dan tidak ada field
# daftar-governor di cache (yang tersimpan cuma governor saat ini), jadi
# scaling_available_governors tetap dibaca live per policy.
command -v hsin_cpu_policy_ids >/dev/null 2>&1 || \
    . "$HSIN_MODULE_PATH/engine/cpu/detect.sh" 2>/dev/null

# Pick best governor for profile from available list
hsin_cpu_governor_pick() {
    _profile="$1"
    _avail="$2"

    case "$_profile" in
        battery)
            # Priority: schedutil > powersave > conservative
            for _g in schedutil powersave conservative; do
                case " $_avail " in
                    *" $_g "*) echo "$_g"; return 0 ;;
                esac
            done
            ;;
        balanced)
            # Priority: schedutil only
            for _g in schedutil; do
                case " $_avail " in
                    *" $_g "*) echo "$_g"; return 0 ;;
                esac
            done
            ;;
        performance)
            # Priority: schedutil first, performance only if available
            for _g in schedutil performance; do
                case " $_avail " in
                    *" $_g "*) echo "$_g"; return 0 ;;
                esac
            done
            ;;
        extreme)
            # Priority: performance > schedutil
            for _g in performance schedutil; do
                case " $_avail " in
                    *" $_g "*) echo "$_g"; return 0 ;;
                esac
            done
            ;;
    esac
    echo ""
    return 1
}

# Apply governor to all clusters
hsin_cpu_governor_apply() {
    _profile="$1"
    _ok=0
    _skip=0
    _fail=0

    hsin_cpu_policy_ids
    for _pid in $HSIN_CPU_POLICY_IDS; do
        _policy="$HSIN_SYSFS_CPU/cpufreq/policy$_pid"
        [ -d "$_policy" ] || continue

        # Check if writable
        [ -w "$_policy/scaling_governor" ] || { _skip=$((_skip + 1)); continue; }

        # Check available governors
        [ -f "$_policy/scaling_available_governors" ] || { _skip=$((_skip + 1)); continue; }

        _avail=""
        read -r _avail < "$_policy/scaling_available_governors" 2>/dev/null
        _target=$(hsin_cpu_governor_pick "$_profile" "$_avail")

        [ -z "$_target" ] && { _skip=$((_skip + 1)); continue; }

        # Check current
        _current=""
        [ -f "$_policy/scaling_governor" ] && _current=$(cat "$_policy/scaling_governor" 2>/dev/null)
        [ "$_current" = "$_target" ] && { _ok=$((_ok + 1)); continue; }

        # Apply
        echo "$_target" > "$_policy/scaling_governor" 2>/dev/null || { _fail=$((_fail + 1)); continue; }

        # Verify
        _verify=$(cat "$_policy/scaling_governor" 2>/dev/null)
        if [ "$_verify" = "$_target" ]; then
            _ok=$((_ok + 1))
        else
            _fail=$((_fail + 1))
        fi
    done

    echo "    Governor [$_profile]: ok=$_ok skip=$_skip fail=$_fail"

    # Scheduler: sched_child_runs_first
    # Ensures child processes (like app spawns) run before parents,
    # reducing app launch latency. Enabled on performance/extreme.
    if [ -w /proc/sys/kernel/sched_child_runs_first ]; then
        case "$_profile" in
            performance|extreme) _scrf="1" ;;
            *)                   _scrf="0" ;;
        esac
        _cur_scrf=$(cat /proc/sys/kernel/sched_child_runs_first 2>/dev/null)
        if [ "$_cur_scrf" != "$_scrf" ]; then
            echo "$_scrf" > /proc/sys/kernel/sched_child_runs_first 2>/dev/null
        fi
    fi

    return 0
}

# Get governor state for all clusters
hsin_cpu_governor_state() {
    hsin_cpu_policy_ids
    for _pid in $HSIN_CPU_POLICY_IDS; do
        _policy="$HSIN_SYSFS_CPU/cpufreq/policy$_pid"
        [ -d "$_policy" ] || continue
        _gov=""
        [ -f "$_policy/scaling_governor" ] && _gov=$(cat "$_policy/scaling_governor" 2>/dev/null)
        printf "    policy%s: %s\n" "$_pid" "${_gov:-?}"
    done
}

return 0 2>/dev/null || true
