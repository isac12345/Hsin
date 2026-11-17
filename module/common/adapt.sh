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
AD_STALL_LOADING="${AD_STALL_LOADING:-1500}"   # jeda >= ini = loading/pindah area, bukan render
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
AD_FPS_HOLD="${AD_FPS_HOLD:-92}"       # 1% low harus >= 92% kandidat FPS supaya dinilai sanggup
AD_CHG_GAP="${AD_CHG_GAP:-30}"        # jeda minimal antar perubahan beban
AD_EVAL_N="${AD_EVAL_N:-4}"           # sampel minimal sebelum menilai kenaikan
AD_HELP_JR="${AD_HELP_JR:-100}"       # jank <= 100/1000 = sudah cukup lancar
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
AD_FPS_TRIED=0   # batas FPS sudah dipilih sesi ini
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

# Adapt memegang frekuensi CPU/GPU selama game (spek "Adapt pengendali penuh").
# Penanda .adapt_own = Adapt satu-satunya penulis frekuensi; nilai asli di
# .adapt_prev; pid uperf/fas-rs yang dibekukan di .adapt_stopped.
AD_CPUFREQ="${HSIN_SYS_CPUFREQ:-/sys/devices/system/cpu/cpufreq}"
AD_DEVFREQ="${HSIN_SYS_DEVFREQ:-/sys/class/devfreq}"
AD_OWN_FILE="$AD_STATE/.adapt_own"
AD_OWN_PREV="$AD_STATE/.adapt_prev"
AD_OWN_STOP="$AD_STATE/.adapt_stopped"
AD_OWN=0         # 1 = sesi ini memegang frekuensi
AD_LCP=0         # lantai CPU sekarang (persen)
AD_LGPU=0        # lantai GPU sekarang (persen)
AD_OWN_LAST=0    # epoch perubahan lantai terakhir
AD_OWN_N=0       # jumlah perubahan lantai sesi ini
AD_OWN_FZ_TS=0   # epoch terakhir memeriksa pid yang lahir ulang
AD_OWN_T0=0      # epoch awal sesi memegang frekuensi
AD_OWN_HOLD=""   # persen lantai yang sedang ditahan (supaya log tidak berulang)
AD_OWN_UNK=0     # sudah memakai satu kenaikan saat suhu tidak terbaca

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

# ---- Adapt memegang frekuensi: simpan asli, bekukan uperf/fas-rs, pulihkan ----
ad_rd() { _adv=""; [ -r "$1" ] && read -r _adv < "$1" 2>/dev/null; printf '%s' "$_adv"; }
ad_wr() { printf '%s' "$2" > "$1" 2>/dev/null; }

ad_own_enabled() {   # sakelar: file ADAPT_OWN berisi "off" = mati
    [ "$(cat "$AD_STATE/ADAPT_OWN" 2>/dev/null | tr -d '[:space:]')" != "off" ]
}

