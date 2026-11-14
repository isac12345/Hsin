#!/system/bin/sh
# HSIN ADAPT - beban adaptif untuk semua aplikasi (ide "adaptasi tanpa batas").
#
# Ringkas:
#   - Modul mengukur kondisi nyata: kelancaran layar, tekanan CPU/IO, sisa RAM,
#     dan suhu. Bukan nama aplikasi, bukan daftar tetap.
#   - Tiap aplikasi punya catatan sendiri (adapt/<paket>.conf), dan catatan itu
#     DIGABUNG dari sesi ke sesi (satu baris per aplikasi, bukan per sesi).
#   - Tersendat terus -> beban naik. Lancar terus -> beban turun. 4 tingkat.
#   - Beban = parameter Mali kbase (domain milik modul). Batas tertinggi:
#     game 3, aplikasi biasa 2.
#   - Berhenti menaikkan bila suhu >= 50 C atau baterai <= 10%.
#   - Bantuan dilepas saat pindah aplikasi, layar mati, atau aplikasi ditutup.
#   - Bank/e-wallet dan kamera tidak disentuh. Saat ada panggilan, modul diam.
#
# Penulis kbase tetap satu: gb_kbase_apply() di gameboost.sh. Saat game,
# gameboost yang memulihkan nilai asli; di luar game, adapt.sh menyimpan dan
# memulihkan sendiri.

AD_DIR="${HSIN_CONF_DIR:-/data/adb/hsin}/adapt"
AD_STATE="${HSIN_CONF_DIR:-/data/adb/hsin}"
AD_TARGET_P1="${AD_TARGET_P1:-20}"
AD_AVG_MIN="${AD_AVG_MIN:-15}"
AD_STALL_JANK="${AD_STALL_JANK:-300}"
AD_PSI_CPU="${AD_PSI_CPU:-60}"
AD_PSI_IO="${AD_PSI_IO:-20}"
AD_MEM_MIN_KB="${AD_MEM_MIN_KB:-400000}"
AD_TEMP_MAX="${AD_TEMP_MAX:-200000}"   # tanpa batas suhu (pilihan pengguna)
AD_BATT_MIN="${AD_BATT_MIN:-10}"
AD_RAISE_SECS="${AD_RAISE_SECS:-5}"
AD_LOWER_SECS="${AD_LOWER_SECS:-40}"
AD_NONGAME_MAX="${AD_NONGAME_MAX:-1}"
AD_GAME_LOWER="${AD_GAME_LOWER:-0}"   # 0: beban game tidak diturunkan selama game berjalan
AD_CHG_MAX="${AD_CHG_MAX:-2}"       # batas beban saat mengisi daya

# Nilai kbase per beban: "boost poll upthreshold". Beban 0 = nilai bawaan
# kernel di HP uji (0/8/88), jadi beban 0 berarti tidak mengubah apa pun.
AD_KBASE_0="0 8 88"
AD_KBASE_1="0 4 75"
AD_KBASE_2="1 2 55"
AD_KBASE_3="1 1 30"

AD_PKG=""
AD_BEBAN=""
AD_BKEY=beban
AD_IS_GAME=0
AD_OPEN=0
AD_KBASE_OWN=0
AD_KB_SAVE1=""
AD_KB_SAVE2=""
AD_KB_SAVE3=""
AD_LAST_TS=0
AD_JANK_SECS=0
AD_CALM_SECS=0
AD_SN=0
AD_SS=0
AD_SJ=0
AD_SMIN=""
AD_SSTALL=0
AD_LAST_MENTOK=0

ad_log() {
    if type monitor_log >/dev/null 2>&1; then
        monitor_log "ADAPT" "$1"
    else
        printf '[%s] [ADAPT] %s\n' "$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date)" "$1" \
            >> "${HSIN_LOG_FILE:-/data/adb/hsin/hsin.log}" 2>/dev/null
    fi
}

