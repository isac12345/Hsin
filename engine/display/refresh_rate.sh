#!/system/bin/sh
# HSIN Display Refresh Rate Lock Engine
#
# Locks the panel's peak AND min refresh rate to the same value so the
# system's adaptive-refresh logic can't step it up/down on its own
# (the "loncat-loncat" jumping between e.g. 60/90/120 that some devices
# do even during light UI use). This is done purely through the
# standard AOSP Settings.System keys (peak_refresh_rate / min_refresh_rate),
# the same mechanism system Settings > Smooth Display uses - no sysfs,
# no vendor-specific path, so it works the same way on every chipset/OEM
# that exposes multiple refresh rate modes. On a device with only one
# panel mode (fixed 60Hz), locking is a harmless no-op since there is
# nothing to jump between anyway.
#
# Requires: HSIN_DATA exported by the caller (service.sh / action.sh both
# already export it).

HSIN_REFRESH_DEFAULT_HZ=120   # fallback target if caller doesn't pass one

# Pick whichever of `settings` / `cmd settings` is actually available on
# this device and put/delete a single System key with it. Every AOSP
# framework ships one of these two, so trying both covers minimal/custom
# ROMs that stripped one of the binaries.
_hsin_refresh_settings_put_scope() {
    _scope="$1"
    _key="$2"
    _val="$3"
    if command -v settings >/dev/null 2>&1; then
        settings put "$_scope" "$_key" "$_val" 2>/dev/null && return 0
    fi
    if command -v cmd >/dev/null 2>&1; then
        cmd settings put "$_scope" "$_key" "$_val" 2>/dev/null && return 0
    fi
    return 1
}

_hsin_refresh_settings_delete_scope() {
    _scope="$1"
    _key="$2"
    if command -v settings >/dev/null 2>&1; then
        settings delete "$_scope" "$_key" >/dev/null 2>&1
    fi
    if command -v cmd >/dev/null 2>&1; then
        cmd settings delete "$_scope" "$_key" >/dev/null 2>&1
    fi
    return 0
}

_hsin_refresh_settings_get_scope() {
    _scope="$1"
    _key="$2"
    _v=""
    if command -v settings >/dev/null 2>&1; then
        _v=$(settings get "$_scope" "$_key" 2>/dev/null)
    fi
    if { [ -z "$_v" ] || [ "$_v" = "null" ]; } && command -v cmd >/dev/null 2>&1; then
        _v=$(cmd settings get "$_scope" "$_key" 2>/dev/null)
    fi
    [ "$_v" = "null" ] && _v=""
    echo "$_v"
}

_hsin_refresh_settings_put() { _hsin_refresh_settings_put_scope "system" "$1" "$2"; }
_hsin_refresh_settings_delete() { _hsin_refresh_settings_delete_scope "system" "$1"; }
_hsin_refresh_settings_get() { _hsin_refresh_settings_get_scope "system" "$1"; }

# List every distinct refresh rate the panel's current display mode set
# advertises (e.g. "60 90 120"), sorted ascending. Parsed from `dumpsys
# display`'s per-mode "fps=" fields. INFORMATIONAL ONLY now (shown in the
# WebUI status line) - no longer used to snap/clamp the requested value,
# because on some devices this dump only exposes the single currently
# active mode instead of the full supported set, which used to make
# hsin_refresh_lock silently collapse every requested Hz down to that one
# repeated number (bug: "refresh rate won't change" while actually
# working through other tools). DisplayManager itself already clamps an
# out-of-range peak/min value to the nearest real mode, so we don't need
# to pre-snap on our side - see hsin_refresh_lock below.
hsin_refresh_detect_supported() {
    _dump="$(dumpsys display 2>/dev/null)"
    printf '%s\n' "$_dump" | grep -o 'fps=[0-9.]*' | cut -d= -f2 | cut -d. -f1 \
        | grep -v '^$' | sort -n -u | tr '\n' ' ' | sed 's/ $//'
}

# Best-effort extra knobs some ROMs need alongside peak/min_refresh_rate,
# because their SurfaceFlinger keeps re-picking a mode based on on-screen
# content (or a vendor "smart/dynamic refresh" layer) regardless of the
# System-table hint, effectively fighting the lock a moment after it's
# applied. Both are no-ops (silently fail) on ROMs that don't have them,
# so it's safe to always attempt.
_hsin_refresh_disable_content_detection() {
    if command -v resetprop >/dev/null 2>&1; then
        resetprop ro.surface_flinger.use_content_detection_for_refresh_rate 0 2>/dev/null
    fi
    _hsin_refresh_settings_put_scope "global" "disable_dynamic_refresh_rate" "1"
}

