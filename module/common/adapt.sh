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
AD_P1_RATIO="${AD_P1_RATIO:-65}"     # 1% low < 65% rata-rata = frame pacing patah
AD_PSI_CPU="${AD_PSI_CPU:-60}"
AD_PSI_IO="${AD_PSI_IO:-20}"
AD_MEM_MIN_KB="${AD_MEM_MIN_KB:-400000}"
AD_TEMP_MAX="${AD_TEMP_MAX:-48000}"   # 48 C: berhenti menaikkan beban
AD_TEMP_CRIT="${AD_TEMP_CRIT:-50000}" # 50 C: langsung turunkan beban
# Suhu otak HP (thermal zone) dipakai sebagai pengaman tambahan: sensor baterai
# jarang naik di atas 42 C walau SoC sudah 69 C, jadi tanpa ini penahan panas
# tidak pernah bekerja saat main lama.
AD_SOC_MAX="${AD_SOC_MAX:-70000}"     # 70 C: berhenti menaikkan beban
AD_SOC_CRIT="${AD_SOC_CRIT:-75000}"   # 75 C: langsung turunkan beban
AD_BATT_MIN="${AD_BATT_MIN:-15}"
AD_RAISE_SECS="${AD_RAISE_SECS:-15}"
AD_LOWER_SECS="${AD_LOWER_SECS:-60}"
AD_MAX_RAISE="${AD_MAX_RAISE:-2}"     # maksimal kenaikan per sesi
AD_RAISE_RESET="${AD_RAISE_RESET:-600}"  # tiap 10 menit main: jatah naik diisi ulang
AD_WARM_SECS="${AD_WARM_SECS:-90}"     # awal sesi game: loading tidak memakai jatah naik
AD_CHG_GAP="${AD_CHG_GAP:-30}"        # jeda minimal antar perubahan beban
AD_EVAL_N="${AD_EVAL_N:-4}"           # sampel minimal sebelum menilai kenaikan
AD_HELP_JR="${AD_HELP_JR:-100}"       # jank <= 100/1000 = sudah cukup lancar
AD_HELP_GAIN="${AD_HELP_GAIN:-20}"    # atau >= 20% lebih baik dari sebelum naik
AD_NONGAME_MAX="${AD_NONGAME_MAX:-1}"
AD_GAME_LOWER="${AD_GAME_LOWER:-1}"   # 1: beban game boleh turun saat sudah lancar
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
AD_OPEN_TS=0
AD_LAST_RESET=0
AD_LAST_CHG=0
AD_RAISE_N=0
AD_PREV_JR=-1    # jank per 1000 sampel sebelum kenaikan terakhir
AD_WN=0          # sampel jendela sejak perubahan beban terakhir
AD_WJ=0          # sampel jendela yang tersendat
AD_TRIED_LVL=""  # tingkat hasil kenaikan yang sedang dinilai
AD_HELP_LVL=0    # tingkat tertinggi yang terbukti menolong sesi ini
AD_BAD_LVL=0     # tingkat yang terbukti tidak menolong sesi ini
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

# Suhu terpanas dari semua thermal zone (mili-C). 0 bila tidak terbaca.
ad_soc_temp_mc() {
    _zt="${SYSFS_THERMAL_PREFIX:-/sys/class/thermal}"
    _mx=0
    for _z in "$_zt"/thermal_zone*/temp; do
        [ -r "$_z" ] || continue
        _v=$(cat "$_z" 2>/dev/null | tr -d '[:space:]')
        case "$_v" in ''|*[!0-9]*) continue ;; esac
        [ "$_v" -lt 1000 ] 2>/dev/null && _v=$((_v * 1000))   # sebagian kernel pakai 0,1 C
        [ "$_v" -gt "$_mx" ] && _mx=$_v
    done
    printf '%s' "$_mx"
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