ad_gpu_dir() {
    for _agd in "$AD_DEVFREQ"/*gpu* "$AD_DEVFREQ"/*mali* "$AD_DEVFREQ"/*kgsl* "$AD_DEVFREQ"/*ged* "$AD_DEVFREQ"/*pvr* "$AD_DEVFREQ"/*3d0*; do
        [ -f "$_agd/min_freq" ] && [ -f "$_agd/max_freq" ] && [ -f "$_agd/available_frequencies" ] && { printf '%s' "$_agd"; return 0; }
    done
    return 1
}

ad_own_freeze() {   # bekukan uperf/fas-rs; pid yang lahir ulang ikut dibekukan
    _owz=$(cat "$AD_OWN_STOP" 2>/dev/null)
    for _own in uperf fas-rs; do
        for _owp in $(pidof "$_own" 2>/dev/null); do
            case " $_owz " in *" $_owp "*) continue ;; esac
            kill -STOP "$_owp" 2>/dev/null && _owz="$_owz $_owp"
        done
    done
    printf '%s\n' "$_owz" > "$AD_OWN_STOP" 2>/dev/null
}

ad_own_mark() {   # penanda: paket, epoch mulai, lantai CPU/GPU sekarang (dibaca hsinctl status)
    [ -f "$AD_OWN_FILE" ] || return 0
    printf '%s\n%s\n%s/%s\n' "$AD_PKG" "${AD_OWN_T0:-0}" "$AD_LCP" "$AD_LGPU" > "$AD_OWN_FILE.tmp" 2>/dev/null \
        && mv -f "$AD_OWN_FILE.tmp" "$AD_OWN_FILE" 2>/dev/null
}

ad_own_thaw() {
    # Overdrive yang membeku ulang memegang pid-nya sendiri; ENGINE_MODE=off membekukan permanen.
    if [ ! -f "$AD_STATE/.ovd_stopped" ] && [ "$(cat "$AD_STATE/ENGINE_MODE" 2>/dev/null | tr -d '[:space:]')" != "off" ]; then
        for _owp in $(cat "$AD_OWN_STOP" 2>/dev/null); do kill -CONT "$_owp" 2>/dev/null; done
    fi
    rm -f "$AD_OWN_STOP"
}

ad_own_on() {   # $1=pkg; return 0 = Adapt memegang frekuensi sesi ini
    [ "$AD_OWN" = "1" ] && return 0
    ad_own_enabled || return 1
    [ -f "$AD_STATE/.ovd_active" ] && return 1
    # sisa sesi lama (crash): pulihkan dulu supaya nilai asli yang tersimpan benar
    if [ -f "$AD_OWN_FILE" ] || [ -f "$AD_OWN_PREV" ] || [ -f "$AD_OWN_STOP" ]; then ad_own_off recover; fi
    : > "$AD_OWN_PREV.tmp" 2>/dev/null || { ad_log "[OWN] gagal menyimpan nilai asli, jalan seperti biasa"; return 1; }
    _owok=0
    for _owd in "$AD_CPUFREQ"/policy*; do
        [ -f "$_owd/scaling_min_freq" ] && [ -f "$_owd/scaling_max_freq" ] || continue
        [ -w "$_owd/scaling_min_freq" ] && [ -w "$_owd/scaling_max_freq" ] && _owok=1
        printf 'cpu|%s|%s|%s\n' "$_owd" "$(ad_rd "$_owd/scaling_min_freq")" "$(ad_rd "$_owd/scaling_max_freq")" >> "$AD_OWN_PREV.tmp"
    done
    _owg=$(ad_gpu_dir) && printf 'gpu|%s|%s|%s\n' "$_owg" "$(ad_rd "$_owg/min_freq")" "$(ad_rd "$_owg/max_freq")" >> "$AD_OWN_PREV.tmp"
    if [ "$_owok" != "1" ]; then
        rm -f "$AD_OWN_PREV.tmp"
        ad_log "[OWN] node frekuensi CPU tidak bisa ditulis, jalan seperti biasa (tabel profil + gameboost)"
        return 1
    fi
    mv -f "$AD_OWN_PREV.tmp" "$AD_OWN_PREV" 2>/dev/null
    AD_OWN_T0=$(date +%s 2>/dev/null)
    printf '%s\n%s\n0/0\n' "$1" "$AD_OWN_T0" > "$AD_OWN_FILE" 2>/dev/null
    ad_own_freeze
    AD_OWN=1; AD_LCP=0; AD_LGPU=0; AD_OWN_LAST=0; AD_OWN_N=0; AD_OWN_HOLD=""; AD_OWN_UNK=0
    AD_OWN_FZ_TS=$(date +%s 2>/dev/null)
    ad_log "[OWN] mulai $1 lantai=0/0"
    return 0
}

ad_own_off() {   # $1=alasan (opsional); pulihkan nilai asli, lanjutkan uperf/fas-rs, hapus penanda
    _owsaw=$AD_OWN
    if [ -f "$AD_OWN_PREV" ]; then
        while IFS='|' read -r _owt _owd _owmn _owmx; do
            [ -n "$_owd" ] && [ -d "$_owd" ] || continue
            case "$_owt" in
                cpu) case "$_owmn" in ''|*[!0-9]*) ;; *) ad_wr "$_owd/scaling_min_freq" "$_owmn" ;; esac   # turunkan min dulu, baru max
                     case "$_owmx" in ''|*[!0-9]*) ;; *) ad_wr "$_owd/scaling_max_freq" "$_owmx" ;; esac ;;
                gpu) case "$_owmn" in ''|*[!0-9]*) ;; *) ad_wr "$_owd/min_freq" "$_owmn" ;; esac
                     case "$_owmx" in ''|*[!0-9]*) ;; *) ad_wr "$_owd/max_freq" "$_owmx" ;; esac ;;
            esac
        done < "$AD_OWN_PREV"
    fi
    ad_own_thaw
    rm -f "$AD_OWN_FILE" "$AD_OWN_PREV"
    if [ "$_owsaw" = "1" ] || [ "${1:-}" = "recover" ]; then
        _owtm=$(ad_temp_mc); case "$_owtm" in ''|*[!0-9]*) _owtm=0 ;; esac
        ad_log "[OWN] selesai ${AD_PKG:-sisa lama} (${AD_OWN_N} perubahan, suhu $((_owtm / 1000))C)${1:+ [$1]}"
    fi
    AD_OWN=0; AD_LCP=0; AD_LGPU=0; AD_OWN_LAST=0; AD_OWN_N=0
}

ad_own_recover() {   # penanda tanpa sesi terbuka = sisa lama (crash/monitor mulai ulang)
    [ "$AD_OWN" = "1" ] && return 0
    [ -f "$AD_OWN_FILE" ] || [ -f "$AD_OWN_PREV" ] || [ -f "$AD_OWN_STOP" ] || return 0
    ad_own_off recover
}

# ---- lantai CPU/GPU dari beban (semua angka dari daftar frekuensi HP) ----
ad_own_pct() {   # beban -> persen lantai; 0 = tidak menulis lantai (biarkan kernel)
    case "$1" in 1) printf 50 ;; 2) printf 70 ;; 3) printf 90 ;; *) printf 0 ;; esac
}

# $1=persen $2=direktori policy CPU atau devfreq GPU -> frekuensi tersedia terkecil
# yang >= persen dari frekuensi tertinggi. Amplop: tidak di bawah cpuinfo_min_freq
# dan tidak di atas cpuinfo_max_freq (bila node itu ada).
ad_own_floor() {
    _ofd=$2
    _ofl=$(cat "$_ofd/scaling_available_frequencies" 2>/dev/null)
    [ -n "$_ofl" ] || _ofl=$(cat "$_ofd/available_frequencies" 2>/dev/null)
    _ofhi=$(ad_rd "$_ofd/cpuinfo_max_freq"); _oflo=$(ad_rd "$_ofd/cpuinfo_min_freq")
    case "$_ofhi" in ''|*[!0-9]*) _ofhi="" ;; esac
    case "$_oflo" in ''|*[!0-9]*) _oflo="" ;; esac
    _ofmax=""
    for _off in $_ofl; do
        case "$_off" in ''|*[!0-9]*) continue ;; esac
        [ -n "$_ofhi" ] && [ "$_off" -gt "$_ofhi" ] && continue
        [ -n "$_oflo" ] && [ "$_off" -lt "$_oflo" ] && continue
        if [ -z "$_ofmax" ] || [ "$_off" -gt "$_ofmax" ]; then _ofmax=$_off; fi
    done
    [ -n "$_ofmax" ] || return 1
    _oft=$(( (_ofmax / 100) * $1 ))
    _ofbest=""
    for _off in $_ofl; do
        case "$_off" in ''|*[!0-9]*) continue ;; esac
        [ -n "$_ofhi" ] && [ "$_off" -gt "$_ofhi" ] && continue
        [ -n "$_oflo" ] && [ "$_off" -lt "$_oflo" ] && continue
        [ "$_off" -ge "$_oft" ] || continue
        if [ -z "$_ofbest" ] || [ "$_off" -lt "$_ofbest" ]; then _ofbest=$_off; fi
    done
    printf '%s' "${_ofbest:-$_ofmax}"
}

ad_own_orig() {   # $1=direktori $2=min|max -> nilai asli dari .adapt_prev
    while IFS='|' read -r _oot _ood _oomn _oomx; do
        [ "$_ood" = "$1" ] || continue
        if [ "$2" = "min" ]; then printf '%s' "$_oomn"; else printf '%s' "$_oomx"; fi
        return 0
    done < "$AD_OWN_PREV"
    return 1
}

# $1=node min $2=node max $3=target min $4=batas max. Naik: tulis max dulu lalu min.
# Turun: tulis min saja (max tetap; nilai asli dipulihkan di ad_own_off).
ad_own_put() {
    _opc=$(ad_rd "$2")
    case "$_opc" in ''|*[!0-9]*) _opc=0 ;; esac
    [ "$3" -gt "$_opc" ] && ad_wr "$2" "$4"
    ad_wr "$1" "$3"
    [ "$(ad_rd "$1")" = "$3" ]
}

# Kenaikan lantai ditahan oleh suhu, baterai, atau pembacaan yang tidak ada.
# Alasan diisi ke AD_OWN_WHY, return 0 bila harus ditahan. Jangan dipanggil
# lewat $(...): AD_OWN_UNK harus tersimpan di shell induk (satu kenaikan saja).
ad_own_block_raise() {
    AD_OWN_WHY=""
    _obt=$(ad_temp_mc); _obs=$(ad_soc_temp_mc); _obb=$(ad_batt_pct)
    case "$_obt" in ''|*[!0-9]*) _obt=0 ;; esac
    case "$_obs" in ''|*[!0-9]*) _obs=0 ;; esac
    case "$_obb" in ''|*[!0-9]*) _obb=100 ;; esac
    if [ "$_obt" -ge "$AD_TEMP_MAX" ]; then AD_OWN_WHY="baterai $((_obt / 1000))C"; return 0; fi
    if [ "$_obs" -ge "$AD_SOC_MAX" ]; then AD_OWN_WHY="SoC $((_obs / 1000))C"; return 0; fi
    if [ "$_obb" -le "$AD_BATT_MIN" ] && ! ad_charging; then AD_OWN_WHY="baterai ${_obb}%"; return 0; fi
    if [ "$_obt" -eq 0 ] && [ "$_obs" -eq 0 ]; then
        # suhu tidak terbaca: anggap normal, tapi hanya satu kenaikan per sesi
        if [ "${AD_OWN_UNK:-0}" = "1" ]; then AD_OWN_WHY="suhu tidak terbaca"; return 0; fi
        AD_OWN_UNK=1
    fi
    return 1
}

ad_own_apply() {   # pasang lantai dari AD_BEBAN (dipanggil tiap perubahan beban dan tiap tick)
    [ "$AD_OWN" = "1" ] || return 0
    [ -f "$AD_OWN_FILE" ] || return 0
    _oap=$(ad_own_pct "$AD_BEBAN")
    [ "$_oap" = "$AD_LCP" ] && return 0
    _oan=$(date +%s 2>/dev/null); case "$_oan" in ''|*[!0-9]*) _oan=0 ;; esac
    # Kenaikan: jeda >=20 dtk, maksimal 3 perubahan per sesi, dan batas suhu/baterai.
    # Turun selalu boleh. Pasangan awal sesi (AD_OWN_LAST=0) sampai 50% tidak ditahan.
    if [ "$_oap" -gt "$AD_LCP" ] && ! { [ "$AD_OWN_LAST" = "0" ] && [ "$_oap" -le 50 ]; }; then
        if [ "$AD_OWN_LAST" != "0" ] && [ $((_oan - AD_OWN_LAST)) -lt 20 ]; then return 0; fi
        if [ "$AD_OWN_N" -ge 3 ]; then return 0; fi
        if ad_own_block_raise; then
            [ "$AD_OWN_HOLD" != "$_oap" ] && ad_log "[OWN] lantai ${AD_LCP}%->${_oap}% ditahan ($AD_OWN_WHY)"
            AD_OWN_HOLD=$_oap
            return 0
        fi
    fi
    _oaok=0; _oabad=0
    for _oad in "$AD_CPUFREQ"/policy*; do
        [ -f "$_oad/scaling_min_freq" ] && [ -w "$_oad/scaling_min_freq" ] || continue
        if [ "$_oap" -le 0 ]; then
            _oat=$(ad_own_orig "$_oad" min)
        else
            _oat=$(ad_own_floor "$_oap" "$_oad")
        fi
        case "$_oat" in ''|*[!0-9]*) continue ;; esac
        _oac=$(ad_rd "$_oad/cpuinfo_max_freq"); [ -n "$_oac" ] || _oac=$(ad_own_floor 100 "$_oad")
        if ad_own_put "$_oad/scaling_min_freq" "$_oad/scaling_max_freq" "$_oat" "$_oac"; then
            _oaok=$((_oaok + 1)); ad_log "[CPU] ${_oad##*/} ${AD_LCP}%->${_oap}% =$_oat"
        else
            _oabad=$((_oabad + 1)); ad_log "[CPU] ${_oad##*/} ditolak kernel (target $_oat)"
        fi
    done
    _oagd=$(ad_gpu_dir)
    if [ -n "$_oagd" ] && [ -w "$_oagd/min_freq" ]; then
        if [ "$_oap" -le 0 ]; then _oat=$(ad_own_orig "$_oagd" min); else _oat=$(ad_own_floor "$_oap" "$_oagd"); fi
        case "$_oat" in ''|*[!0-9]*) ;; *)
            _oac=$(ad_own_floor 100 "$_oagd")
            if ad_own_put "$_oagd/min_freq" "$_oagd/max_freq" "$_oat" "$_oac"; then
                ad_log "[GPU] ${AD_LGPU}%->${_oap}% =$_oat"; AD_LGPU=$_oap
            else
                ad_log "[GPU] ditolak kernel (target $_oat)"
            fi ;;
        esac
    fi
    if [ "$_oaok" -eq 0 ] && [ "$_oabad" -gt 0 ]; then
        # Semua policy menolak: sesi ini jatuh ke perilaku lama (tabel profil + gameboost).
        ad_own_off "gagal menulis"
        ad_log "[OWN] kernel menolak lantai, sesi ini memakai tabel profil + gameboost"
        return 1
    fi
    AD_LCP=$_oap
    AD_OWN_HOLD=""
    [ "$AD_OWN_LAST" != "0" ] && AD_OWN_N=$((AD_OWN_N + 1))
    AD_OWN_LAST=$_oan
    ad_own_mark
    return 0
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
        # Sebagian zona di ROM tertentu melaporkan angka ngawur (930 C, 114 C).
        # Tanpa saringan ini nilai itu terbaca sebagai kritis dan menurunkan
        # beban tanpa sebab. Batas wajar SoC: di bawah 105 C.
        [ "$_v" -gt 105000 ] 2>/dev/null && continue
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
# --- batas FPS sesuai kemampuan perangkat --------------------------------
ad_fps_cur() {   # batas fps yang sekarang dipasang untuk $1 (kosong = belum ada)
    sed -n "s/^$(printf '%s' "$1" | sed 's/\./\\./g'):fps=//p" \
        "$AD_STATE/game_opts.conf" 2>/dev/null | tail -n 1 | tr -d '[:space:]'
}

