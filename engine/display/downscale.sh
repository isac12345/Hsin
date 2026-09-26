#!/system/bin/sh
# HSIN Display Downscale Engine
#
# System-wide (not per-game) resolution downscale. Unlike game auto-boost,
# this changes `wm size` for the whole OS - launcher, settings, every app -
# and stays applied across reboots until the user explicitly disables it.
# Density is left untouched, so icons/text/UI elements keep their normal
# physical size; only the render resolution drops, which is what actually
# saves the compositor/GPU fill-rate work that causes stutter on a heavy
# stock UI.
#
# Native resolution is captured ONCE, the very first time this runs on a
# device, into a file under $HSIN_DATA. This is critical: `wm size` is
# stateful, so if we ever tried to re-detect "native" by reading `wm size`
# after a downscale was already applied, we'd read back the downscaled
# value and lock the user out of ever recovering their true native res.
#
# Requires: HSIN_DATA exported by the caller (service.sh / action.sh both
# already export it).

HSIN_DOWNSCALE_NATIVE_FILE="$HSIN_DATA/native_res"
HSIN_DOWNSCALE_NATIVE_DENSITY_FILE="$HSIN_DATA/native_density"
HSIN_DOWNSCALE_DEFAULT_PERCENT=30   # fallback if caller doesn't pass one
HSIN_DOWNSCALE_MIN_SHORT_SIDE=144   # hard floor: shortest side never goes below 144px (~144p)

# Round a number DOWN to the nearest even value. Odd surface dimensions
# can cause chroma subsampling / codec issues on some SurfaceFlinger
# implementations, so we stay even to be safe.
_hsin_downscale_round_even() {
    _n="$1"
    _rem=$((_n % 2))
    if [ "$_rem" -ne 0 ]; then
        _n=$((_n - 1))
    fi
    echo "$_n"
}

# Validates a percent string is an integer from 1 to 99 inclusive. Prints
# nothing; just sets the exit code. 0% would mean "no change" (pointless
# toggle) and 100% would mean "zero resolution" (crashes everything), so
# both ends are excluded on purpose - the slider range should match this.
_hsin_downscale_valid_percent() {
    case "$1" in
        ''|*[!0-9]*) return 1 ;;
    esac
    [ "$1" -ge 1 ] && [ "$1" -le 99 ]
}

# Reads the CURRENT `wm size` (physical line only, ignoring any "Override
# size" line) and prints it as "WIDTHxHEIGHT". This is only ever safe to
# treat as "native" the very first time the module runs, before any
# override has been written - hsin_downscale_capture_native() guards that.
_hsin_downscale_read_physical_size() {
    wm size 2>/dev/null | grep '^Physical size:' | sed 's/^Physical size: //' | tr -d '[:space:]'
}

# Same idea but for `wm density` - prints the physical (native) DPI value
# only, ignoring any "Override density" line.
_hsin_downscale_read_physical_density() {
    wm density 2>/dev/null | grep '^Physical density:' | sed 's/^Physical density: //' | tr -d '[:space:]'
}

# Capture native resolution AND density to disk, but ONLY if we haven't
# already. Safe to call unconditionally on every boot - it's a no-op
# after the first successful capture. Density capture failing does not
# block resolution capture (older/weirder ROMs may not print a density
# line the same way) - hsin_downscale_apply() falls back to a computed
# default density if native_density was never captured.
hsin_downscale_capture_native() {
    if [ ! -f "$HSIN_DOWNSCALE_NATIVE_FILE" ]; then
        _phys="$(_hsin_downscale_read_physical_size)"
        case "$_phys" in
            [0-9]*x[0-9]*)
                echo "$_phys" > "$HSIN_DOWNSCALE_NATIVE_FILE" 2>/dev/null
                ;;
        esac
    fi

    if [ ! -f "$HSIN_DOWNSCALE_NATIVE_DENSITY_FILE" ]; then
        _dens="$(_hsin_downscale_read_physical_density)"
        case "$_dens" in
            [0-9]*)
                echo "$_dens" > "$HSIN_DOWNSCALE_NATIVE_DENSITY_FILE" 2>/dev/null
                ;;
        esac
    fi

    [ -f "$HSIN_DOWNSCALE_NATIVE_FILE" ]
}

