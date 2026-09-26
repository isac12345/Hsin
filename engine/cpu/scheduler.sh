#!/system/bin/sh
# HSIN CPU Engine - Scheduler Engine

[ -z "$HSIN_MODULE_PATH" ] && HSIN_MODULE_PATH="/data/adb/modules/hsin"
command -v hsin_cpu_policy_ids >/dev/null 2>&1 || \
    . "$HSIN_MODULE_PATH/engine/cpu/detect.sh" 2>/dev/null
# Diisi hsin_cpu_policy_hwmax() (engine/cpu/detect.sh).
_hcpw=""

# Detect CPU topology (big vs LITTLE)
# cpuinfo_max_freq per policy dari cache scan (topologi statis, field 5),
# jadi tidak ada glob cpufreq/policy* dua kali seperti sebelumnya. Mask
# `cpus` (bisa berubah saat hotplug) tetap dibaca live supaya hasilnya sama
# persis dengan scan lama.
hsin_cpu_topo_detect() {
    HSIN_CPU_BIG=""
    HSIN_CPU_LITTLE=""
    _max_overall=0

    hsin_cpu_policy_ids

    # Find highest max_freq
    for _pid in $HSIN_CPU_POLICY_IDS; do
        _p="$HSIN_SYSFS_CPU/cpufreq/policy$_pid"
        [ -d "$_p" ] || continue
        hsin_cpu_policy_hwmax "$_pid"; _max="$_hcpw"
        # Guard against empty/zero values so the arithmetic compare
        # never trips on a string.
        if [ -n "$_max" ] && [ "$_max" -gt "$_max_overall" ] 2>/dev/null; then
            _max_overall="$_max"
        fi
    done

    [ "$_max_overall" -eq 0 ] && return 1

    # Split cores
    for _pid in $HSIN_CPU_POLICY_IDS; do
        _p="$HSIN_SYSFS_CPU/cpufreq/policy$_pid"
        [ -d "$_p" ] || continue
        hsin_cpu_policy_hwmax "$_pid"; _max="$_hcpw"
        _cpus=""
        if [ -f "$_p/cpus" ]; then
            IFS= read -r _cpus < "$_p/cpus" 2>/dev/null
        elif [ -f "$_p/related_cpus" ]; then
            IFS= read -r _cpus < "$_p/related_cpus" 2>/dev/null
        fi
        [ -z "$_cpus" ] && continue
        # Sama seperti "cat | tr '\n' ' '" yang lama: satu spasi penutup,
        # supaya hasil sed di bawah identik dengan versi sebelumnya.
        _cpus="$_cpus "

        if [ -n "$_max" ] && [ "$_max" -ge "$_max_overall" ] 2>/dev/null; then
            HSIN_CPU_BIG="${HSIN_CPU_BIG} $_cpus"
        else
            HSIN_CPU_LITTLE="${HSIN_CPU_LITTLE} $_cpus"
        fi
    done

    # Clean spaces
    HSIN_CPU_BIG=$(echo "$HSIN_CPU_BIG" | sed 's/^ //;s/  */ /g')
    HSIN_CPU_LITTLE=$(echo "$HSIN_CPU_LITTLE" | sed 's/^ //;s/  */ /g')
}

# Apply cpuset settings
hsin_cpu_cpuset_apply() {
    _profile="$1"

    # Check if cpuset is available
    [ -d "/dev/cpuset" ] || { echo "    cpuset: not available"; return 0; }

    # Detect topology
    hsin_cpu_topo_detect

    # If no big/LITTLE split, skip
    if [ -z "$HSIN_CPU_BIG" ] || [ -z "$HSIN_CPU_LITTLE" ]; then
        echo "    cpuset: homogeneous CPU (skip)"
        return 0
    fi

    case "$_profile" in
        battery|balanced)
            # Default: let kernel decide
            echo "    cpuset: default (kernel placement)"
            ;;
        performance|extreme)
            # top-app + foreground -> BIG cores
            for _grp in top-app foreground; do
                [ -w "/dev/cpuset/$_grp/cpus" ] && {
                    echo "$HSIN_CPU_BIG" > "/dev/cpuset/$_grp/cpus" 2>/dev/null
                }
            done
            for _grp in background system-background; do
                [ -w "/dev/cpuset/$_grp/cpus" ] && {
                    echo "$HSIN_CPU_LITTLE" > "/dev/cpuset/$_grp/cpus" 2>/dev/null
                }
            done
            echo "    cpuset: top-app/foreground -> BIG ($_cpus)"
            ;;
    esac
    return 0
}