ad_cget() {   # $1=pkg $2=key
    sed -n "s/^$2=//p" "$AD_DIR/$1.conf" 2>/dev/null | tail -n 1 | tr -d '[:space:]'
}

ad_cset() {   # $1=pkg $2=key $3=val  (ganti satu baris, sisanya tetap)
    mkdir -p "$AD_DIR" 2>/dev/null
    _f="$AD_DIR/$1.conf"
    touch "$_f" 2>/dev/null
    grep -v "^$2=" "$_f" > "$_f.tmp.$$" 2>/dev/null
    printf '%s=%s\n' "$2" "$3" >> "$_f.tmp.$$"
    mv -f "$_f.tmp.$$" "$_f" 2>/dev/null
}

ad_kbase_set() {   # $1=beban -> titip ke gameboost (satu penulis)
    case "$1" in
        0) _kv=$AD_KBASE_0 ;;
        1) _kv=$AD_KBASE_1 ;;
        2) _kv=$AD_KBASE_2 ;;
        3) _kv=$AD_KBASE_3 ;;
        *) return 0 ;;
    esac
    GB_KBASE_BOOST=${_kv%% *}
    _rest=${_kv#* }
    GB_KBASE_POLL=${_rest%% *}
    GB_KBASE_UP=${_rest##* }
}

# --- aplikasi yang tidak boleh disentuh ------------------------------------
# Daftar pola, satu per baris, dicocokkan ke nama paket (format case sh).
# User bisa menambah di $AD_STATE/adapt_deny.conf.
ad_deny_list() {
    # Satu pola per baris. Bawaan: kamera, bank, e-wallet, video call. Ini
    # pola nama, bukan daftar aplikasi tetap; salah tebak cukup tambah/hapus
    # baris di $AD_STATE/adapt_deny.conf (satu pola per baris).
    cat <<'ADSEED'
*camera*
*gcam*
*bank*
*wallet*
*dana*
*gopay*
*ovo*
*shopeepay*
*linkaja*
id.co.bri*
id.co.bni*
id.co.mandiri*
id.co.permata*
id.co.cimb*
id.co.btpn*
*zoom*
*meet*
*teams*
ADSEED
    [ -f "$AD_STATE/adapt_deny.conf" ] && cat "$AD_STATE/adapt_deny.conf"
}

ad_denied() {   # $1=pkg; return 0 = jangan disentuh
    while IFS= read -r _pat; do
        case "$_pat" in ''|'#'*) continue ;; esac
        # shellcheck disable=SC2254
        case "$1" in $_pat) return 0 ;; esac
    done <<ADEOF
$(ad_deny_list)
ADEOF
    return 1
}

# Panggilan telepon/video aktif = jangan sentuh apa pun.
ad_in_call() {
    dumpsys audio 2>/dev/null | grep -qE 'MODE_IN_COMMUNICATION|MODE_IN_CALL'
}

# --- pengukuran -------------------------------------------------------------
ad_psi() {   # $1=cpu|io -> some avg10
    sed -n 's/^some avg10=\([0-9][0-9]*\).*/\1/p' "/proc/pressure/$1" 2>/dev/null | head -n 1
}

ad_memavail_kb() {
    sed -n 's/^MemAvailable:[[:space:]]*\([0-9][0-9]*\).*/\1/p' /proc/meminfo 2>/dev/null | head -n 1
}

# Temp baterai dibaca dalam 0,1 C (mis. 361 = 36,1 C), lalu disimpan milli-C
# supaya sama dengan ambang AD_TEMP_MAX (50000 = 50 C).
ad_temp_mc() {
    _t=$(cat "${SYSFS_POWER_PREFIX:-/sys/class/power_supply}/battery/temp" 2>/dev/null | tr -d '[:space:]')
    case "$_t" in ''|*[!0-9]*) printf '0'; return ;; esac
    printf '%s' $((_t * 100))
}

ad_batt_pct() {
    cat "${SYSFS_POWER_PREFIX:-/sys/class/power_supply}/battery/capacity" 2>/dev/null | tr -d '[:space:]'
}