# Prints "WIDTHxHEIGHT" for native resolution, or nothing (+ exit 1) if
# it was never captured (e.g. this boot is the very first run and `wm`
# wasn't ready yet - caller should retry next boot).
hsin_downscale_get_native() {
    [ -f "$HSIN_DOWNSCALE_NATIVE_FILE" ] || return 1
    cat "$HSIN_DOWNSCALE_NATIVE_FILE" 2>/dev/null
}

# Prints native DPI, or nothing (+ exit 1) if it was never captured.
hsin_downscale_get_native_density() {
    [ -f "$HSIN_DOWNSCALE_NATIVE_DENSITY_FILE" ] || return 1
    cat "$HSIN_DOWNSCALE_NATIVE_DENSITY_FILE" 2>/dev/null
}

# Computes the EFFECTIVE keep-percent for a requested cut percent,
# clamped so the shortest native side never drops below
# HSIN_DOWNSCALE_MIN_SHORT_SIDE. This is the single source of truth for
# the clamp - both hsin_downscale_calc_target() and
# hsin_downscale_calc_density() call this so resolution and density are
# guaranteed to always scale by the identical factor, even when the
# floor kicks in. Prints an integer 1-100, or nothing (+ exit 1) if
# native res isn't known yet or the percent is out of range.
_hsin_downscale_effective_keep_percent() {
    _percent="$1"
    _hsin_downscale_valid_percent "$_percent" || return 1

    _native="$(hsin_downscale_get_native)" || return 1
    _nw="${_native%x*}"
    _nh="${_native#*x}"
    case "$_nw" in ''|*[!0-9]*) return 1 ;; esac
    case "$_nh" in ''|*[!0-9]*) return 1 ;; esac

    _short_side="$_nw"
    [ "$_nh" -lt "$_short_side" ] && _short_side="$_nh"

    _keep_percent=$((100 - _percent))

    # Minimum keep-percent that still keeps the shortest side >= floor,
    # rounded UP (ceiling division) so we never land one pixel under the
    # floor due to integer truncation.
    _min_keep_percent=$(( (HSIN_DOWNSCALE_MIN_SHORT_SIDE * 100 + _short_side - 1) / _short_side ))
    if [ "$_keep_percent" -lt "$_min_keep_percent" ]; then
        _keep_percent="$_min_keep_percent"
    fi
    [ "$_keep_percent" -gt 100 ] && _keep_percent=100

    echo "$_keep_percent"
}

# Computes the downscaled target from the stored native resolution,
# keeping aspect ratio exact (integer math, so we scale width and height
# by the identical fraction rather than recalculating one from the other's
# ratio - that avoids rounding drift bending the aspect ratio slightly).
#
# The requested percent is clamped so the shortest side never drops below
# HSIN_DOWNSCALE_MIN_SHORT_SIDE (144px, ~144p) - a slider that goes all
# the way to 99% would otherwise ask for something like 7x16 on a normal
# phone panel, which SurfaceFlinger will refuse or choke on. The clamp
# scales BOTH sides together (same keep-percent) so aspect ratio is never
# distorted by the floor - only how far down we're allowed to go changes.
#
# $1 = percent to cut (1-99), defaults to HSIN_DOWNSCALE_DEFAULT_PERCENT.
# Prints "WIDTHxHEIGHT", or nothing (+ exit 1) if native isn't known yet
# or the percent given is out of range.
hsin_downscale_calc_target() {
    _percent="${1:-$HSIN_DOWNSCALE_DEFAULT_PERCENT}"

    _native="$(hsin_downscale_get_native)" || return 1
    _nw="${_native%x*}"
    _nh="${_native#*x}"
    case "$_nw" in ''|*[!0-9]*) return 1 ;; esac
    case "$_nh" in ''|*[!0-9]*) return 1 ;; esac

    _keep_percent="$(_hsin_downscale_effective_keep_percent "$_percent")" || return 1

    _tw=$(( _nw * _keep_percent / 100 ))
    _th=$(( _nh * _keep_percent / 100 ))

    _tw="$(_hsin_downscale_round_even "$_tw")"
    _th="$(_hsin_downscale_round_even "$_th")"

    # Guard against a degenerate 0x0 or 0xN result on extreme percent +
    # tiny native res combos - wm size would just error out on that
    # anyway, better to fail here with a clear reason.
    [ "$_tw" -gt 0 ] && [ "$_th" -gt 0 ] || return 1

    echo "${_tw}x${_th}"
}

