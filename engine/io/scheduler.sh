#!/system/bin/sh
# HSIN IO Engine - Scheduler Management

[ -z "$HSIN_MODULE_PATH" ] && HSIN_MODULE_PATH="/data/adb/modules/hsin"

# Pick best IO scheduler for profile
hsin_io_pick_scheduler() {
    _profile="$1"
    _list="$2"

    case "$_profile" in
        battery)
            for _s in bfq none; do
                case " $_list " in
                    *" [$_s] "*|*" $_s "*|*"$_s"*) echo "$_s"; return 0 ;;
                esac
            done
            ;;
        balanced)
            for _s in mq-deadline kyber bfq; do
                case " $_list " in
                    *" [$_s] "*|*" $_s "*|*"$_s"*) echo "$_s"; return 0 ;;
                esac
            done
            ;;
        performance|extreme)
            for _s in mq-deadline none; do
                case " $_list " in
                    *" [$_s] "*|*" $_s "*|*"$_s"*) echo "$_s"; return 0 ;;
                esac
            done
            ;;
    esac
    echo ""
    return 1
}

# Apply scheduler to all block devices
hsin_io_apply_scheduler() {
    _profile="$1"
    _ok=0
    _skip=0

    for _b in /sys/block/*; do
        [ -d "$_b" ] || continue
        _name=$(basename "$_b")

        # Skip non-block devices
        case "$_name" in
            loop*|ram*|zram*|dm-*) continue ;;
        esac

        # Check scheduler exists
        [ -f "$_b/queue/scheduler" ] || { _skip=$((_skip + 1)); continue; }

        # Check writable
        [ -w "$_b/queue/scheduler" ] || { _skip=$((_skip + 1)); continue; }

        _list=$(cat "$_b/queue/scheduler" 2>/dev/null)

        # Special case for rotational devices (HDD)
        _rot=$(cat "$_b/queue/rotational" 2>/dev/null)
        if [ "$_rot" = "1" ]; then
            _target="bfq"
        else
            _target=$(hsin_io_pick_scheduler "$_profile" "$_list")
        fi

        [ -z "$_target" ] && { _skip=$((_skip + 1)); continue; }

        echo "$_target" > "$_b/queue/scheduler" 2>/dev/null && _ok=$((_ok + 1)) || _skip=$((_skip + 1))
    done

    echo "    Scheduler [$_profile]: ok=$_ok skip=$_skip"
    return 0
}

# Get current scheduler state
hsin_io_scheduler_state() {
    echo "  IO Scheduler State:"
    for _b in /sys/block/*; do
        [ -d "$_b" ] || continue
        _name=$(basename "$_b")
        case "$_name" in
            loop*|ram*|zram*|dm-*) continue ;;
        esac
        [ -f "$_b/queue/scheduler" ] || continue
        _cur=$(cat "$_b/queue/scheduler" 2>/dev/null)
        printf "    %-15s %s\n" "$_name" "$_cur"
    done
}

return 0 2>/dev/null || true