# --- kbase milik sendiri (di luar game) ------------------------------------
ad_gb_active() {
    [ -n "${GB_ACTIVE_FILE:-}" ] && [ -f "$GB_ACTIVE_FILE" ] && \
        [ "$(cat "$GB_ACTIVE_FILE" 2>/dev/null)" = "1" ]
}

ad_kbase_own_apply() {
    command -v gb_kbase_apply >/dev/null 2>&1 || return 0
    _kb="${SYSFS_MODULE_PREFIX:-/sys/module}/mali_kbase/parameters"
    [ -d "$_kb" ] || return 0
    ad_gb_active && return 0
    if [ "$AD_KBASE_OWN" != "1" ]; then
        AD_KB_SAVE1=$(cat "$_kb/gpu_boost_level2" 2>/dev/null | tr -d '[:space:]')
        AD_KB_SAVE2=$(cat "$_kb/gpu_pollingtime" 2>/dev/null | tr -d '[:space:]')
        AD_KB_SAVE3=$(cat "$_kb/gpu_upthreshold" 2>/dev/null | tr -d '[:space:]')
    fi
    gb_kbase_apply
    AD_KBASE_OWN=1
}

ad_kbase_own_restore() {
    [ "$AD_KBASE_OWN" = "1" ] || return 0
    _kb="${SYSFS_MODULE_PREFIX:-/sys/module}/mali_kbase/parameters"
    AD_KBASE_OWN=0
    case "$AD_KB_SAVE1$AD_KB_SAVE2$AD_KB_SAVE3" in
        ''|*[!0-9]*) return 0 ;;
    esac
    printf '%s\n' "$AD_KB_SAVE1" > "$_kb/gpu_boost_level2" 2>/dev/null
    printf '%s\n' "$AD_KB_SAVE2" > "$_kb/gpu_pollingtime" 2>/dev/null
    printf '%s\n' "$AD_KB_SAVE3" > "$_kb/gpu_upthreshold" 2>/dev/null
}

ad_charging() {
    case "$(cat /sys/class/power_supply/battery/status 2>/dev/null)" in Charging|Full) return 0 ;; esac
    return 1
}
ad_max_beban() {
    if [ "$AD_IS_GAME" = "1" ]; then _m=3; else _m=$AD_NONGAME_MAX; fi
    if ad_charging && [ "$_m" -gt "$AD_CHG_MAX" ]; then _m=$AD_CHG_MAX; fi
    printf '%s' "$_m"
}

ad_tier_beban() {   # beban awal aplikasi tanpa riwayat
    if [ "$AD_IS_GAME" = "1" ]; then
        printf '2'    # game baru mulai di beban 2 (pilihan pengguna)
    else
        printf '0'    # aplikasi biasa: mulai tanpa bantuan
    fi
}

