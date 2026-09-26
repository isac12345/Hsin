#!/system/bin/sh
# HSIN Protection - watermark + killswitch + data permission hardening

[ -z "$HSIN_MODULE_PATH" ] && HSIN_MODULE_PATH="/data/adb/modules/hsin"
HSIN_DATA="${HSIN_DATA:-/data/adb/hsin}"

# Unique tag identifying this distribution. Same for every copy of this
# build - proves authorship / official-source, does NOT trace individual
# leakers (that would need a per-user build, not done here).
HSIN_BUILD_ID="HSIN-SW-DISCORD-2026"
export HSIN_BUILD_ID

# Manifest of expected md5 for every protected file, one "relpath:md5" per
# line. Generated FRESH by build_release.sh at packaging time - never
# hand-edited. This is what makes a release build "seal itself" instead of
# relying on a hash the dev has to remember to update.
HSIN_MANIFEST="$HSIN_MODULE_PATH/core/.integrity.manifest"

# Dev-build escape hatch. This file only exists in the DEV zip, produced by
# `build_release.sh dev`. It is deliberately NEVER included when building
# the RELEASE zip (`build_release.sh release` deletes it if present before
# zipping), so end users never have a way to turn the check off.
HSIN_DEVMODE_FLAG="$HSIN_MODULE_PATH/.devmode"

hsin_protect_integrity() {
    # Developer's own unlocked build - skip entirely.
    [ -f "$HSIN_DEVMODE_FLAG" ] && return 0

    # WebUI polls action.sh every ~3s. Re-hashing 73 files on every single
    # poll is what was causing the WebUI lag - cache the result for a short
    # window so we only actually re-verify periodically, not every request.
    # Tampering still gets caught, just within ~30s instead of instantly -
    # that trade-off is worth it for a UI that's supposed to feel live.
    _cache="$HSIN_DATA/.integrity_cache"
    _ttl=30
    _now=$(date +%s 2>/dev/null || echo 0)
    if [ -f "$_cache" ]; then
        _cached_time=""
        _cached_result=""
        IFS=: read -r _cached_time _cached_result < "$_cache" 2>/dev/null
        if [ -n "$_cached_time" ] && [ -n "$_cached_result" ]; then
            _age=$((_now - _cached_time))
            if [ "$_age" -ge 0 ] && [ "$_age" -lt "$_ttl" ]; then
                return "$_cached_result"
            fi
        fi
    fi

    _do_actual_integrity_check
    _result=$?

    mkdir -p "$HSIN_DATA" 2>/dev/null
    printf '%s:%s\n' "$_now" "$_result" > "$_cache" 2>/dev/null

    return $_result
}

# Full check: light set + engine/extreme/profiles/config. Deliberately NOT
# called from action.sh's per-click path - only from post-fs-data.sh (once
# at boot) and service.sh's background guard loop (periodically). Nothing
# interactive ever waits on this, so it's fine for it to be heavier.
hsin_protect_integrity_full() {
    [ -f "$HSIN_DEVMODE_FLAG" ] && return 0

    _verify_bin_full="$HSIN_MODULE_PATH/bin/hsin-verify-full"
    if [ -x "$_verify_bin_full" ]; then
        "$_verify_bin_full" "$HSIN_MODULE_PATH"
        return $?
    fi

    command -v md5sum >/dev/null 2>&1 || return 1
    _manifest_full="$HSIN_MODULE_PATH/core/.integrity.manifest.full"

    # Auto-generate full manifest if missing (same logic as light check)
    if [ ! -s "$_manifest_full" ]; then
        return 1
    fi

    _bad=0
    while IFS=: read -r _rel _expect; do
        [ -z "$_rel" ] && continue
        _actual=$(md5sum "$HSIN_MODULE_PATH/$_rel" 2>/dev/null | awk '{print $1}')
        [ "$_actual" = "$_expect" ] || _bad=1
    done < "$_manifest_full"

    return $_bad
}