# Apply uclamp settings if available
hsin_cpu_uclamp_apply() {
    _profile="$1"

    # Check if uclamp is available
    [ -d "/dev/cpuctl" ] || return 0

    case "$_profile" in
        battery)
            _min="0"; _max="50" ;;
        balanced)
            _min="0"; _max="100" ;;
        performance)
            # Casual-gaming tier: lower floor than before (was 20) now
            # that extreme is the dedicated max-floor tier - keeps this
            # one lighter on sustained power draw.
            _min="15"; _max="100" ;;
        extreme)
            # Hardcore tier: higher floor (was 50) so frame pacing stays
            # consistent under sustained heavy load instead of dipping
            # between bursts.
            _min="60"; _max="100" ;;
    esac

    # Apply to foreground
    if [ -w "/dev/cpuctl/foreground/cpu.uclamp.min" ]; then
        echo "$_min" > "/dev/cpuctl/foreground/cpu.uclamp.min" 2>/dev/null
    fi
    if [ -w "/dev/cpuctl/foreground/cpu.uclamp.max" ]; then
        echo "$_max" > "/dev/cpuctl/foreground/cpu.uclamp.max" 2>/dev/null
    fi

    echo "    uclamp: min=$_min max=$_max"
    return 0
}

# Apply stune settings if available
hsin_cpu_stune_apply() {
    _profile="$1"

    # Check if stune is available
    [ -d "/dev/stune" ] || return 0

    case "$_profile" in
        battery)
            _boost="0" ;;
        balanced)
            # "Dinaikin dikit": tiny top-app boost instead of 0, so
            # everyday app launches/scrolling feel a touch snappier
            # without turning balanced into a performance profile.
            _boost="10" ;;
        performance)
            # Casual-gaming tier - a notch lighter than before (was 50)
            # now that extreme owns full boost.
            _boost="40" ;;
        extreme)
            _boost="100" ;;
    esac

    # Apply to top-app
    if [ -w "/dev/stune/top-app/schedtune.boost" ]; then
        echo "$_boost" > "/dev/stune/top-app/schedtune.boost" 2>/dev/null
    fi

    echo "    stune: boost=$_boost"
    return 0
}

# Get cpuset state
hsin_cpu_cpuset_state() {
    [ -d "/dev/cpuset" ] || return 0
    echo "  cpuset state:"
    for _grp in top-app foreground background system-background; do
        [ -f "/dev/cpuset/$_grp/cpus" ] || continue
        _cpus=$(cat "/dev/cpuset/$_grp/cpus" 2>/dev/null)
        printf "    %-20s %s\n" "$_grp" "$_cpus"
    done
}

# ---------------------------------------------------------------------------
# CFS scheduler latency tuning (sched_latency_ns / min_granularity /
# wakeup_granularity / migration_cost)
#
# Why this helps frame pacing specifically: these control how long a task
# can run before the scheduler considers preempting it, and how "sticky" a
# task is to the core it's already running on. A high sched_latency /
# wakeup_granularity means the render thread can sit queued a few ms longer
# than it should when something else wants the CPU - that shows up as
# occasional frame time spikes even when average FPS looks fine, which is
# exactly what "frame pacing" complaints usually are. migration_cost going
# the OTHER direction (higher) reduces jitter from the scheduler bouncing
# the render thread between cores mid-frame (cache gets cold every bounce).
#
# UNIVERSAL BY DESIGN: values are captured ONCE per device (native, whatever
# the vendor kernel shipped) and every profile scales off that captured
# baseline by percentage - never an absolute ns number. Absolute values
# tuned for one SoC's kernel defaults are meaningless (or actively wrong)
# on a different kernel's defaults. Same reasoning as
# hsin_downscale_capture_native() in engine/display/downscale.sh.
#
# TWO POSSIBLE LOCATIONS, tried in order:
#   1. /proc/sys/kernel/sched_<name>       - classic sysctl (older kernels)
#   2. /sys/kernel/debug/sched/<name>      - upstream moved these behind
#      debugfs around Linux 5.13 (CONFIG_SCHED_DEBUG=y alone no longer
#      guarantees the /proc path - debugfs also has to be mounted, which
#      isn't automatic on every Android boot config, so we try mounting
#      it ourselves once before giving up).
# ---------------------------------------------------------------------------

