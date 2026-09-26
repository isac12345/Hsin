#!/system/bin/sh
# HSIN IO Engine - Manager

[ -z "$HSIN_MODULE_PATH" ] && HSIN_MODULE_PATH="/data/adb/modules/hsin"
HSIN_DATA="${HSIN_DATA:-/data/adb/hsin}"

# Load dependencies
. "$HSIN_MODULE_PATH/core/logger.sh" 2>/dev/null
. "$HSIN_MODULE_PATH/core/validator.sh" 2>/dev/null
. "$HSIN_MODULE_PATH/engine/io/scheduler.sh" 2>/dev/null
. "$HSIN_MODULE_PATH/engine/io/readahead.sh" 2>/dev/null

# Main IO engine apply
hsin_io_apply() {
    _profile="$1"

    echo ""
    echo "╔══════════════════════════════════════╗"
    echo "║   IO Engine (profile=$_profile)       ║"
    echo "╚══════════════════════════════════════╝"
    echo ""

    # Apply scheduler
    hsin_io_apply_scheduler "$_profile"

    # Apply readahead
    hsin_io_apply_readahead "$_profile"

    echo ""
    echo "  Status: COMPLETE (unsupported nodes skipped)"
    echo ""
    return 0
}

# CLI interface
hsin_io_main() {
    _action="${1:-help}"
    _profile="${2:-balanced}"

    case "$_action" in
        state)
            hsin_io_scheduler_state
            hsin_io_readahead_state
            ;;
        apply)
            hsin_io_apply "$_profile"
            ;;
        help|*)
            echo "HSIN IO Engine"
            echo ""
            echo "Usage: hsin io <action> [profile]"
            echo ""
            echo "Actions:"
            echo "  apply <profile>     Apply profile (battery|balanced|performance|extreme)"
            echo "  state               Show current state"
            echo "  help                Show this help"
            ;;
    esac
}

return 0 2>/dev/null || true