# Refresh tertinggi yang 1% low-nya masih >= AD_FPS_HOLD persen: itulah batas
# yang perangkat ini benar-benar sanggup, bukan angka statis per kelas HP.
ad_fps_pick() {   # $1=rata $2=1%low
    _mx=$(sed -n 's/^REFRESH_MAX=//p' "$AD_STATE/device_profile.env" 2>/dev/null | tail -n 1)
    case "$_mx" in ''|*[!0-9]*) return 0 ;; esac
    for _r in 144 120 90 60 30; do
        [ "$_r" -le "$_mx" ] || continue
        [ "$2" -ge $((_r * AD_FPS_HOLD / 100)) ] 2>/dev/null && { printf '%s' "$_r"; return 0; }
    done
}

ad_gamefps_set() {   # $1=pkg $2=fps -> tulis batas fps + refresh lewat hsinctl
    sh "${AD_HSC:-${MODDIR:-/data/adb/modules/hsin}/common/hsinctl.sh}" \
        gamefps set "$1" "$2" 2>&1
}

ad_fps_once() {   # $1=rata $2=1%low; dipakai sekali per sesi game
    case "${1:-}:${2:-}" in *[!0-9:]*|:*|*:) return 0 ;; esac
    _cur=$(ad_fps_cur "$AD_PKG")
    # Batas yang sudah ada (diatur pengguna atau seed) tidak ditimpa.
    [ -z "$_cur" ] || [ "$_cur" = "off" ] || return 0
    _fps=$(ad_fps_pick "$1" "$2")
    [ -n "$_fps" ] || return 0
    _fso=$(ad_gamefps_set "$AD_PKG" "$_fps")
    if [ $? -eq 0 ]; then
        ad_cset "$AD_PKG" fps_auto "$_fps"
        ad_log "fps: batas $_fps dipilih dari ukur (rata=$1 p1=$2), aktif saat game dibuka lagi ($AD_PKG)"
    else
        ad_log "fps: gagal menyimpan batas $_fps untuk $AD_PKG ($_fso)"
    fi
}

