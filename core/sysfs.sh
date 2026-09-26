#!/system/bin/sh
# HSIN Universal node helpers
# No vendor-specific write is performed unless the node actually exists,
# is writable, and (for clock limits) the requested OPP is valid.

# Read one value without forking cat.
hsin_node_read() {
    _hn_p="$1"
    _hn_v=""
    [ -r "$_hn_p" ] || return 1
    IFS= read -r _hn_v < "$_hn_p" 2>/dev/null || return 1
    printf '%s\n' "$_hn_v"
    return 0
}

# Write and verify exact value. Returns non-zero on unsupported/rejected node.
hsin_node_write_verify() {
    _hn_p="$1"
    _hn_v="$2"
    [ -f "$_hn_p" ] && [ -w "$_hn_p" ] || return 1
    printf '%s\n' "$_hn_v" > "$_hn_p" 2>/dev/null || return 1
    _hn_cur="$(hsin_node_read "$_hn_p" 2>/dev/null)"
    [ "$_hn_cur" = "$_hn_v" ]
}

# Return the highest available numeric value <= requested target.
# If none is <= target, return the lowest available OPP.
hsin_opp_cap_pick() {
    _hn_target="$1"
    _hn_avail="$2"
    case "$_hn_target" in ''|*[!0-9]*) return 1 ;; esac
    _hn_best=""
    _hn_low=""
    for _hn_f in $_hn_avail; do
        case "$_hn_f" in ''|*[!0-9]*) continue ;; esac
        if [ -z "$_hn_low" ] || [ "$_hn_f" -lt "$_hn_low" ] 2>/dev/null; then
            _hn_low="$_hn_f"
        fi
        if [ "$_hn_f" -le "$_hn_target" ] 2>/dev/null; then
            if [ -z "$_hn_best" ] || [ "$_hn_f" -gt "$_hn_best" ] 2>/dev/null; then
                _hn_best="$_hn_f"
            fi
        fi
    done
    [ -n "$_hn_best" ] && printf '%s\n' "$_hn_best" || printf '%s\n' "$_hn_low"
}

# Return the lowest available numeric value >= requested target.
hsin_opp_floor_pick() {
    _hn_target="$1"
    _hn_avail="$2"
    case "$_hn_target" in ''|*[!0-9]*) return 1 ;; esac
    _hn_best=""
    _hn_high=""
    for _hn_f in $_hn_avail; do
        case "$_hn_f" in ''|*[!0-9]*) continue ;; esac
        if [ -z "$_hn_high" ] || [ "$_hn_f" -gt "$_hn_high" ] 2>/dev/null; then
            _hn_high="$_hn_f"
        fi
        if [ "$_hn_f" -ge "$_hn_target" ] 2>/dev/null; then
            if [ -z "$_hn_best" ] || [ "$_hn_f" -lt "$_hn_best" ] 2>/dev/null; then
                _hn_best="$_hn_f"
            fi
        fi
    done
    [ -n "$_hn_best" ] && printf '%s\n' "$_hn_best" || printf '%s\n' "$_hn_high"
}

# Highest numeric token in an OPP list.
hsin_opp_max() {
    _hn_max=""
    for _hn_f in $1; do
        case "$_hn_f" in ''|*[!0-9]*) continue ;; esac
        if [ -z "$_hn_max" ] || [ "$_hn_f" -gt "$_hn_max" ] 2>/dev/null; then
            _hn_max="$_hn_f"
        fi
    done
    [ -n "$_hn_max" ] && printf '%s\n' "$_hn_max"
}

# Lowest numeric token in an OPP list.
hsin_opp_min() {
    _hn_min=""
    for _hn_f in $1; do
        case "$_hn_f" in ''|*[!0-9]*) continue ;; esac
        if [ -z "$_hn_min" ] || [ "$_hn_f" -lt "$_hn_min" ] 2>/dev/null; then
            _hn_min="$_hn_f"
        fi
    done
    [ -n "$_hn_min" ] && printf '%s\n' "$_hn_min"
}

# Classify a devfreq node using name + OF compatible/device metadata.
# This is deliberately vendor-neutral: Unisoc nodes often look like
# 23100000.gpu rather than containing "mali".
hsin_devfreq_gpu_candidate() {
    _hn_d="$1"
    [ -d "$_hn_d" ] || return 1
    _hn_n=$(basename "$_hn_d" 2>/dev/null | tr '[:upper:]' '[:lower:]')
    case "$_hn_n" in
        *gpu*|*gfx*|*mali*|*kgsl*|*adreno*|*pvr*|*img*) return 0 ;;
    esac
    for _hn_c in \
        "$_hn_d/device/of_node/compatible" \
        "$_hn_d/device/uevent" \
        "$_hn_d/device/modalias" \
        "$_hn_d/name"; do
        [ -f "$_hn_c" ] || continue
        _hn_v=$(tr '\0' ' ' < "$_hn_c" 2>/dev/null | tr '[:upper:]' '[:lower:]')
        case "$_hn_v" in
            *gpu*|*gfx*|*mali*|*adreno*|*kgsl*|*powervr*|*imgtec*|*pvr*) return 0 ;;
        esac
    done
    return 1
}

# Print a compact support line for a skipped node.
hsin_report_skip() {
    printf '    SKIP: %s\n' "$1"
}

return 0 2>/dev/null || true
