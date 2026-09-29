#!/system/bin/sh
# HSIN GPU Engine - ARM Mali Specific
# Credit: logic inspired by GTurbo (GPU governor control)
#
# KONVENSI _profile (WAJIB dibaca sebelum menambah fungsi di file engine):
# _profile disetel SEKALI oleh pemanggil di awal rantai apply, lalu dipakai
# bersama. Fungsi yang butuh nilai turunan sendiri (mis. hasil pemetaan atau
# klasifikasi lokal) WAJIB memakai nama variabelnya sendiri - contoh
# hsin_gpu_kbase_knobs_apply memakai _mk_profile - dan TIDAK boleh membaca
# _profile karena itu milik pemanggil. Pelajaran: bug $_mk_profile dulu
# menulis NILAI KOSONG ke node kbase hanya karena salah nama variabel.

[ -z "$HSIN_MODULE_PATH" ] && HSIN_MODULE_PATH="/data/adb/modules/hsin"
# shellcheck disable=SC1091
. "$HSIN_MODULE_PATH/core/sysfs.sh" 2>/dev/null
. "$HSIN_MODULE_PATH/core/logger.sh" 2>/dev/null
. "$HSIN_MODULE_PATH/core/user_knobs.sh" 2>/dev/null

# Apply Mali tweaks
hsin_gpu_mali_apply() {
    _profile="$1"

    # Load detector
    . "$HSIN_MODULE_PATH/engine/gpu/detector.sh" 2>/dev/null
    hsin_gpu_detect

    [ "$HSIN_GPU_VENDOR" = "mali" ] || return 1
    _applied=0

    # Apply via devfreq if available
    if [ -n "$HSIN_GPU_DEVFREQ" ] && [ -d "$HSIN_GPU_DEVFREQ" ]; then
        . "$HSIN_MODULE_PATH/engine/gpu/generic.sh" 2>/dev/null
        hsin_gpu_generic_apply "$_profile" "$HSIN_GPU_DEVFREQ"
        _applied=$?
    fi

    # Apply Mali platform specific (if available)
    if [ -n "$HSIN_GPU_MALI" ] && [ -d "$HSIN_GPU_MALI" ]; then
        # power_policy: always_on vs coarse_demand
        if [ -w "$HSIN_GPU_MALI/power_policy" ]; then
            case "$_profile" in
                battery)     _pp="coarse_demand" ;;
                balanced)    _pp="always_on" ;;
                performance) _pp="always_on" ;;
                extreme)     _pp="always_on" ;;
            esac
            echo "$_pp" > "$HSIN_GPU_MALI/power_policy" 2>/dev/null && _applied=$((_applied + 1))
        fi

        # dvfs_governor: 0=coarse_demand, 1=ondemand, 2=performance
        if [ -w "$HSIN_GPU_MALI/dvfs_governor" ]; then
            case "$_profile" in
                battery)     _dg="1" ;;
                balanced)    _dg="1" ;;
                performance) _dg="2" ;;
                extreme)     _dg="2" ;;
            esac
            echo "$_dg" > "$HSIN_GPU_MALI/dvfs_governor" 2>/dev/null && _applied=$((_applied + 1))
        fi

        # js_scheduling_period
        if [ -w "$HSIN_GPU_MALI/js_scheduling_period" ]; then
            case "$_profile" in
                battery)     _jsp="3" ;;
                balanced)    _jsp="2" ;;
                performance) _jsp="1" ;;
                extreme)     _jsp="1" ;;
            esac
            echo "$_jsp" > "$HSIN_GPU_MALI/js_scheduling_period" 2>/dev/null && _applied=$((_applied + 1))
        fi
    fi

    # Parameter kbase dipindah ke hsin_gpu_kbase_knobs_apply (lihat bawah):
    # dipanggil dari pipeline GPU dan di-gate HANYA oleh keberadaan node, bukan
    # nama vendor GPU (syarat deteksi ketat K3).
    if command -v hsin_gpu_kbase_knobs_apply >/dev/null 2>&1; then
        hsin_gpu_kbase_knobs_apply "$_profile"
    fi

    echo "    Mali: applied=$_applied"
    return 0
}