ad_wj_r() {   # jank per 1000 sampel sejak perubahan beban terakhir (-1 = belum ada)
    [ "${AD_WN:-0}" -gt 0 ] 2>/dev/null || { printf '%s' "-1"; return 0; }
    printf '%s' $((AD_WJ * 1000 / AD_WN))
}

# 1 = kenaikan terakhir menolong, 0 = tidak, -1 = sampel belum cukup.
# Menolong = jank berkurang sama sekali dibanding sebelum naik (bukan pakai
# ambang persen yang perlu disetel per HP), atau jendela sudah cukup lancar.
ad_raise_helped() {
    [ "${AD_WN:-0}" -ge "$AD_EVAL_N" ] 2>/dev/null || { printf '%s' "-1"; return 0; }
    _r=$(ad_wj_r)
    if [ "$_r" -le "$AD_HELP_JR" ]; then printf '1'; return 0; fi
    if [ "${AD_PREV_JR:--1}" -ge 0 ] 2>/dev/null && [ "$_r" -lt "$AD_PREV_JR" ]; then
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
        # profil performance: mulai dari beban tertinggi (turun sendiri saat tenang); lainnya mulai 1
        case "$(tr -d '[:space:]' < "$AD_STATE/active_profile" 2>/dev/null)" in
            performance) printf '3' ;;
            *) printf '1' ;;    # game baru mulai di beban 1, naik hanya bila perlu
        esac
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
    AD_LAST_AVG=""
    AD_LAST_CHG=0
    AD_LAST_TS=$(date +%s 2>/dev/null)
    AD_OPEN_TS=$AD_LAST_TS
    AD_LAST_RESET=$AD_LAST_TS
    AD_WN=0; AD_WJ=0; AD_PREV_JR=-1; AD_FPS_TRIED=0
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
    [ "$AD_IS_GAME" = "1" ] && ad_own_on "$1"
    [ "$AD_IS_GAME" = "1" ] && [ "$_sesi" -eq 0 ] && ad_seed_game "$1"
    ad_apply
    ad_log "mulai $1 game=$AD_IS_GAME beban=$AD_BEBAN sesi=$((_sesi + 1))"
}

ad_apply() {   # pasang beban sekarang
    ad_kbase_set "$AD_BEBAN"
    AD_WN=0; AD_WJ=0; AD_TRIED_LVL=""   # jendela penilaian mulai dari sini
    # Penanda untuk APK (notifikasi/orb): paket|beban|game|epoch
    # Ditulis lewat tmp+mv: APK tidak boleh membaca baris separuh.
    printf '%s|%s|%s|%s\n' "$AD_PKG" "$AD_BEBAN" "$AD_IS_GAME" "$(date +%s 2>/dev/null)" \
        > "$AD_STATE/.adapt_now.tmp.$$" 2>/dev/null \
        && mv -f "$AD_STATE/.adapt_now.tmp.$$" "$AD_STATE/.adapt_now" 2>/dev/null
    if [ "$AD_IS_GAME" = "1" ]; then ad_own_apply; return 0; fi   # game: Adapt memasang lantai bila memegang frekuensi; kbase tetap lewat gameboost
    if [ "$AD_BEBAN" -le 0 ] 2>/dev/null; then ad_kbase_own_restore; ad_kbase_fix_leftover; return 0; fi
    ad_kbase_own_apply
}

