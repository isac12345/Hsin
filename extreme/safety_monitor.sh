#!/system/bin/sh
# HSIN Extreme Safety Monitor

[ -z "$HSIN_MODULE_PATH" ] && HSIN_MODULE_PATH="/data/adb/modules/hsin"
HSIN_DATA="${HSIN_DATA:-/data/adb/hsin}"

# Emergency thresholds (millidegrees)
HSIN_SAFETY_WARN=90000
HSIN_SAFETY_EMERGENCY=95000
HSIN_SAFETY_PANIC=100000

# Monitor interval
HSIN_SAFETY_INTERVAL=5

# Start safety monitor
hsin_safety_monitor_start() {
    echo "╔══════════════════════════════════════╗"
    echo "║   HSIN Safety Monitor                 ║"
    echo "╚══════════════════════════════════════╝"
    echo ""
    echo "  Warning:      $(( HSIN_SAFETY_WARN / 1000 ))C"
    echo "  Emergency:    $(( HSIN_SAFETY_EMERGENCY / 1000 ))C"
    echo "  Panic:        $(( HSIN_SAFETY_PANIC / 1000 ))C"
    echo ""
    echo "  Monitoring..."

    mkdir -p "$HSIN_DATA" 2>/dev/null
    printf '%s\n' "$$" > "$HSIN_DATA/safety_monitor.pid" 2>/dev/null
    while true; do
        # Read max temperature
        _max=0
        for _zone in /sys/class/thermal/thermal_zone*/temp; do
            [ -f "$_zone" ] || continue
            _t=$(cat "$_zone" 2>/dev/null)
            case "$_t" in ''|*[!0-9-]*) continue ;; esac
            if [ "$_t" -gt 1000 ] 2>/dev/null; then
                _c=$((_t / 1000))
            elif [ "$_t" -gt 200 ] 2>/dev/null; then
                _c=$((_t / 10))
            else
                _c="$_t"
            fi
            [ "$_c" -le 150 ] 2>/dev/null || continue
            [ "$_c" -gt "$_max" ] 2>/dev/null && _max="$_c"
        done

        # Format
        _fmt="N/A"
        [ "$_max" -gt 0 ] 2>/dev/null && _fmt="${_max}C"

        # Check thresholds
        if [ "$_max" -ge 100 ] 2>/dev/null; then
            printf "  [%s] %s PANIC - Force rollback!\n" "$(date +%H:%M:%S)" "$_fmt"
            . "$HSIN_MODULE_PATH/extreme/restore_extreme.sh" 2>/dev/null
            hsin_extreme_quick_rollback
            return 1
        elif [ "$_max" -ge 95 ] 2>/dev/null; then
            printf "  [%s] %s EMERGENCY - Rolling back!\n" "$(date +%H:%M:%S)" "$_fmt"
            . "$HSIN_MODULE_PATH/extreme/restore_extreme.sh" 2>/dev/null
            hsin_extreme_restore
            return 2
        elif [ "$_max" -ge 90 ] 2>/dev/null; then
            printf "  [%s] %s WARNING\n" "$(date +%H:%M:%S)" "$_fmt"
        else
            printf "  [%s] %s OK\n" "$(date +%H:%M:%S)" "$_fmt"
        fi

        sleep "$HSIN_SAFETY_INTERVAL"
    done
}

# Stop safety monitor
hsin_safety_monitor_stop() {
    _pid_file="$HSIN_DATA/safety_monitor.pid"
    if [ -f "$_pid_file" ]; then
        read -r _pid < "$_pid_file" 2>/dev/null
        case "$_pid" in ''|*[!0-9]*) ;; *) kill "$_pid" 2>/dev/null ;; esac
        rm -f "$_pid_file" 2>/dev/null
    fi
    echo "[SAFETY] Monitor stopped"
}

return 0 2>/dev/null || true