_hsin_refresh_restore_content_detection() {
    _hsin_refresh_settings_delete_scope "global" "disable_dynamic_refresh_rate"
}

# Lock peak AND min refresh rate to the requested value (raw, no manual
# snapping - see the note on hsin_refresh_detect_supported above; the OS
# already clamps out-of-range values to the nearest real mode on its own).
# $1 = requested Hz, defaults to HSIN_REFRESH_DEFAULT_HZ.
# Prints the ACTUALLY applied Hz on success, returns 1 on total failure
# (neither settings nor cmd binary available, or the write didn't stick).
hsin_refresh_lock() {
    _requested="${1:-$HSIN_REFRESH_DEFAULT_HZ}"
    case "$_requested" in
        ''|*[!0-9]*) echo "ERROR: hz must be a number" >&2; return 1 ;;
    esac

    _hsin_refresh_disable_content_detection

    _ok=0
    _hsin_refresh_settings_put "peak_refresh_rate" "$_requested" && _ok=1
    _hsin_refresh_settings_put "min_refresh_rate" "$_requested" && _ok=1
    echo "[refresh_rate] put peak/min=$_requested -> put_ok=$_ok" >&2

    [ "$_ok" -eq 1 ] || { echo "[refresh_rate] FAIL: no settings/cmd binary" >&2; return 1; }

    # Read back to confirm the value actually stuck (rather than trusting
    # the put command's exit code, which some ROMs return 0 for even when
    # a policy silently reverts the key right after).
    _peak_readback="$(_hsin_refresh_settings_get "peak_refresh_rate")"
    _min_readback="$(_hsin_refresh_settings_get "min_refresh_rate")"
    echo "[refresh_rate] readback peak=$_peak_readback min=$_min_readback (available modes: $(hsin_refresh_detect_supported))" >&2
    if [ "$_peak_readback" != "$_requested" ] || [ "$_min_readback" != "$_requested" ]; then
        echo "[refresh_rate] WARNING: readback mismatch - value was overwritten right after being set" >&2
    fi

    echo "$_requested"
    return 0
}

# Restore adaptive/auto behavior by clearing both override keys entirely
# (not just setting them back to a wide range) - this hands full control
# back to the system the same as if HSIN had never touched it.
hsin_refresh_unlock() {
    _hsin_refresh_settings_delete "peak_refresh_rate"
    _hsin_refresh_settings_delete "min_refresh_rate"
    _hsin_refresh_restore_content_detection
}

# Status line for the WebUI: supported modes, currently-locked values (if
# any) and whether the feature is presently enabled per hsin.conf. Caller
# passes in the enabled flag and saved Hz (only action.sh knows how to
# read those from hsin.conf). Prints a small JSON object.
hsin_refresh_status() {
    _enabled="${1:-false}"
    _saved_hz="${2:-$HSIN_REFRESH_DEFAULT_HZ}"

    _avail="$(hsin_refresh_detect_supported)"
    [ -z "$_avail" ] && _avail="unknown"

    _peak="$(_hsin_refresh_settings_get "peak_refresh_rate")"
    [ -z "$_peak" ] && _peak="auto"
    _min="$(_hsin_refresh_settings_get "min_refresh_rate")"
    [ -z "$_min" ] && _min="auto"

    echo "{\"enabled\":\"$_enabled\",\"saved_hz\":\"$_saved_hz\",\"peak\":\"$_peak\",\"min\":\"$_min\",\"supported\":\"$_avail\"}"
}

