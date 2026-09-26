#!/system/bin/sh
# HSIN Frame Rate Limit Disabler (system-wide)
#
# Different from refresh_rate.sh: that controls the PANEL's Hz mode
# (peak/min_refresh_rate). This controls SurfaceFlinger's internal FPS
# throttle/software cap that some OEM skins (and a few stock builds)
# apply on top of the panel mode, silently capping composited frames
# below the panel's actual refresh rate even when the panel itself is
# already running at e.g. 120Hz. Applies system-wide (every app), not
# per-package, per user's explicit request.
#
# All props here are documented resetprop-safe AOSP/SurfaceFlinger
# debug switches, same safety scope as engine/render/renderer.sh - no
# kernel/sysfs paths touched, so this never risks the blacklist.

[ -z "$HSIN_MODULE_PATH" ] && HSIN_MODULE_PATH="/data/adb/modules/hsin"
HSIN_DATA="${HSIN_DATA:-/data/adb/hsin}"

_hsin_frl_setprop() {
    _key="$1"; _val="$2"
    resetprop "$_key" "$_val" 2>/dev/null || setprop "$_key" "$_val" 2>/dev/null
}

_hsin_frl_delprop() {
    resetprop --delete "$1" 2>/dev/null
}

_hsin_frl_log() {
    mkdir -p "$HSIN_DATA/logs" 2>/dev/null
    echo "$(date '+%Y-%m-%d %H:%M:%S') $1" >> "$HSIN_DATA/logs/frame_limit.log" 2>/dev/null
}

# Disable the software FPS cap: raises/removes SurfaceFlinger's frame-rate
# override so composited output isn't throttled below the panel's actual
# active mode. debug.sf.frame_rate_multiple_threshold=0 turns off SF's
# "only allow specific multiples of the frame rate" heuristic; the fps
# override at -1 tells SF "no override, use whatever the panel is doing".
hsin_frame_limit_disable() {
    _hsin_frl_setprop "debug.sf.disable_backpressure" "1"
    _hsin_frl_setprop "debug.sf.frame_rate_multiple_threshold" "0"
    _hsin_frl_setprop "debug.sf.fps_override" "-1"
    _hsin_frl_log "frame rate limit disabled (system-wide)"
    echo "OK: system-wide frame rate limit disabled"
}

# Restore SurfaceFlinger's default throttle behavior.
hsin_frame_limit_restore() {
    _hsin_frl_delprop "debug.sf.disable_backpressure"
    _hsin_frl_delprop "debug.sf.frame_rate_multiple_threshold"
    _hsin_frl_delprop "debug.sf.fps_override"
    _hsin_frl_log "frame rate limit restored to system default"
    echo "OK: frame rate limit restored to system default"
}

hsin_frame_limit_status() {
    echo "  Frame Rate Limit State:"
    printf "    disable_backpressure:         %s\n" "$(getprop debug.sf.disable_backpressure 2>/dev/null)"
    printf "    frame_rate_multiple_threshold: %s\n" "$(getprop debug.sf.frame_rate_multiple_threshold 2>/dev/null)"
    printf "    fps_override:                  %s\n" "$(getprop debug.sf.fps_override 2>/dev/null)"
}

# hsin.conf key: FRAME_RATE_LIMIT_DISABLED=false
hsin_frame_limit_apply_from_conf() {
    _conf="${1:-$HSIN_MODULE_PATH/config/hsin.conf}"
    [ -f "$_conf" ] || return 0
    _enabled=false
    while IFS='=' read -r _k _v || [ -n "$_k" ]; do
        [ "$_k" = "FRAME_RATE_LIMIT_DISABLED" ] && _enabled="$_v"
    done < "$_conf"

    if [ "$_enabled" = "true" ]; then
        hsin_frame_limit_disable
    else
        hsin_frame_limit_restore
    fi
}

hsin_frame_limit_main() {
    _action="${1:-status}"
    case "$_action" in
        disable) hsin_frame_limit_disable ;;
        restore|enable) hsin_frame_limit_restore ;;
        status) hsin_frame_limit_status ;;
        *) echo "Usage: hsin framelimit <disable|restore|status>" ;;
    esac
}

return 0 2>/dev/null || true