ad_save() {   # tulis catatan GABUNGAN (bukan per sesi)
    [ -n "$AD_PKG" ] || return 0
    mkdir -p "$AD_DIR" 2>/dev/null
    _f="$AD_DIR/$AD_PKG.conf"
    touch "$_f" 2>/dev/null
    _n=$(ad_cget "$AD_PKG" n);        case "$_n" in ''|*[!0-9]*) _n=0 ;; esac
    _sum=$(ad_cget "$AD_PKG" sum_p1); case "$_sum" in ''|*[!0-9]*) _sum=0 ;; esac
    _min=$(ad_cget "$AD_PKG" p1_min); case "$_min" in ''|*[!0-9]*) _min="" ;; esac
    _stm=$(ad_cget "$AD_PKG" stall_max); case "$_stm" in ''|*[!0-9]*) _stm=0 ;; esac
    _jn=$(ad_cget "$AD_PKG" jank_n);  case "$_jn" in ''|*[!0-9]*) _jn=0 ;; esac
    _n=$((_n + AD_SN))
    _sum=$((_sum + AD_SS))
    _jn=$((_jn + AD_SJ))
    if [ -n "$AD_SMIN" ]; then
        if [ -z "$_min" ] || [ "$AD_SMIN" -lt "$_min" ]; then _min=$AD_SMIN; fi
    fi
    [ "$AD_SSTALL" -gt "$_stm" ] && _stm=$AD_SSTALL
    # Clamp: data lama bisa punya jank_n > n (mis. dua monitor sempat jalan
    # bersamaan). Persentase tidak boleh lebih dari 100.
    [ "$_jn" -gt "$_n" ] && _jn=$_n
    _avg=0; _jp=0
    [ "$_n" -gt 0 ] && { _avg=$((_sum / _n)); _jp=$((_jn * 100 / _n)); }
    grep -v -E '^(n|sum_p1|p1_min|stall_max|jank_n|p1_avg|jank_pct)=' "$_f" > "$_f.tmp.$$" 2>/dev/null
    printf 'n=%s\nsum_p1=%s\np1_min=%s\nstall_max=%s\njank_n=%s\np1_avg=%s\njank_pct=%s\n' \
        "$_n" "$_sum" "${_min:-0}" "$_stm" "$_jn" "$_avg" "$_jp" >> "$_f.tmp.$$"
    mv -f "$_f.tmp.$$" "$_f" 2>/dev/null
    AD_SN=0; AD_SS=0; AD_SJ=0; AD_SMIN=""; AD_SSTALL=0
}

ad_flush() {
    ad_save
    ad_cset "$AD_PKG" "${AD_BKEY:-beban}" "$AD_BEBAN"
    ad_cset "$AD_PKG" terakhir "$(date '+%Y-%m-%d %H:%M' 2>/dev/null || date)"
}

ad_open() {   # $1=pkg
    AD_PKG="$1"
    AD_IS_GAME=0
    command -v get_game_profile >/dev/null 2>&1 && \
        [ -n "$(get_game_profile "$1")" ] && AD_IS_GAME=1
    AD_OPEN=1
    AD_JANK_SECS=0
    AD_CALM_SECS=0
    AD_LAST_TS=$(date +%s 2>/dev/null)
    AD_SN=0; AD_SS=0; AD_SJ=0; AD_SMIN=""; AD_SSTALL=0
    if ad_charging; then AD_BKEY=beban_cas; else AD_BKEY=beban; fi
    AD_BEBAN=$(ad_cget "$1" "$AD_BKEY")
    # catatan lama yang tetap patah parah (>=60%) dibuang: mulai lagi dari awal
    _jp=$(ad_cget "$1" jank_pct); case "$_jp" in ''|*[!0-9]*) _jp=0 ;; esac
    [ "$_jp" -ge 60 ] 2>/dev/null && AD_BEBAN=""
    case "$AD_BEBAN" in ''|*[!0-9]*) AD_BEBAN=$(ad_tier_beban) ;; esac
    _max=$(ad_max_beban)
    [ "$AD_BEBAN" -gt "$_max" ] 2>/dev/null && AD_BEBAN=$_max
    _sesi=$(ad_cget "$1" sesi)
    case "$_sesi" in ''|*[!0-9]*) _sesi=0 ;; esac
    ad_cset "$1" sesi $((_sesi + 1))
    ad_apply
    ad_log "mulai $1 game=$AD_IS_GAME beban=$AD_BEBAN sesi=$((_sesi + 1))"
}

ad_apply() {   # pasang beban sekarang
    ad_kbase_set "$AD_BEBAN"
    # Penanda untuk APK (notifikasi/orb): paket|beban|game|epoch
    printf '%s|%s|%s|%s\n' "$AD_PKG" "$AD_BEBAN" "$AD_IS_GAME" "$(date +%s 2>/dev/null)" > "$AD_STATE/.adapt_now" 2>/dev/null
    if [ "$AD_IS_GAME" = "1" ]; then return 0; fi   # game: gameboost yang menulis
    if [ "$AD_BEBAN" -le 0 ] 2>/dev/null; then ad_kbase_own_restore; return 0; fi
    ad_kbase_own_apply
}

