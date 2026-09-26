#!/system/bin/sh
# HSIN GPU Engine - Devfreq Management

[ -z "$HSIN_MODULE_PATH" ] && HSIN_MODULE_PATH="/data/adb/modules/hsin"

# Apply devfreq GPU governor
hsin_gpu_devfreq_apply() {
    _profile="$1"
    _devfreq="$2"

    [ -d "$_devfreq" ] || return 1

    # Check if governor is available
    [ -f "$_devfreq/available_governors" ] || return 1
    _avail=$(cat "$_devfreq/available_governors" 2>/dev/null)

    # Pick governor based on profile
    _target=""
    case "$_profile" in
        battery)
            for _g in powersave simple_ondemand; do
                case " $_avail" in
                    *" $_g "*) _target="$_g"; break ;;
                esac
            done
            ;;
        balanced)
            for _g in schedutil simple_ondemand ondemand; do
                case " $_avail" in
                    *" $_g "*) _target="$_g"; break ;;
                esac
            done
            ;;
        performance|extreme)
            for _g in performance msm-adreno-tz; do
                case " $_avail" in
                    *" $_g "*) _target="$_g"; break ;;
                esac
            done
            ;;
    esac

    [ -z "$_target" ] && return 1

    # Check current
    _current=""
    [ -f "$_devfreq/governor" ] && _current=$(cat "$_devfreq/governor" 2>/dev/null)
    [ "$_current" = "$_target" ] && return 0

    # Apply
    [ -w "$_devfreq/governor" ] || return 1
    echo "$_target" > "$_devfreq/governor" 2>/dev/null || return 1

    # Verify
    _verify=$(cat "$_devfreq/governor" 2>/dev/null)
    [ "$_verify" = "$_target" ] && return 0 || return 1
}

# Apply devfreq min/max frequency
hsin_gpu_devfreq_freq() {
    _profile="$1"
    _devfreq="$2"

    [ -d "$_devfreq" ] || return 1

    # Get available frequencies
    [ -f "$_devfreq/available_frequencies" ] || return 1
    _avail=$(cat "$_devfreq/available_frequencies" 2>/dev/null)

    # Get min/max from available
    _min_avail=$(echo "$_avail" | tr ' ' '\n' | grep -v '^$' | sort -n | head -1)
    _max_avail=$(echo "$_avail" | tr ' ' '\n' | grep -v '^$' | sort -nr | head -1)

    case "$_profile" in
        battery)
            _min="$_min_avail"
            _max="$_max_avail"  # Let governor decide
            ;;
        balanced)
            _min="$_min_avail"
            _max="$_max_avail"
            ;;
        performance)
            _min="$_max_avail"  # Lock to max
            _max="$_max_avail"
            ;;
        extreme)
            _min="$_max_avail"
            _max="$_max_avail"
            ;;
    esac

    # Apply max first
    [ -w "$_devfreq/max_freq" ] && echo "$_max" > "$_devfreq/max_freq" 2>/dev/null
    [ -w "$_devfreq/min_freq" ] && echo "$_min" > "$_devfreq/min_freq" 2>/dev/null

    return 0
}

# Get devfreq state
hsin_gpu_devfreq_state() {
    _devfreq="$1"
    [ -d "$_devfreq" ] || return 1

    echo "  Devfreq State: $(basename $_devfreq)"
    [ -f "$_devfreq/governor" ] && {
        _gov=$(cat "$_devfreq/governor" 2>/dev/null)
        printf "    governor: %s\n" "$_gov"
    }
    [ -f "$_devfreq/cur_freq" ] && {
        _freq=$(cat "$_devfreq/cur_freq" 2>/dev/null)
        _freq_mhz=$((_freq / 1000000))
        printf "    cur_freq: %s MHz\n" "$_freq_mhz"
    }
    [ -f "$_devfreq/min_freq" ] && {
        _min=$(cat "$_devfreq/min_freq" 2>/dev/null)
        _min_mhz=$((_min / 1000000))
        printf "    min_freq: %s MHz\n" "$_min_mhz"
    }
    [ -f "$_devfreq/max_freq" ] && {
        _max=$(cat "$_devfreq/max_freq" 2>/dev/null)
        _max_mhz=$((_max / 1000000))
        printf "    max_freq: %s MHz\n" "$_max_mhz"
    }
}

return 0 2>/dev/null || true