# Computes the downscaled density using the EXACT same keep-percent as
# the resolution, so px-per-dp stays constant and every UI element keeps
# its real physical/visual size - only the actual pixel grid gets
# coarser, which is what saves the compositor/GPU work. This is the
# missing piece from the first version of this feature: shrinking
# resolution alone without also shrinking density makes Android treat
# the screen as having a much higher-density-relative-to-size, so every
# dp-based UI element renders proportionally larger on screen.
# $1 = percent to cut (1-99), defaults to HSIN_DOWNSCALE_DEFAULT_PERCENT.
# Prints an integer DPI, or nothing (+ exit 1) if native density isn't
# known yet or the percent is out of range.
# Computes the downscaled density using the EXACT same effective
# keep-percent as the resolution (including the 144p floor clamp), so
# px-per-dp stays constant and every UI element keeps its real
# physical/visual size - only the actual pixel grid gets coarser, which
# is what saves the compositor/GPU work. This is the missing piece from
# the first version of this feature: shrinking resolution alone without
# also shrinking density makes Android treat the screen as having a
# much higher-density-relative-to-size, so every dp-based UI element
# renders proportionally larger on screen.
# $1 = percent to cut (1-99), defaults to HSIN_DOWNSCALE_DEFAULT_PERCENT.
# Prints an integer DPI, or nothing (+ exit 1) if native density isn't
# known yet or the percent is out of range.
hsin_downscale_calc_density() {
    _percent="${1:-$HSIN_DOWNSCALE_DEFAULT_PERCENT}"

    _native_dpi="$(hsin_downscale_get_native_density)" || return 1
    case "$_native_dpi" in ''|*[!0-9]*) return 1 ;; esac

    _keep_percent="$(_hsin_downscale_effective_keep_percent "$_percent")" || return 1
    _target_dpi=$(( _native_dpi * _keep_percent / 100 ))
    [ "$_target_dpi" -gt 0 ] || return 1

    echo "$_target_dpi"
}

# Restarts the HOME launcher (and SystemUI) so icon/text sizes actually
# refresh after a `wm size`/`wm density` change. This is the fix for
# "kadang icon gede/kecil semua sampai reboot": `wm size`/`wm density`
# DO broadcast a config change immediately, but a lot of OEM launchers
# (and SystemUI, for the status bar / recents) only recompute their
# icon-grid cell size and cached icon bitmaps once, at process start -
# they don't relayout on a live config change. A full reboot "fixes" it
# only because it restarts those processes anyway; force-stopping just
# the two of them gets the same result in under a second and without
# killing whatever app the user currently has open.
# Self-contained on purpose (duplicates the launcher-detection one-liner
# from game_manager.sh) so downscale.sh doesn't need to source another
# engine file just for this.
_hsin_downscale_kick_ui() {
    _lpkg=""
    if command -v cmd >/dev/null 2>&1; then
        _lpkg=$(cmd package resolve-activity --brief -a android.intent.action.MAIN -c android.intent.category.HOME 2>/dev/null | tail -1 | cut -d/ -f1)
    fi
    if [ -z "$_lpkg" ] && command -v pm >/dev/null 2>&1; then
        _lpkg=$(pm resolve-activity -a android.intent.action.MAIN -c android.intent.category.HOME 2>/dev/null | grep -m1 "package:" | sed 's/.*package:\([^ ]*\).*/\1/')
    fi
    [ -n "$_lpkg" ] && am force-stop "$_lpkg" 2>/dev/null

    # SystemUI is restarted automatically by system_server right after
    # this - status bar/quick settings/recents icons pick up the new
    # density the same way the launcher does.
    am force-stop com.android.systemui 2>/dev/null
}

