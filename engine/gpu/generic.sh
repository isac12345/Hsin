#!/system/bin/sh
# HSIN GPU Engine - Generic devfreq backend (works across vendors)
[ -z "$HSIN_MODULE_PATH" ] && HSIN_MODULE_PATH="/data/adb/modules/hsin"
. "$HSIN_MODULE_PATH/core/sysfs.sh" 2>/dev/null
# Daftar OPP devfreq (available_frequencies) statis -> dari cache scan lewat
# hsin_gpu_opp_list(); tanpa cache dibaca file seperti sebelumnya. Daftar
# governor TIDAK ada di cache, jadi tetap live.
command -v hsin_gpu_opp_list >/dev/null 2>&1 || \
    . "$HSIN_MODULE_PATH/engine/gpu/detector.sh" 2>/dev/null
_hgo_avail=""

hsin_gpu_generic_pick_gov() {
    _profile="$1"; _avail="$2"
    case "$_profile" in
        battery) for _g in powersave simple_ondemand ondemand; do case " $_avail " in *" $_g "*) echo "$_g"; return 0;; esac; done ;;
        balanced) for _g in simple_ondemand schedutil ondemand performance; do case " $_avail " in *" $_g "*) echo "$_g"; return 0;; esac; done ;;
        performance) for _g in performance schedutil simple_ondemand ondemand; do case " $_avail " in *" $_g "*) echo "$_g"; return 0;; esac; done ;;
        extreme) for _g in performance schedutil simple_ondemand ondemand; do case " $_avail " in *" $_g "*) echo "$_g"; return 0;; esac; done ;;
    esac
    return 1
}

hsin_gpu_generic_apply() {
    _profile="$1"; _d="$2"
    if [ ! -d "$_d" ]; then
        hsin_report_skip "GPU node ${_d##*/} tidak ada (devfreq hilang/umum)"
        return 1
    fi
    hsin_gpu_opp_list "$_d"; _avail="$_hgo_avail"
    _max=$(hsin_opp_max "$_avail")
    _min=$(hsin_opp_min "$_avail")
    case "$_profile" in
        battery) _pct=65 ;;
        balanced) _pct=100 ;;
        performance) _pct=100 ;;
        extreme) _pct=100 ;;
        *) _pct=100 ;;
    esac
    _target_max="$_max"
    if [ "$_pct" -lt 100 ]; then
        [ -n "$_max" ] && _target_max=$(hsin_opp_cap_pick "$((_max * _pct / 100))" "$_avail")
    fi
    [ -n "$_target_max" ] || hsin_report_skip "GPU node $(basename "$_d") tidak punya available_frequencies - max_freq dilewati, governor tetap"
    _ok=0; _fail=0
    if [ -n "$_target_max" ] && [ -w "$_d/max_freq" ]; then
        if hsin_node_write_verify "$_d/max_freq" "$_target_max"; then _ok=$((_ok+1)); else _fail=$((_fail+1)); fi
    else
        _fail=$((_fail+0))
    fi
    _gov=""; [ -f "$_d/available_governors" ] && _gov=$(hsin_gpu_generic_pick_gov "$_profile" "$(cat "$_d/available_governors" 2>/dev/null)")
    if [ -n "$_gov" ] && [ -w "$_d/governor" ]; then
        if hsin_node_write_verify "$_d/governor" "$_gov"; then _ok=$((_ok+1)); else _fail=$((_fail+1)); fi
    fi
    if [ "$_ok" -gt 0 ]; then
        echo "    GPU node $(basename "$_d"): profile=$_profile max=$_target_max gov=${_gov:-unchanged} ok=$_ok fail=$_fail"
        return 0
    fi
    echo "    SKIP: GPU node $(basename "$_d") has no writable supported controls"
    return 0
}

hsin_gpu_generic_state() {
    _d="$1"; [ -d "$_d" ] || return 0
    printf "    %s: gov=%s min=%s max=%s cur=%s\n" "$(basename "$_d")" "$(cat "$_d/governor" 2>/dev/null)" "$(cat "$_d/min_freq" 2>/dev/null)" "$(cat "$_d/max_freq" 2>/dev/null)" "$(cat "$_d/cur_freq" 2>/dev/null)"
}
return 0 2>/dev/null || true
