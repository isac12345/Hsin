#!/system/bin/sh
# HSIN Memory Engine - zRAM Engine

[ -z "$HSIN_MODULE_PATH" ] && HSIN_MODULE_PATH="/data/adb/modules/hsin"
. "$HSIN_MODULE_PATH/core/logger.sh" 2>/dev/null
# shellcheck disable=SC1091
. "$HSIN_MODULE_PATH/core/scan_cache.sh" 2>/dev/null
[ -n "$HSIN_SYSFS_BLOCK" ] || HSIN_SYSFS_BLOCK="${SYSFS_BLOCK_PREFIX:-/sys/block}"
# hsin_mem_zram_names() (daftar nama zram tanpa glob /sys/block/zram*)
# defined di detect.sh; file ini di-source setelahnya oleh apply.sh, tapi
# kalau di-source sendiri detect.sh tetap diambil.
command -v hsin_mem_zram_names >/dev/null 2>&1 || \
    . "$HSIN_MODULE_PATH/engine/memory/detect.sh" 2>/dev/null

# Detect zRAM devices
hsin_zram_detect() {
    HSIN_ZRAM_LIST=""
    HSIN_ZRAM_COUNT=0

    # Nama device dari module param kernel (hsin_mem_zram_names), bukan
    # glob /sys/block/zram*; nilai SELALU live karena HSIN sendiri yang
    # menulis comp_algorithm/disksize.
    hsin_mem_zram_names
    for _name in $HSIN_MEM_ZRAM_NAMES; do
        _dev="$HSIN_SYSFS_BLOCK/$_name"
        if [ ! -d "$_dev" ]; then
            hsin_log_warn "memory" "zRAM: $_name hilang sejak probe (skip)"
            continue
        fi

        _size=""
        [ -f "$_dev/disksize" ] && IFS= read -r _size < "$_dev/disksize" 2>/dev/null

        _algo=""
        [ -f "$_dev/comp_algorithm" ] && IFS= read -r _algo < "$_dev/comp_algorithm" 2>/dev/null

        _max_streams=""
        [ -f "$_dev/max_comp_streams" ] && IFS= read -r _max_streams < "$_dev/max_comp_streams" 2>/dev/null

        _writable="false"
        [ -w "$_dev/comp_algorithm" ] && _writable="true"

        HSIN_ZRAM_LIST="${HSIN_ZRAM_LIST}${_name}|${_size}|${_algo}|${_max_streams}|${_writable}
"
        HSIN_ZRAM_COUNT=$((HSIN_ZRAM_COUNT + 1))
    done
}

# Get recommended swappiness for profile
hsin_zram_swappiness() {
    _profile="$1"
    case "$_profile" in
        battery)     echo "120" ;;
        balanced)    echo "100" ;;
        performance) echo "60" ;;
        extreme)     echo "40" ;;
        *)           echo "100" ;;
    esac
}

# Get recommended compression algorithm for profile
hsin_zram_algo() {
    _profile="$1"
    case "$_profile" in
        battery)     echo "zstd" ;;
        balanced)
            # Try zstd first, fallback to lz4
            hsin_mem_zram_names
            for _name in $HSIN_MEM_ZRAM_NAMES; do
                _algo_file="$HSIN_SYSFS_BLOCK/$_name/comp_algorithm"
                [ -f "$_algo_file" ] || continue
                _avail=""
                IFS= read -r _avail < "$_algo_file" 2>/dev/null
                case " $_avail " in
                    *" zstd "*) echo "zstd"; return 0 ;;
                    *" lz4 "*)  echo "lz4"; return 0 ;;
                esac
            done
            echo "lz4"
            ;;
        performance) echo "lz4" ;;
        extreme)     echo "lz4" ;;
        *)           echo "lz4" ;;
    esac
}

# Apply zRAM settings for profile
hsin_zram_apply() {
    _profile="$1"

    # Check if zRAM exists
    [ "$HSIN_ZRAM_COUNT" -gt 0 ] 2>/dev/null || { echo "    zRAM: not available"; return 0; }

    _target_algo=$(hsin_zram_algo "$_profile")
    _ok=0
    _skip=0

    # BUG FIX: piping into `while` runs the loop in a subshell, so
    # _ok/_skip incremented inside it never made it back out - the
    # summary line below always printed "ok=0 skip=0" no matter what
    # actually happened. The comp_algorithm writes themselves were
    # unaffected (real file I/O, not shell state), only the reported
    # counters were wrong. Switched to a heredoc-fed loop (no pipe, no
    # subshell) so the counters are accurate.
    while IFS='|' read -r _name _size _algo _streams _w; do
        [ -z "$_name" ] && continue

        # Change algorithm if writable and different
        if [ "$_w" = "true" ] && [ -n "$_target_algo" ]; then
            case " $_algo" in
                *" $_target_algo "*) # Already set
                    _ok=$((_ok + 1))
                    ;;
                *)
                    # Try to set algorithm
                    if echo "$_target_algo" > "$HSIN_SYSFS_BLOCK/$_name/comp_algorithm" 2>/dev/null; then
                        _ok=$((_ok + 1))
                    else
                        _skip=$((_skip + 1))
                    fi
                    ;;
            esac
        else
            _skip=$((_skip + 1))
        fi
    done <<EOF
$HSIN_ZRAM_LIST
EOF

    echo "    zRAM [$_profile]: algo=$_target_algo ok=$_ok skip=$_skip"
    return 0
}

# Trigger zRAM compaction (optional, safe)
hsin_zram_compact() {
    hsin_mem_zram_names
    for _name in $HSIN_MEM_ZRAM_NAMES; do
        _dev="$HSIN_SYSFS_BLOCK/$_name"
        [ -d "$_dev" ] || { hsin_log_warn "memory" "zRAM compact: $_name hilang sejak probe (skip)"; continue; }
        [ -w "$_dev/compact" ] && echo 1 > "$_dev/compact" 2>/dev/null
    done
}

# Get zRAM state
hsin_zram_state() {
    [ "$HSIN_ZRAM_COUNT" -gt 0 ] 2>/dev/null || { echo "  zRAM: not available"; return 0; }

    echo "  zRAM State:"
    echo "$HSIN_ZRAM_LIST" | while IFS='|' read -r _name _size _algo _streams _w; do
        [ -z "$_name" ] && continue
        _size_mb=$((_size / 1024 / 1024))
        printf "    %-10s %s MB  algo=%s  streams=%s  writable=%s\n" "$_name" "$_size_mb" "${_algo:-?}" "${_streams:-?}" "$_w"
    done
}

return 0 2>/dev/null || true