# --- Global Refresh Rate Control (Stellar-style: peak/min independent) ---
#
# Unlike hsin_refresh_lock (which pins peak=min to one value for an
# anti-jump lock), this lets peak and min differ - e.g. peak=120 min=60
# to keep adaptive-refresh ON but capped, which is what most "reduce
# refresh rate to save battery" toggles actually want instead of a hard
# single-Hz lock.
#
# $1 = peak Hz, $2 = min Hz, $3 = force (true/false, optional)
# force=true re-applies even if the readback already matches (some ROMs
# silently revert the key on screen-on/doze-exit, so a periodic re-apply
# from service.sh's monitor loop needs this instead of skipping on match).
hsin_refresh_set_range() {
    _peak="${1:-$HSIN_REFRESH_DEFAULT_HZ}"
    _min="${2:-60}"
    _force="${3:-false}"

    case "$_peak" in ''|*[!0-9]*) echo "ERROR: peak hz must be a number" >&2; return 1 ;; esac
    case "$_min" in ''|*[!0-9]*) echo "ERROR: min hz must be a number" >&2; return 1 ;; esac

    if [ "$_force" != "true" ]; then
        _cur_peak="$(_hsin_refresh_settings_get "peak_refresh_rate")"
        _cur_min="$(_hsin_refresh_settings_get "min_refresh_rate")"
        if [ "$_cur_peak" = "$_peak" ] && [ "$_cur_min" = "$_min" ]; then
            echo "OK: already peak=$_peak min=$_min (no change)"
            return 0
        fi
    fi

    _hsin_refresh_settings_put "peak_refresh_rate" "$_peak"
    _hsin_refresh_settings_put "min_refresh_rate" "$_min"

    _peak_readback="$(_hsin_refresh_settings_get "peak_refresh_rate")"
    _min_readback="$(_hsin_refresh_settings_get "min_refresh_rate")"
    echo "[refresh_rate] set peak=$_peak min=$_min (readback peak=$_peak_readback min=$_min_readback)" >&2

    if [ "$_peak_readback" != "$_peak" ] || [ "$_min_readback" != "$_min" ]; then
        echo "WARNING: readback mismatch, value may have been reverted"
        return 1
    fi
    echo "OK: peak=$_peak min=$_min applied"
    return 0
}

# "Reduced RR" convenience mode: caps peak to a lower Hz for battery saving
# while leaving min alone (or at the lowest supported), keeping adaptive
# behavior instead of a hard lock. $1 = target peak Hz (default 60).
hsin_refresh_reduced_apply() {
    _target_peak="${1:-60}"
    _force="${2:-false}"
    _avail="$(hsin_refresh_detect_supported)"
    _lowest_min=60
    if [ -n "$_avail" ] && [ "$_avail" != "unknown" ]; then
        _lowest_min="$(printf '%s\n' "$_avail" | tr ' ' '\n' | sort -n | head -1)"
    fi
    hsin_refresh_set_range "$_target_peak" "$_lowest_min" "$_force"
}

# Called from service.sh's periodic monitor loop and from post-fs-data.sh.
# Reads the three global_refreshrate keys from hsin.conf and applies
# whichever mode is enabled. No-op (returns 0 silently) if disabled.
#
# hsin.conf keys used:
#   GLOBAL_RR_ENABLED=false
#   GLOBAL_RR_REDUCED=false      # reduced/battery-saving mode
#   GLOBAL_RR_FORCE=false        # re-apply every call, ignore readback match
#   GLOBAL_RR_PEAK_HZ=120
#   GLOBAL_RR_MIN_HZ=60
hsin_refresh_global_apply_from_conf() {
    _conf="${1:-$HSIN_MODULE_PATH/config/hsin.conf}"
    [ -f "$_conf" ] || return 0

    _enabled=false; _reduced=false; _force=false; _peak=120; _min=60
    while IFS='=' read -r _k _v || [ -n "$_k" ]; do
        case "$_k" in
            GLOBAL_RR_ENABLED) _enabled="$_v" ;;
            GLOBAL_RR_REDUCED) _reduced="$_v" ;;
            GLOBAL_RR_FORCE) _force="$_v" ;;
            GLOBAL_RR_PEAK_HZ) _peak="$_v" ;;
            GLOBAL_RR_MIN_HZ) _min="$_v" ;;
        esac
    done < "$_conf"

    [ "$_enabled" = "true" ] || return 0

    if [ "$_reduced" = "true" ]; then
        hsin_refresh_reduced_apply "$_peak" "$_force"
    else
        hsin_refresh_set_range "$_peak" "$_min" "$_force"
    fi
}

# Turn global RR control fully off and hand control back to the system.
hsin_refresh_global_disable() {
    hsin_refresh_unlock
    echo "OK: global refresh rate control disabled, system default restored"
}

return 0 2>/dev/null || true
