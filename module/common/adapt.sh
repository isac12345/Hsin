#!/system/bin/sh
# HSIN ADAPT - beban adaptif per game (ide "adaptasi tanpa batas").
#
# Cara kerja:
#   - Modul menilai hasil kerjanya sendiri dari data FPS nyata (fpsd, 10 dtk).
#   - Tiap sesi game, beban 0..3 dipilih ulang dari hasil sesi sebelumnya.
#   - Beban = seberapa keras modul menekan GPU Mali (gpu_boost_level2 /
#     gpu_pollingtime / gpu_upthreshold). Ini domain milik modul, bukan
#     setelan user, jadi tidak bertabrakan dengan downscale/fps per game.
#   - Sesi jelek (1% low < 15 atau >= 20% sampel di bawah target) -> naik.
#   - Sesi bagus (1% low >= 45, tanpa sampel jelek) -> turun: coba lebih
#     ringan, karena tenaga ekstra yang tidak perlu cuma menambah panas.
#   - Hasil disimpan per paket di adapt/<paket>.conf dan dinilai ulang tiap
#     sesi. Jadi game baru, update game, atau HP memanas tetap diikuti.
#
# Ringan: tanpa loop/fork baru. Dipanggil dari tick game monitor.sh yang sudah
# ada; statistik ditulis satu kali tiap 15 tick (~30 dtk).
#
# Penulis kbase tetap SATU: adapt.sh hanya menitipkan angka ke variabel
# GB_KBASE_*, dan gameboost.sh yang menulis ke sysfs.

AD_DIR="${HSIN_CONF_DIR:-/data/adb/hsin}/adapt"
AD_TARGET_P1="${AD_TARGET_P1:-20}"
AD_MIN_P1="${AD_MIN_P1:-15}"
AD_GOOD_P1="${AD_GOOD_P1:-45}"
AD_JANK_PCT="${AD_JANK_PCT:-20}"
AD_TICK_FLUSH="${AD_TICK_FLUSH:-15}"

# Nilai kbase per beban: "boost poll upthreshold"
AD_KBASE_0="0 8 88"    # adem
AD_KBASE_1="0 4 75"    # ringan
AD_KBASE_2="1 2 55"    # sedang
AD_KBASE_3="1 1 30"    # agresif (sama dengan game boost ekstrem)

AD_PKG=""
AD_BEBAN=""
AD_N=0
AD_SUM=0
AD_MIN=""
AD_STALL=""
AD_JANK=0
AD_OPEN=0

ad_log() {
    if type monitor_log >/dev/null 2>&1; then
        monitor_log "ADAPT" "$1"
    else
        printf '[%s] [ADAPT] %s\n' "$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date)" "$1" \
            >> "${HSIN_LOG_FILE:-/data/adb/hsin/hsin.log}" 2>/dev/null
    fi
}

ad_cget() {   # $1=pkg $2=key -> nilai
    sed -n "s/^$2=//p" "$AD_DIR/$1.conf" 2>/dev/null | tail -n 1 | tr -d '[:space:]'
}

ad_cset() {   # $1=pkg $2=key $3=val
    mkdir -p "$AD_DIR" 2>/dev/null
    _f="$AD_DIR/$1.conf"
    touch "$_f" 2>/dev/null
    grep -v "^$2=" "$_f" > "$_f.tmp.$$" 2>/dev/null
    printf '%s=%s\n' "$2" "$3" >> "$_f.tmp.$$"
    mv -f "$_f.tmp.$$" "$_f" 2>/dev/null
}

ad_kbase_set() {   # $1=beban -> titip nilai ke gameboost (satu penulis)
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

ad_tier_beban() {   # awal untuk game yang belum punya riwayat
    case "${DEVICE_TIER:-mid}" in
        low)  printf '3' ;;
        high) printf '1' ;;
        *)    printf '2' ;;
    esac
}

ad_save() {
    [ -n "$AD_PKG" ] || return 0
    mkdir -p "$AD_DIR" 2>/dev/null
    _f="$AD_DIR/$AD_PKG.conf"
    touch "$_f" 2>/dev/null
    grep -v -E '^(n|sum|p1_min|stall_max|jank)=' "$_f" > "$_f.tmp.$$" 2>/dev/null
    printf 'n=%s\nsum=%s\np1_min=%s\nstall_max=%s\njank=%s\n' \
        "$AD_N" "$AD_SUM" "${AD_MIN:-0}" "${AD_STALL:-0}" "$AD_JANK" >> "$_f.tmp.$$"
    mv -f "$_f.tmp.$$" "$_f" 2>/dev/null
}

