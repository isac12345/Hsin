#!/system/bin/sh
# HSIN SurfaceFlinger Toggle
#
# Scope by design, same philosophy as engine/render/renderer.sh: only
# ships resetprop switches that are documented/confirmed-safe AOSP
# SurfaceFlinger debug props. Deliberately excludes anything that risks
# a black screen / SystemUI crash loop (e.g. forcing GPU composition off
# entirely, or touching hwc service props directly).
#
# What this toggles ON (performance-leaning, matches Stellar's
# "surfaceflinger" utility toggle):
#   debug.sf.latch_unsignaled=1        - let SF latch buffers before their
#                                         fence signals, cutting a frame of
#                                         input latency on some GPU drivers
#   debug.sf.enable_gl_backpressure=0  - don't block the app's render
#                                         thread waiting on the previous
#                                         frame's GL fence
# Both are read at SurfaceFlinger's own start-up in most AOSP versions,
# so a live toggle restarts surfaceflinger via `stop surfaceflinger` /
# `start surfaceflinger` to pick the new values up immediately - this is
# the same safe restart AOSP itself does for a display-service prop
# change, but it DOES blank the screen for a fraction of a second.

[ -z "$HSIN_MODULE_PATH" ] && HSIN_MODULE_PATH="/data/adb/modules/hsin"
HSIN_DATA="${HSIN_DATA:-/data/adb/hsin}"

_hsin_sf_setprop() {
    resetprop "$1" "$2" 2>/dev/null || setprop "$1" "$2" 2>/dev/null
}
_hsin_sf_delprop() {
    resetprop --delete "$1" 2>/dev/null
}
_hsin_sf_log() {
    mkdir -p "$HSIN_DATA/logs" 2>/dev/null
    echo "$(date '+%Y-%m-%d %H:%M:%S') $1" >> "$HSIN_DATA/logs/surfaceflinger.log" 2>/dev/null
}

# Boot-time apply (post-fs-data, before SF's own first start - no restart
# needed, it just reads these at its normal startup).
hsin_sf_apply_boot() {
    _enable="${1:-false}"
    [ "$_enable" = "true" ] || return 0
    _hsin_sf_setprop "debug.sf.latch_unsignaled" "1"
    _hsin_sf_setprop "debug.sf.enable_gl_backpressure" "0"
    _hsin_sf_log "boot apply: enabled"
}

# Live apply/restore - restarts surfaceflinger so the prop change is
# actually picked up (screen blanks briefly, same as any SF prop change).
hsin_sf_apply_live() {
    _enable="${1:-false}"
    if [ "$_enable" = "true" ]; then
        _hsin_sf_setprop "debug.sf.latch_unsignaled" "1"
        _hsin_sf_setprop "debug.sf.enable_gl_backpressure" "0"
        _action="enabled"
    else
        _hsin_sf_delprop "debug.sf.latch_unsignaled"
        _hsin_sf_delprop "debug.sf.enable_gl_backpressure"
        _action="disabled"
    fi

    if command -v stop >/dev/null 2>&1 && command -v start >/dev/null 2>&1; then
        stop surfaceflinger 2>/dev/null
        sleep 1
        start surfaceflinger 2>/dev/null
        _restarted="yes"
    else
        _restarted="no (stop/start unavailable, takes effect next reboot)"
    fi

    _hsin_sf_log "live apply: $_action, restarted=$_restarted"
    echo "OK: SurfaceFlinger tweak $_action (restarted: $_restarted)"
}

hsin_sf_status() {
    echo "  SurfaceFlinger State:"
    printf "    latch_unsignaled:       %s\n" "$(getprop debug.sf.latch_unsignaled 2>/dev/null)"
    printf "    enable_gl_backpressure: %s\n" "$(getprop debug.sf.enable_gl_backpressure 2>/dev/null)"
}

# hsin.conf key: SURFACEFLINGER_TWEAK_ENABLED=false
hsin_sf_apply_from_conf() {
    _conf="${1:-$HSIN_MODULE_PATH/config/hsin.conf}"
    [ -f "$_conf" ] || return 0
    _enabled=false
    while IFS='=' read -r _k _v || [ -n "$_k" ]; do
        [ "$_k" = "SURFACEFLINGER_TWEAK_ENABLED" ] && _enabled="$_v"
    done < "$_conf"
    hsin_sf_apply_boot "$_enabled"
}

hsin_sf_main() {
    _action="${1:-status}"
    case "$_action" in
        enable) hsin_sf_apply_live "true" ;;
        disable) hsin_sf_apply_live "false" ;;
        status) hsin_sf_status ;;
        *) echo "Usage: hsin surfaceflinger <enable|disable|status>" ;;
    esac
}

return 0 2>/dev/null || true