# ---- benih perangkat: game baru (belum ada riwayat) tidak mulai dari 100% ----
# Kelas perangkat dari jumlah core dan frekuensi CPU tertinggi (kHz). Ambang bebas:
#   low  = core <= 6 atau frekuensi tertinggi < 2,0 GHz
#   high = core >= 8 dan frekuensi tertinggi >= 2,8 GHz
#   mid  = selain itu
# Benih resolusi: HP yang lebih lemah mulai lebih rendah (low 80, mid 85, high 90);
# ad_auto_tune lalu menggeser dari hasil ukur. Benih FPS: refresh layar, satu tangga
# lebih rendah untuk kelas low. Disimpan di device_profile.env (scan ulang tweaks.sh
# menimpa berkas itu, jadi dihitung lagi bila kuncinya hilang).
ad_dev_seed() {
    _dpf="$AD_STATE/device_profile.env"
    grep -q '^AD_DS_SEED=' "$_dpf" 2>/dev/null && return 0
    _dcd="${HSIN_SYS_CPU:-/sys/devices/system/cpu}"
    _dn=0
    for _dc in "$_dcd"/cpu[0-9]*; do [ -d "$_dc" ] && _dn=$((_dn + 1)); done
    _dmx=0
    for _dc in "$AD_CPUFREQ"/policy*; do
        _dv=$(ad_rd "$_dc/cpuinfo_max_freq"); case "$_dv" in ''|*[!0-9]*) continue ;; esac
        [ "$_dv" -gt "$_dmx" ] && _dmx=$_dv
    done
    [ "$_dn" -gt 0 ] && [ "$_dmx" -gt 0 ] || return 1   # tidak terbaca: jangan menebak
    if [ "$_dn" -le 6 ] || [ "$_dmx" -lt 2000000 ]; then _dt=low; _dds=80
    elif [ "$_dn" -ge 8 ] && [ "$_dmx" -ge 2800000 ]; then _dt=high; _dds=90
    else _dt=mid; _dds=85; fi
    _drm=$(sed -n 's/^REFRESH_MAX=//p' "$_dpf" 2>/dev/null | tail -n 1); case "$_drm" in ''|*[!0-9]*) _drm=60 ;; esac
    _dfp=30
    for _dl in 30 45 60 90 120; do [ "$_dl" -le "$_drm" ] && _dfp=$_dl; done
    [ "$_dt" = low ] && _dfp=$(ad_fps_step down "$_dfp")
    { printf 'AD_DEV_TIER=%s\nAD_DS_SEED=%s\nAD_FPS_SEED=%s\n' "$_dt" "$_dds" "$_dfp"; } >> "$_dpf" 2>/dev/null
    ad_log "benih perangkat: kelas=$_dt core=$_dn cpu_max=${_dmx}kHz resolusi=${_dds}% fps=$_dfp"
    return 0
}

ad_seed_game() {   # $1=pkg game tanpa riwayat: pasang benih resolusi + FPS lewat hsinctl gameauto
    _sgp="$1"
    _sgo=$(printf '%s' "$_sgp" | sed 's/\./\\./g')
    [ "$(sed -n "s/^$_sgo:AUTO=//p" "$AD_STATE/game_opts.conf" 2>/dev/null | tail -n 1)" = "off" ] && return 0
    # pilihan yang sudah ada (pengguna atau sesi lama) tidak ditimpa
    grep -q "^$_sgo:\(downscale\|fps\)=" "$AD_STATE/game_opts.conf" 2>/dev/null && return 0
    ad_dev_seed || return 0
    _sgd=$(sed -n 's/^AD_DS_SEED=//p' "$AD_STATE/device_profile.env" 2>/dev/null | tail -n 1)
    _sgf=$(sed -n 's/^AD_FPS_SEED=//p' "$AD_STATE/device_profile.env" 2>/dev/null | tail -n 1)
    case "$_sgd" in ''|*[!0-9]*) return 0 ;; esac
    case "$_sgf" in ''|*[!0-9]*) _sgf=keep ;; esac
    _sgo2=$(sh "${AD_HSC:-${MODDIR:-/data/adb/modules/hsin}/common/hsinctl.sh}" \
        gameauto set "$_sgp" "$(ad_ds_fmt "$_sgd")" "$_sgf" 2>&1) \
        || ad_log "benih: $_sgp gagal disimpan ($_sgo2)"
    ad_log "benih: $_sgp resolusi ${_sgd}% fps $_sgf (game baru, berlaku saat dibuka berikutnya)"
}

# ---- saran resolusi (sekali pakai): dihitung di akhir sesi game dari catatan gabungan ----
ad_ds_pct() {   # nilai downscale game_opts -> persen bulat (off/kosong = 100)
    case "$1" in
        ''|off|default|1|1.0|1.00) printf '100' ;;
        0.[0-9]) printf '%s0' "${1#0.}" ;;
        0.[0-9][0-9]) printf '%s' "${1#0.}" ;;
        *) printf '100' ;;
    esac
}

