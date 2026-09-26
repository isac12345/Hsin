#!/system/bin/sh
# HSIN CPU Engine - Apply Controller
# Credit: logic inspired by UPerf (CPU frequency control)

[ -z "$HSIN_MODULE_PATH" ] && HSIN_MODULE_PATH="/data/adb/modules/hsin"
HSIN_DATA="${HSIN_DATA:-/data/adb/hsin}"

# Load dependencies
. "$HSIN_MODULE_PATH/core/logger.sh" 2>/dev/null
. "$HSIN_MODULE_PATH/core/validator.sh" 2>/dev/null
. "$HSIN_MODULE_PATH/core/backup.sh" 2>/dev/null
. "$HSIN_MODULE_PATH/engine/cpu/detect.sh" 2>/dev/null
. "$HSIN_MODULE_PATH/engine/cpu/governor.sh" 2>/dev/null
. "$HSIN_MODULE_PATH/engine/cpu/frequency.sh" 2>/dev/null
. "$HSIN_MODULE_PATH/engine/cpu/scheduler.sh" 2>/dev/null
. "$HSIN_MODULE_PATH/engine/cpu/safety.sh" 2>/dev/null

# Backup current CPU state
hsin_cpu_backup() {
    _backup_dir="$HSIN_DATA/backups/cpu_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$_backup_dir" 2>/dev/null

    for _policy in /sys/devices/system/cpu/cpufreq/policy*; do
        [ -d "$_policy" ] || continue
        _name=$(basename "$_policy")
        _backup_file="$_backup_dir/$_name"
        {
            [ -f "$_policy/scaling_governor" ] && echo "governor=$(cat "$_policy/scaling_governor" 2>/dev/null)"
            [ -f "$_policy/scaling_min_freq" ] && echo "min_freq=$(cat "$_policy/scaling_min_freq" 2>/dev/null)"
            [ -f "$_policy/scaling_max_freq" ] && echo "max_freq=$(cat "$_policy/scaling_max_freq" 2>/dev/null)"
        } > "$_backup_file" 2>/dev/null
    done

    echo "$_backup_dir"
}
# Restore CPU state from backup
hsin_cpu_restore() {
    _backup_dir="$1"
    [ -d "$_backup_dir" ] || return 1

    _ok=0
    for _backup_file in "$_backup_dir"/policy*; do
        [ -f "$_backup_file" ] || continue
        _name=$(basename "$_backup_file")
        _policy="/sys/devices/system/cpu/cpufreq/$_name"
        [ -d "$_policy" ] || continue

        # Restore governor
        _gov=$(grep "^governor=" "$_backup_file" 2>/dev/null | cut -d= -f2)
        [ -n "$_gov" ] && [ -w "$_policy/scaling_governor" ] && {
            echo "$_gov" > "$_policy/scaling_governor" 2>/dev/null
        }

        # Restore max freq first
        _max=$(grep "^max_freq=" "$_backup_file" 2>/dev/null | cut -d= -f2)
        [ -n "$_max" ] && [ -w "$_policy/scaling_max_freq" ] && {
            echo "$_max" > "$_policy/scaling_max_freq" 2>/dev/null
        }

        # Restore min freq
        _min=$(grep "^min_freq=" "$_backup_file" 2>/dev/null | cut -d= -f2)
        [ -n "$_min" ] && [ -w "$_policy/scaling_min_freq" ] && {
            echo "$_min" > "$_policy/scaling_min_freq" 2>/dev/null
        }

        _ok=$((_ok + 1))
    done

    echo "    Restored $_ok clusters from backup"

    # Scheduler latency nodes aren't part of the per-policy backup file
    # above (they're global, not per-cluster) - restore them separately
    # from their own native-value capture so a rollback/disable always
    # puts the kernel back to fully stock, not just CPU freq/governor.
    hsin_cpu_sched_lat_restore

    return 0
}

# Verify CPU state after apply
hsin_cpu_verify() {
    _healthy=0
    _total=0

    for _policy in /sys/devices/system/cpu/cpufreq/policy*; do
        [ -d "$_policy" ] || continue
        _total=$((_total + 1))

        # Check if policy is still accessible
        if [ -f "$_policy/scaling_governor" ] && [ -r "$_policy/scaling_governor" ]; then
            _healthy=$((_healthy + 1))
        fi
    done

    [ "$_total" -eq 0 ] && return 2
    [ "$_healthy" -eq "$_total" ] && return 0
    [ "$_healthy" -gt 0 ] && return 1
    return 2
}