# Sisa tingkat boost dari sesi lama (monitor mati mendadak) dibersihkan saat
# tidak ada bantuan yang dibutuhkan, supaya GPU tidak tertinggal panas.
ad_kbase_fix_leftover() {
    command -v gb_kbase_apply >/dev/null 2>&1 || return 0
    _kb="${SYSFS_MODULE_PREFIX:-/sys/module}/mali_kbase/parameters"
    [ -d "$_kb" ] || return 0
    ad_gb_active && return 0
    _cur="$(cat "$_kb/gpu_boost_level2" 2>/dev/null | tr -d '[:space:]') $(cat "$_kb/gpu_pollingtime" 2>/dev/null | tr -d '[:space:]') $(cat "$_kb/gpu_upthreshold" 2>/dev/null | tr -d '[:space:]')"
    # Cocokkan juga pasangan poll+up saja: pernah kejadian node tertinggal
    # campuran (0/2/55) karena penulisan terputus saat monitor dimatikan.
    case "$_cur" in
        "$AD_KBASE_1"|"$AD_KBASE_2"|"$AD_KBASE_3") ;;
        *" ${AD_KBASE_1#* }"|*" ${AD_KBASE_2#* }"|*" ${AD_KBASE_3#* }") ;;
        *) return 0 ;;
    esac
    GB_KBASE_BOOST=${AD_KBASE_0%% *}
    _r0=${AD_KBASE_0#* }
    GB_KBASE_POLL=${_r0%% *}
    GB_KBASE_UP=${_r0#* }
    gb_kbase_apply
    ad_log "pulihkan sisa boost: $_cur -> $AD_KBASE_0"
}

ad_kbase_own_restore() {
    [ "$AD_KBASE_OWN" = "1" ] || return 0
    _kb="${SYSFS_MODULE_PREFIX:-/sys/module}/mali_kbase/parameters"
    AD_KBASE_OWN=0
    case "$AD_KB_SAVE1$AD_KB_SAVE2$AD_KB_SAVE3" in
        ''|*[!0-9]*) return 0 ;;
    esac
    # Kalau nilai "asli" yang tersimpan ternyata salah satu tingkat boost kita
    # sendiri (sisa sesi yang tidak sempat dipulihkan), jangan disalin lagi:
    # kembalikan ke nilai bawaan beban 0. Tanpa ini GPU bisa tertinggal di
    # tingkat 2 padahal tidak ada aplikasi yang sedang dibantu (panas + boros).
    case "$AD_KB_SAVE1 $AD_KB_SAVE2 $AD_KB_SAVE3" in
        "$AD_KBASE_1"|"$AD_KBASE_2"|"$AD_KBASE_3")
            AD_KB_SAVE1=${AD_KBASE_0%% *}
            _r2=${AD_KBASE_0#* }
            AD_KB_SAVE2=${_r2%% *}
            AD_KB_SAVE3=${_r2#* }
            ;;
    esac
    printf '%s\n' "$AD_KB_SAVE1" > "$_kb/gpu_boost_level2" 2>/dev/null
    printf '%s\n' "$AD_KB_SAVE2" > "$_kb/gpu_pollingtime" 2>/dev/null
    printf '%s\n' "$AD_KB_SAVE3" > "$_kb/gpu_upthreshold" 2>/dev/null
}

ad_charging() {
    case "$(cat "${SYSFS_POWER_PREFIX:-/sys/class/power_supply}/battery/status" 2>/dev/null)" in Charging|Full) return 0 ;; esac
    return 1
}
ad_wj_r() {   # jank per 1000 sampel sejak perubahan beban terakhir (-1 = belum ada)
    [ "${AD_WN:-0}" -gt 0 ] 2>/dev/null || { printf '%s' "-1"; return 0; }
    printf '%s' $((AD_WJ * 1000 / AD_WN))
}

# 1 = kenaikan terakhir menolong, 0 = tidak, -1 = sampel belum cukup
ad_raise_helped() {
    [ "${AD_WN:-0}" -ge "$AD_EVAL_N" ] 2>/dev/null || { printf '%s' "-1"; return 0; }
    _r=$(ad_wj_r)
    if [ "$_r" -le "$AD_HELP_JR" ]; then printf '1'; return 0; fi
    if [ "${AD_PREV_JR:--1}" -ge 0 ] 2>/dev/null && \
       [ "$_r" -le $((AD_PREV_JR - AD_PREV_JR * AD_HELP_GAIN / 100)) ]; then
        printf '1'; return 0
    fi
    printf '0'
}