_HSIN_SCHED_LAT_CANON="sched_latency_ns sched_min_granularity_ns sched_wakeup_granularity_ns sched_migration_cost_ns"
_HSIN_SCHED_LAT_DEBUGFS="/sys/kernel/debug/sched"
_HSIN_SCHED_LAT_DEBUGFS_MOUNT_TRIED=0

# Makes sure debugfs is mounted, but only ever tries once per process -
# if it fails (locked down by SELinux, CONFIG_DEBUG_FS=n, whatever) there's
# no point retrying it on every single node lookup.
_hsin_sched_lat_ensure_debugfs() {
    [ -d "$_HSIN_SCHED_LAT_DEBUGFS" ] && return 0
    [ "$_HSIN_SCHED_LAT_DEBUGFS_MOUNT_TRIED" = "1" ] && return 1
    _HSIN_SCHED_LAT_DEBUGFS_MOUNT_TRIED=1
    mount -t debugfs debugfs /sys/kernel/debug 2>/dev/null
    [ -d "$_HSIN_SCHED_LAT_DEBUGFS" ]
}

# Resolves a canonical node name (e.g. "sched_latency_ns") to whichever
# real, writable path actually backs it on this kernel. Prints the path,
# or nothing (+ exit 1) if neither location has it.
_hsin_sched_lat_resolve_path() {
    _canon="$1"
    if [ -w "/proc/sys/kernel/$_canon" ]; then
        echo "/proc/sys/kernel/$_canon"
        return 0
    fi
    _short="${_canon#sched_}"   # sched_latency_ns -> latency_ns
    if _hsin_sched_lat_ensure_debugfs && [ -w "$_HSIN_SCHED_LAT_DEBUGFS/$_short" ]; then
        echo "$_HSIN_SCHED_LAT_DEBUGFS/$_short"
        return 0
    fi
    return 1
}

# Prints "name=path" for every node that resolves on this kernel (either
# location). Empty output = neither /proc nor debugfs has any of them -
# every caller below treats that as "feature not available here".
_hsin_sched_lat_available_nodes() {
    for _canon in $_HSIN_SCHED_LAT_CANON; do
        _path="$(_hsin_sched_lat_resolve_path "$_canon")" || continue
        printf '%s=%s\n' "$_canon" "$_path"
    done
}

# Captures native (untouched) values for every available node, once. Safe
# to call unconditionally on every boot/apply - no-op after first success.
# Needs HSIN_DATA exported by the caller (service.sh / action.sh already do).
hsin_cpu_sched_lat_capture_native() {
    _file="$HSIN_DATA/native_sched_lat"
    [ -f "$_file" ] && return 0

    _pairs="$(_hsin_sched_lat_available_nodes)"
    [ -z "$_pairs" ] && return 1

    : > "$_file.tmp" 2>/dev/null || return 1
    _old_ifs="$IFS"
    IFS='
'
    for _pair in $_pairs; do
        _canon="${_pair%%=*}"
        _path="${_pair#*=}"
        _val="$(cat "$_path" 2>/dev/null)"
        case "$_val" in
            ''|*[!0-9]*) continue ;;
        esac
        echo "$_canon=$_val" >> "$_file.tmp"
    done
    IFS="$_old_ifs"
    mv "$_file.tmp" "$_file" 2>/dev/null
}

# Reads one native value by canonical node name from the capture file.
# Prints nothing (+ exit 1) if never captured or that node wasn't in it.
_hsin_sched_lat_get_native() {
    _file="$HSIN_DATA/native_sched_lat"
    [ -f "$_file" ] || return 1
    _line="$(grep "^$1=" "$_file" 2>/dev/null | head -1)"
    [ -z "$_line" ] && return 1
    echo "${_line#*=}"
}