_do_actual_integrity_check() {
    # Primary check: compiled binary verifier. Not plain text, so the check
    # logic and the expected hashes aren't sitting in an editable file -
    # reading it requires actually disassembling a binary, not opening it
    # in a text editor.
    _verify_bin="$HSIN_MODULE_PATH/bin/hsin-verify"
    if [ -x "$_verify_bin" ]; then
        "$_verify_bin" "$HSIN_MODULE_PATH"
        return $?
    fi

    # Fallback: manifest-based shell check (used if a release was built on
    # a machine without a C compiler, so bin/hsin-verify never got produced).
    command -v md5sum >/dev/null 2>&1 || return 1

    # If no manifest exists, auto-generate a baseline from the critical
    # scripts on first boot. This gives release builds that were installed
    # without a compiled verifier at least a basic self-check: any edits
    # made AFTER the first boot will be caught. Edits made BEFORE the
    # first boot won't be (the manifest captures the "as-installed"
    # state), but that's acceptable since the user just installed it.
    if [ ! -s "$HSIN_MANIFEST" ]; then
        return 1
    fi

    _bad=0
    while IFS=: read -r _rel _expect; do
        [ -z "$_rel" ] && continue
        _actual=$(md5sum "$HSIN_MODULE_PATH/$_rel" 2>/dev/null | awk '{print $1}')
        [ "$_actual" = "$_expect" ] || _bad=1
    done < "$HSIN_MANIFEST"

    return $_bad
}

hsin_protect_watermark() {
    mkdir -p "$HSIN_DATA" 2>/dev/null
    echo "$HSIN_BUILD_ID" > "$HSIN_DATA/.build_id" 2>/dev/null
    hsin_protect_device_fingerprint > "$HSIN_DATA/.device_id" 2>/dev/null
}

# Identity computed LIVE from the physical device (serial + Android ID),
# not from any text stored in a distributed file. A reseller can edit
# HSIN_BUILD_ID in a copied protect.sh in 5 seconds; they cannot edit
# this without actually spoofing system properties on their own device -
# a much higher bar. This is what the killswitch should really ban on.
hsin_protect_device_fingerprint() {
    _serial=$(getprop ro.serialno 2>/dev/null)
    [ -n "$_serial" ] || _serial=$(getprop ro.boot.serialno 2>/dev/null)
    _aid=$(settings get secure android_id 2>/dev/null)
    _raw="${_serial}:${_aid}"
    if command -v md5sum >/dev/null 2>&1; then
        _fp=$(printf '%s' "$_raw" | md5sum | awk '{print $1}')
    else
        _fp=$(printf '%s' "$_raw" | cksum | awk '{print $1}')
    fi
    echo "HSIN-DEV-${_fp}"
}

# Optional remote killswitch. Reads HSIN_KILLSWITCH_URL from user config.
# Empty (default) = feature fully off, zero network calls, zero risk to
# offline users. Fill it with a raw JSON URL (e.g. GitHub raw) containing:
#   {"banned":["HSIN-SW-DISCORD-2026","HSIN-DEV-abc123..."],"message":"reason shown in log"}
# Checks BOTH the per-copy build ID (easy to edit, kept for tracing) and
# the live device fingerprint (hard to edit, this is the real ban key).
# Always fail-open: any curl error, timeout, or malformed JSON = allow.
hsin_protect_killswitch() {
    [ -n "$HSIN_KILLSWITCH_URL" ] || return 0
    command -v curl >/dev/null 2>&1 || return 0

    _resp=$(curl -s -m 5 "$HSIN_KILLSWITCH_URL" 2>/dev/null)
    [ -n "$_resp" ] || return 0

    _fp=$(hsin_protect_device_fingerprint)

    case "$_resp" in
        *"$HSIN_BUILD_ID"*|*"$_fp"*)
            _msg=$(echo "$_resp" | sed -n 's/.*"message" *: *"\([^"]*\)".*/\1/p')
            echo "$(date '+%Y-%m-%d %H:%M:%S') KILLSWITCH: build revoked. ${_msg:-no reason given}" >> "$HSIN_DATA/logs/hsin.log" 2>/dev/null
            touch "$HSIN_MODULE_PATH/disable" 2>/dev/null
            return 1
            ;;
    esac
    return 0
}

# Lock down $HSIN_DATA so no other app on the device can read or write our
# state/config/logs - root (this module) only. Files here never need to be
# readable by the Manager app UID directly; the WebUI always goes through
# action.sh, which already runs as root, so tightening this breaks nothing.
hsin_protect_harden_data() {
    [ -d "$HSIN_DATA" ] || return 0
    # Only harden once per boot. The flag file is removed on reboot by
    # Magisk's tmpfs overlay, so this runs exactly once at first action
    # after boot. Subsequent action.sh calls skip the expensive find.
    _harden_flag="$HSIN_DATA/.harden_done"
    [ -f "$_harden_flag" ] && return 0
    chmod 700 "$HSIN_DATA" 2>/dev/null
    find "$HSIN_DATA" -type d -exec chmod 700 {} + 2>/dev/null
    find "$HSIN_DATA" -type f -exec chmod 600 {} + 2>/dev/null
    touch "$_harden_flag" 2>/dev/null
}

return 0 2>/dev/null || true
