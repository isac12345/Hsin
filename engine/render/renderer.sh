#!/system/bin/sh
# HSIN Render Engine - Skia backend switcher (GL/Vulkan)
#
# Scope by design: only ships props that are (a) documented/real AOSP HWUI
# switches or (b) harmless dirty-region hints. Deliberately excludes:
#   - hwui.disable_vsync            -> causes tearing, not a real fix for stutter
#   - debug.vulkan.layers.enable    -> validation layer, adds overhead, debug-only
#   - *SkiaTracingFeature*          -> tracing/profiling flag, not a perf tweak
#   - ro.ui.pipeline / ro.hwui.*    -> read-only build props, resetprop on these
#                                      is unreliable across vendors and two of
#                                      the values seen in the wild directly
#                                      contradict each other (skiavk vs vulkan)
# See /areas/hsin.md for the audit this was based on.

[ -z "$HSIN_MODULE_PATH" ] && HSIN_MODULE_PATH="/data/adb/modules/hsin"
HSIN_DATA="${HSIN_DATA:-/data/adb/hsin}"

# Valid renderer targets. "system" means: don't touch it, let the vendor
# default stand (some devices ship a Vulkan driver mature enough to be the
# sane default already - never assume GL is universally safer).
hsin_render_valid_target() {
    case "$1" in
        skiagl|skiavk|system) return 0 ;;
        *) return 1 ;;
    esac
}

# Read the renderer HWUI is currently using (live, from getprop).
hsin_render_current() {
    getprop debug.hwui.renderer 2>/dev/null
}

# Apply the safe tier-1 prop set for a given target. Only touches props that
# are confirmed real AOSP/HWUI switches.
_hsin_render_set_props() {
    _target="$1"

    case "$_target" in
        skiagl|skiavk)
            # NOTE: must NOT use "resetprop -n" here - that flag means
            # "only set if the prop doesn't already exist yet", and
            # debug.hwui.renderer ships pre-set (often empty) on stock
            # Android, so -n silently no-ops and the || setprop fallback
            # never fires because resetprop still exits 0. Force it.
            resetprop debug.hwui.renderer "$_target" 2>/dev/null \
                || setprop debug.hwui.renderer "$_target" 2>/dev/null
            ;;
        system)
            # Clear our override so the vendor/system default takes over
            # again. resetprop --delete falls back to a plain unset if the
            # bridge doesn't support deletion.
            resetprop --delete debug.hwui.renderer 2>/dev/null
            ;;
    esac

    # Dirty-region redraw: real HWUI flag, reduces full-screen redraws.
    # Safe at every profile including battery - this is a "do less work"
    # optimization, not an aggressive one.
    case "$_target" in
        skiagl|skiavk)
            resetprop debug.hwui.render_dirty_regions true 2>/dev/null \
                || setprop debug.hwui.render_dirty_regions true 2>/dev/null
            ;;
    esac
}

# Force-stop all third-party (user-installed) apps so they respawn under the
# new renderer immediately, without a full device reboot. System/vendor
# processes are left untouched on purpose - force-stopping those can crash
# SystemUI/launcher into a loop.
hsin_render_restart_apps() {
    _n=0
    for _pkg in $(pm list packages -3 2>/dev/null | sed 's/^package://'); do
        [ -n "$_pkg" ] || continue
        am force-stop "$_pkg" 2>/dev/null && _n=$((_n + 1))
    done
    echo "$_n"
}

# Boot-time apply: called from post-fs-data.sh, before Zygote spawns the
# first app. No force-stop needed here - nothing has launched yet, so every
# app just inherits the prop on first spawn.
hsin_render_apply_boot() {
    _target="$1"
    hsin_render_valid_target "$_target" || return 1
    [ "$_target" = "system" ] && return 0   # nothing to do, leave vendor default
    _hsin_render_set_props "$_target"
    return 0
}

# Live apply: called from the WebUI / action.sh while the system is already
# booted. Sets the prop then force-stops user apps so the change is visible
# immediately, without requiring a device reboot.
hsin_render_apply_live() {
    _target="$1"
    hsin_render_valid_target "$_target" || { echo "ERROR: invalid renderer target: $_target"; return 1; }

    _before=$(hsin_render_current)
    if [ "$_target" != "system" ] && [ "$_before" = "$_target" ]; then
        echo "OK: renderer already $_target (no change)"
        return 0
    fi

    _hsin_render_set_props "$_target"
    _restarted=$(hsin_render_restart_apps)

    _log_dir="$HSIN_DATA/logs"
    mkdir -p "$_log_dir" 2>/dev/null
    echo "$(date '+%Y-%m-%d %H:%M:%S') renderer: $_before -> $_target (apps_restarted=$_restarted)" \
        >> "$_log_dir/renderer.log" 2>/dev/null

    echo "OK: renderer set to $_target, $_restarted app(s) restarted"
    return 0
}

hsin_render_state() {
    _current=$(hsin_render_current)
    [ -z "$_current" ] && _current="(system default)"
    echo "  Renderer State:"
    printf "    debug.hwui.renderer:      %s\n" "$_current"
    printf "    render_dirty_regions:     %s\n" "$(getprop debug.hwui.render_dirty_regions 2>/dev/null)"
}

# CLI interface
hsin_render_main() {
    _action="${1:-help}"
    _target="${2:-system}"

    case "$_action" in
        apply-boot)
            hsin_render_apply_boot "$_target"
            ;;
        apply)
            hsin_render_apply_live "$_target"
            ;;
        state)
            hsin_render_state
            ;;
        current)
            hsin_render_current
            ;;
        help|*)
            echo "HSIN Render Engine"
            echo ""
            echo "Usage: hsin render <action> [target]"
            echo ""
            echo "Actions:"
            echo "  apply-boot <target>   Apply at boot (post-fs-data, no restart needed)"
            echo "  apply <target>        Apply live (force-stops 3rd-party apps)"
            echo "  state                 Show current renderer state"
            echo "  current               Print raw debug.hwui.renderer value"
            echo ""
            echo "Targets: skiagl | skiavk | system (leave vendor default)"
            ;;
    esac
}

return 0 2>/dev/null || true