ad_saran() {   # $1=pkg game; tulis saran/saran_why/saran_ts ke catatan, atau hapus bila tidak ada alasan
    _sp="$1"
    _jp=$(ad_cget "$_sp" jank_pct); _pa=$(ad_cget "$_sp" p1_avg)
    _sm=$(ad_cget "$_sp" stall_max); _sn=$(ad_cget "$_sp" n)
    for _v in "$_jp" "$_pa" "$_sm" "$_sn"; do case "$_v" in ''|*[!0-9]*) return 0 ;; esac; done
    _fps=$(ad_fps_cur "$_sp"); case "$_fps" in ''|*[!0-9]*|0) _fps=0 ;; esac
    _cur=$(ad_ds_pct "$(sed -n "s/^$(printf '%s' "$_sp" | sed 's/\./\\./g'):downscale=//p" "$AD_STATE/game_opts.conf" 2>/dev/null | tail -n 1 | tr -d '[:space:]')")
    _new=""; _why=""
    if [ "$_jp" -ge 30 ]; then _new=$((_cur - 5)); _why="sering tersendat (${_jp}%)"
    elif [ "$_fps" -gt 0 ] && [ $((_pa * 100)) -lt $((_fps * 60)) ]; then _new=$((_cur - 5)); _why="1% low rendah (${_pa} fps)"
    elif [ "$_sm" -gt 400 ]; then _new=$((_cur - 5)); _why="ada jeda ${_sm} ms"
    elif [ "$_jp" -le 5 ] && [ "$_fps" -gt 0 ] && [ $((_pa * 100)) -ge $((_fps * 90)) ] && [ "$_sn" -ge 300 ]; then
        _new=$((_cur + 5)); _why="sudah lancar (p1 ${_pa} fps)"
    fi
    if [ -z "$_new" ] || [ "$_new" -lt 10 ] || [ "$_new" -gt 100 ] || [ "$_new" -eq "$_cur" ]; then
        ad_cdel "$_sp" saran; ad_cdel "$_sp" saran_why; ad_cdel "$_sp" saran_ts
        return 0
    fi
    # sudah pernah ditawarkan dan nilainya belum berubah >= 10 poin: tetap dianggap tampil
    _off=$(ad_cget "$_sp" saran_ditawarkan); case "$_off" in ''|*[!0-9]*) _off="" ;; esac
    if [ -n "$_off" ]; then
        _d=$((_new - _off)); [ "$_d" -lt 0 ] && _d=$((0 - _d))
        [ "$_d" -ge 10 ] && ad_cset "$_sp" saran_tampil 0
    fi
    ad_cset "$_sp" saran "$(printf '%d.%02d' $((_new / 100)) $((_new % 100)))"
    ad_cset "$_sp" saran_why "$_why"
    ad_cset "$_sp" saran_ts "$(date +%s 2>/dev/null)"
}

ad_cdel() {   # $1=pkg $2=key
    _f="$AD_DIR/$1.conf"; [ -f "$_f" ] || return 0
    grep -v "^$2=" "$_f" > "$_f.tmp.$$" 2>/dev/null; mv -f "$_f.tmp.$$" "$_f" 2>/dev/null
}

# ---- preset per game (Grafik / Stabil / Performa), dipelajari dari catatan sesi ----
# Dipelajari hanya dari sesi tanpa preset aktif (pengaturan manual), supaya angkanya tidak ikut
# bergeser setiap kali preset dipakai. Aturan sederhana dan transparan, bukan hasil uji bertahap:
#   Stabil   = resolusi sekarang diturunkan 15/10/0 poin menurut jank dan rasio 1% low terhadap batas FPS,
#              tetapi tidak di bawah resolusi yang sengaja dipilih pengguna (< 100%)
#   Performa = Stabil - 15 poin, Game Mode performance
#   Grafik   = Stabil + 15 poin (maks 100), Game Mode standard
ad_preset_learn() {   # $1=pkg game  [$2=resolusi acuan dalam persen; diberikan = hitung ulang paksa]
    _lp="$1"
    case "$2" in ''|*[!0-9]*) _ref="" ;; *) _ref="$2" ;; esac
    [ -z "$_ref" ] && [ -n "$(sed -n "s/^$(printf '%s' "$_lp" | sed 's/\./\\./g'):PRESET=//p" "$AD_STATE/game_opts.conf" 2>/dev/null | tail -n 1)" ] && return 0
    _jp=$(ad_cget "$_lp" jank_pct); _pa=$(ad_cget "$_lp" p1_avg); _sn=$(ad_cget "$_lp" n)
    for _v in "$_jp" "$_pa" "$_sn"; do case "$_v" in ''|*[!0-9]*) return 0 ;; esac; done
    [ "$_sn" -ge 300 ] || return 0
    _fps=$(ad_fps_cur "$_lp"); case "$_fps" in ''|*[!0-9]*|0) _fps=$(ad_cget "$_lp" fps_auto) ;; esac
    case "$_fps" in ''|*[!0-9]*|0) _fps=30 ;; esac
    _cur=$(ad_ds_pct "$(sed -n "s/^$(printf '%s' "$_lp" | sed 's/\./\\./g'):downscale=//p" "$AD_STATE/game_opts.conf" 2>/dev/null | tail -n 1 | tr -d '[:space:]')")
    [ -n "$_ref" ] && _cur=$_ref
    # Resolusi yang sengaja diturunkan pengguna (< 100) dianggap batas bawahnya: preset tidak
    # menurunkan lagi di bawah itu. Bawaan 100 boleh turun sampai 40.
    _floor=40; [ "$_cur" -lt 100 ] && [ "$_cur" -gt 40 ] && _floor=$_cur
    [ "$_cur" -le 40 ] && _floor=$_cur
    _r=$((_pa * 100 / _fps))
    if [ "$_jp" -ge 30 ] || [ "$_r" -lt 60 ]; then _st=$((_cur - 15))
    elif [ "$_jp" -ge 15 ] || [ "$_r" -lt 80 ]; then _st=$((_cur - 10))
    else _st=$_cur; fi
    [ "$_st" -lt "$_floor" ] && _st=$_floor
    [ "$_st" -gt 100 ] && _st=100
    _pf=$((_st - 15)); [ "$_pf" -lt "$_floor" ] && _pf=$_floor
    _gr=$((_st + 15)); [ "$_gr" -gt 100 ] && _gr=100
    # Batas FPS ikut hasil ukur: 1% low >= 92% batas = HP sanggup lebih, Grafik naik satu tangga;
    # 1% low < 60% batas = kewalahan, Stabil dan Performa turun satu tangga (minimal 30).
    # Catatan: selama batas dipasang, ukuran mentok di batas itu; kemampuan penuh baru terlihat
    # kalau game pernah dimainkan tanpa batas (fps_auto dari ad_fps_once dipakai sebagai acuan).
    _fa=$(ad_cget "$_lp" fps_auto); case "$_fa" in ''|*[!0-9]*|0) _fa="" ;; esac
    _base=${_fa:-$_fps}
    _fs=$_base; _fp=$_base; _fg=$_base
    if [ $((_pa * 100)) -ge $((_base * 92)) ]; then _fg=$(ad_fps_step up "$_base")
    elif [ $((_pa * 100)) -lt $((_base * 60)) ]; then _fs=$(ad_fps_step down "$_base"); _fp=$_fs; fi
    ad_cset "$_lp" pre_stabil "$(ad_ds_fmt $_st),$_fs,performance"
    ad_cset "$_lp" pre_performa "$(ad_ds_fmt $_pf),$_fp,performance"
    ad_cset "$_lp" pre_grafik "$(ad_ds_fmt $_gr),$_fg,standard"
}

