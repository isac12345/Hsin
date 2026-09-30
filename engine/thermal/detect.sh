#!/system/bin/sh
# HSIN Thermal Detection

[ -z "$HSIN_MODULE_PATH" ] && HSIN_MODULE_PATH="/data/adb/modules/hsin"
HSIN_DATA="${HSIN_DATA:-/data/adb/hsin}"
# shellcheck disable=SC1091
. "$HSIN_MODULE_PATH/core/scan_cache.sh" 2>/dev/null
. "$HSIN_MODULE_PATH/engine/thermal/monitor.sh" 2>/dev/null
[ -n "$HSIN_SYSFS_THERMAL" ] || HSIN_SYSFS_THERMAL="${SYSFS_THERMAL_PREFIX:-/sys/class/thermal}"
# Diisi hsin_scan_classify() (core/scan_cache.sh) tiap zona.
_sc_class="other"

# Detect all thermal zones
# Pakai daftar zona dari cache scan-sekali-simpan; kalau cache tidak ada/
# rusak, hsin_scan_thermal_live() globby sysfs seperti biasa. `mode` tidak
# disimpan di cache (itu setting runtime yang bisa berubah sewaktu-waktu),
# jadi tidak ditampilkan lagi; yang ditampilkan dari cache adalah zona
# writable + penanda zona utama.
hsin_thermal_detect() {
    echo ""
    echo "╔══════════════════════════════════════╗"
    echo "║   HSIN Thermal Detection             ║"
    echo "╚══════════════════════════════════════╝"
    echo ""

    hsin_scan_thermal_zones_get

    _cpu_zones=""
    _gpu_zones=""
    _battery_zones=""
    _other_zones=""
    _total=0
    _writable=0

    for _zone in $HSIN_SCAN_THERMAL_ZONES; do
        _total=$((_total + 1))
        _zname="${_zone%%\\\|*}"
        _ztype="${_zone#*\\\|}"
        _ztype="${_ztype%%\\\|*}"
        _zw="${_zone##*\\\|}"
        [ "$_zw" = "1" ] && _writable=$((_writable + 1))

        # Classify by type
        hsin_scan_classify "$_ztype"
        _class="$_sc_class"

        # Format temperature
        _zpath="$HSIN_SYSFS_THERMAL/$_zname"
        _temp=""
        [ -f "$_zpath/temp" ] && IFS= read -r _temp < "$_zpath/temp" 2>/dev/null
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

        _tag=""
        [ "$_zname" = "$HSIN_SCAN_THERMAL_MAXZONE" ] && _tag=" (primary)"

        # Collect by class
        case "$_class" in
            cpu)
                _cpu_zones="${_cpu_zones}  $_zname $_ztype $_temp_c$_tag\n"
                ;;
            gpu)
                _gpu_zones="${_gpu_zones}  $_zname $_ztype $_temp_c$_tag\n"
                ;;
            battery)
                _battery_zones="${_battery_zones}  $_zname $_ztype $_temp_c$_tag\n"
                ;;
            other)
                _other_zones="${_other_zones}  $_zname $_ztype $_temp_c$_tag\n"
                ;;
        esac
    done

    printf "  Zones source: %s total=%s writable=%s\n" \
        "${HSIN_SCAN_THERMAL_SOURCE:-scan}" "$_total" "$_writable"
    echo ""

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
    for _cdev in "$HSIN_SYSFS_THERMAL"/cooling_device*; do
        [ -d "$_cdev" ] || continue
        _cooling=$((_cooling + 1))
    done
    printf "    Found: %d cooling devices\n" "$_cooling"
    echo ""
}

# Get max temperature across all zones
# Pakai hasil single-pass hsin_thermal_read() (MAX_TEMP_ALL = max semua
# zona) supaya tidak globby thermal_zone* dua kali.
hsin_thermal_max_temp() {
    hsin_thermal_read
    echo "$HSIN_THERMAL_MAX_TEMP_ALL"
}

# Get temperature for a specific zone type
hsin_thermal_zone_temp() {
    _target="$1"
    _max=0

    hsin_scan_thermal_zones_get
    for _zone in $HSIN_SCAN_THERMAL_ZONES; do
        _ztype="${_zone#*\\\|}"
        _ztype="${_ztype%%\\\|*}"
        hsin_scan_classify "$_ztype"
        [ "$_sc_class" = "$_target" ] || continue
        _temp=""
        _zpath="$HSIN_SYSFS_THERMAL/${_zone%%\\\|*}"
        [ -f "$_zpath/temp" ] && IFS= read -r _temp < "$_zpath/temp" 2>/dev/null
        case "$_temp" in ''|*[!0-9]*) continue ;; esac
        [ "$_temp" -gt "$_max" ] 2>/dev/null && _max="$_temp"
    done

    echo "$_max"
}

# Save thermal zone list to JSON
# Jalur ini tetap live untuk `mode` (runtime setting, tidak di-cache) dan
# `temp` (selalu berubah) - yang dipakai daftar zona tetap cache/live
# resolve yang sama seperti hsin_thermal_read().
hsin_thermal_save_detection() {
    _out="$HSIN_DATA/thermal_zones.json"
    mkdir -p "$HSIN_DATA" 2>/dev/null

    hsin_scan_thermal_zones_get

    {
        echo "{"
        echo "  \"zones\": ["
        _first=true
        for _zone in $HSIN_SCAN_THERMAL_ZONES; do
            _zname="${_zone%%\\\|*}"
            _ztype="${_zone#*\\\|}"
            _ztype="${_ztype%%\\\|*}"
            _zpath="$HSIN_SYSFS_THERMAL/$_zname"
            _temp=""
            _mode=""
            [ -f "$_zpath/temp" ] && IFS= read -r _temp < "$_zpath/temp" 2>/dev/null
            [ -f "$_zpath/mode" ] && IFS= read -r _mode < "$_zpath/mode" 2>/dev/null

            [ "$_first" = "true" ] && _first=false || echo ","
            printf '    {"path":"%s","type":"%s","temp":"%s","mode":"%s"}' \
                "$_zname" "$_ztype" "${_temp:-N/A}" "${_mode:-N/A}"
        done
        echo ""
        echo "  ]"
        echo "}"
    } > "$_out"
}

return 0 2>/dev/null || true