# Log results
hsin_cpu_log() {
    _profile="$1"
    _status="$2"
    _backup_dir="$3"

    _log_dir="$HSIN_DATA/logs"
    mkdir -p "$_log_dir" 2>/dev/null
    _log_file="$_log_dir/cpu.log"

    {
        echo "========================================"
        echo "Date: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "Profile: $_profile"
        echo "Status: $_status"
        echo "Backup: $_backup_dir"
        echo ""
        echo "Governor State:"
        hsin_cpu_governor_state
        echo ""
        echo "Frequency State:"
        hsin_cpu_freq_state
        echo ""
        echo "Sched-Latency State:"
        hsin_cpu_sched_lat_state
        echo ""
    } >> "$_log_file" 2>/dev/null
}

# Main apply function
hsin_cpu_apply() {
    _profile="$1"

    echo ""
    echo "╔══════════════════════════════════════╗"
    echo "║   [HSIN CPU]                         ║"
    echo "╚══════════════════════════════════════╝"
    echo ""

    # Step 1: Detect
    echo "  Step 1: Detect"
    hsin_cpu_detect
    printf "    Clusters: %s\n" "$HSIN_CPU_CLUSTER_COUNT"
    printf "    Cores:    %s\n" "$HSIN_CPU_CORES"
    printf "    Governor: %s\n" "${HSIN_CPU_GOVS:-none}"
    printf "    Freq:     %s-%s kHz\n" "${HSIN_CPU_FREQ_MIN:-?}" "${HSIN_CPU_FREQ_MAX:-?}"
    echo ""

    # Step 2: Safety Check
    echo "  Step 2: Safety Check"
    hsin_cpu_safety_print
    _eff_profile=$(hsin_cpu_safety_effective "$_profile")
    if [ "$_eff_profile" != "$_profile" ]; then
        echo "    [SAFETY] $_profile -> $_eff_profile"
        _profile="$_eff_profile"
    fi
    echo ""

    # Step 3: Validate
    echo "  Step 3: Validate"
    if [ "$HSIN_CPU_WRITABLE_GOV" = "false" ] && [ "$HSIN_CPU_WRITABLE_MIN" = "false" ]; then
        echo "    [WARN] No writable nodes - limited tweaks"
    fi
    echo ""

    # Step 4: Backup
    echo "  Step 4: Backup"
    _backup_dir=$(hsin_cpu_backup)
    echo "    Saved: $_backup_dir"
    echo ""

    # Step 5: Apply
    echo "  Step 5: Apply"

    # Governor
    echo "  Governor:"
    hsin_cpu_governor_apply "$_profile"

    # Frequency
    echo "  Frequency:"
    hsin_cpu_freq_apply "$_profile"

    # Scheduler (cpuset, uclamp, stune)
    echo "  Scheduler:"
    hsin_cpu_cpuset_apply "$_profile"
    hsin_cpu_uclamp_apply "$_profile"
    hsin_cpu_stune_apply "$_profile"
    hsin_cpu_sched_lat_apply "$_profile"
    echo ""

    # Step 6: Verify
    echo "  Step 6: Verify"
    hsin_cpu_verify
    _status=$?
    # Default to FAILED so a stray return code from hsin_cpu_verify (which
    # only ever returns 0/1/2 in this file) never gets us logging an
    # empty string as a "status".
    _status_str="UNKNOWN"
    case "$_status" in
        0) _status_str="SUCCESS"; echo "    Status: $_status_str" ;;
        1) _status_str="DEGRADED"; echo "    Status: $_status_str" ;;
        2)
            _status_str="FAILED"
            echo "    Status: FAILED - rolling back"
            hsin_cpu_restore "$_backup_dir"
            ;;
        *)
            # Defensive: any other return code (e.g. shell injected 127).
            _status_str="ERROR"
            echo "    Status: ERROR ($_status)"
            ;;
    esac
    echo ""

    # Step 7: Log
    hsin_cpu_log "$_profile" "$_status_str" "$_backup_dir"

    echo "╔══════════════════════════════════════╗"
    echo "║   CPU Apply Complete                  ║"
    echo "╚══════════════════════════════════════╝"
    echo ""
    return 0
}

# CLI interface
hsin_cpu_main() {
    _action="${1:-help}"
    _profile="${2:-balanced}"

    case "$_action" in
        apply)
            hsin_cpu_apply "$_profile"
            ;;
        detect)
            . "$HSIN_MODULE_PATH/engine/cpu/detect.sh" 2>/dev/null
            hsin_cpu_detect
            hsin_cpu_print
            ;;
        state)
            . "$HSIN_MODULE_PATH/engine/cpu/governor.sh" 2>/dev/null
            hsin_cpu_governor_state
            ;;
        help|*)
            echo "HSIN CPU Engine"
            echo ""
            echo "Usage: hsin cpu <action> [profile]"
            echo ""
            echo "Actions:"
            echo "  apply <profile>    Apply profile (battery|balanced|performance|extreme)"
            echo "  detect             Detect CPU info"
            echo "  state              Show current governor state"
            echo "  help               Show this help"
            ;;
    esac
}

return 0 2>/dev/null || true
