#!/system/bin/sh
# HSIN State Manager

[ -z "$HSIN_MODULE_PATH" ] && HSIN_MODULE_PATH="/data/adb/modules/hsin"
HSIN_DATA="${HSIN_DATA:-/data/adb/hsin}"

HSIN_STATE_LOCK="$HSIN_DATA/state.lock"

# Initialize state lock file
hsin_state_init() {
    mkdir -p "$HSIN_DATA" 2>/dev/null

    [ -f "$HSIN_STATE_LOCK" ] && return 0

    {
        echo "OWNER=HSIN"
        echo "VERSION=1.0.0"
        echo "CPU_ENGINE=idle"
        echo "GPU_ENGINE=idle"
        echo "MEMORY_ENGINE=idle"
        echo "IO_ENGINE=idle"
        echo "NETWORK_ENGINE=idle"
        echo "THERMAL_ENGINE=idle"
        echo "ACTIVE_PROFILE=none"
        echo "LAST_APPLIED=0"
    } > "$HSIN_STATE_LOCK"
}

# Update engine state
hsin_state_update() {
    _engine="$1"
    _status="$2"

    [ -f "$HSIN_STATE_LOCK" ] || hsin_state_init

    # Serialize background WebUI applies; shared temp files otherwise race.
    _su_lock="$HSIN_STATE_LOCK.lock"
    _su_wait=0
    while ! mkdir "$_su_lock" 2>/dev/null; do
        _su_wait=$((_su_wait + 1))
        [ "$_su_wait" -ge 50 ] && return 1
        sleep 0.02
    done

    # Update the line
    _tmp="$HSIN_STATE_LOCK.tmp"
    _su_found=0
    while IFS= read -r _line; do
        case "$_line" in
            ${_engine}=*)
                echo "${_engine}=${_status}"
                _su_found=1
                ;;
            *)
                echo "$_line"
                ;;
        esac
    done < "$HSIN_STATE_LOCK" > "$_tmp"
    # BUG FIX (critical): this loop only OVERWRITES a line that already
    # matches "${_engine}=*" - if the key isn't already present in
    # state.lock it just copies the file through unchanged and the key
    # is silently never added. hsin_state_init's template only seeds
    # OWNER/VERSION/*_ENGINE/ACTIVE_PROFILE/LAST_APPLIED - it does NOT
    # include APPLY_STATUS or CPU_GOVERNOR, both of which are written
    # via this same function elsewhere (action.sh's apply flow,
    # hsin_state_save_before_apply). That meant APPLY_STATUS could NEVER
    # be created, so the WebUI's "wait for APPLY_STATUS=done:*" apply
    # confirmation (see script.js) was waiting on a key that would never
    # exist, and hsin_state_check_external's CPU_GOVERNOR drift check
    # never had anything to compare against either. Append the key if no
    # existing line matched it.
    if [ "$_su_found" -eq 0 ]; then
        echo "${_engine}=${_status}" >> "$_tmp"
    fi
    if ! mv "$_tmp" "$HSIN_STATE_LOCK"; then
        rmdir "$_su_lock" 2>/dev/null
        return 1
    fi
    rmdir "$_su_lock" 2>/dev/null
}

# Update active profile
hsin_state_profile() {
    _profile="$1"
    hsin_state_update "ACTIVE_PROFILE" "$_profile"
    hsin_state_update "LAST_APPLIED" "$(date +%s)"
}

# Check if HSIN owns the current state
hsin_state_check_ownership() {
    [ -f "$HSIN_STATE_LOCK" ] || return 1

    _owner=""
    while IFS='=' read -r _k _v || [ -n "$_k" ]; do
        [ "$_k" = "OWNER" ] && { _owner="$_v"; break; }
    done < "$HSIN_STATE_LOCK"
    [ "$_owner" = "HSIN" ] && return 0 || return 1
}

# Check for external changes
hsin_state_check_external() {
    [ -f "$HSIN_STATE_LOCK" ] || return 1

    # Check CPU governor
    _lock_gov=""
    while IFS='=' read -r _k _v || [ -n "$_k" ]; do
        [ "$_k" = "CPU_GOVERNOR" ] && { _lock_gov="$_v"; break; }
    done < "$HSIN_STATE_LOCK"
    if [ -n "$_lock_gov" ]; then
        for _policy in /sys/devices/system/cpu/cpufreq/policy*; do
            [ -d "$_policy" ] || continue
            [ -f "$_policy/scaling_governor" ] || continue
            _cur=""
            read -r _cur < "$_policy/scaling_governor" 2>/dev/null
            if [ "$_cur" != "$_lock_gov" ]; then
                echo "[STATE] WARNING: External CPU governor change ($_lock_gov -> $_cur)"
                return 1
            fi
        done
    fi

    return 0
}

# Save current engine states before apply
hsin_state_save_before_apply() {
    [ -f "$HSIN_STATE_LOCK" ] || hsin_state_init

    # Save current CPU governor
    for _policy in /sys/devices/system/cpu/cpufreq/policy*; do
        [ -d "$_policy" ] || continue
        [ -f "$_policy/scaling_governor" ] || continue
        _gov=""
        read -r _gov < "$_policy/scaling_governor" 2>/dev/null
        hsin_state_update "CPU_GOVERNOR" "$_gov"
        break
    done
}

# Mark engine as active
hsin_state_engine_start() {
    _engine="$1"
    hsin_state_update "${_engine}_ENGINE" "active"
}

# Mark engine as complete
hsin_state_engine_done() {
    _engine="$1"
    hsin_state_update "${_engine}_ENGINE" "done"
}

# Print state lock
hsin_state_print() {
    [ -f "$HSIN_STATE_LOCK" ] || { echo "No state lock found"; return 1; }

    echo ""
    echo "╔══════════════════════════════════════╗"
    echo "║   State Lock                         ║"
    echo "╚══════════════════════════════════════╝"
    echo ""
    while IFS='=' read -r _key _val; do
        printf "  %-20s %s\n" "$_key" "$_val"
    done < "$HSIN_STATE_LOCK"
    echo ""
}

return 0 2>/dev/null || true