ad_max_beban() {
    if [ "$AD_IS_GAME" = "1" ]; then _m=3; else _m=$AD_NONGAME_MAX; fi
    # Tingkat yang sudah terbukti tidak menolong tidak dicoba lagi sesi ini.
    if [ "${AD_BAD_LVL:-0}" -ge 2 ] 2>/dev/null && [ "$_m" -ge "$AD_BAD_LVL" ]; then
        _m=$((AD_BAD_LVL - 1))
    fi
    if ad_charging && [ "$_m" -gt "$AD_CHG_MAX" ]; then _m=$AD_CHG_MAX; fi
    printf '%s' "$_m"
}

ad_tier_beban() {   # beban awal aplikasi tanpa riwayat
    if [ "$AD_IS_GAME" = "1" ]; then
        printf '1'    # game baru mulai di beban 1, naik hanya bila perlu
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
    AD_RAISE_N=0
    AD_LAST_CHG=0
    AD_LAST_TS=$(date +%s 2>/dev/null)
    AD_OPEN_TS=$AD_LAST_TS
    AD_LAST_RESET=$AD_LAST_TS
    AD_WN=0; AD_WJ=0; AD_PREV_JR=-1
    AD_TRIED_LVL=""; AD_HELP_LVL=0; AD_BAD_LVL=0
    AD_SN=0; AD_SS=0; AD_SJ=0; AD_SMIN=""; AD_SSTALL=0
    if ad_charging; then AD_BKEY=beban_cas; else AD_BKEY=beban; fi
    AD_BEBAN=$(ad_cget "$1" "$AD_BKEY")
    # catatan lama yang tetap patah parah (>=60%) dibuang seluruhnya: beban dan
    # statistiknya. Kalau hanya beban yang dihapus, jank_pct tetap >=60 dan
    # setiap sesi berikutnya membuang beban lagi (ingatan tidak pernah dipakai).
    _jp=$(ad_cget "$1" jank_pct); case "$_jp" in ''|*[!0-9]*) _jp=0 ;; esac
    if [ "$_jp" -ge 60 ] 2>/dev/null; then
        AD_BEBAN=""
        _f="$AD_DIR/$1.conf"
        if [ -f "$_f" ]; then
            grep -v -E '^(n|sum_p1|p1_min|stall_max|jank_n|p1_avg|jank_pct)=' "$_f" > "$_f.tmp.$$" 2>/dev/null \
                && mv -f "$_f.tmp.$$" "$_f" 2>/dev/null
        fi
    fi
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
    AD_WN=0; AD_WJ=0; AD_TRIED_LVL=""   # jendela penilaian mulai dari sini
    # Penanda untuk APK (notifikasi/orb): paket|beban|game|epoch
    printf '%s|%s|%s|%s\n' "$AD_PKG" "$AD_BEBAN" "$AD_IS_GAME" "$(date +%s 2>/dev/null)" > "$AD_STATE/.adapt_now" 2>/dev/null
    if [ "$AD_IS_GAME" = "1" ]; then return 0; fi   # game: gameboost yang menulis
    if [ "$AD_BEBAN" -le 0 ] 2>/dev/null; then ad_kbase_own_restore; ad_kbase_fix_leftover; return 0; fi
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
    AD_WN=0; AD_WJ=0; AD_PREV_JR=-1
    AD_TRIED_LVL=""; AD_HELP_LVL=0; AD_BAD_LVL=0
}

