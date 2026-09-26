#!/system/bin/sh
# HSIN Memory Engine - Apply Controller

[ -z "$HSIN_MODULE_PATH" ] && HSIN_MODULE_PATH="/data/adb/modules/hsin"
HSIN_DATA="${HSIN_DATA:-/data/adb/hsin}"

# Load dependencies
. "$HSIN_MODULE_PATH/core/logger.sh" 2>/dev/null
. "$HSIN_MODULE_PATH/core/validator.sh" 2>/dev/null
. "$HSIN_MODULE_PATH/core/backup.sh" 2>/dev/null
. "$HSIN_MODULE_PATH/engine/memory/detect.sh" 2>/dev/null
. "$HSIN_MODULE_PATH/engine/memory/zram.sh" 2>/dev/null
. "$HSIN_MODULE_PATH/engine/memory/vm.sh" 2>/dev/null
. "$HSIN_MODULE_PATH/engine/memory/oom.sh" 2>/dev/null

# Backup current memory state
hsin_mem_backup() {
    _backup_dir="$HSIN_DATA/backups/memory_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$_backup_dir" 2>/dev/null

    # Backup VM state
    hsin_vm_backup "$_backup_dir"

    echo "$_backup_dir"
}

# Restore memory state from backup
hsin_mem_restore() {
    _backup_dir="$1"
    [ -d "$_backup_dir" ] || return 1

    # Restore VM
    hsin_vm_restore "$_backup_dir"

    echo "    Restored memory state from backup"
    return 0
}

# Verify memory state after apply
hsin_mem_verify() {
    # Check if meminfo is still readable
    [ -f "$HSIN_PROC/meminfo" ] || return 2

    # If no VM nodes were writable before, don't fail
    return 0
}

# Log results
hsin_mem_log() {
    _profile="$1"
    _status="$2"
    _backup_dir="$3"

    _log_dir="$HSIN_DATA/logs"
    mkdir -p "$_log_dir" 2>/dev/null
    _log_file="$_log_dir/memory.log"

    {
        echo "========================================"
        echo "Date: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "Profile: $_profile"
        echo "Status: $_status"
        echo "Backup: $_backup_dir"
        echo ""
        echo "VM State:"
        hsin_vm_state
        echo ""
        echo "zRAM State:"
        hsin_zram_state
        echo ""
    } >> "$_log_file" 2>/dev/null
}

# Main apply function
hsin_mem_apply() {
    _profile="$1"

    echo ""
    echo "╔══════════════════════════════════════╗"
    echo "║   [HSIN Memory]                      ║"
    echo "╚══════════════════════════════════════╝"
    echo ""

    # Step 1: Detect
    echo "  Step 1: Detect"
    hsin_mem_detect
    # Kabel detect->apply: hsin_mem_detect hanya mengisi HSIN_MEM_ZRAM_*,
    # sedangkan hsin_zram_apply (dan hsin_zram_state) baca HSIN_ZRAM_*.
    # Tanpa probe zram.sh di sini, apply selalu "not available".
    hsin_zram_detect
    hsin_mem_print
    hsin_log_info "memory" "apply detect: zram=$HSIN_MEM_ZRAM_COUNT src=$HSIN_MEM_ZRAM_SOURCE zram_list=$HSIN_ZRAM_COUNT"

    # Step 2: Validate
    echo "  Step 2: Validate"
    # BUG FIX: piped `while` ran in a subshell, so _vm_ok set inside it
    # never survived past the loop (same class of bug as vm.sh/zram.sh -
    # see notes there). Switched to a heredoc-fed loop so it works.
    _vm_ok="false"
    while IFS='|' read -r _name _val _w; do
        [ "$_w" = "true" ] && _vm_ok="true"
    done <<EOF
$HSIN_MEM_VM_NODES
EOF
    if [ "$HSIN_MEM_ZRAM_COUNT" -gt 0 ] 2>/dev/null; then
        echo "    zRAM: available"
    else
        echo "    zRAM: not available"
    fi
    echo ""

    # Step 3: Backup
    echo "  Step 3: Backup"
    _backup_dir=$(hsin_mem_backup)
    echo "    Saved: $_backup_dir"
    echo ""

    # Step 4: Apply
    echo "  Step 4: Apply"

    # 4a: zRAM
    echo "  zRAM:"
    hsin_zram_apply "$_profile"
    echo ""

    # 4b: VM Tuning
    echo "  VM Tuning:"
    hsin_vm_apply "$_profile"
    echo ""

    # 4c: OOM Management
    echo "  OOM:"
    case "$_profile" in
        battery|balanced)
            hsin_oom_release_background
            ;;
        performance|extreme)
            # Protect the game first so it's excluded below (already-negative
            # adj gets skipped by release_background), THEN free up whatever
            # else is idle in the background to give the game more headroom.
            hsin_oom_protect_foreground
            hsin_oom_release_background
            ;;
    esac
    echo ""

    # Step 5: Verify
    echo "  Step 5: Verify"
    hsin_mem_verify
    _status=$?
    case "$_status" in
        0) _status_str="SUCCESS"; echo "    Status: $_status_str" ;;
        1) _status_str="DEGRADED"; echo "    Status: $_status_str" ;;
        2)
            _status_str="FAILED"
            echo "    Status: FAILED - rolling back"
            hsin_mem_restore "$_backup_dir"
            ;;
    esac
    echo ""

    # Step 6: Log
    hsin_mem_log "$_profile" "$_status_str" "$_backup_dir"

    echo "╔══════════════════════════════════════╗"
    echo "║   Memory Apply Complete               ║"
    echo "╚══════════════════════════════════════╝"
    echo ""
    return 0
}

# CLI interface
hsin_mem_main() {
    _action="${1:-help}"
    _profile="${2:-balanced}"

    case "$_action" in
        detect)
            hsin_mem_detect
            hsin_mem_print
            ;;
        apply)
            hsin_mem_apply "$_profile"
            ;;
        state)
            hsin_mem_detect
            hsin_zram_state
            hsin_vm_state
            ;;
        backup)
            hsin_mem_backup
            ;;
        restore)
            hsin_mem_restore "$_profile"  # profile arg is backup dir
            ;;
        help|*)
            echo "HSIN Memory Engine"
            echo ""
            echo "Usage: hsin memory <action> [profile]"
            echo ""
            echo "Actions:"
            echo "  detect              Detect memory info"
            echo "  apply <profile>     Apply profile (battery|balanced|performance|extreme)"
            echo "  state               Show current state"
            echo "  backup              Backup current state"
            echo "  restore <dir>       Restore from backup"
            echo "  help                Show this help"
            ;;
    esac
}

# Alias for callers expecting the naming convention used by
hsin_memory_apply() {
    hsin_mem_apply "$@"
}

return 0 2>/dev/null || true
