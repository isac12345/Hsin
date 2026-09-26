#!/system/bin/sh
# HSIN Extreme Frequency Unlock

[ -z "$HSIN_MODULE_PATH" ] && HSIN_MODULE_PATH="/data/adb/modules/hsin"
HSIN_DATA="${HSIN_DATA:-/data/adb/hsin}"

# Detect available frequencies for a policy
hsin_extreme_freq_detect() {
    _policy="$1"

    [ -d "$_policy" ] || return 1
    [ -f "$_policy/available_frequencies" ] || return 1

    cat "$_policy/available_frequencies" 2>/dev/null | tr ' ' '\n' | sort -n | tr '\n' ' '
}

# Get highest available frequency
hsin_extreme_freq_max() {
    _policy="$1"
    hsin_extreme_freq_detect "$_policy" | tr ' ' '\n' | sort -n | tail -1
}

# Backup current frequencies
hsin_extreme_freq_backup() {
    # FIX (stuck-at-extreme bug): kalau extreme SUDAH aktif (mis. dari
    # game sebelumnya yang belum sempat direstore, atau dua kali masuk
    # game beruntun), jangan backup ulang - sysfs saat ini sudah berisi
    # nilai extreme, bukan nilai profil normal aslinya. Backup ulang di
    # titik ini akan MENIMPA snapshot asli yang benar dengan nilai
    # extreme, sehingga restore berikutnya "mengembalikan" ke extreme.
    if [ -f "$HSIN_DATA/extreme_active" ] && [ -f "$HSIN_DATA/freq_backup_latest" ]; then
        _existing=$(cat "$HSIN_DATA/freq_backup_latest" 2>/dev/null)
        [ -d "$_existing" ] && { echo "$_existing"; return 0; }
    fi

    _backup_dir="$HSIN_DATA/backups/freq_extreme_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$_backup_dir" 2>/dev/null

    for _policy in /sys/devices/system/cpu/cpufreq/policy*; do
        [ -d "$_policy" ] || continue

        _policy_num=$(basename "$_policy" | sed 's/policy//')
        _policy_backup="$_backup_dir/policy$_policy_num"
        mkdir -p "$_policy_backup" 2>/dev/null

        [ -f "$_policy/scaling_max_freq" ] && cat "$_policy/scaling_max_freq" > "$_policy_backup/scaling_max_freq" 2>/dev/null
        [ -f "$_policy/scaling_min_freq" ] && cat "$_policy/scaling_min_freq" > "$_policy_backup/scaling_min_freq" 2>/dev/null
        [ -f "$_policy/scaling_governor" ] && cat "$_policy/scaling_governor" > "$_policy_backup/scaling_governor" 2>/dev/null
        [ -f "$_policy/cpuinfo_max_freq" ] && cat "$_policy/cpuinfo_max_freq" > "$_policy_backup/cpuinfo_max_freq" 2>/dev/null
        [ -f "$_policy/cpuinfo_min_freq" ] && cat "$_policy/cpuinfo_min_freq" > "$_policy_backup/cpuinfo_min_freq" 2>/dev/null

        echo "$_backup_dir" > "$HSIN_DATA/freq_backup_latest"
    done

    echo "$_backup_dir"
}

# Apply extreme frequencies
hsin_extreme_freq_apply() {
    echo "Detecting CPU policies..."

    for _policy in /sys/devices/system/cpu/cpufreq/policy*; do
        [ -d "$_policy" ] || continue

        _policy_num=$(basename "$_policy" | sed 's/policy//')

        # Detect available frequencies
        _avail=$(hsin_extreme_freq_detect "$_policy")
        _max=$(hsin_extreme_freq_max "$_policy")

        [ -z "$_max" ] && {
            echo "  policy$_policy_num: SKIP (no frequencies found)"
            continue
        }

        echo "  policy$_policy_num:"
        echo "    Available: $_avail"
        echo "    Highest:   $_max Hz"

        # Apply max frequency
        if [ -f "$_policy/scaling_max_freq" ]; then
            if printf '%s\n' "$_max" > "$_policy/scaling_max_freq" 2>/dev/null; then
                echo "    Status:    OK (max=$_max)"
            else
                echo "    Status:    FAILED (read-only)"
            fi
        else
            echo "    Status:    SKIP (no scaling_max_freq)"
        fi
    done
}

# Restore frequencies from backup
hsin_extreme_freq_restore() {
    [ -f "$HSIN_DATA/freq_backup_latest" ] || {
        echo "No frequency backup found"
        return 1
    }

    _backup_dir=$(cat "$HSIN_DATA/freq_backup_latest" 2>/dev/null)
    [ -d "$_backup_dir" ] || {
        echo "Backup directory not found"
        return 1
    }

    _restored=0
    for _policy_dir in "$_backup_dir"/policy*; do
        [ -d "$_policy_dir" ] || continue

        _policy_num=$(basename "$_policy_dir" | sed 's/policy//')
        _target="/sys/devices/system/cpu/cpufreq/policy$_policy_num"
        [ -d "$_target" ] || continue

        # Restore governor
        [ -f "$_policy_dir/scaling_governor" ] && {
            _val=$(cat "$_policy_dir/scaling_governor" 2>/dev/null)
            [ -n "$_val" ] && echo "$_val" > "$_target/scaling_governor" 2>/dev/null
        }

        # Restore max freq
        [ -f "$_policy_dir/scaling_max_freq" ] && {
            _val=$(cat "$_policy_dir/scaling_max_freq" 2>/dev/null)
            [ -n "$_val" ] && echo "$_val" > "$_target/scaling_max_freq" 2>/dev/null
            _restored=$((_restored + 1))
        }

        # Restore min freq
        [ -f "$_policy_dir/scaling_min_freq" ] && {
            _val=$(cat "$_policy_dir/scaling_min_freq" 2>/dev/null)
            [ -n "$_val" ] && echo "$_val" > "$_target/scaling_min_freq" 2>/dev/null
            _restored=$((_restored + 1))
        }
    done

    echo "Restored: $_restored frequency settings"
}

return 0 2>/dev/null || true
