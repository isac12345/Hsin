#!/system/bin/sh
# HSIN Network Engine - Manager

[ -z "$HSIN_MODULE_PATH" ] && HSIN_MODULE_PATH="/data/adb/modules/hsin"
HSIN_DATA="${HSIN_DATA:-/data/adb/hsin}"

# Load dependencies
. "$HSIN_MODULE_PATH/core/logger.sh" 2>/dev/null
. "$HSIN_MODULE_PATH/core/validator.sh" 2>/dev/null
. "$HSIN_MODULE_PATH/engine/network/tcp.sh" 2>/dev/null

# Main network engine apply
hsin_network_apply() {
    _profile="$1"

    echo ""
    echo "╔══════════════════════════════════════╗"
    echo "║   Network Engine (profile=$_profile)  ║"
    echo "╚══════════════════════════════════════╝"
    echo ""

    # Apply TCP
    echo "  TCP:"
    if hsin_network_apply_tcp "$_profile"; then
        _tcp=$(cat /proc/sys/net/ipv4/tcp_congestion_control 2>/dev/null)
        echo "    tcp_congestion: $_tcp"
    else
        echo "    tcp_congestion: skip (not writable)"
    fi

    # Apply TFO
    hsin_network_apply_tfo "$_profile"

    # Apply sysctl
    echo "  Sysctl:"
    hsin_network_apply_sysctl "$_profile"

    echo ""
    echo "  Status: COMPLETE"
    echo ""
    return 0
}

# CLI interface
hsin_network_main() {
    _action="${1:-help}"
    _profile="${2:-balanced}"

    case "$_action" in
        state)
            hsin_network_state
            ;;
        apply)
            hsin_network_apply "$_profile"
            ;;
        help|*)
            echo "HSIN Network Engine"
            echo ""
            echo "Usage: hsin network <action> [profile]"
            echo ""
            echo "Actions:"
            echo "  apply <profile>     Apply profile (battery|balanced|performance|extreme)"
            echo "  state               Show current state"
            echo "  help                Show this help"
            ;;
    esac
}

return 0 2>/dev/null || true