# Get Mali state
hsin_gpu_mali_state() {
    . "$HSIN_MODULE_PATH/engine/gpu/detector.sh" 2>/dev/null
    hsin_gpu_detect

    [ "$HSIN_GPU_VENDOR" = "mali" ] || return 1

    echo "  Mali State:"
    if [ -n "$HSIN_GPU_DEVFREQ" ] && [ -d "$HSIN_GPU_DEVFREQ" ]; then
        . "$HSIN_MODULE_PATH/engine/gpu/generic.sh" 2>/dev/null
        hsin_gpu_generic_state "$HSIN_GPU_DEVFREQ"
    fi

    if [ -n "$HSIN_GPU_MALI" ] && [ -d "$HSIN_GPU_MALI" ]; then
        [ -f "$HSIN_GPU_MALI/power_policy" ] && {
            _pp=$(cat "$HSIN_GPU_MALI/power_policy" 2>/dev/null)
            printf "    power_policy:      %s\n" "$_pp"
        }
        [ -f "$HSIN_GPU_MALI/dvfs_governor" ] && {
            _dg=$(cat "$HSIN_GPU_MALI/dvfs_governor" 2>/dev/null)
            printf "    dvfs_governor:     %s\n" "$_dg"
        }
    fi

    if [ -n "$HSIN_GPU_KBASE" ] && [ -d "$HSIN_GPU_KBASE" ]; then
        [ -f "$HSIN_GPU_KBASE/gpu_boost_level2" ] && {
            _bl=$(cat "$HSIN_GPU_KBASE/gpu_boost_level2" 2>/dev/null)
            printf "    boost_level2:      %s\n" "$_bl"
        }
        [ -f "$HSIN_GPU_KBASE/gpu_pollingtime" ] && {
            _pt=$(cat "$HSIN_GPU_KBASE/gpu_pollingtime" 2>/dev/null)
            printf "    pollingtime:       %s\n" "$_pt"
        }
        [ -f "$HSIN_GPU_KBASE/gpu_upthreshold" ] && {
            _ut=$(cat "$HSIN_GPU_KBASE/gpu_upthreshold" 2>/dev/null)
            printf "    upthreshold:       %s\n" "$_ut"
        }
    fi
}