ad_tick() {   # $1=pkg foreground. Dipanggil tiap tick monitor.
    _pkg="$1"
    case "$_pkg" in ''|*[!A-Za-z0-9._]*) return 0 ;; esac

    if ad_denied "$_pkg"; then
        [ "$AD_OPEN" = "1" ] && ad_end
        return 0
    fi
    # Mode Puncak (profil performance) mematikan Adapt: pengguna minta tenaga penuh.
    case "$(tr -d '[:space:]' < "$AD_STATE/active_profile" 2>/dev/null)" in
        performance|puncak|overdrive)
            [ "$AD_OPEN" = "1" ] && ad_end
            return 0
            ;;
    esac
    if [ "$AD_OPEN" = "1" ] && [ "$AD_PKG" != "$_pkg" ]; then
        ad_end    # pindah aplikasi: semua kembali normal
    fi
    [ "$AD_OPEN" = "1" ] || ad_open "$_pkg"

    # Pembersih RAM otomatis saat sempit (memfx: PSI + ambang + jeda sendiri).
    command -v mf_relief_tick >/dev/null 2>&1 && mf_relief_tick "$_pkg"

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
    _soc=$(ad_soc_temp_mc); case "$_soc" in ''|*[!0-9]*) _soc=0 ;; esac
    _bat=$(ad_batt_pct); case "$_bat" in ''|*[!0-9]*) _bat=100 ;; esac

    # --- nilai: tersendat atau lancar ---
    _jank=0; _calm=0; _why=""
    if [ -n "$_avg" ] && [ "$_avg" -ge "$AD_AVG_MIN" ]; then
        if [ "$_p1" -lt "$AD_TARGET_P1" ]; then _jank=1; _why="1%low=$_p1"; fi
        # Frame pacing: 1% low jauh di bawah rata-rata = ada drop besar walau
        # FPS rata-rata masih kelihatan bagus (mis. 30 turun ke 15 sebentar).
        if [ $((_p1 * 100)) -lt $((_avg * AD_P1_RATIO)) ]; then
            _jank=1; _why=${_why:-"p1=$_p1 rata=$_avg"}
        fi
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
            if [ -n "$_p1" ] && [ $((_p1 * 100)) -lt $((_avg * AD_P1_RATIO)) ]; then _calm=0; fi
        fi
        [ "$_pc" -ge 30 ] && _calm=0
        [ "$_pi" -ge 10 ] && _calm=0
        [ "$_mem" -lt 700000 ] && _calm=0
    fi

    AD_WN=$((AD_WN + 1))
    [ "$_jank" -eq 1 ] && AD_WJ=$((AD_WJ + 1))

    # --- akumulasi waktu (bukan jumlah tick: interval game dan app beda) ---
    _now=$(date +%s 2>/dev/null)
    case "$_now" in ''|*[!0-9]*) _now=$AD_LAST_TS ;; esac
    _dt=$((_now - AD_LAST_TS))
    [ "$_dt" -gt 30 ] && _dt=30
    [ "$_dt" -lt 0 ] && _dt=0
    AD_LAST_TS=$_now

    # Awal sesi game = loading dan pemanasan. Jangan pakai jatah naik di sini,
    # karena dulu dua kenaikan habis sebelum game benar-benar mulai.
    if [ "$AD_IS_GAME" = "1" ] && [ $((_now - AD_OPEN_TS)) -lt "$AD_WARM_SECS" ] 2>/dev/null; then
        _jank=0; _calm=0
    fi
    if [ "$_jank" -eq 1 ]; then
        AD_JANK_SECS=$((AD_JANK_SECS + _dt)); AD_CALM_SECS=0
    elif [ "$_calm" -eq 1 ]; then
        AD_CALM_SECS=$((AD_CALM_SECS + _dt)); AD_JANK_SECS=0
    fi

    # Sesi panjang (main 1-2 jam): jatah naik diisi ulang tiap 10 menit main,
    # tidak perlu menunggu lancar. Tanpa ini jatah habis di menit awal lalu area
    # berat yang datang belakangan tidak pernah ditolong.
    if [ $((_now - AD_LAST_RESET)) -ge "$AD_RAISE_RESET" ] 2>/dev/null; then
        AD_LAST_RESET=$_now
        if [ "$AD_RAISE_N" -gt 0 ]; then
            AD_RAISE_N=0
            ad_log "jatah naik diisi ulang ($(($AD_RAISE_RESET / 60)) menit main, $AD_PKG)"
        fi
        # Satu kesempatan lagi untuk tingkat yang dulu dinilai sia-sia, supaya
        # satu pengukuran keliru (mis. saat loading) tidak mengunci sesi.
        AD_BAD_LVL=0
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
    _gap_ok=0
    [ $((_now - AD_LAST_CHG)) -ge "$AD_CHG_GAP" ] 2>/dev/null && _gap_ok=1

    # Suhu kritis: menang atas segalanya, langsung turunkan satu tingkat.
    if [ "$_tmp" -ge "$AD_TEMP_CRIT" ] && [ "$AD_BEBAN" -gt 0 ] && [ "$_gap_ok" = "1" ]; then
        AD_BEBAN=$((AD_BEBAN - 1)); AD_LAST_CHG=$_now; AD_CALM_SECS=0; AD_JANK_SECS=0
        ad_apply; ad_flush
        ad_log "turun: suhu baterai $((_tmp / 1000))C kritis, beban=$AD_BEBAN ($AD_PKG)"
        return 0
    fi
    if [ "$_soc" -ge "$AD_SOC_CRIT" ] && [ "$AD_BEBAN" -gt 0 ] && [ "$_gap_ok" = "1" ]; then
        AD_BEBAN=$((AD_BEBAN - 1)); AD_LAST_CHG=$_now; AD_CALM_SECS=0; AD_JANK_SECS=0
        ad_apply; ad_flush
        ad_log "turun: suhu otak HP $((_soc / 1000))C kritis, beban=$AD_BEBAN ($AD_PKG)"
        return 0
    fi

    if [ "$AD_JANK_SECS" -ge "$AD_RAISE_SECS" ] && [ "$_gap_ok" = "1" ]; then
        AD_JANK_SECS=0
        _hlp=-1
        [ -n "$AD_TRIED_LVL" ] && _hlp=$(ad_raise_helped)
        if [ -n "$AD_TRIED_LVL" ] && [ "$_hlp" = "1" ]; then
            # Kenaikan terakhir terbukti menolong di perangkat ini: tingkat itu
            # dipertahankan, tidak diturunkan hanya karena masih ada tersendat.
            AD_HELP_LVL=$AD_TRIED_LVL
            AD_TRIED_LVL=""
            ad_log "tahan: naik ke $AD_HELP_LVL menolong (jank $(ad_wj_r)/1000, dulu ${AD_PREV_JR}/1000), tetap beban $AD_BEBAN ($AD_PKG)"
        elif [ -n "$AD_TRIED_LVL" ] && [ "$_hlp" = "0" ]; then
            # Kenaikan tidak menolong: mundur satu tingkat dan catat tingkat itu
            # supaya tidak dicoba lagi sesi ini (dulu naik-turun 1-2-3-1 terus,
            # dan itu sendiri yang bikin gambar patah).
            _bad=$AD_TRIED_LVL; _jr=$(ad_wj_r)
            AD_TRIED_LVL=""
            [ "$_bad" -ge 2 ] 2>/dev/null && AD_BAD_LVL=$_bad
            if [ "$AD_BEBAN" -gt 0 ] && { [ "$AD_IS_GAME" != "1" ] || [ "$AD_BEBAN" -gt 1 ]; }; then
                AD_BEBAN=$((AD_BEBAN - 1)); AD_LAST_CHG=$_now
                ad_apply; ad_flush
                ad_log "turun: naik ke $_bad tidak menolong (jank ${_jr}/1000), beban=$AD_BEBAN, beban $_bad dilewati sesi ini ($AD_PKG)"
            else
                ad_log "mentok: naik ke $_bad tidak menolong (jank ${_jr}/1000), tetap beban $AD_BEBAN ($AD_PKG)"
            fi
        elif [ -n "$AD_TRIED_LVL" ]; then
            :   # sampel belum cukup untuk menilai; jangan naik lagi dulu
        elif [ "$_tmp" -ge "$AD_TEMP_MAX" ]; then
            ad_log "tahan: suhu baterai $((_tmp / 1000))C, tidak menaikkan beban ($AD_PKG)"
        elif [ "$_soc" -ge "$AD_SOC_MAX" ]; then
            ad_log "tahan: suhu otak HP $((_soc / 1000))C, tidak menaikkan beban ($AD_PKG)"
        elif [ "$_bat" -le "$AD_BATT_MIN" ]; then
            ad_log "tahan: baterai ${_bat}%, tidak menaikkan beban ($AD_PKG)"
        elif ad_in_call; then
            ad_log "tahan: ada panggilan aktif ($AD_PKG)"
        elif [ "${_why#ram=}" != "$_why" ]; then
            # RAM sempit bukan masalah GPU: menaikkan kbase tidak menolong.
            # Pembersihan RAM otomatis lewat mf_relief_tick di atas.
            if [ $((_now - AD_LAST_MENTOK)) -ge 120 ] 2>/dev/null; then
                AD_LAST_MENTOK=$_now
                ad_log "tahan: ram sempit ($_why), tidak menaikkan beban ($AD_PKG)"
            fi
        elif [ "$AD_BEBAN" -lt "$_max" ] && [ "$AD_RAISE_N" -lt "$AD_MAX_RAISE" ]; then
            AD_PREV_JR=$(ad_wj_r)
            AD_BEBAN=$((AD_BEBAN + 1)); AD_RAISE_N=$((AD_RAISE_N + 1)); AD_LAST_CHG=$_now
            ad_apply
            AD_TRIED_LVL=$AD_BEBAN
            ad_flush
            ad_log "naik: $AD_PKG beban=$AD_BEBAN (ke-$AD_RAISE_N/$AD_MAX_RAISE) ($_why) suhu=$((_tmp / 1000))C ram=$((_mem / 1024))MB"
        elif [ "$AD_BEBAN" -gt "${AD_HELP_LVL:-0}" ] \
            && { [ "$AD_IS_GAME" != "1" ] || [ "$AD_BEBAN" -gt 1 ]; }; then
            # Tidak ada kenaikan yang bisa dinilai, tetapi masih tersendat:
            # mundur supaya tidak menambah panas. Tingkat yang sudah terbukti
            # menolong tidak diturunkan. Game berhenti di beban 1.
            AD_BEBAN=$((AD_BEBAN - 1)); AD_LAST_CHG=$_now
            ad_apply
            ad_flush
            ad_log "turun: naik tidak menolong, beban=$AD_BEBAN ($AD_PKG) ($_why)"
        elif [ $((_now - AD_LAST_MENTOK)) -ge 120 ] 2>/dev/null; then
            AD_LAST_MENTOK=$_now
            ad_log "mentok: $AD_PKG beban=$AD_BEBAN ($_why) suhu=$((_tmp / 1000))C"
        fi
    elif [ "$AD_CALM_SECS" -ge "$AD_LOWER_SECS" ] && [ -n "$AD_TRIED_LVL" ]; then
        # Lancar tepat setelah naik = naik itu menolong. Tingkatnya dipakai
        # terus, jangan diturunkan lagi (itu yang bikin naik-turun berulang).
        AD_CALM_SECS=0
        AD_HELP_LVL=$AD_TRIED_LVL; AD_TRIED_LVL=""
        ad_log "tahan: naik ke $AD_HELP_LVL menolong (lancar $AD_LOWER_SECS s), tetap beban $AD_BEBAN ($AD_PKG)"
    elif [ "$AD_CALM_SECS" -ge "$AD_LOWER_SECS" ] && [ "$AD_BEBAN" -gt "${AD_HELP_LVL:-0}" ] && [ "$_gap_ok" = "1" ] \
        && { [ "$AD_IS_GAME" != "1" ] || { [ "$AD_GAME_LOWER" = "1" ] && [ "$AD_BEBAN" -gt 1 ]; }; }; then
        AD_CALM_SECS=0
        AD_BEBAN=$((AD_BEBAN - 1)); AD_LAST_CHG=$_now
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