ad_begin() {   # $1=pkg
    # Sesi sebelumnya belum ditutup (monitor mati/ganti game): tutup dulu
    # supaya statistiknya tidak menimpa paket yang baru.
    [ "$AD_OPEN" = "1" ] && ad_end
    AD_PKG="$1"
    AD_N=0; AD_SUM=0; AD_MIN=""; AD_STALL=""; AD_JANK=0; AD_OPEN=1
    _sesi=$(ad_cget "$1" sesi)
    case "$_sesi" in ''|*[!0-9]*) _sesi=0 ;; esac
    AD_BEBAN=$(ad_cget "$1" beban)
    case "$AD_BEBAN" in ''|*[!0-9]*) AD_BEBAN=$(ad_tier_beban) ;; esac
    [ "$AD_BEBAN" -gt 3 ] 2>/dev/null && AD_BEBAN=3
    ad_kbase_set "$AD_BEBAN"
    ad_cset "$1" sesi $((_sesi + 1))
    ad_log "mulai $1 beban=$AD_BEBAN sesi=$((_sesi + 1)) kbase=${GB_KBASE_BOOST:-?}/${GB_KBASE_POLL:-?}/${GB_KBASE_UP:-?}"
}

ad_tick() {   # $1=pkg; baca FPS_LAST_P1/FPS_LAST_STALL dari monitor.sh
    [ -n "$1" ] || return 0
    if [ "$AD_OPEN" != "1" ] || [ "$1" != "$AD_PKG" ]; then
        ad_begin "$1" || return 0
    fi
    _p1="${FPS_LAST_P1:-}"
    case "$_p1" in ''|*[!0-9]*) return 0 ;; esac
    AD_N=$((AD_N + 1))
    AD_SUM=$((AD_SUM + _p1))
    if [ -z "$AD_MIN" ] || [ "$_p1" -lt "$AD_MIN" ]; then AD_MIN=$_p1; fi
    _st="${FPS_LAST_STALL:-0}"
    case "$_st" in ''|*[!0-9]*) _st=0 ;; esac
    [ "$_st" -gt "${AD_STALL:-0}" ] && AD_STALL=$_st
    [ "$_p1" -lt "$AD_TARGET_P1" ] && AD_JANK=$((AD_JANK + 1))
    [ $((AD_N % AD_TICK_FLUSH)) -eq 0 ] && ad_save
    return 0
}

ad_end() {
    [ "$AD_OPEN" = "1" ] || return 0
    AD_OPEN=0
    [ "$AD_N" -gt 0 ] 2>/dev/null || { AD_PKG=""; return 0; }
    _avg=$((AD_SUM / AD_N))
    _jpct=$((AD_JANK * 100 / AD_N))
    _b="$AD_BEBAN"
    case "$_b" in ''|*[!0-9]*) _b=2 ;; esac
    _why=""
    if [ "$AD_MIN" -lt "$AD_MIN_P1" ] 2>/dev/null || [ "$_jpct" -ge "$AD_JANK_PCT" ] 2>/dev/null; then
        if [ "$_b" -lt 3 ]; then _b=$((_b + 1)); _why="naik"; fi
    elif [ "$AD_MIN" -ge "$AD_GOOD_P1" ] 2>/dev/null && [ "$AD_JANK" -eq 0 ]; then
        if [ "$_b" -gt 0 ]; then _b=$((_b - 1)); _why="turun"; fi
    fi
    ad_save
    ad_cset "$AD_PKG" beban "$_b"
    ad_cset "$AD_PKG" p1_avg "$_avg"
    ad_cset "$AD_PKG" jank_pct "$_jpct"
    ad_cset "$AD_PKG" terakhir "$(date '+%Y-%m-%d %H:%M' 2>/dev/null || date)"
    ad_log "selesai $AD_PKG p1_min=$AD_MIN rata=$_avg jank=${_jpct}% beban ${AD_BEBAN}->$_b${_why:+ ($_why)}"
    AD_PKG=""; AD_N=0; AD_SUM=0; AD_MIN=""; AD_STALL=""; AD_JANK=0
}
