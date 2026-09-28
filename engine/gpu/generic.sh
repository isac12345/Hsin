#!/system/bin/sh
# HSIN GPU Engine - Generic devfreq backend (works across vendors)
[ -z "$HSIN_MODULE_PATH" ] && HSIN_MODULE_PATH="/data/adb/modules/hsin"
. "$HSIN_MODULE_PATH/core/sysfs.sh" 2>/dev/null
# Daftar OPP devfreq (available_frequencies) statis -> dari cache scan lewat
# hsin_gpu_opp_list(); tanpa cache dibaca file seperti sebelumnya. Daftar
# governor TIDAK ada di cache, jadi tetap live.
command -v hsin_gpu_opp_list >/dev/null 2>&1 || \
    . "$HSIN_MODULE_PATH/engine/gpu/detector.sh" 2>/dev/null
# Override knob user per node + logger untuk mencatat override yang
# dipakai/ditolak.
. "$HSIN_MODULE_PATH/core/logger.sh" 2>/dev/null
. "$HSIN_MODULE_PATH/core/user_knobs.sh" 2>/dev/null
_hgo_avail=""
# Diisi _uk_sanitize() (core/user_knobs.sh) - dideklarasikan di sini
# seperti _hgo_avail supaya jelas file ini memang memakainya.
_uk_sn=""

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
    # Override knob user = kHz absolut untuk node ini, hanya kalau ada di
    # daftar OPP node; di luar tabel disnap ke OPP terdekat <= dan dicatat
    # (devfreq menolak max_freq yang bukan OPP dengan diam-diam).
    # Nama node disanitasi sekali di sini juga supaya kunci yang ditulis ke
    # log persis sama dengan kunci yang disimpan user_knobs.env (nama node
    # device bisa mengandung karakter yang jadi '_', mis. "23100000.gpu").
    # Mode manual: tanpa override, lewati penulisan.
    _uk_sanitize "${_d##*/}"
    _uk_kmax="gpu_node_${_uk_sn}_max_khz"
    _uk_kgov="gpu_node_${_uk_sn}_gov"
    _uk_gmax=$(hsin_uk_gpu_field "$_d" max_khz 2>/dev/null)
    _uk_gov=$(hsin_uk_gpu_field "$_d" gov 2>/dev/null)
    if [ "$_profile" = "manual" ] && [ -z "$_uk_gmax" ] && [ -z "$_uk_gov" ]; then
        hsin_uk_result "$_uk_kmax" "(manual)" "-" "SKIPPED" "tidak diatur (mode manual)" 2>/dev/null || true
        hsin_uk_result "$_uk_kgov" "(manual)" "-" "SKIPPED" "tidak diatur (mode manual)" 2>/dev/null || true
        echo "    SKIP: GPU node $(basename "$_d") dilewati (mode manual, tanpa override)"
        return 0
    fi
    if [ -n "$_uk_gmax" ]; then
        if [ -z "$_avail" ]; then
            hsin_log_warn "gpu" "override ${_uk_kmax}=$_uk_gmax ditolak: node tidak punya daftar available_frequencies (pakai profil)"
        else
            case " $_avail " in
                *" $_uk_gmax "*)
                    _target_max="$_uk_gmax"
                    hsin_uk_used "gpu" "$_uk_kmax" "$_uk_gmax"
                    ;;
                *)
                    _uk_snap=$(hsin_opp_cap_pick "$_uk_gmax" "$_avail")
                    if [ -n "$_uk_snap" ]; then
                        _target_max="$_uk_snap"
                        hsin_log_warn "gpu" "override ${_uk_kmax}=$_uk_gmax tidak ada di tabel OPP; snap ke $_uk_snap"
                        hsin_uk_result "$_uk_kmax" "$_uk_gmax" "$_uk_snap" "FALLBACK" "tidak ada di tabel OPP; snap ke $_uk_snap" 2>/dev/null || true
                    else
                        hsin_log_warn "gpu" "override ${_uk_kmax}=$_uk_gmax ditolak: tabel OPP tidak terbaca (pakai profil)"
                        hsin_uk_result "$_uk_kmax" "$_uk_gmax" "$_target_max" "FALLBACK" "ditolak: tabel OPP tidak terbaca (pakai profil)" 2>/dev/null || true
                    fi
                    ;;
            esac
        fi
    fi
    [ -n "$_target_max" ] || hsin_report_skip "GPU node $(basename "$_d") tidak punya available_frequencies - max_freq dilewati (hasil governor ikut baris hasil di bawah)"
    if [ -z "$_uk_gmax" ]; then
        if [ "$_profile" = "manual" ]; then
            hsin_uk_result "$_uk_kmax" "(manual)" "-" "SKIPPED" "tidak diatur (mode manual)" 2>/dev/null || true
            _target_max=""
        else
            hsin_uk_result "$_uk_kmax" "(profil)" "$_target_max" "APPLIED" "nilai profil (tanpa override)" 2>/dev/null || true
        fi
    fi
    _ok=0; _fail=0
    if [ -n "$_target_max" ] && [ -w "$_d/max_freq" ]; then
        if hsin_node_write_verify "$_d/max_freq" "$_target_max"; then _ok=$((_ok+1)); else _fail=$((_fail+1)); fi
    else
        _fail=$((_fail+0))
    fi
    _gov=""; [ -f "$_d/available_governors" ] && _gov=$(hsin_gpu_generic_pick_gov "$_profile" "$(cat "$_d/available_governors" 2>/dev/null)")
    # Override governor: hanya kalau nama itu ada di available_governors
    # node ini, kalau tidak SKIP + WARN (jangan tulis governor ngawur).
    _uk_gov=$(hsin_uk_gpu_field "$_d" gov 2>/dev/null)
    if [ -n "$_uk_gov" ]; then
        _uk_govs=$(hsin_node_read "$_d/available_governors" 2>/dev/null)
        if [ -z "$_uk_govs" ]; then
            hsin_log_warn "gpu" "override ${_uk_kgov}=$_uk_gov ditolak: available_governors tidak terbaca (pakai profil)"
            hsin_uk_result "$_uk_kgov" "$_uk_gov" "$_gov" "FALLBACK" "ditolak: available_governors tidak terbaca (pakai profil)" 2>/dev/null || true
        else
            case " $_uk_govs " in
                *" $_uk_gov "*)
                    _gov="$_uk_gov"
                    hsin_uk_used "gpu" "$_uk_kgov" "$_uk_gov"
                    ;;
                *)
                    hsin_log_warn "gpu" "override ${_uk_kgov}=$_uk_gov ditolak: tidak ada di available_governors node ini (pakai profil)"
                    hsin_uk_result "$_uk_kgov" "$_uk_gov" "$_gov" "FALLBACK" "ditolak: tidak ada di available_governors (pakai profil)" 2>/dev/null || true
                    ;;
            esac
        fi
    fi
    if [ -z "$_uk_gov" ]; then
        if [ "$_profile" = "manual" ]; then
            hsin_uk_result "$_uk_kgov" "(manual)" "-" "SKIPPED" "tidak diatur (mode manual)" 2>/dev/null || true
            _gov=""
        else
            hsin_uk_result "$_uk_kgov" "(profil)" "$_gov" "APPLIED" "nilai profil (tanpa override)" 2>/dev/null || true
        fi
    fi
    if [ -n "$_gov" ] && [ -w "$_d/governor" ]; then
        if hsin_node_write_verify "$_d/governor" "$_gov"; then _ok=$((_ok+1)); else _fail=$((_fail+1)); fi
    fi
    if [ "$_ok" -gt 0 ]; then
        echo "    GPU node $(basename "$_d"): profile=$_profile max=${_target_max:-unchanged} gov=${_gov:-unchanged} ok=$_ok fail=$_fail"
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
