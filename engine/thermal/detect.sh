#!/system/bin/sh
# HSIN Thermal Detection

[ -z "$HSIN_MODULE_PATH" ] && HSIN_MODULE_PATH="/data/adb/modules/hsin"
HSIN_DATA="${HSIN_DATA:-/data/adb/hsin}"

# Detect all thermal zones
hsin_thermal_detect() {
    echo ""
    echo "╔══════════════════════════════════════╗"
    echo "║   HSIN Thermal Detection             ║"
    echo "╚══════════════════════════════════════╝"
    echo ""

    _cpu_zones=""
    _gpu_zones=""
    _battery_zones=""
    _other_zones=""
    _total=0

    for _zone_dir in /sys/class/thermal/thermal_zone*; do
        [ -d "$_zone_dir" ] || continue

        _name=""
        _temp=""
        _mode=""
        _type=""

        [ -f "$_zone_dir/type" ] && _type=$(cat "$_zone_dir/type" 2>/dev/null)
        [ -f "$_zone_dir/temp" ] && _temp=$(cat "$_zone_dir/temp" 2>/dev/null)
        [ -f "$_zone_dir/mode" ] && _mode=$(cat "$_zone_dir/mode" 2>/dev/null)

        [ -z "$_type" ] && continue
        _total=$((_total + 1))

        # Classify by type
        _class="other"
        case "$_type" in
            *cpu*|*CPU*|*tsens_tz_sensor*) _class="cpu" ;;
            *gpu*|*GPU*|*kgsl*) _class="gpu" ;;
            *battery*|*batt*|*Battery*) _class="battery" ;;
        esac

        # Format temperature
        _temp_c="N/A"
        if [ -n "$_temp" ]; then
            if [ "$_temp" -gt 1000 ] 2>/dev/null; then
                _temp_c="$(( _temp / 1000 ))C"
            elif [ "$_temp" -gt 200 ] 2>/dev/null; then
                _temp_c="$(( _temp / 10 ))C"
            else
                _temp_c="${_temp}C"
            fi
        fi

        # Mode status
        _mode_str="N/A"
        [ -n "$_mode" ] && _mode_str="$_mode"

        # Collect by class
        case "$_class" in
            cpu)
                _cpu_zones="${_cpu_zones}  zone$_total $_type $_temp_c mode=$_mode_str\n"
                ;;
            gpu)
                _gpu_zones="${_gpu_zones}  zone$_total $_type $_temp_c mode=$_mode_str\n"
                ;;
            battery)
                _battery_zones="${_battery_zones}  zone$_total $_type $_temp_c mode=$_mode_str\n"
                ;;
            other)
                _other_zones="${_other_zones}  zone$_total $_type $_temp_c mode=$_mode_str\n"
                ;;
        esac
    done

    # Print CPU
    printf "  CPU:\n"
    if [ -n "$_cpu_zones" ]; then
        printf "$_cpu_zones"
    else
        printf "    (none found)\n"
    fi
    echo ""

    # Print GPU
    printf "  GPU:\n"
    if [ -n "$_gpu_zones" ]; then
        printf "$_gpu_zones"
    else
        printf "    (none found)\n"
    fi
    echo ""

    # Print Battery
    printf "  Battery:\n"
    if [ -n "$_battery_zones" ]; then
        printf "$_battery_zones"
    else
        printf "    (none found)\n"
    fi
    echo ""

    # Print Other
    if [ -n "$_other_zones" ]; then
        printf "  Other:\n"
        printf "$_other_zones"
        echo ""
    fi

    # Cooling devices
    printf "  Cooling Devices:\n"
    _cooling=0
    for _cdev in /sys/class/thermal/cooling_device*; do
        [ -d "$_cdev" ] || continue
        _cooling=$((_cooling + 1))
    done
    printf "    Found: %d cooling devices\n" "$_cooling"
    echo ""
}

# Get max temperature across all zones
hsin_thermal_max_temp() {
    _max=0
    for _zone_dir in /sys/class/thermal/thermal_zone*/temp; do
        [ -f "$_zone_dir" ] || continue
        _t=$(cat "$_zone_dir" 2>/dev/null)
        [ -n "$_t" ] && [ "$_t" -gt "$_max" ] 2>/dev/null && _max="$_t"
    done
    echo "$_max"
}

# Get temperature for a specific zone type
hsin_thermal_zone_temp() {
    _target="$1"
    _max=0

    for _zone_dir in /sys/class/thermal/thermal_zone*; do
        [ -d "$_zone_dir" ] || continue
        [ -f "$_zone_dir/type" ] || continue

        _type=$(cat "$_zone_dir/type" 2>/dev/null)
        case "$_type" in
            *cpu*|*CPU*)
                [ "$_target" = "cpu" ] || continue
                ;;
            *gpu*|*GPU*|*kgsl*)
                [ "$_target" = "gpu" ] || continue
                ;;
            *battery*|*batt*|*Battery*)
                [ "$_target" = "battery" ] || continue
                ;;
            *)
                continue
                ;;
        esac

        [ -f "$_zone_dir/temp" ] || continue
        _t=$(cat "$_zone_dir/temp" 2>/dev/null)
        [ -n "$_t" ] && [ "$_t" -gt "$_max" ] 2>/dev/null && _max="$_t"
    done

    echo "$_max"
}

# Save thermal zone list to JSON
hsin_thermal_save_detection() {
    _out="$HSIN_DATA/thermal_zones.json"
    mkdir -p "$HSIN_DATA" 2>/dev/null

    {
        echo "{"
        echo "  \"zones\": ["
        _first=true
        for _zone_dir in /sys/class/thermal/thermal_zone*; do
            [ -d "$_zone_dir" ] || continue

            _type=""
            _temp=""
            _mode=""
            _path=$(basename "$_zone_dir")

            [ -f "$_zone_dir/type" ] && _type=$(cat "$_zone_dir/type" 2>/dev/null)
            [ -f "$_zone_dir/temp" ] && _temp=$(cat "$_zone_dir/temp" 2>/dev/null)
            [ -f "$_zone_dir/mode" ] && _mode=$(cat "$_zone_dir/mode" 2>/dev/null)

            [ -z "$_type" ] && continue

            [ "$_first" = "true" ] && _first=false || echo ","
            printf '    {"path":"%s","type":"%s","temp":"%s","mode":"%s"}' \
                "$_path" "$_type" "${_temp:-N/A}" "${_mode:-N/A}"
        done
        echo ""
        echo "  ]"
        echo "}"
    } > "$_out"
}

return 0 2>/dev/null || true
