#!/system/bin/sh
# HSIN Capability Export

[ -z "$HSIN_MODULE_PATH" ] && HSIN_MODULE_PATH="/data/adb/modules/hsin"
HSIN_DATA="${HSIN_DATA:-/data/adb/hsin}"
# /proc via $HSIN_PROC supaya bisa di-sandbox (prefix palsu), default /proc.
[ -n "$HSIN_PROC" ] || HSIN_PROC="${SYSFS_PROC_PREFIX:-/proc}"

# Export capability report
hsin_export_report() {
    _out="${1:-$HSIN_DATA/report.json}"
    mkdir -p "$(dirname "$_out")" 2>/dev/null

    # Detect hardware
    . "$HSIN_MODULE_PATH/core/hardware.sh" 2>/dev/null
    . "$HSIN_MODULE_PATH/engine/cpu/detect.sh" 2>/dev/null
    . "$HSIN_MODULE_PATH/engine/gpu/detector.sh" 2>/dev/null

    # Get SoC
    _soc="unknown"
    [ -f "$HSIN_PROC/device-tree/compatible" ] && _soc=$(cat "$HSIN_PROC/device-tree/compatible" 2>/dev/null | tr '\0' '\n' | head -1)
    [ -f /sys/devices/soc0/soc_id ] && _soc="ID$(cat /sys/devices/soc0/soc_id 2>/dev/null)"

    # Get GPU
    _gpu="unknown"
    for _devfreq in /sys/class/devfreq/*; do
        [ -d "$_devfreq" ] || continue
        _name=$(basename "$_devfreq")
        case "$_name" in
            *gpu*|*mali*|*kgsl*|*adreno*)
                _gpu="$_name"
                break
                ;;
        esac
    done

    # CPU policies (dynamic - count all cpufreq policy dirs)
    _cpu_policies=0
    for _p in /sys/devices/system/cpu/cpufreq/policy*; do
        [ -d "$_p" ] && _cpu_policies=$((_cpu_policies + 1))
    done 2>/dev/null

    # Thermal
    _thermal="false"
    [ -d /sys/class/thermal/thermal_zone0 ] && _thermal="true"

    # Devfreq
    _devfreq="false"
    ls /sys/class/devfreq/ >/dev/null 2>&1 && _devfreq="true"

    # eBPF
    _ebpf="false"
    [ -f /sys/kernel/debug/tracing/available_events ] && _ebpf="true"

    # Generate JSON
    cat > "$_out" << EOF
{
    "device": {
        "soc": "$_soc",
        "gpu": "$_gpu",
        "cpu_policies": $_cpu_policies
    },
    "capabilities": {
        "thermal": $_thermal,
        "devfreq": $_devfreq,
        "ebpf": $_ebpf
    },
    "hsin": {
        "version": "4.0.0",
        "module_path": "$HSIN_MODULE_PATH",
        "data_path": "$HSIN_DATA"
    },
    "timestamp": "$(date -Iseconds)"
}
EOF

    echo "[EXPORT] Report saved: $_out"
}

# Print report
hsin_export_print() {
    [ -f "$HSIN_DATA/report.json" ] || {
        echo "No report found. Run: hsin export"
        return 1
    }

    echo ""
    echo "╔══════════════════════════════════════╗"
    echo "║   HSIN Capability Report              ║"
    echo "╚══════════════════════════════════════╝"
    echo ""

    # Simple JSON pretty print
    while IFS= read -r _line; do
        case "$_line" in
            *": "*)
                _key=$(echo "$_line" | sed 's/.*"\([^"]*\)".*/\1/')
                _val=$(echo "$_line" | sed 's/.*: "\(.*\)".*/\1/' | sed 's/.*: \([0-9]*\).*/\1/')
                printf "  %-20s %s\n" "$_key:" "$_val"
                ;;
        esac
    done < "$HSIN_DATA/report.json"

    echo ""
}

return 0 2>/dev/null || true