# K3: knob parameter Mali KBase (gpu_boost_level2, gpu_pollingtime,
# gpu_upthreshold). Gate = node ADA + writable (bukan nama vendor/SoC).
# Tanpa override: profil menulis seperti sebelumnya; mode manual nol tulis.
hsin_gpu_kbase_knobs_apply() {
    _mk_profile="$1"
    _mk_applied=0
    # Gate = node kbase ADA. Kalau detector belum jalan, turunkan ke path
    # default yang sama dengan yang dipakai detector (HSIN_SYSFS_KBASE),
    # jadi fungsi ini tidak bergantung pada urutan pemanggilan.
    if [ -z "$HSIN_GPU_KBASE" ]; then
        [ -n "$HSIN_SYSFS_KBASE" ] || HSIN_SYSFS_KBASE="${SYSFS_KBASE_PREFIX:-/sys/module/mali_kbase/parameters}"
        HSIN_GPU_KBASE="$HSIN_SYSFS_KBASE"
    fi

    [ -n "$HSIN_GPU_KBASE" ] && [ -d "$HSIN_GPU_KBASE" ] || return 0
    # K3: ketiganya jadi knob user (kunci global: satu set parameter kbase
    # per device, bukan per node). Tanpa override, profil tetap menulis
    # seperti sebelumnya; di mode manual TIDAK menulis apa pun kecuali user
    # menyetel knob.
    _mk_manual=0
    [ "$_mk_profile" = "manual" ] && _mk_manual=1
    # key|node|min|max|def_battery|def_balanced|def_performance|def_extreme
    for _mk_spec in \
        "mali_boost_level2|gpu_boost_level2|0|1|0|0|1|1" \
        "mali_pollingtime|gpu_pollingtime|1|10|8|4|4|1" \
        "mali_upthreshold|gpu_upthreshold|10|100|88|72|55|30"; do
        _mk_key="${_mk_spec%%|*}"
        _mk_rest="${_mk_spec#*|}"
        _mk_node="$HSIN_GPU_KBASE/${_mk_rest%%|*}"
        _mk_rest2="${_mk_rest#*|}"
        _mk_min="${_mk_rest2%%|*}"
        _mk_rest3="${_mk_rest2#*|}"
        _mk_max="${_mk_rest3%%|*}"
        _mk_defs="${_mk_rest3#*|}"
        _mk_uk=$(hsin_uk_get "$_mk_key" 2>/dev/null)
        if [ -n "$_mk_uk" ]; then
            # Cek ulang di engine (pola tfo): file override bisa manual.
            _mk_bad=0
            case "$_mk_uk" in
                ''|*[!0-9]*) _mk_bad=1 ;;
                *)
                    [ "$_mk_uk" -lt "$_mk_min" ] 2>/dev/null && _mk_bad=1
                    [ "$_mk_uk" -gt "$_mk_max" ] 2>/dev/null && _mk_bad=1
                    ;;
            esac
            if [ "$_mk_bad" = "1" ]; then
                hsin_log_warn "gpu" "override $_mk_key=$_mk_uk ditolak: harus $_mk_min-$_mk_max"
                if [ "$_mk_manual" = "1" ]; then
                    hsin_uk_result "$_mk_key" "$_mk_uk" "-" "SKIPPED" "ditolak: di luar $_mk_min-$_mk_max (mode manual, tidak ditulis)" 2>/dev/null || true
                else
                    _mk_uk=""
                fi
            fi
        fi
        if [ -z "$_mk_uk" ]; then
            if [ "$_mk_manual" = "1" ]; then
                hsin_uk_result "$_mk_key" "(manual)" "-" "SKIPPED" "tidak diatur (mode manual)" 2>/dev/null || true
                continue
            fi
            # Nilai profil persis seperti sebelumnya (perilaku lama).
            _mk_v_bat=${_mk_defs%%|*}; _mk_rest4="${_mk_defs#*|}"
            _mk_v_bal=${_mk_rest4%%|*}; _mk_rest5="${_mk_rest4#*|}"
            _mk_v_perf=${_mk_rest5%%|*}; _mk_v_ext=${_mk_rest5#*|}
            _mk_req="(profil)"
            case "$_mk_profile" in
                battery)     _mk_v="$_mk_v_bat" ;;
                balanced)    _mk_v="$_mk_v_bal" ;;
                performance) _mk_v="$_mk_v_perf" ;;
                extreme)     _mk_v="$_mk_v_ext" ;;
                *)
                    # Profil tak dikenal = TIDAK menulis. Tanpa guard ini
                    # nilai kosong akan ditulis ke node kernel (bukan
                    # sekadar dilewati) - pelajaran dari bug variabel profil.
                    hsin_log_warn "gpu" "mali kbase: profile tidak dikenal, dilewati"
                    _mk_v=""
                    ;;
            esac
            [ -n "$_mk_v" ] || continue
        else
            _mk_v="$_mk_uk"
            _mk_req="$_mk_uk"
        fi
        if [ ! -f "$_mk_node" ] || [ ! -w "$_mk_node" ]; then
            hsin_uk_result "$_mk_key" "$_mk_req" "-" "UNAVAILABLE" "node ${_mk_node##*/} hilang atau read-only" 2>/dev/null || true
            continue
        fi
        if hsin_node_write_verify "$_mk_node" "$_mk_v"; then
            _mk_applied=$((_mk_applied + 1))
            if [ "$_mk_req" = "(profil)" ]; then
                hsin_uk_result "$_mk_key" "(profil)" "$_mk_v" "APPLIED" "nilai profil (tanpa override)" 2>/dev/null || true
            else
                hsin_uk_used "gpu" "$_mk_key" "$_mk_v"
            fi
        else
            _mk_now=$(hsin_node_read "$_mk_node" 2>/dev/null)
            [ -n "$_mk_now" ] || _mk_now="tidak terbaca"
            hsin_log_warn "gpu" "$_mk_key: tulis $_mk_v gagal (node tetap $_mk_now)"
            hsin_uk_result "$_mk_key" "$_mk_req" "$_mk_now" "FAILED" "tulis/readback gagal" 2>/dev/null || true
        fi
    done
    [ "$_mk_applied" -gt 0 ] && echo "    Mali kbase knobs: applied=$_mk_applied"
    return 0
}

return 0 2>/dev/null || true
