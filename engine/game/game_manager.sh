#!/system/bin/sh
# HSIN Game Detection Engine - Manager
# Credit: logic inspired by FAS-RS (FPS/game management)

[ -z "$HSIN_MODULE_PATH" ] && HSIN_MODULE_PATH="/data/adb/modules/hsin"
HSIN_DATA="${HSIN_DATA:-/data/adb/hsin}"

# Load dependencies
. "$HSIN_MODULE_PATH/core/logger.sh" 2>/dev/null
. "$HSIN_MODULE_PATH/engine/game/detector.sh" 2>/dev/null

# Game mode state
HSIN_GAME_MODE="normal"

# Check and update game mode
hsin_game_check() {
    if hsin_game_is_running; then
        HSIN_GAME_MODE="gaming"
        return 0
    else
        HSIN_GAME_MODE="normal"
        return 1
    fi
}

# Rank profiles so we can pick the "higher" of two - never used to
# downgrade a profile the user already picked manually, only to boost.
_hsin_profile_rank() {
    case "$1" in
        battery) echo 0 ;;
        balanced) echo 1 ;;
        performance) echo 2 ;;
        extreme) echo 3 ;;
        *) echo 1 ;;
    esac
}

# Get effective profile based on game mode
# $1 = base profile, $2 = foreground package (optional; if omitted,
# hsin_game_detect is called as fallback for backward-compat callers
# like `hsin_game_main effective`).  Passing $2 explicitly avoids a
# second independent detection call that can race with the caller's
# own detection (Bug F fix).
hsin_game_effective_profile() {
    _requested="$1"
    _pkg="${2:-}"

    # Skip manual mode: game boost tidak aktif di mode manual
    if [ "$_requested" = "manual" ]; then
        # Log ke stderr (bukan stdout — stdout dipakai command substitution)
        echo "game boost tidak aktif di mode manual" >&2
        # Tidak ubah stdout: hanya echo manual untuk command substitution
        echo "manual"
        return 0
    fi

    if [ -z "$_pkg" ]; then
        _pkg=$(hsin_game_detect)
    fi
    [ -z "$_pkg" ] && { echo "$_requested"; return 0; }

    # `_is_boostable`=0 means "we'll boost for this game", =1 means
    # "fall through to whatever the user requested" (named confusingly in
    # an earlier draft, kept the semantics but renamed the var so the
    # next reader doesn't have to mentally invert it).
    _is_boostable=1
    hsin_game_is_known "$_pkg" && _is_boostable=0
    if [ "$_is_boostable" -ne 0 ]; then
        case "$_pkg" in
            *game*|*Game*|*GAME*) _is_boostable=0 ;;
        esac
    fi
    [ "$_is_boostable" -ne 0 ] && { echo "$_requested"; return 0; }

    # Per-game mapping from games.conf if listed there, else the old
    # blanket default of "performance" for any detected/known game.
    _mapped=$(hsin_game_mapped_profile "$_pkg" 2>/dev/null)
    [ -z "$_mapped" ] && _mapped="performance"
    # Defensive: if the games.conf line is corrupt and the mapped profile
    # isn't a known profile name, fall back to "performance" rather than
    # echoing garbage that breaks the rank comparison below.
    case "$_mapped" in
        battery|balanced|performance|extreme) ;;
        *) _mapped="performance" ;;
    esac

    _req_rank=$(_hsin_profile_rank "$_requested")
    _map_rank=$(_hsin_profile_rank "$_mapped")

    if [ "$_map_rank" -gt "$_req_rank" ]; then
        echo "$_mapped"
    else
        echo "$_requested"
    fi
}

# Print game detection status
hsin_game_status() {
    echo ""
    echo "╔══════════════════════════════════════╗"
    echo "║   Game Detection Status              ║"
    echo "╚══════════════════════════════════════╝"
    echo ""

    _pkg=$(hsin_game_detect)
    if [ -n "$_pkg" ]; then
        _is_known="no"
        hsin_game_is_known "$_pkg" && _is_known="yes"
        printf "  Foreground:  %s\n" "$_pkg"
        printf "  Known Game:  %s\n" "$_is_known"
        printf "  Mode:        GAMING\n"
    else
        printf "  Foreground:  none\n"
        printf "  Mode:        NORMAL\n"
    fi
    echo ""
}

# CLI interface
hsin_game_main() {
    _action="${1:-help}"

    case "$_action" in
        detect)
            hsin_game_status
            ;;
        check)
            hsin_game_check && echo "Game detected" || echo "No game"
            ;;
        effective)
            _profile="${2:-balanced}"
            _eff=$(hsin_game_effective_profile "$_profile")
            echo "Requested: $_profile -> Effective: $_eff"
            ;;
        help|*)
            echo "HSIN Game Detection Engine"
            echo ""
            echo "Usage: hsin game <action>"
            echo ""
            echo "Actions:"
            echo "  detect              Detect game status"
            echo "  check               Check if game running"
            echo "  effective <profile> Get effective profile"
            echo "  help                Show this help"
            ;;
    esac
}

# ===== Game list management (backs the WebUI "Add Game" picker) =====

# Rewrite games.conf without the given package (helper for add/remove)
_hsin_game_conf_remove_pkg() {
    _target="$1"
    [ -f "$HSIN_GAMES_CONF" ] || return 0
    _tmp="${HSIN_GAMES_CONF}.tmp.$$"
    : > "$_tmp"
    while IFS= read -r _line || [ -n "$_line" ]; do
        case "$_line" in
            ""|"#"*) printf '%s\n' "$_line" >> "$_tmp"; continue ;;
        esac
        [ "${_line%%:*}" = "$_target" ] && continue
        printf '%s\n' "$_line" >> "$_tmp"
    done < "$HSIN_GAMES_CONF"
    mv "$_tmp" "$HSIN_GAMES_CONF"
}

