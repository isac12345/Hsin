#!/system/bin/sh
# HSIN CPU Engine - Frequency Engine

[ -z "$HSIN_MODULE_PATH" ] && HSIN_MODULE_PATH="/data/adb/modules/hsin"
. "$HSIN_MODULE_PATH/core/sysfs.sh" 2>/dev/null
# cpuinfo_max_freq + tabel OPP datang dari cache scan (topologi statis);
# daftar policy dari hsin_cpu_policy_ids(). Nilai yang HSIN tulis sendiri
# (scaling_min/max) tetap dibaca live.
command -v hsin_cpu_policy_ids >/dev/null 2>&1 || \
    . "$HSIN_MODULE_PATH/engine/cpu/detect.sh" 2>/dev/null
# Diisi hsin_scan_lookup() (core/scan_cache.sh) dan hsin_cpu_policy_hwmax()
# (engine/cpu/detect.sh).
_sc_f=""
_hcpw=""

hsin_cpu_freq_pick() {
    _pos="$1"
    _avail="$2"
    [ -z "$_avail" ] && return 1
    case "$_pos" in
        min) hsin_opp_min "$_avail"; return $? ;;
        max) hsin_opp_max "$_avail"; return $? ;;
        mid)
            _n=0; _mid=0
            for _f in $_avail; do case "$_f" in ''|*[!0-9]*) continue;; esac; _n=$((_n+1)); done
            [ "$_n" -gt 0 ] || return 1
            _mid=$(((_n+1)/2)); _i=0; _best=""
            # Keep this simple and fork-free; select the middle after sorting numerically.
            _sorted=$(printf '%s\n' $_avail | sort -n)
            for _f in $_sorted; do _i=$((_i+1)); [ "$_i" -ge "$_mid" ] && { _best="$_f"; break; }; done
            printf '%s\n' "$_best"; return 0
            ;;
        cap:*)
            _pct="${_pos#cap:}"
            case "$_pct" in ''|*[!0-9]*) return 1;; esac
            [ "$_pct" -gt 100 ] && _pct=100
            _max=$(hsin_opp_max "$_avail") || return 1
            _target=$((_max * _pct / 100))
            hsin_opp_cap_pick "$_target" "$_avail"
            return $?
            ;;
        floor:*)
            _pct="${_pos#floor:}"
            case "$_pct" in ''|*[!0-9]*) return 1;; esac
            [ "$_pct" -gt 100 ] && _pct=100
            _max=$(hsin_opp_max "$_avail") || return 1
            _target=$((_max * _pct / 100))
            hsin_opp_floor_pick "$_target" "$_avail"
            return $?
            ;;
        *)
            # Legacy numeric form = ceiling/cap semantics. This avoids the
            # old bug where 65% could round upward to 100% of the hardware max.
            case "$_pos" in ''|*[!0-9]*) return 1;; esac
            hsin_cpu_freq_pick "cap:$_pos" "$_avail"
            return $?
            ;;
    esac
}

# Available frequencies of one policy: cache first (field 7 CPU_POLICY_<id>,
# CSV) so the per-apply read + tr|grep|sort|tr chain disappears; fallback
# reads scaling_available_frequencies exactly like before. Caller keeps
# passing the policy path, the id comes from the basename.
# The list is order-independent for every consumer (hsin_opp_min/max,
# hsin_opp_floor_pick, hsin_opp_cap_pick, the " $_min " membership test),
# so the unsorted cache order is safe.
hsin_cpu_freq_available() {
    _policy="$1"
    _hcf_pid="${_policy##*/policy}"
    hsin_cpu_policy_ids
    if [ "$HSIN_CPU_POLICY_SOURCE" = "cache" ]; then
        hsin_scan_lookup "$HSIN_SCAN_CPU_POLICY_LINES" "$_hcf_pid" 7
        hsin_cpu_csv_to_words "$_sc_f"
        [ -n "$_hcd_words" ] || return 1
        printf '%s\n' "$_hcd_words"
        return 0
    fi
    [ -f "$_policy/scaling_available_frequencies" ] || return 1
    tr ' ' '\n' < "$_policy/scaling_available_frequencies" 2>/dev/null | grep -v '^$' | sort -n | tr '\n' ' '
}

