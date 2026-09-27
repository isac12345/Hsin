#!/system/bin/sh
# HSIN Thermal Engine - Manager
# Credit: logic inspired by Sasha (thermal control)

[ -z "$HSIN_MODULE_PATH" ] && HSIN_MODULE_PATH="/data/adb/modules/hsin"
HSIN_DATA="${HSIN_DATA:-/data/adb/hsin}"

# Load dependencies
. "$HSIN_MODULE_PATH/core/logger.sh" 2>/dev/null
. "$HSIN_MODULE_PATH/core/validator.sh" 2>/dev/null
. "$HSIN_MODULE_PATH/engine/thermal/detect.sh" 2>/dev/null
. "$HSIN_MODULE_PATH/engine/thermal/monitor.sh" 2>/dev/null
. "$HSIN_MODULE_PATH/engine/thermal/policy.sh" 2>/dev/null

# Main thermal engine manage (CLI wrapper - NOT the same as hsin_thermal_apply in policy.sh)
hsin_thermal_engine_manage() {
    _mode="$1"

    echo ""
    echo "╔══════════════════════════════════════╗"
    echo "║   Thermal Engine (mode=$_mode)        ║"
    echo "╚══════════════════════════════════════╝"
    echo ""

    # Detect thermal zones
    hsin_thermal_detect
    hsin_thermal_monitor_print

    # Monitor current temperature
    _temp=$(hsin_thermal_max_temp)
    _temp_c=$((_temp / 1000))
    hsin_thermal_classify "$_temp"
    _status="$HSIN_THERMAL_STATE"
    echo "  Current: ${_temp_c}°C ($_status)"
    echo ""

    # Apply policy
    hsin_thermal_apply "$_mode"

    echo ""
    echo "  Status: COMPLETE"
    echo "  NOTE: Thermal protection remains active"
    echo ""
    return 0
}

# CLI interface
hsin_thermal_main() {
    _action="${1:-help}"
    _mode="${2:-safe}"

    case "$_action" in
        detect)
            hsin_thermal_detect
            hsin_thermal_monitor_print
            ;;
        apply)
            hsin_thermal_engine_manage "$_mode"
            ;;
        monitor)
            _temp=$(hsin_thermal_max_temp)
            _temp_c=$((_temp / 1000))
            hsin_thermal_classify "$_temp"
            _status="$HSIN_THERMAL_STATE"
            echo "Thermal: ${_temp_c}°C ($_status)"
            ;;
        state)
            hsin_thermal_detect
            hsin_thermal_monitor_print
            hsin_thermal_policy_print
            ;;
        help|*)
            echo "HSIN Thermal Engine"
            echo ""
            echo "Usage: hsin thermal <action> [mode]"
            echo ""
            echo "Actions:"
            echo "  detect              Detect thermal zones"
            echo "  apply <mode>        Apply mode (safe|performance|extreme)"
            echo "  monitor             Check current temperature"
            echo "  state               Show full thermal state"
            echo "  help                Show this help"
            echo ""
            echo "NOTE: Thermal protection is NEVER disabled."
            echo "      Only safe threshold adjustments are made."
            ;;
    esac
}

return 0 2>/dev/null || true