# Applies scheduler latency tuning for a profile, scaled off native. Safe
# no-op (returns 0, does nothing) if this kernel doesn't expose the nodes
# in either location.
# $1 = profile (battery|balanced|performance|extreme)
hsin_cpu_sched_lat_apply() {
    _profile="$1"

    # Trace log written DIRECTLY by this function - the "$_canon: X -> Y"
    # and WARNING lines below were previously only echo'd to stdout, which
    # nothing captures during a real apply (hsin_cpu_log() only calls the
    # separate *_state() functions afterward, it doesn't record apply()'s
    # own output). That gap is exactly why the battery current=1 bug went
    # unnoticed, and why the floor-clamp being hit for latency_ns couldn't
    # be explained from the log alone - there was no record of what the
    # RAW pre-floor target actually was. Writing straight to cpu.log here
    # fixes that for good, independent of whatever else logs around it.
    _lat_log="$HSIN_DATA/logs/cpu.log"
    mkdir -p "$HSIN_DATA/logs" 2>/dev/null

    hsin_cpu_sched_lat_capture_native || { echo "    sched-latency: not available on this kernel"; return 0; }

    # Percent of native value to apply, per node. Lower % on the three
    # "granularity" nodes = shorter max time a thread waits its turn
    # (snappier preemption = tighter frame pacing). Higher % on
    # migration_cost = task stays put on its core longer (less jitter
    # from core-hopping). battery/balanced deliberately restore 100%
    # (native, untouched) rather than a battery-favoring alternate value -
    # this feature exists to fix gaming frame pacing, not to also invent
    # an unrequested battery-saving scheduler behavior.
    case "$_profile" in
        battery|balanced)
            _lat_pct=100; _mingran_pct=100; _wake_pct=100; _migr_pct=100 ;;
        performance)
            _lat_pct=70;  _mingran_pct=70;  _wake_pct=60;  _migr_pct=400 ;;
        extreme)
            _lat_pct=40;  _mingran_pct=40;  _wake_pct=30;  _migr_pct=1000 ;;
        *)
            echo "    sched-latency: unknown profile '$_profile', skipped" >&2
            return 1 ;;
    esac

    # HARD FLOOR: confirmed on real hardware that writing certain vendor
    # kernels' CFS nodes can silently clamp/rewrite EACH OTHER's values
    # (they're not 4 independent knobs - some kernels recompute
    # granularity/wakeup off latency internally). Worst observed case was
    # sched_latency_ns landing at 1ns in BATTERY mode (should have been
    # 100%/native, untouched) - 1ns preemption is pathological, it thrashes
    # context switches constantly and is a plausible cause of the near-
    # freeze (1.0 min FPS) seen in real PGR testing. This floor makes that
    # specific failure mode impossible regardless of what the kernel does
    # to our intended target underneath us.
    _HSIN_SCHED_LAT_FLOOR_NS=500000   # 0.5ms - below this is never sane for any of these 4 nodes

    _hsin_sched_lat_scale_write() {
        _canon="$1"; _pct="$2"
        _path="$(_hsin_sched_lat_resolve_path "$_canon")" || return 0
        _native="$(_hsin_sched_lat_get_native "$_canon")" || return 0
        # Divide BEFORE multiplying, not after: native(24,000,000) * pct(100)
        # = 2.4 billion overflows 32-bit signed arithmetic on this shell
        # (max ~2.147 billion) and wraps to a garbage negative number - that
        # was the ENTIRE bug, confirmed on real hardware (raw_target came
        # back as -18949672 for exactly this node/profile combo). Dividing
        # first keeps every intermediate value tiny (native/100 is at most
        # in the low millions, times pct up to 1000 stays nowhere near the
        # 32-bit ceiling) at the cost of a fraction of a percent of rounding
        # error, which is irrelevant at nanosecond tuning granularity.
        _target_raw=$(( _native / 100 * _pct ))
        _target="$_target_raw"
        [ "$_target" -ge "$_HSIN_SCHED_LAT_FLOOR_NS" ] || _target="$_HSIN_SCHED_LAT_FLOOR_NS"
        echo "$_target" > "$_path" 2>/dev/null
        _actual_after="$(cat "$_path" 2>/dev/null)"
        echo "    [sched-lat] $_canon: native=$_native pct=$_pct raw_target=$_target_raw floored_target=$_target wrote_then_read_back=$_actual_after [$_path]" >> "$_lat_log" 2>/dev/null
    }

    # TWO PASSES, same order both times: on the hardware this was tested
    # against, a handful of the 4 writes didn't stick on the first pass
    # (wakeup_granularity/migration_cost specifically stayed at whatever
    # they were before, or landed at a different value than requested) -
    # consistent with the kernel deriving/re-clamping one node's value as
    # a side effect of writing another. Re-asserting all 4 a second time,
    # after whatever internal derivation the first pass triggered has
    # already happened, is a blunt but effective way to make our intended
    # values the ones that are still there afterward, without needing to
    # know this vendor kernel's exact internal dependency graph.
    _pass=1
    while [ "$_pass" -le 2 ]; do
        echo "    [sched-lat] === pass $_pass (profile=$_profile) ===" >> "$_lat_log" 2>/dev/null
        _hsin_sched_lat_scale_write sched_latency_ns "$_lat_pct"
        _hsin_sched_lat_scale_write sched_min_granularity_ns "$_mingran_pct"
        _hsin_sched_lat_scale_write sched_wakeup_granularity_ns "$_wake_pct"
        _hsin_sched_lat_scale_write sched_migration_cost_ns "$_migr_pct"
        _pass=$(( _pass + 1 ))
    done

    # Verify pass: read back what's ACTUALLY there now and flag (loudly,
    # in the log) any node that still doesn't match what we asked for -
    # so a mismatch is visible instead of silently assumed to have worked,
    # which is exactly how the battery/current=1 bug went unnoticed until
    # a real PGR run surfaced it.
    _hsin_sched_lat_verify_one() {
        _canon="$1"; _pct="$2"
        _path="$(_hsin_sched_lat_resolve_path "$_canon")" || return 0
        _native="$(_hsin_sched_lat_get_native "$_canon")" || return 0
        _expect=$(( _native / 100 * _pct ))
        [ "$_expect" -ge "$_HSIN_SCHED_LAT_FLOOR_NS" ] || _expect="$_HSIN_SCHED_LAT_FLOOR_NS"
        _actual="$(cat "$_path" 2>/dev/null)"
        case "$_actual" in ''|*[!0-9]*) _actual=0 ;; esac
        if [ "$_actual" != "$_expect" ]; then
            echo "    [sched-lat] WARNING: $_canon final value drifted after both passes - wanted $_expect, kernel now has $_actual" >> "$_lat_log" 2>/dev/null
        fi
    }
    _hsin_sched_lat_verify_one sched_latency_ns "$_lat_pct"
    _hsin_sched_lat_verify_one sched_min_granularity_ns "$_mingran_pct"
    _hsin_sched_lat_verify_one sched_wakeup_granularity_ns "$_wake_pct"
    _hsin_sched_lat_verify_one sched_migration_cost_ns "$_migr_pct"

    return 0
}