ad_end() {
    [ "$AD_OPEN" = "1" ] || return 0
    _tail=""
    ad_flush
    _tail="p1_min=$(ad_cget "$AD_PKG" p1_min) rata=$(ad_cget "$AD_PKG" p1_avg) jank=$(ad_cget "$AD_PKG" jank_pct)%"
    ad_kbase_own_restore
    rm -f "$AD_STATE/.adapt_now" 2>/dev/null
    ad_log "selesai $AD_PKG beban=$AD_BEBAN $_tail"
    AD_PKG=""
    AD_OPEN=0
    AD_BEBAN=""
    AD_JANK_SECS=0
    AD_CALM_SECS=0
}

ad_tick() {   # $1=pkg foreground. Dipanggil tiap tick monitor.
    _pkg="$1"
    case "$_pkg" in ''|*[!A-Za-z0-9._]*) return 0 ;; esac

    if ad_denied "$_pkg"; then
        [ "$AD_OPEN" = "1" ] && ad_end
        return 0
    fi
    if [ "$AD_OPEN" = "1" ] && [ "$AD_PKG" != "$_pkg" ]; then
        ad_end    # pindah aplikasi: semua kembali normal
    fi
    [ "$AD_OPEN" = "1" ] || ad_open "$_pkg"

    # --- ukur ---
    _st=""
    command -v monitor_fps_stat >/dev/null 2>&1 && \
        _st=$(monitor_fps_stat "${AD_STATE}/fpsd.out" 2>/dev/null)
    _p1=""; _avg=""; _stall=""
    if [ -n "$_st" ]; then
        _p1=${_st%% *}
        _rest=${_st#* }
        _avg=${_rest%% *}
        _stall=${_rest##* }
    fi
    case "$_p1$_avg$_stall" in
        ''|*[!0-9]*) _p1=""; _avg=""; _stall="" ;;
    esac
    _pc=$(ad_psi cpu); case "$_pc" in ''|*[!0-9]*) _pc=0 ;; esac
    _pi=$(ad_psi io);  case "$_pi" in ''|*[!0-9]*) _pi=0 ;; esac
    _mem=$(ad_memavail_kb); case "$_mem" in ''|*[!0-9]*) _mem=99999999 ;; esac
    _tmp=$(ad_temp_mc); case "$_tmp" in ''|*[!0-9]*) _tmp=0 ;; esac
    _bat=$(ad_batt_pct); case "$_bat" in ''|*[!0-9]*) _bat=100 ;; esac

    # --- nilai: tersendat atau lancar ---
    _jank=0; _calm=0; _why=""
    if [ -n "$_avg" ] && [ "$_avg" -ge "$AD_AVG_MIN" ]; then
        if [ "$_p1" -lt "$AD_TARGET_P1" ]; then _jank=1; _why="1%low=$_p1"; fi
        if [ "$_stall" -gt "$AD_STALL_JANK" ]; then _jank=1; _why=${_why:-"jeda=${_stall}ms"}; fi
    fi
    if [ "$_jank" -eq 0 ]; then
        if [ "$_pc" -ge "$AD_PSI_CPU" ]; then _jank=1; _why="tekanan cpu=$_pc"; fi
        if [ "$_pi" -ge "$AD_PSI_IO" ]; then _jank=1; _why=${_why:-"tekanan io=$_pi"}; fi
        if [ "$_mem" -lt "$AD_MEM_MIN_KB" ]; then _jank=1; _why=${_why:-"ram=$((_mem / 1024))MB"}; fi
    fi
    if [ "$_jank" -eq 0 ]; then
        _calm=1
        if [ -n "$_avg" ] && [ "$_avg" -ge "$AD_AVG_MIN" ]; then
            if [ -n "$_p1" ] && [ "$_p1" -lt "$AD_TARGET_P1" ]; then _calm=0; fi
        fi
        [ "$_pc" -ge 30 ] && _calm=0
        [ "$_pi" -ge 10 ] && _calm=0
        [ "$_mem" -lt 700000 ] && _calm=0
    fi

    # --- akumulasi waktu (bukan jumlah tick: interval game dan app beda) ---
    _now=$(date +%s 2>/dev/null)
    case "$_now" in ''|*[!0-9]*) _now=$AD_LAST_TS ;; esac
    _dt=$((_now - AD_LAST_TS))
    [ "$_dt" -gt 30 ] && _dt=30
    [ "$_dt" -lt 0 ] && _dt=0
    AD_LAST_TS=$_now
    if [ "$_jank" -eq 1 ]; then
        AD_JANK_SECS=$((AD_JANK_SECS + _dt)); AD_CALM_SECS=0
    elif [ "$_calm" -eq 1 ]; then
        AD_CALM_SECS=$((AD_CALM_SECS + _dt)); AD_JANK_SECS=0
    fi

    # --- catat sampel (gabungan) ---
    if [ -n "$_p1" ]; then
        AD_SN=$((AD_SN + 1))
        AD_SS=$((AD_SS + _p1))
        if [ -z "$AD_SMIN" ] || [ "$_p1" -lt "$AD_SMIN" ]; then AD_SMIN=$_p1; fi
        [ "${_stall:-0}" -gt "$AD_SSTALL" ] && AD_SSTALL=$_stall
        [ "$_jank" -eq 1 ] && AD_SJ=$((AD_SJ + 1))
    fi

    # --- putuskan ---
    _max=$(ad_max_beban)
    if [ "$AD_JANK_SECS" -ge "$AD_RAISE_SECS" ]; then
        AD_JANK_SECS=0
        if [ "$_tmp" -ge "$AD_TEMP_MAX" ]; then
            ad_log "tahan: suhu $((_tmp / 1000))C, tidak menaikkan beban ($AD_PKG)"
        elif [ "$_bat" -le "$AD_BATT_MIN" ]; then
            ad_log "tahan: baterai ${_bat}%, tidak menaikkan beban ($AD_PKG)"
        elif ad_in_call; then
            ad_log "tahan: ada panggilan aktif ($AD_PKG)"
        elif [ "${_why#ram=}" != "$_why" ]; then
            # RAM sempit bukan masalah GPU: menaikkan kbase tidak menolong.
            # Pembersihan RAM dilakukan tombol di APK (ROM ini tanpa am kill-all).
            if [ $((_now - AD_LAST_MENTOK)) -ge 120 ] 2>/dev/null; then
                AD_LAST_MENTOK=$_now
                ad_log "tahan: ram sempit ($_why), tidak menaikkan beban ($AD_PKG)"
            fi
        elif [ "$AD_BEBAN" -lt "$_max" ]; then
            AD_BEBAN=$((AD_BEBAN + 1))
            ad_apply
            ad_flush
            ad_log "naik: $AD_PKG beban=$AD_BEBAN ($_why) suhu=$((_tmp / 1000))C ram=$((_mem / 1024))MB"
        elif [ $((_now - AD_LAST_MENTOK)) -ge 120 ] 2>/dev/null; then
            AD_LAST_MENTOK=$_now
            ad_log "mentok: $AD_PKG beban=$AD_BEBAN ($_why) suhu=$((_tmp / 1000))C"
        fi
    elif [ "$AD_CALM_SECS" -ge "$AD_LOWER_SECS" ] && [ "$AD_BEBAN" -gt 0 ] && { [ "$AD_IS_GAME" != "1" ] || [ "$AD_GAME_LOWER" = "1" ]; }; then
        AD_CALM_SECS=0
        AD_BEBAN=$((AD_BEBAN - 1))
        ad_apply
        ad_flush
        ad_log "turun: $AD_PKG beban=$AD_BEBAN (lancar $AD_LOWER_SECS s)"
    fi
    return 0
}

# Dipanggil saat layar mati / monitor berhenti: lepas semua bantuan.
ad_release() {
    [ "$AD_OPEN" = "1" ] && ad_end
    return 0
}
