#!/system/bin/sh
# HSIN IO Engine - Readahead Management

[ -z "$HSIN_MODULE_PATH" ] && HSIN_MODULE_PATH="/data/adb/modules/hsin"

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

    for _b in /sys/block/*; do
        [ -d "$_b" ] || continue
        _name=$(basename "$_b")
        case "$_name" in
            loop*|ram*|zram*|dm-*) continue ;;
        esac

        [ -f "$_b/queue/read_ahead_kb" ] || { _skip=$((_skip + 1)); continue; }
        [ -w "$_b/queue/read_ahead_kb" ] || { _skip=$((_skip + 1)); continue; }

        echo "$_ra" > "$_b/queue/read_ahead_kb" 2>/dev/null && _ok=$((_ok + 1)) || _skip=$((_skip + 1))
    done

    echo "    Readahead [$_ra KB]: ok=$_ok skip=$_skip"
    return 0
}

# Get current readahead state
hsin_io_readahead_state() {
    echo "  Readahead State:"
    for _b in /sys/block/*; do
        [ -d "$_b" ] || continue
        _name=$(basename "$_b")
        case "$_name" in
            loop*|ram*|zram*|dm-*) continue ;;
        esac
        [ -f "$_b/queue/read_ahead_kb" ] || continue
        _ra=$(cat "$_b/queue/read_ahead_kb" 2>/dev/null)
        printf "    %-15s %s KB\n" "$_name" "$_ra"
    done
}

return 0 2>/dev/null || true