hsin_cpu_freq_apply_one() {
    _policy="$1"; _min="$2"; _max="$3"
    [ -d "$_policy" ] || return 1
    [ -w "$_policy/scaling_min_freq" ] || [ -w "$_policy/scaling_max_freq" ] || return 1

    # Validasi min/max harus ada di tabel OPP. Sumbernya sama dengan
    # hsin_cpu_freq_apply (cache dulu), jadi tidak perlu baca file kedua.
    _avail=$(hsin_cpu_freq_available "$_policy")
    if [ -n "$_avail" ]; then
        [ -z "$_min" ] || case " $_avail " in *" $_min "*) ;; *) return 1;; esac
        [ -z "$_max" ] || case " $_avail " in *" $_max "*) ;; *) return 1;; esac
    fi

    # Never leave min > max. Adjust the floor to the highest valid OPP <= max.
    if [ -n "$_min" ] && [ -n "$_max" ] && [ "$_min" -gt "$_max" ] 2>/dev/null; then
        _min="$_max"
    fi

    if [ -n "$_min" ] && [ -n "$_max" ] && [ "$_min" -gt "$_max" ] 2>/dev/null; then
        # Lower floor first when the new ceiling is below the old floor.
        [ -w "$_policy/scaling_min_freq" ] || return 1
        printf '%s\n' "$_min" > "$_policy/scaling_min_freq" 2>/dev/null || return 1
        _v=$(hsin_node_read "$_policy/scaling_min_freq" 2>/dev/null)
        [ "$_v" = "$_min" ] || return 1
    fi
    if [ -n "$_max" ]; then
        [ -w "$_policy/scaling_max_freq" ] || return 1
        printf '%s\n' "$_max" > "$_policy/scaling_max_freq" 2>/dev/null || return 1
        _v=$(hsin_node_read "$_policy/scaling_max_freq" 2>/dev/null)
        [ "$_v" = "$_max" ] || return 1
    fi
    if [ -n "$_min" ] && ! { [ -n "$_max" ] && [ "$_min" -gt "$_max" ] 2>/dev/null; }; then
        [ -w "$_policy/scaling_min_freq" ] || return 1
        printf '%s\n' "$_min" > "$_policy/scaling_min_freq" 2>/dev/null || return 1
        _v=$(hsin_node_read "$_policy/scaling_min_freq" 2>/dev/null)
        [ "$_v" = "$_min" ] || return 1
    fi
    return 0
}

hsin_cpu_freq_apply() {
    _profile="$1"; _ok=0; _skip=0; _fail=0
    hsin_cpu_policy_ids
    for _pid in $HSIN_CPU_POLICY_IDS; do
        _policy="$HSIN_SYSFS_CPU/cpufreq/policy$_pid"
        [ -d "$_policy" ] || continue
        [ -w "$_policy/scaling_min_freq" ] || [ -w "$_policy/scaling_max_freq" ] || { _skip=$((_skip+1)); continue; }
        _avail=$(hsin_cpu_freq_available "$_policy")
        [ -z "$_avail" ] && { _skip=$((_skip+1)); continue; }
        _stock_min=""
        [ -f "$_policy/cpuinfo_min_freq" ] && read -r _stock_min < "$_policy/cpuinfo_min_freq" 2>/dev/null
        hsin_cpu_policy_hwmax "$_pid"; _stock_max="$_hcpw"
        [ -z "$_stock_max" ] && _stock_max=$(hsin_opp_max "$_avail")
        [ -z "$_stock_min" ] && _stock_min=$(hsin_opp_min "$_avail")
        case "$_profile" in
            battery)     _min="$_stock_min"; _max=$(hsin_cpu_freq_pick cap:80 "$_avail") ;;
            balanced)    _min=$(hsin_cpu_freq_pick floor:15 "$_avail"); _max="$_stock_max" ;;
            performance) _min=$(hsin_cpu_freq_pick floor:35 "$_avail"); _max="$_stock_max" ;;
            extreme)     _min="$_stock_max"; _max="$_stock_max" ;;
            *)           _min="$_stock_min"; _max="$_stock_max" ;;
        esac
        if hsin_cpu_freq_apply_one "$_policy" "$_min" "$_max"; then _ok=$((_ok+1)); else _fail=$((_fail+1)); fi
    done
    echo "    Frequency [$_profile]: ok=$_ok skip=$_skip fail=$_fail"
    return 0
}

hsin_cpu_freq_state() {
    hsin_cpu_policy_ids
    for _pid in $HSIN_CPU_POLICY_IDS; do
        _policy="$HSIN_SYSFS_CPU/cpufreq/policy$_pid"
        [ -d "$_policy" ] || continue
        _min=""; _max=""
        [ -f "$_policy/scaling_min_freq" ] && read -r _min < "$_policy/scaling_min_freq" 2>/dev/null
        [ -f "$_policy/scaling_max_freq" ] && read -r _max < "$_policy/scaling_max_freq" 2>/dev/null
        printf "    policy%s: %s-%s kHz\n" "$_pid" "${_min:-?}" "${_max:-?}"
    done
}

return 0 2>/dev/null || true
