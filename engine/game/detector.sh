#!/system/bin/sh
# HSIN Game Detection Engine - Detector
# Credit: logic inspired by FAS-RS (FPS/game management)

[ -z "$HSIN_MODULE_PATH" ] && HSIN_MODULE_PATH="/data/adb/modules/hsin"

# Load games config
HSIN_GAMES_CONF="$HSIN_MODULE_PATH/engine/game/games.conf"
HSIN_GAME_FOREGROUND=""

# Check if package is a known game (tolerates "pkg" or "pkg:profile" lines)
hsin_game_is_known() {
    _target="$1"
    [ -f "$HSIN_GAMES_CONF" ] || return 1
    while IFS= read -r _line || [ -n "$_line" ]; do
        case "$_line" in
            ""|"#"*) continue ;;
        esac
        [ "${_line%%:*}" = "$_target" ] && return 0
    done < "$HSIN_GAMES_CONF"
    return 1
}

# Look up the profile mapped to a package in games.conf. Echoes the profile
# and returns 0 if found (plain listing = "performance", "pkg:profile"
# lines = that profile). Returns 1 if the package isn't listed at all.
hsin_game_mapped_profile() {
    _target="$1"
    [ -f "$HSIN_GAMES_CONF" ] || return 1
    while IFS= read -r _line || [ -n "$_line" ]; do
        case "$_line" in
            ""|"#"*) continue ;;
        esac
        if [ "${_line%%:*}" = "$_target" ]; then
            case "$_line" in
                *:*) echo "${_line#*:}" ;;
                *) echo "performance" ;;
            esac
            return 0
        fi
    done < "$HSIN_GAMES_CONF"
    return 1
}

# Get foreground activity package
hsin_game_detect_dumpsys() {
    if command -v dumpsys >/dev/null 2>&1; then
        _line=$(dumpsys activity activities 2>/dev/null | grep -m1 "mResumedActivity")
        # Pull the "package.name/.Activity" component out of the line
        # wherever it sits - the last whitespace field is actually the
        # task id (e.g. "t123}"), not the package, so don't rely on
        # position.
        _fg=$(printf '%s' "$_line" | grep -oE '[A-Za-z0-9_.]+/[A-Za-z0-9_.]+' | head -1 | cut -d/ -f1)
        [ -n "$_fg" ] && echo "$_fg" && return 0
    fi
    return 1
}

# Level 2: ps -A
# Get foreground app via window focus - historically more reliable across
# Android versions than parsing "mResumedActivity" out of activity dumps,
# since the activity-dump format has shifted around (per-display sections,
# multi-window, etc) in ways that broke the regex on some devices.
hsin_game_detect_window() {
    if command -v dumpsys >/dev/null 2>&1; then
        _line=$(dumpsys window windows 2>/dev/null | grep -m1 "mCurrentFocus")
        [ -z "$_line" ] && _line=$(dumpsys window 2>/dev/null | grep -m1 "mCurrentFocus")
        _fg=$(printf '%s' "$_line" | grep -oE '[A-Za-z0-9_.]+/[A-Za-z0-9_.]+' | head -1 | cut -d/ -f1)
        [ -n "$_fg" ] && echo "$_fg" && return 0
    fi
    return 1
}

hsin_game_detect_ps() {
    # Get foreground process (highest priority)
    _fg=$(ps -A -o PID,NAME 2>/dev/null | grep -E "(game|unity|unreal|godot)" | head -1 | awk '{print $2}')
    [ -n "$_fg" ] && echo "$_fg" && return 0
    return 1
}

# Main detection: returns package name or empty
hsin_game_detect() {
    # Try dumpsys activity first
    _pkg=$(hsin_game_detect_dumpsys)
    # PATCH v4.0: skip log kalau hasil kosong (spam tiap poll). Log cuma
    # pas paket game beneran ke-detect lewat method ini.
    if [ -n "$_pkg" ]; then
        echo "GAMEBOOST: method=activity result=[$_pkg]" >> "${HSIN_DEBUG_LOG:-/dev/null}" 2>/dev/null
    fi
    if [ -n "$_pkg" ]; then
        HSIN_GAME_FOREGROUND="$_pkg"
        echo "$_pkg"
        return 0
    fi

    # Try dumpsys window (mCurrentFocus) - often works when the above doesn't
    _pkg=$(hsin_game_detect_window)
    # PATCH v4.0: skip log kalau hasil kosong (spam tiap poll). Log cuma
    # pas paket game beneran ke-detect lewat method ini.
    if [ -n "$_pkg" ]; then
        echo "GAMEBOOST: method=window result=[$_pkg]" >> "${HSIN_DEBUG_LOG:-/dev/null}" 2>/dev/null
    fi
    if [ -n "$_pkg" ]; then
        HSIN_GAME_FOREGROUND="$_pkg"
        echo "$_pkg"
        return 0
    fi

    # Try ps fallback
    _pkg=$(hsin_game_detect_ps)
    # PATCH v4.0: skip log kalau hasil kosong (spam tiap poll). Log cuma
    # pas paket game beneran ke-detect lewat method ini.
    if [ -n "$_pkg" ]; then
        echo "GAMEBOOST: method=ps result=[$_pkg]" >> "${HSIN_DEBUG_LOG:-/dev/null}" 2>/dev/null
    fi
    if [ -n "$_pkg" ]; then
        HSIN_GAME_FOREGROUND="$_pkg"
        echo "$_pkg"
        return 0
    fi

    HSIN_GAME_FOREGROUND=""
    return 1
}

# Check if game is running
hsin_game_is_running() {
    _pkg=$(hsin_game_detect)
    [ -z "$_pkg" ] && return 1

    # Check if it's a known game or has "game" in name
    hsin_game_is_known "$_pkg" && return 0
    case "$_pkg" in
        *game*|*Game*|*GAME*) return 0 ;;
    esac

    return 1
}

# Get game mode based on detection
hsin_game_mode() {
    if hsin_game_is_running; then
        echo "gaming"
    else
        echo "unknown"
    fi
}

return 0 2>/dev/null || true
