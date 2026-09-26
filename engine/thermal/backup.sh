#!/system/bin/sh
# HSIN Thermal Backup

[ -z "$HSIN_MODULE_PATH" ] && HSIN_MODULE_PATH="/data/adb/modules/hsin"
HSIN_DATA="${HSIN_DATA:-/data/adb/hsin}"
. "$HSIN_MODULE_PATH/core/logger.sh" 2>/dev/null
# shellcheck disable=SC1091
. "$HSIN_MODULE_PATH/core/scan_cache.sh" 2>/dev/null
[ -n "$HSIN_SYSFS_THERMAL" ] || HSIN_SYSFS_THERMAL="${SYSFS_THERMAL_PREFIX:-/sys/class/thermal}"

hsin_thermal_log() {
    command -v hsin_log_info >/dev/null 2>&1 && hsin_log_info "thermal" "$1"
    return 0
}

# Backup thermal state
hsin_thermal_backup() {
    _backup_dir="$HSIN_DATA/backups/thermal_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$_backup_dir" 2>/dev/null

    # Backup thermal zones.
    # Daftar zona diambil dari cache scan-sekali-simpan (core/scan_cache.sh):
    # kalau cache valid, jalur ini hanya iterasi HSIN_SCAN_THERMAL_ZONES tanpa
    # glob thermal_zone* sama sekali. Cache absen/rusak/boot beda ->
    # hsin_scan_thermal_zones_get() scan live (glob) seperti sebelumnya, jadi
    # jalur fallback tetap menghasilkan backup yang sama.
    hsin_scan_thermal_zones_get
    _zone_src="${HSIN_SCAN_THERMAL_SOURCE:-scan}"
    _zones=0

    for _zone in $HSIN_SCAN_THERMAL_ZONES; do
        _zone_name="${_zone%%|*}"
        _zone_dir="$HSIN_SYSFS_THERMAL/$_zone_name"
        if [ ! -d "$_zone_dir" ]; then
            hsin_thermal_log "backup: zone gone, skip: $_zone_name"
            continue
        fi

        _zones=$((_zones + 1))
        _zone_backup="$_backup_dir/$_zone_name"
        mkdir -p "$_zone_backup" 2>/dev/null

        # Backup type, temp, mode, policy
        [ -f "$_zone_dir/type" ] && cp "$_zone_dir/type" "$_zone_backup/type" 2>/dev/null
        [ -f "$_zone_dir/temp" ] && cp "$_zone_dir/temp" "$_zone_backup/temp" 2>/dev/null
        [ -f "$_zone_dir/mode" ] && cp "$_zone_dir/mode" "$_zone_backup/mode" 2>/dev/null
        [ -f "$_zone_dir/policy" ] && cp "$_zone_dir/policy" "$_zone_backup/policy" 2>/dev/null
        [ -f "$_zone_dir/trip_point_0_temp" ] && cp "$_zone_dir/trip_point_0_temp" "$_zone_backup/trip_point_0_temp" 2>/dev/null
    done

    # Backup cooling devices. Scan cache hanya menyimpan zona, bukan cooling
    # device, jadi daftar ini tetap diambil langsung dari sysfs.
    _cdevs=0
    for _cdev_dir in "$HSIN_SYSFS_THERMAL"/cooling_device*; do
        [ -d "$_cdev_dir" ] || continue

        _cdevs=$((_cdevs + 1))
        _cdev_name=${_cdev_dir##*/}
        _cdev_backup="$_backup_dir/$_cdev_name"
        mkdir -p "$_cdev_backup" 2>/dev/null

        [ -f "$_cdev_dir/type" ] && cp "$_cdev_dir/type" "$_cdev_backup/type" 2>/dev/null
        [ -f "$_cdev_dir/cur_state" ] && cp "$_cdev_dir/cur_state" "$_cdev_backup/cur_state" 2>/dev/null
        [ -f "$_cdev_dir/max_state" ] && cp "$_cdev_dir/max_state" "$_cdev_backup/max_state" 2>/dev/null
    done

    # Save backup path
    echo "$_backup_dir" > "$HSIN_DATA/thermal_backup_latest"

    hsin_thermal_log "backup: zones=$_zones src=$_zone_src cdevs=$_cdevs dir=$_backup_dir"
    echo "[THERMAL] Backup saved: $_backup_dir (zones=$_zones source=$_zone_src cdevs=$_cdevs)"
}

# Restore thermal state from backup
hsin_thermal_restore() {
    [ -f "$HSIN_DATA/thermal_backup_latest" ] || {
        echo "[THERMAL] No backup found"
        return 1
    }

    _backup_dir=$(cat "$HSIN_DATA/thermal_backup_latest" 2>/dev/null)
    [ -d "$_backup_dir" ] || {
        echo "[THERMAL] Backup directory not found: $_backup_dir"
        return 1
    }

    _restored=0

    # Restore thermal zones
    for _zone_dir in "$_backup_dir"/thermal_zone*; do
        [ -d "$_zone_dir" ] || continue

        _zone_name=${_zone_dir##*/}
        _target="$HSIN_SYSFS_THERMAL/$_zone_name"
        [ -d "$_target" ] || continue

        # Restore mode
        [ -f "$_zone_dir/mode" ] && {
            _val=$(cat "$_zone_dir/mode" 2>/dev/null)
            [ -n "$_val" ] && [ -w "$_target/mode" ] && echo "$_val" > "$_target/mode" 2>/dev/null && _restored=$((_restored + 1))
        }

        # Restore policy
        [ -f "$_zone_dir/policy" ] && {
            _val=$(cat "$_zone_dir/policy" 2>/dev/null)
            [ -n "$_val" ] && [ -w "$_target/policy" ] && echo "$_val" > "$_target/policy" 2>/dev/null && _restored=$((_restored + 1))
        }

        # Restore trip point
        [ -f "$_zone_dir/trip_point_0_temp" ] && {
            _val=$(cat "$_zone_dir/trip_point_0_temp" 2>/dev/null)
            [ -n "$_val" ] && [ -w "$_target/trip_point_0_temp" ] && echo "$_val" > "$_target/trip_point_0_temp" 2>/dev/null && _restored=$((_restored + 1))
        }
    done

    # Restore cooling devices
    for _cdev_dir in "$_backup_dir"/cooling_device*; do
        [ -d "$_cdev_dir" ] || continue

        _cdev_name=${_cdev_dir##*/}
        _target="$HSIN_SYSFS_THERMAL/$_cdev_name"
        [ -d "$_target" ] || continue

        [ -f "$_cdev_dir/cur_state" ] && {
            _val=$(cat "$_cdev_dir/cur_state" 2>/dev/null)
            [ -n "$_val" ] && [ -w "$_target/cur_state" ] && echo "$_val" > "$_target/cur_state" 2>/dev/null && _restored=$((_restored + 1))
        }
    done

    echo "[THERMAL] Restored: $_restored items"
}

return 0 2>/dev/null || true