# Applies the computed downscaled resolution AND density system-wide,
# together, so UI elements keep their real physical size while the
# actual render resolution drops. $1 = percent to cut (1-99), defaults
# to HSIN_DOWNSCALE_DEFAULT_PERCENT.
hsin_downscale_apply() {
    _percent="${1:-$HSIN_DOWNSCALE_DEFAULT_PERCENT}"
    _target="$(hsin_downscale_calc_target "$_percent")" || {
        echo "ERROR: could not compute target (native res unknown or percent out of range)" >&2
        return 1
    }
    wm size "$_target" 2>/dev/null

    # Density is best-effort: if native density was never captured (e.g.
    # a very old capture from before this feature existed, or a device
    # whose `wm density` output didn't match our parser), we still keep
    # the resolution change rather than failing the whole apply - a
    # slightly-off UI scale beats no downscale at all.
    _target_dpi="$(hsin_downscale_calc_density "$_percent" 2>/dev/null)"
    if [ -n "$_target_dpi" ]; then
        wm density "$_target_dpi" 2>/dev/null
    fi

    _hsin_downscale_kick_ui
}

# Restores true native resolution AND density, clearing both overrides
# entirely (`wm size reset` / `wm density reset`, not `wm size <native>` -
# this fully removes HSIN's override lines so `wm size`/`wm density`
# report back clean, exactly as if downscale had never run).
hsin_downscale_reset() {
    wm size reset 2>/dev/null
    wm density reset 2>/dev/null
    _hsin_downscale_kick_ui
}

# Status line for the WebUI: native, current override (if any), and
# whether the feature is presently enabled per hsin.conf. Caller passes
# in the enabled flag and the saved percent (both only action.sh knows
# how to read from hsin.conf). Prints a small JSON object.
hsin_downscale_status() {
    _enabled="${1:-false}"
    _percent="${2:-$HSIN_DOWNSCALE_DEFAULT_PERCENT}"
    _hsin_downscale_valid_percent "$_percent" || _percent="$HSIN_DOWNSCALE_DEFAULT_PERCENT"

    _native="$(hsin_downscale_get_native 2>/dev/null)"
    [ -z "$_native" ] && _native="unknown"

    _current="$(wm size 2>/dev/null | grep '^Override size:' | sed 's/^Override size: //' | tr -d '[:space:]')"
    [ -z "$_current" ] && _current="$_native"

    _target="$(hsin_downscale_calc_target "$_percent" 2>/dev/null)"
    [ -z "$_target" ] && _target="unknown"

    _native_dpi="$(hsin_downscale_get_native_density 2>/dev/null)"
    [ -z "$_native_dpi" ] && _native_dpi="unknown"

    _current_dpi="$(wm density 2>/dev/null | grep '^Override density:' | sed 's/^Override density: //' | tr -d '[:space:]')"
    [ -z "$_current_dpi" ] && _current_dpi="$_native_dpi"

    echo "{\"enabled\":\"$_enabled\",\"native\":\"$_native\",\"current\":\"$_current\",\"target\":\"$_target\",\"percent\":\"$_percent\",\"native_dpi\":\"$_native_dpi\",\"current_dpi\":\"$_current_dpi\"}"
}