# Restores every node to its captured native value. Called on module
# disable/uninstall/rollback so nothing is left tuned away from stock.
hsin_cpu_sched_lat_restore() {
    _file="$HSIN_DATA/native_sched_lat"
    [ -f "$_file" ] || return 0
    while IFS='=' read -r _canon _val; do
        [ -n "$_canon" ] || continue
        _path="$(_hsin_sched_lat_resolve_path "$_canon")" || continue
        echo "$_val" > "$_path" 2>/dev/null
    done < "$_file"
}

# WebUI/CLI status line.
hsin_cpu_sched_lat_state() {
    _pairs="$(_hsin_sched_lat_available_nodes)"
    if [ -z "$_pairs" ]; then
        echo "  sched-latency: not available on this kernel"
        return 0
    fi
    echo "  sched-latency state:"
    _old_ifs="$IFS"
    IFS='
'
    for _pair in $_pairs; do
        _canon="${_pair%%=*}"
        _path="${_pair#*=}"
        _cur="$(cat "$_path" 2>/dev/null)"
        _native="$(_hsin_sched_lat_get_native "$_canon" 2>/dev/null)"
        [ -z "$_native" ] && _native="?"
        printf "    %-28s current=%-12s native=%-12s [%s]\n" "$_canon" "$_cur" "$_native" "$_path"
    done
    IFS="$_old_ifs"
}

return 0 2>/dev/null || true
