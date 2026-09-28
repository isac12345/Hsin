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
# Daftar policy dari hsin_cpu_policy_ids() (cache scan-sekali-simpan, fallback
# glob) supaya tidak ada glob cpufreq/policy* per apply. Isi snapshot per
# policy tidak berubah.
hsin_cpu_backup() {
    _backup_dir="$HSIN_DATA/backups/cpu_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$_backup_dir" 2>/dev/null

    hsin_cpu_policy_ids
    for _pid in $HSIN_CPU_POLICY_IDS; do
        _policy="$HSIN_SYSFS_CPU/cpufreq/policy$_pid"
        [ -d "$_policy" ] || continue
        _name="policy$_pid"
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
        _name="${_backup_file##*/}"
        _policy="$HSIN_SYSFS_CPU/cpufreq/$_name"
        [ -d "$_policy" ] || continue

        # Reset variabel per cluster — hindari bocor antar cluster
        _gov_read=""
        _max_read=""
        _min_read=""
        _all_ok=1  # semua operasi yang dilakukan harus berhasil
        _has_op=0  # apakah ada operasi yang diperlukan

        # Restore governor
        _gov=$(grep "^governor=" "$_backup_file" 2>/dev/null | cut -d= -f2)
        [ -n "$_gov" ] && [ -w "$_policy/scaling_governor" ] && {
            _has_op=1
            echo "$_gov" > "$_policy/scaling_governor" 2>/dev/null
            # Readback: verifikasi nilai yang ditulis
            _gov_read=""
            [ -f "$_policy/scaling_governor" ] && IFS= read -r _gov_read < "$_policy/scaling_governor" 2>/dev/null
            # Bandingkan string langsung (tanpa filter pola).
            if [ -n "$_gov_read" ] && [ "$_gov_read" = "$_gov" ]; then
                : # ok
            else
                echo "    [RESTORE WARNING] governor readback mismatch: expected=$_gov got=$_gov_read" >&2
                _all_ok=0
            fi
        } || {
            [ -n "$_gov" ] && echo "    [RESTORE SKIP] governor not writable" >&2
            # Jika operasi diperlukan tapi tidak bisa dilakukan, gagal
            if [ -n "$_gov" ]; then
                _has_op=1
                _all_ok=0
            fi
        }

        # Restore max freq first
        _max=$(grep "^max_freq=" "$_backup_file" 2>/dev/null | cut -d= -f2)
        [ -n "$_max" ] && [ -w "$_policy/scaling_max_freq" ] && {
            _has_op=1
            echo "$_max" > "$_policy/scaling_max_freq" 2>/dev/null
            # Readback
            _max_read=""
            [ -f "$_policy/scaling_max_freq" ] && IFS= read -r _max_read < "$_policy/scaling_max_freq" 2>/dev/null
            case "$_max_read" in ''|*[!0-9]*) _max_read=0 ;; esac
            if [ -n "$_max_read" ] && [ "$_max_read" = "$_max" ]; then
                : # ok
            else
                echo "    [RESTORE WARNING] max_freq readback mismatch: expected=$_max got=$_max_read" >&2
                _all_ok=0
            fi
        }

        # Restore min freq
        _min=$(grep "^min_freq=" "$_backup_file" 2>/dev/null | cut -d= -f2)
        [ -n "$_min" ] && [ -w "$_policy/scaling_min_freq" ] && {
            _has_op=1
            echo "$_min" > "$_policy/scaling_min_freq" 2>/dev/null
            # Readback
            _min_read=""
            [ -f "$_policy/scaling_min_freq" ] && IFS= read -r _min_read < "$_policy/scaling_min_freq" 2>/dev/null
            case "$_min_read" in ''|*[!0-9]*) _min_read=0 ;; esac
            if [ -n "$_min_read" ] && [ "$_min_read" = "$_min" ]; then
                : # ok
            else
                echo "    [RESTORE WARNING] min_freq readback mismatch: expected=$_min got=$_min_read" >&2
                _all_ok=0
            fi
        }

        # Hitung ok: SEMUA operasi yang dilakukan harus berhasil.
        # Operasi yang tidak diperlukan (kosong) tidak mengubah hasil,
        # tapi operasi yang dilakukan dan gagal = tidak ok.
        # Jika tidak ada operasi yang diperlukan tapi file ada = tetap ok.
        if [ "$_has_op" -eq 0 ]; then
            _all_ok=1
        fi
        [ "$_all_ok" -eq 1 ] && _ok=$((_ok + 1))
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

    hsin_cpu_policy_ids
    for _pid in $HSIN_CPU_POLICY_IDS; do
        _policy="$HSIN_SYSFS_CPU/cpufreq/policy$_pid"
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
    printf "    Source:   %s (policies: %s)\n" \
        "${HSIN_CPU_POLICY_SOURCE:-scan}" "$HSIN_CPU_POLICY_IDS"
    printf "    Clusters: %s\n" "$HSIN_CPU_CLUSTER_COUNT"
    printf "    Cores:    %s\n" "$HSIN_CPU_CORES"
    printf "    Governor: %s\n" "${HSIN_CPU_GOVS:-none}"
    printf "    Freq:     %s-%s kHz\n" "${HSIN_CPU_FREQ_MIN:-?}" "${HSIN_CPU_FREQ_MAX:-?}"
    echo ""

    # Step 2: Safety Check
    echo "  Step 2: Safety Check"
    hsin_cpu_safety_print
    # Di mode manual: intervensi termal kritis hanya lewat thermal cap (bukan profil penuh).
    # Remap low-battery/critical ke profil battery TIDAK boleh menulis profil.
    if [ "$_profile" = "manual" ]; then
        # Tetap cetak safety status + log alasan, tapi JANGAN assign _eff_profile.
        echo "    [SAFETY] mode manual: safety remap dilewati (intervensi hanya lewat thermal cap)"
        # Tidak mengubah _profile; biarkan manual tanpa remap profil.
    else
        _eff_profile=$(hsin_cpu_safety_effective "$_profile")
        if [ "$_eff_profile" != "$_profile" ]; then
            echo "    [SAFETY] $_profile -> $_eff_profile"
            _profile="$_eff_profile"
        fi
    fi
    echo ""

    # Step 3: Validate
    echo "  Step 3: Validate"
    if [ "$HSIN_CPU_WRITABLE_GOV" = "false" ] && [ "$HSIN_CPU_WRITABLE_MIN" = "false" ]; then
        echo "    [WARN] No writable nodes - limited tweaks"
    fi
    echo ""

    # Step 4: Backup
    # The pipeline (core/apply_engines.sh) or the boot path (service.sh) already
    # took ONE snapshot of these nodes - reuse it instead of snapshotting the
    # same governor/min/max a second time. Outside those paths (standalone CLI
    # apply) keep taking an engine snapshot so step 6 rollback always has a
    # source.
    echo "  Step 4: Backup"
    if [ -z "${HSIN_APPLY_BACKUP:-}" ] && [ -n "${HSIN_BACKUP_CUR:-}" ] \
        && [ -f "$HSIN_BACKUP_CUR/nodes.list" ]; then
        HSIN_APPLY_BACKUP="$HSIN_BACKUP_CUR"
    fi
    case "${HSIN_APPLY_BACKUP:-}" in
        ''|none)
            _backup_dir=$(hsin_cpu_backup)
            _backup_ref="$_backup_dir"
            ;;
        *)
            _backup_dir=""
            _backup_ref="$HSIN_APPLY_BACKUP"
            command -v hsin_log_info >/dev/null 2>&1 && \
                hsin_log_info "cpu" "backup reuse pipeline snapshot: $_backup_ref"
            ;;
    esac
    echo "    Snapshot: $_backup_ref"
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
            if [ -n "$_backup_dir" ]; then
                hsin_cpu_restore "$_backup_dir"
            elif [ -n "${HSIN_APPLY_BACKUP:-}" ] \
                && [ -f "$HSIN_APPLY_BACKUP/nodes.list" ] \
                && command -v hsin_restore_session >/dev/null 2>&1; then
                # Roll back from the pipeline snapshot (nodes.list format, not
                # the per-policy files hsin_cpu_restore reads). At this point
                # only CPU nodes have been touched, so restoring the session is
                # CPU-only in effect; sched-latency nodes live outside the
                # session and are restored separately.
                hsin_restore_session "${HSIN_APPLY_BACKUP##*/}"
                hsin_cpu_sched_lat_restore
            else
                echo "    No snapshot available - nothing to roll back"
            fi
            ;;
        *)
            # Defensive: any other return code (e.g. shell injected 127).
            _status_str="ERROR"
            echo "    Status: ERROR ($_status)"
            ;;
    esac
    echo ""

    # Step 7: Log
    hsin_cpu_log "$_profile" "$_status_str" "$_backup_ref"

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