ad_fps_step() {   # $1=up|down $2=fps -> tangga 30 45 60 90 120 (naik tidak melewati refresh maksimum layar)
    _mx=$(sed -n 's/^REFRESH_MAX=//p' "$AD_STATE/device_profile.env" 2>/dev/null | tail -n 1)
    case "$_mx" in ''|*[!0-9]*) _mx=60 ;; esac
    _prev=30; _res=$2
    for _t in 30 45 60 90 120; do
        [ "$_t" -le "$_mx" ] || break
        if [ "$1" = up ] && [ "$_t" -gt "$2" ]; then _res=$_t; break; fi
        if [ "$1" = down ] && [ "$_t" -ge "$2" ]; then _res=$_prev; break; fi
        _prev=$_t
    done
    printf '%s' "$_res"
}

ad_ds_fmt() {   # persen -> nilai downscale (100 = off)
    if [ "$1" -ge 100 ]; then printf 'off'; else printf '%d.%02d' $(($1 / 100)) $(($1 % 100)); fi
}

# ---- penyetelan otomatis resolusi + FPS per game (umpan balik antar sesi) ----
# Setiap sesi game yang datanya cukup: tersendat -> resolusi turun 5 poin (FPS turun satu tangga bila
# parah), sangat lancar -> naik 5 poin (FPS naik satu tangga). Resolusi dibatasi lantai menurut kelas HP
# (low 55, mid 60, high 70) dan 100. Statistik direset setiap ada perubahan supaya sesi berikutnya
# mengukur pengaturan yang baru. Nilai dipasang lebih dulu (pre-arm) dan berlaku di buka berikutnya.
AD_AUTO_MIN_N="${AD_AUTO_MIN_N:-120}"
ad_auto_tune() {   # $1=pkg game
    _ap="$1"
    _ore=$(printf '%s' "$_ap" | sed 's/\./\\./g')
    [ "$(sed -n "s/^$_ore:AUTO=//p" "$AD_STATE/game_opts.conf" 2>/dev/null | tail -n 1)" = "off" ] && return 0
    _jp=$(ad_cget "$_ap" jank_pct); _pa=$(ad_cget "$_ap" p1_avg); _sn=$(ad_cget "$_ap" n)
    for _v in "$_jp" "$_pa" "$_sn"; do case "$_v" in ''|*[!0-9]*) return 0 ;; esac; done
    [ "$_sn" -ge "$AD_AUTO_MIN_N" ] || return 0
    _tier=$(sed -n 's/^DEVICE_TIER=//p' "$AD_STATE/detected.conf" 2>/dev/null | tail -n 1 | tr -d '"[:space:]')
    case "$_tier" in low) _floor=${AD_AUTO_FLOOR_LOW:-55} ;; high) _floor=${AD_AUTO_FLOOR_HIGH:-70} ;; *) _floor=${AD_AUTO_FLOOR_MID:-60} ;; esac
    _cur=$(ad_ds_pct "$(sed -n "s/^$_ore:downscale=//p" "$AD_STATE/game_opts.conf" 2>/dev/null | tail -n 1 | tr -d '[:space:]')")
    _fps=$(ad_fps_cur "$_ap"); case "$_fps" in ''|*[!0-9]*|0) _fps=$(ad_cget "$_ap" fps_auto) ;; esac
    case "$_fps" in ''|*[!0-9]*|0) _fps="" ;; esac
    _nds=$_cur; _nfps=$_fps
    _r=100; [ -n "$_fps" ] && _r=$((_pa * 100 / _fps))
    if [ "$_jp" -ge 30 ] || [ "$_r" -lt 60 ]; then
        _nds=$((_cur - 5))
        { [ "$_jp" -ge 40 ] || [ "$_r" -lt 50 ]; } && [ -n "$_fps" ] && _nfps=$(ad_fps_step down "$_fps")
    elif [ "$_jp" -le 5 ] && [ "$_r" -ge 92 ]; then
        _nds=$((_cur + 5))
        [ -n "$_fps" ] && _nfps=$(ad_fps_step up "$_fps")
    fi
    [ "$_nds" -lt "$_floor" ] && _nds=$_floor
    [ "$_nds" -gt 100 ] && _nds=100
    _chg=0
    [ "$_nds" != "$_cur" ] && _chg=1
    [ "$_nfps" != "$_fps" ] && _chg=1
    _aok=1
    _aset=$(sh "${AD_HSC:-${MODDIR:-/data/adb/modules/hsin}/common/hsinctl.sh}" \
        gameauto set "$_ap" "$(ad_ds_fmt "$_nds")" "${_nfps:-keep}" 2>&1) \
        || { _aok=0; ad_log "auto: $_ap gagal menyimpan pengaturan ($_aset)"; }
    if [ "$_chg" = 1 ] && [ "$_aok" = "1" ]; then
        _f="$AD_DIR/$_ap.conf"
        grep -v -E '^(n|sum_p1|p1_min|stall_max|jank_n|p1_avg|jank_pct|saran|saran_why|saran_ts)=' "$_f" > "$_f.tmp.$$" 2>/dev/null \
            && mv -f "$_f.tmp.$$" "$_f" 2>/dev/null
        ad_log "auto: $_ap resolusi $_cur%->$_nds% fps ${_fps:--}->${_nfps:--} (jank=${_jp}% p1=${_pa} lantai=$_floor)"
    fi
}