# Emit games.conf as a JSON array: [{"package":"...","profile":"..."}]
hsin_game_list_conf() {
    [ -f "$HSIN_GAMES_CONF" ] || { echo "[]"; return 0; }
    _out="["
    _first=1
    while IFS= read -r _line || [ -n "$_line" ]; do
        case "$_line" in
            ""|"#"*) continue ;;
        esac
        _pkg="${_line%%:*}"
        case "$_line" in
            *:*) _prof="${_line#*:}" ;;
            *) _prof="performance" ;;
        esac
        [ "$_first" -eq 0 ] && _out="${_out},"
        _out="${_out}{\"package\":\"${_pkg}\",\"profile\":\"${_prof}\"}"
        _first=0
    done < "$HSIN_GAMES_CONF"
    echo "${_out}]"
}

# Add (or update) a game's mapped profile
hsin_game_add() {
    _pkg="$1"
    _profile="${2:-performance}"
    [ -z "$_pkg" ] && { echo "ERROR: package required"; return 1; }
    case "$_profile" in
        battery|balanced|performance|extreme) : ;;
        *) echo "ERROR: invalid profile: $_profile"; return 1 ;;
    esac
    # Safety net: reject the default HOME launcher even if the picker
    # somehow let it through.
    _launcher=$(_hsin_detect_default_launcher)
    if [ -n "$_launcher" ] && [ "$_pkg" = "$_launcher" ]; then
        echo "ERROR: $_pkg is the default launcher, not a game"
        return 1
    fi
    case "$_pkg" in
        *launcher*|*Launcher*)
            echo "ERROR: $_pkg looks like a launcher, not a game"
            return 1 ;;
    esac
    [ -f "$HSIN_GAMES_CONF" ] || : > "$HSIN_GAMES_CONF"
    _hsin_game_conf_remove_pkg "$_pkg"
    printf '%s:%s\n' "$_pkg" "$_profile" >> "$HSIN_GAMES_CONF"
    echo "OK: $_pkg -> $_profile"
}

# Remove a game from the list entirely
hsin_game_remove() {
    _pkg="$1"
    [ -z "$_pkg" ] && { echo "ERROR: package required"; return 1; }
    [ -f "$HSIN_GAMES_CONF" ] || { echo "ERROR: games.conf not found"; return 1; }
    _hsin_game_conf_remove_pkg "$_pkg"
    echo "OK: removed $_pkg"
}

# Helper: detect the device's default HOME launcher package.  Works across
# all OEMs - no hardcoded vendor names needed.
_hsin_detect_default_launcher() {
    # Method 1: cmd package (Android 10+)
    _lpkg=""
    if command -v cmd >/dev/null 2>&1; then
        _lpkg=$(cmd package resolve-activity --brief -a android.intent.action.MAIN -c android.intent.category.HOME 2>/dev/null | tail -1 | cut -d/ -f1)
    fi
    # Method 2: pm resolve-activity fallback (older Android)
    if [ -z "$_lpkg" ] && command -v pm >/dev/null 2>&1; then
        _lpkg=$(pm resolve-activity -a android.intent.action.MAIN -c android.intent.category.HOME 2>/dev/null | grep -m1 "package:" | sed 's/.*package:\([^ ]*\).*/\1/')
    fi
    echo "$_lpkg"
}

# List installed third-party apps as a JSON array of package name strings,
# minus a blocklist of common non-game apps (messaging, social, OEM system
# apps) so the WebUI picker doesn't get cluttered with WhatsApp etc. This
# can't show human-readable app names or icons - a plain root shell has no
# reliable way to pull those without a companion app, so the picker works
# off package names only (still recognizable for most games).
hsin_game_list_installed() {
    command -v pm >/dev/null 2>&1 || { echo "[]"; return 0; }

    # Detect the current default HOME launcher once upfront so we can
    # exclude it regardless of vendor name.
    _default_launcher=$(_hsin_detect_default_launcher)

    _pkgs=$(pm list packages -3 2>/dev/null | sed 's/^package://' | sort)
    _out="["
    _first=1
    _old_ifs="$IFS"
    IFS='
'
    for _pkg in $_pkgs; do
        IFS="$_old_ifs"
        [ -z "$_pkg" ] && continue
        # Generic: exclude the default HOME launcher (any vendor)
        [ "$_pkg" = "$_default_launcher" ] && { IFS='
'; continue; }
        case "$_pkg" in
            com.whatsapp|com.facebook.*|com.instagram.android|com.google.android.*|\
            com.android.*|com.samsung.*|com.sec.android.*|com.miui.*|com.xiaomi.*|\
            com.oppo.*|com.coloros.*|com.vivo.*|com.microsoft.*|org.telegram.*|\
            com.twitter.android|com.snapchat.android|com.spotify.music|\
            com.netflix.mediaclient|com.zhiliaoapp.musically|com.ss.android.*|\
            com.unisoc.*|com.sprd.*)
                IFS='
'
                continue ;;
        esac
        # Fallback pattern: anything that looks like a launcher
        case "$_pkg" in
            *launcher*|*Launcher*) IFS='
'; continue ;;
        esac
        # Already added via the picker before - don't show it again.
        hsin_game_is_known "$_pkg" && { IFS='
'; continue; }
        [ "$_first" -eq 0 ] && _out="${_out},"
        _out="${_out}\"${_pkg}\""
        _first=0
        IFS='
'
    done
    IFS="$_old_ifs"
    echo "${_out}]"
}

return 0 2>/dev/null || true
