#!/system/bin/sh
# HSIN IO Engine - Readahead Management

[ -z "$HSIN_MODULE_PATH" ] && HSIN_MODULE_PATH="/data/adb/modules/hsin"
. "$HSIN_MODULE_PATH/core/sysfs.sh" 2>/dev/null
. "$HSIN_MODULE_PATH/core/logger.sh" 2>/dev/null
# shellcheck disable=SC1091
. "$HSIN_MODULE_PATH/core/scan_cache.sh" 2>/dev/null
# hsin_io_block_devs() (daftar block cache-first) ada di scheduler.sh, file
# pertama yang di-source io_manager.sh. Kalau file ini di-source sendiri,
# scheduler.sh tetap diambil.
command -v hsin_io_block_devs >/dev/null 2>&1 || \
    . "$HSIN_MODULE_PATH/engine/io/scheduler.sh" 2>/dev/null

# Apply read_ahead_kb for profile
hsin_io_apply_readahead() {
    _profile="$1"

    case "$_profile" in
        battery)     _ra="128" ;;
        balanced)    _ra="512" ;;
        performance) _ra="2048" ;;
        extreme)     _ra="4096" ;;
    esac

    _ok=0
    _skip=0

    hsin_io_block_devs
    for _b in $HSIN_IO_BLOCKS; do
        _name="${_b##*/}"

        # Node hilang sejak scan - skip + log, bukan crash.
        if [ ! -d "$_b" ]; then
            hsin_report_skip "readahead: block $_name hilang sejak scan"
            _skip=$((_skip + 1))
            continue
        fi

        case "$_name" in
            loop*|ram*|zram*|dm-*) continue ;;
        esac

        [ -f "$_b/queue/read_ahead_kb" ] || { _skip=$((_skip + 1)); continue; }
        [ -w "$_b/queue/read_ahead_kb" ] || { _skip=$((_skip + 1)); continue; }

        echo "$_ra" > "$_b/queue/read_ahead_kb" 2>/dev/null && _ok=$((_ok + 1)) || _skip=$((_skip + 1))
    done

    echo "    Readahead [$_ra KB]: ok=$_ok skip=$_skip"
    hsin_log_info "io" "readahead src=$HSIN_IO_BLOCK_SOURCE ra_kb=$_ra ok=$_ok skip=$_skip"
    return 0
}

# Get current readahead state
hsin_io_readahead_state() {
    echo "  Readahead State:"
    hsin_io_block_devs
    for _b in $HSIN_IO_BLOCKS; do
        [ -d "$_b" ] || continue
        _name="${_b##*/}"
        case "$_name" in
            loop*|ram*|zram*|dm-*) continue ;;
        esac
        [ -f "$_b/queue/read_ahead_kb" ] || continue
        _ra=$(hsin_node_read "$_b/queue/read_ahead_kb")
        printf "    %-15s %s KB\n" "$_name" "$_ra"
    done
}

return 0 2>/dev/null || true