ad_end() {
    [ "$AD_OPEN" = "1" ] || return 0
    _tail=""
    ad_flush
    [ "$AD_IS_GAME" = "1" ] && ad_saran "$AD_PKG"
    [ "$AD_IS_GAME" = "1" ] && ad_preset_learn "$AD_PKG"
    [ "$AD_IS_GAME" = "1" ] && ad_auto_tune "$AD_PKG"
    _tail="p1_min=$(ad_cget "$AD_PKG" p1_min) p1_rata=$(ad_cget "$AD_PKG" p1_avg) jank=$(ad_cget "$AD_PKG" jank_pct)% fps=${AD_LAST_AVG:--}"
    [ "$AD_OWN" = "1" ] && ad_own_off selesai
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
    # Hanya Puncak/Overdrive yang aktif mematikan Adapt. Profil performance tetap Adapt
    # (mulai dari beban tinggi, lihat ad_tier_beban) supaya tidak mati selamanya setelah Puncak.
    # Overdrive yang sedang menyala memegang frekuensi: Adapt tidak boleh ikut menulis.
    [ -f "$AD_STATE/.ovd_active" ] && { [ "$AD_OPEN" = "1" ] && ad_end; return 0; }
    case "$(tr -d '[:space:]' < "$AD_STATE/active_profile" 2>/dev/null)" in
        puncak|overdrive)
            [ "$AD_OPEN" = "1" ] && ad_end
            return 0
            ;;
    esac
    if [ "$AD_OPEN" = "1" ] && [ "$AD_PKG" != "$_pkg" ]; then
        ad_end    # pindah aplikasi: semua kembali normal
    fi
    [ "$AD_OPEN" = "1" ] || { ad_own_recover; ad_open "$_pkg"; }

    # Adapt memegang frekuensi: pid uperf/fas-rs yang lahir ulang ikut dibekukan (tiap >=20 dtk).
    if [ "$AD_OWN" = "1" ]; then
        if [ ! -f "$AD_OWN_FILE" ]; then
            AD_OWN=0   # penanda dicabut pihak lain (Puncak): jangan menulis frekuensi lagi
        else
            _ozn=$(date +%s 2>/dev/null)
            case "$_ozn" in ''|*[!0-9]*) _ozn=0 ;; esac
            if [ $((_ozn - AD_OWN_FZ_TS)) -ge 20 ]; then AD_OWN_FZ_TS=$_ozn; ad_own_freeze; fi
        fi
    fi

    # Pembersih RAM otomatis saat sempit (memfx: PSI + ambang + jeda sendiri).
    command -v mf_relief_tick >/dev/null 2>&1 && mf_relief_tick "$_pkg"

    # --- ukur ---
    _st=""
    command -v monitor_fps_stat >/dev/null 2>&1 && \
        _st=$(monitor_fps_stat "${AD_STATE}/fpsd.out" "$_pkg" 2>/dev/null)
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
        if [ "$_p1" -lt "$AD_TARGET_P1" ]; then _jank=1; _why="1%low=$_p1 rata=$_avg"; fi
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

    [ -n "$_avg" ] && AD_LAST_AVG=$_avg
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
    _warm=0
    if [ "$AD_IS_GAME" = "1" ] && [ $((_now - AD_OPEN_TS)) -lt "$AD_WARM_SECS" ] 2>/dev/null; then
        _jank=0; _calm=0; _warm=1
    fi
    # Jeda sangat panjang (loading, pindah area, app ditahan) bukan masalah render.
    # Tanpa ini satu freeze 2 detik menurunkan resolusi sesi berikutnya.
    if [ "${_stall:-0}" -ge "$AD_STALL_LOADING" ] 2>/dev/null; then _jank=0; _calm=0; _warm=1; fi

    # --- batas FPS mengikuti kemampuan nyata perangkat (sekali per sesi) ---
    if [ "$AD_IS_GAME" = "1" ] && [ "$AD_FPS_TRIED" = "0" ] && [ -n "$_avg" ] && [ -n "$_p1" ] \
        && [ $((_now - AD_OPEN_TS)) -ge "$AD_WARM_SECS" ] 2>/dev/null; then
        AD_FPS_TRIED=1
        ad_fps_once "$_avg" "$_p1"
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
    # Sampel pemanasan/loading tidak dicatat: dulu 1% low-nya menarik rata-rata
    # turun, lalu auto tune menurunkan resolusi karena beban loading, bukan main.
    if [ -n "$_p1" ] && [ "$_warm" = "0" ]; then
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
            _pv="?"
            [ "${AD_PREV_JR:--1}" -ge 0 ] 2>/dev/null && _pv="${AD_PREV_JR}/1000"
            ad_log "tahan: naik ke $AD_HELP_LVL menolong (jank $(ad_wj_r)/1000, dulu $_pv), tetap beban $AD_BEBAN ($AD_PKG)"
        elif [ -n "$AD_TRIED_LVL" ] && [ "$_hlp" = "0" ]; then
            # Kenaikan tidak menolong: mundur satu tingkat dan catat tingkat itu
            # supaya tidak dicoba lagi sesi ini (dulu naik-turun 1-2-3-1 terus,
            # dan itu sendiri yang bikin gambar patah).
            _bad=$AD_TRIED_LVL; _jr=$(ad_wj_r)
            AD_TRIED_LVL=""
            [ "$_bad" -ge 2 ] 2>/dev/null && AD_BAD_LVL=$_bad
            _msg="turun: naik ke $_bad tidak menolong (jank ${_jr}/1000), beban=$((AD_BEBAN - 1))"
            [ "$AD_BAD_LVL" = "$_bad" ] && _msg="$_msg, beban $_bad dilewati sesi ini"
            if [ "$AD_BEBAN" -gt 0 ] && { [ "$AD_IS_GAME" != "1" ] || [ "$AD_BEBAN" -gt 1 ]; }; then
                AD_BEBAN=$((AD_BEBAN - 1)); AD_LAST_CHG=$_now
                ad_apply; ad_flush
                ad_log "$_msg ($AD_PKG)"
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
    # Lantai yang tertahan (jeda/suhu) dicoba lagi tiap tick; murah bila sudah sama.
    [ "$AD_OWN" = "1" ] && ad_own_apply
    return 0
}

# Dipanggil saat layar mati / monitor berhenti: lepas semua bantuan.
ad_release() {
    [ "$AD_OPEN" = "1" ] && ad_end
    ad_own_recover
    return 0
}
