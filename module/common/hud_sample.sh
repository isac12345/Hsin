#!/system/bin/sh
# HSIN - hud_sample: metrik live untuk HUD di HSIN.
#
#   hud_sample.sh --once <pkg>   satu sampel (key=value), buat uji lewat `hsinctl hud sample <pkg>`
#   hud_sample.sh --loop <pkg>   sampel tiap detik, tiap blok diakhiri baris "--"
#                                (APK membaca stream ini lewat satu proses su; berhenti sendiri
#                                 saat pembaca menutup pipa)
#
# CATATAN PENTING: /system/bin/sh (mksh) di sebagian ROM berhitung 32-bit. Timestamp frame (nanodetik,
#   14 digit) TIDAK BOLEH dihitung/dibandingkan di sini. Script hanya meneruskan timestamp mentah
#   (satu baris "lat=<ns> <ns> ..."); FPS dihitung di aplikasi (Kotlin, 64-bit).
#
# Keluaran:
#   lat       timestamp frame layer game (actualPresentTime, spasi-terpisah, maks 70); APK menghitung FPS-nya
#   fps_x10   FPS x10 dari jalur cadangan (counter/timestats), kosong bila jalur layer (lat) yang dipakai
#   last_ts   penanda perubahan jalur cadangan; APK mendeteksi frame macet bila nilainya sama
#   gpu       persen beban GPU, kosong bila node tidak dikenal di kernel ini
#   cpu       baris pertama /proc/stat (APK menghitung persen dari selisih antar sampel)
#   temp_mc   suhu baterai, soc_mc suhu zona termal terpanas (milli-derajat C)

STATE_DIR="${HSIN_STATE_DIR:-/data/adb/hsin}"
LAYER_CACHE="$STATE_DIR/.hud_layer"
SYS_THERMAL="${SYSFS_THERMAL_PREFIX:-/sys/class/thermal}"
SYS_POWER="${SYSFS_POWER_PREFIX:-/sys/class/power_supply}"

# ---- daemon FPS native (module/bin/hsin-fpsd-*): baca frame langsung lewat binder, tanpa fork dumpsys.
# Kalau tidak ada/gagal, semua jalur lama di bawah tetap dipakai. HSIN_FPSD=0 mematikannya.
FPSD_DIR="$STATE_DIR"
FPSD_OUT="$STATE_DIR/fpsd.out"
FPSD_PKG="$STATE_DIR/fpsd.pkg"
FPSD_ON="${HSIN_FPSD:-1}"
FPSD_N=0
FPSD_BAD=0
fpsd_bin() {
    _fb_mod="${HSIN_MODDIR:-${0%/common/*}}"
    if [ -e /system/lib64/libbinder_ndk.so ]; then _fb_a=arm64; _fb_b=arm32; else _fb_a=arm32; _fb_b=arm64; fi
    for _fb_x in "$_fb_a" "$_fb_b"; do
        [ -x "$_fb_mod/bin/hsin-fpsd-$_fb_x" ] && { printf '%s' "$_fb_mod/bin/hsin-fpsd-$_fb_x"; return 0; }
    done
    return 1
}
# Hidupkan daemon bila belum jalan (dicek tiap ~10 sampel). Gagal selftest = tandai, jangan dicoba lagi.
fpsd_ensure() {
    [ "$FPSD_ON" = 1 ] && [ "$FPSD_BAD" = 0 ] || return 1
    FPSD_N=$((FPSD_N + 1))
    [ $((FPSD_N % 10)) -eq 1 ] || return 0
    _fe_pid=""
    [ -r "$STATE_DIR/fpsd.pid" ] && read -r _fe_pid < "$STATE_DIR/fpsd.pid"
    if [ -n "$_fe_pid" ] && kill -0 "$_fe_pid" 2>/dev/null; then return 0; fi
    _fe_bin=$(fpsd_bin) || { FPSD_BAD=1; return 1; }
    if ! "$_fe_bin" --selftest >/dev/null 2>&1; then FPSD_BAD=1; return 1; fi
    ( "$_fe_bin" "$FPSD_DIR" >/dev/null 2>&1 & )
    return 0
}
# Epoch detik tanpa fork date: /proc/uptime + offset (date sekali, diperbarui tiap 600 dtk).
HS_EP0=""; HS_EP0_AT=0
hs_now() {
    HS_NOW=""
    _hn_u=""; read -r _hn_u _ 2>/dev/null < /proc/uptime
    _hn_u=${_hn_u%%.*}
    case "$_hn_u" in
        ''|*[!0-9]*) HS_NOW=$(date +%s) ;;
        *)
            if [ -z "$HS_EP0" ] || [ $((_hn_u - HS_EP0_AT)) -ge 600 ] || [ "$_hn_u" -lt "$HS_EP0_AT" ]; then
                HS_NOW=$(date +%s)
                HS_EP0=$((HS_NOW - _hn_u)); HS_EP0_AT=$_hn_u
            else
                HS_NOW=$((HS_EP0 + _hn_u))
            fi ;;
    esac
}
# Hasil daemon bila segar (< 4 dtk) dan untuk game yang sama. FL_LAT diisi baris timestamp.
fpsd_read() {
    FL_LAT=""
    [ "$FPSD_ON" = 1 ] && [ "$FPSD_BAD" = 0 ] || return 1
    printf '%s' "$1" > "$FPSD_PKG" 2>/dev/null
    [ -r "$FPSD_OUT" ] || return 1
    _fr_m=$(stat -c %Y "$FPSD_OUT" 2>/dev/null) || return 1
    hs_now; _fr_n=$HS_NOW
    [ $((_fr_n - _fr_m)) -le 4 ] || return 1
    _fr_pkg=""; _fr_lat=""
    while IFS= read -r _fr_l; do
        case "$_fr_l" in
            pkg=*) _fr_pkg="${_fr_l#pkg=}" ;;
            lat=*) _fr_lat="${_fr_l#lat=}" ;;
        esac
    done < "$FPSD_OUT"
    [ "$_fr_pkg" = "$1" ] && [ -n "$_fr_lat" ] || return 1
    FL_LAT="$_fr_lat"
    return 0
}

# FPS cara Smollming: counter SurfaceFlinger 1013 (selisih per detik), fallback
# ke latency per layer kalau counter gagal/diam 3x berturut-turut.
CNT_PREV=""
CNT_TPREV=""
CNT_FAIL=0
ZERO_RUN=0
LAYER_FAIL=0
SRC_DEAD=0
SRC_N=0
src_dead() {
    [ "$SRC_DEAD" = 1 ] || return 1
    SRC_N=$((SRC_N + 1))
    if [ "$SRC_N" -ge 60 ]; then
        SRC_DEAD=0; SRC_N=0; LAYER_FAIL=0; CNT_FAIL=3; TS_PREV=""
        return 1
    fi
    return 0
}
LIST_WAIT=0
LR_OUT=""
LR_N=0
LR_LAST=""
PL_LAST=""
FL_PREVTS=""
STALE_N=0
PL_OUT=""
FL_LAT=""
TS_ON=0
TS_PREV=""
DBG_N=0
DBG_LOG="$STATE_DIR/hud_debug.log"
TICK_S=1
LIGHT=0   # 1 = app biasa (bukan game): sampling jarang, tanpa fallback berat
FL_RES=""
PL_LAYER=""
PL_RES=""
TS_RES=""

# Hasil lewat variabel SC_RES (bukan stdout): state counter harus hidup di
# proses loop, sedangkan $(...) berjalan di subshell dan membuang state.
sf_counter() {
    SC_RES=""
    _sc_g=""
    _sc_out=$(service call SurfaceFlinger 1013 2>/dev/null)
    # Hasil "Result: Parcel(00000000 0000abcd   '....')": dua kata hex 8 digit setelah "Parcel(".
    # Dipotong dengan shell (dulu printf | sed = 2 fork per sampel).
    case "$_sc_out" in
        *"Parcel("*) _sc_g=${_sc_out#*Parcel(}; set -- $_sc_g ;;
        *) set -- ;;
    esac
    case "$1:$2" in
        ????????:????????) ;;
        *) set --; ;;
    esac
    case "$1$2" in *[!0-9a-fA-F]*) set -- ;; esac
    [ "$1" = "00000000" ] || { CNT_FAIL=$((CNT_FAIL + 1)); return 1; }
    _sc_c=$((0x$2)); CNT_FAIL=0
    _sc_p=$CNT_PREV; CNT_PREV=$_sc_c
    # selang NYATA dari /proc/uptime (centidetik): iterasi bisa molor, jangan asumsikan 1 dtk
    _sc_u=""; read -r _sc_u _ 2>/dev/null < /proc/uptime
    _sc_t=${_sc_u%.*}${_sc_u#*.}
    case "$_sc_t" in ''|*[!0-9]*) _sc_t="" ;; esac
    _sc_tp=$CNT_TPREV; CNT_TPREV=$_sc_t
    [ -n "$_sc_p" ] && [ "$_sc_c" -ge "$_sc_p" ] || return 1
    _sc_dt=$(( TICK_S * 100 ))
    [ -n "$_sc_t" ] && [ -n "$_sc_tp" ] && [ "$_sc_t" -gt "$_sc_tp" ] && _sc_dt=$(( _sc_t - _sc_tp ))
    SC_RES="$(( (_sc_c - _sc_p) * 1000 / _sc_dt )) $_sc_c"
}

# Daftar layer milik paket (tanpa baris pembantu "Background for"/"Bounds for"/"Dim ").
layer_list() {
    dumpsys SurfaceFlinger --list 2>/dev/null | grep -F "$1" | grep -v -E '^(Background for|Bounds for|Dim )'
}

# Kandidat berurut prioritas (maks 6): SurfaceView BLAST > SurfaceView > BLAST > lainnya.
# Game bisa punya lebih dari satu SurfaceView (mis. iklan/WebView), jadi tidak cukup
# mengambil satu saja: layer terbaik dipilih dari yang benar-benar punya frame.
layer_candidates() {
    _lc_all=$(layer_list "$1")
    [ -n "$_lc_all" ] || return 1
    {
        printf '%s\n' "$_lc_all" | grep -F "SurfaceView" | grep -F "BLAST"
        printf '%s\n' "$_lc_all" | grep -F "SurfaceView" | grep -v -F "BLAST"
        printf '%s\n' "$_lc_all" | grep -F "BLAST" | grep -v -F "SurfaceView"
        printf '%s\n' "$_lc_all" | grep -v -F "BLAST" | grep -v -F "SurfaceView"
    } | head -n "$([ "$LIGHT" = 1 ] && echo 2 || echo 6)"
}

# Timestamp frame mentah layer: kolom 2 (actualPresentTime) dari 70 baris terakhir
# `dumpsys SurfaceFlinger --latency`. Hanya uji teks (case), tanpa aritmetika pada nilai besar.
# Hasil: LR_OUT = timestamp dipisah spasi (satu per frame), LR_N = jumlah baris valid.
lat_rows() {
    LR_OUT=""
    LR_N=0
    LR_LAST=""
    _lr_out=$(dumpsys SurfaceFlinger --latency "$1" 2>/dev/null | tail -n 70)
    [ -n "$_lr_out" ] || return 1
    _lr_i=0
    while read -r _lr_a _lr_b _lr_c; do
        _lr_i=$((_lr_i + 1))
        [ "$_lr_i" -eq 1 ] && continue
        case "$_lr_b" in ''|0|9223372036854775807|*[!0-9]*) continue ;; esac
        LR_OUT="$LR_OUT $_lr_b"
        LR_LAST="$_lr_b"
        LR_N=$((LR_N + 1))
    done <<EOF
$_lr_out
EOF
    [ "$LR_N" -ge 3 ]
}

# Bilangan bulat pertama dari isi node (format beda antar vendor: "45", "45 %", "46@800000000Hz", "36 36 4")
first_int() {
    [ -r "$1" ] || return 1
    # Tanpa proses anak: baris pertama, buang awalan non-digit, ambil deret digit pertama
    # (dulu head | tr | sed | cut = 4 fork per node, dua kali per sampel).
    _fi=""
    IFS= read -r _fi 2>/dev/null < "$1" || [ -n "$_fi" ] || return 1
    _fi=${_fi#"${_fi%%[0-9]*}"}
    _fi=${_fi%%[!0-9]*}
    [ -n "$_fi" ] || return 1
    printf '%s' "$_fi"
}

GPU_PATH=""
gp_path() {
    [ -n "$GPU_PATH" ] && [ -d "$GPU_PATH" ] && return 0
    # node resmi dari deteksi HSIN (mis. /sys/class/devfreq/23100000.gpu)
    GPU_PATH=$(sed -n 's/^GPU_DEVFREQ_PATH="\(.*\)"/\1/p' "$STATE_DIR/detected.conf" 2>/dev/null | head -n 1)
    if [ -z "$GPU_PATH" ] || [ ! -d "$GPU_PATH" ]; then
        for _gp_d in /sys/class/devfreq/*gpu* /sys/class/kgsl/kgsl-3d0; do
            [ -d "$_gp_d" ] && { GPU_PATH="$_gp_d"; break; }
        done
    fi
    [ -n "$GPU_PATH" ] && [ -d "$GPU_PATH" ]
}

gpu_freq_mhz() {
    gp_path || return 1
    _gf=$(first_int "$GPU_PATH/cur_freq") || _gf=$(first_int "$GPU_PATH/devfreq/cur_freq") || return 1
    if [ "$_gf" -ge 10000000 ]; then _gf=$((_gf / 1000000))
    elif [ "$_gf" -ge 10000 ]; then _gf=$((_gf / 1000)); fi
    printf '%s' "$_gf"
}

gpu_load() {
    _g_nodes="/sys/class/kgsl/kgsl-3d0/gpu_busy_percentage
        /sys/class/kgsl/kgsl-3d0/devfreq/gpu_load /sys/kernel/gpu/gpu_busy
        /sys/kernel/ged/hal/gpu_utilization /sys/kernel/debug/ged/hal/gpu_utilization
        /sys/module/ged/parameters/gpu_loading /proc/mtk_mali/gpu_utilization
        /sys/class/misc/mali0/device/utilization /sys/class/misc/mali0/device/gpu_utilization
        /proc/mali/utilization"
    gp_path && _g_nodes="$_g_nodes $GPU_PATH/load $GPU_PATH/utilization $GPU_PATH/gpu_load
        $GPU_PATH/device/utilization $GPU_PATH/device/gpu_utilization"
    for _g_n in $_g_nodes /sys/class/devfreq/*gpu*/load /sys/class/devfreq/*gpu*/utilisation \
        /sys/class/devfreq/*mali*/load; do
        _g_v=$(first_int "$_g_n") && { printf '%s' "$_g_v"; return 0; }
    done
    # Adreno: gpubusy = "busy total" (selisih interval), lainnya persen langsung
    if [ -r /sys/class/kgsl/kgsl-3d0/gpubusy ]; then
        read -r _g_b _g_t < /sys/class/kgsl/kgsl-3d0/gpubusy 2>/dev/null
        case "$_g_b$_g_t" in ''|*[!0-9]*) ;; *)
            [ "$_g_t" -gt 0 ] && { printf '%s' $((_g_b * 100 / _g_t)); return 0; }
        ;; esac
    fi
    return 1
}

soc_temp_mc() {
    _st_max=0
    for _st_z in "$SYS_THERMAL"/thermal_zone*; do
        [ -r "$_st_z/temp" ] || continue
        read -r _st_v < "$_st_z/temp" 2>/dev/null
        case "$_st_v" in ''|*[!0-9-]*) continue ;; esac
        [ "${_st_v#-}" -le 1000 ] 2>/dev/null && _st_v=$((_st_v * 1000))
        [ "$_st_v" -ge 0 ] 2>/dev/null || continue
        [ "$_st_v" -lt 125000 ] 2>/dev/null || continue
        [ "$_st_v" -gt "$_st_max" ] && _st_max=$_st_v
    done
    printf '%s' "$_st_max"
}

batt_temp_mc() {
    read -r _bt < "$SYS_POWER/battery/temp" 2>/dev/null
    case "$_bt" in ''|*[!0-9-]*) printf '0' ;; *) printf '%s' $((_bt * 100)) ;; esac
}

# a > b untuk timestamp 14+ digit: expr memakai 64-bit (shell ROM ini 32-bit, tidak boleh dibandingkan di sini).
ts_newer() {
    [ -n "$1" ] || return 1
    [ -n "$2" ] || return 0
    [ "$(expr "$1" '>' "$2" 2>/dev/null)" = 1 ]
}

# Pilih layer terbaik: yang frame TERBARU-nya paling baru (layer basi/diam kalah), lalu urutan prioritas.
# Hasil lewat PL_LAYER / PL_OUT (bukan stdout, supaya state tidak hilang di subshell).
pick_layer() {
    PL_LAYER=""
    PL_OUT=""
    PL_LAST=""
    _pl_cands=$(layer_candidates "$1") || return 1
    while IFS= read -r _pl_l; do
        [ -n "$_pl_l" ] || continue
        lat_rows "$_pl_l" || continue
        if [ -z "$PL_LAYER" ] || ts_newer "$LR_LAST" "$PL_LAST"; then
            PL_LAST=$LR_LAST
            PL_LAYER=$_pl_l
            PL_OUT=$LR_OUT
        fi
    done <<EOF
$_pl_cands
EOF
    [ -n "$PL_LAYER" ]
}

# Timestamp frame layer app. Hasil di FL_LAT (baris "lat=...") atau kosong.
fps_layer() {
    _fl_pkg="$1"
    FL_LAT=""
    _fl_layer=""
    fpsd_ensure
    if fpsd_read "$_fl_pkg"; then return 0; fi
    command -v dumpsys >/dev/null 2>&1 || return 1
    if [ -f "$LAYER_CACHE" ]; then
        IFS='|' read -r _fl_cp _fl_cl < "$LAYER_CACHE"
        [ "$_fl_cp" = "$_fl_pkg" ] && _fl_layer="$_fl_cl"
    fi
    if [ -n "$_fl_layer" ] && lat_rows "$_fl_layer"; then
        FL_LAT=$LR_OUT
        # layer yang tidak menghasilkan frame baru 3 sampel berturut-turut = bukan layer game: cari ulang
        if [ "$LR_LAST" = "$FL_PREVTS" ]; then STALE_N=$((STALE_N + 1)); else STALE_N=0; fi
        FL_PREVTS=$LR_LAST
        if [ "$STALE_N" -ge 3 ]; then
            STALE_N=0
            rm -f "$LAYER_CACHE" 2>/dev/null
            LIST_WAIT=0
            if pick_layer "$_fl_pkg" && [ "$PL_LAST" != "$FL_PREVTS" ]; then
                printf '%s|%s\n' "$_fl_pkg" "$PL_LAYER" > "$LAYER_CACHE" 2>/dev/null
                FL_LAT=$PL_OUT; FL_PREVTS=$PL_LAST
            fi
        fi
    else
        # layer basi (game restart ganti nomor layer) atau belum pernah dicari.
        # Mendaftar ulang layer itu berat: paling sering sekali per 3 sampel.
        if [ "$LIST_WAIT" -le 0 ]; then
            LIST_WAIT=3
            if pick_layer "$_fl_pkg"; then
                # app biasa: layer ketemu = jarang dicari ulang (hemat SurfaceFlinger); gagal = coba lagi cepat
                [ "$LIGHT" = 1 ] && LIST_WAIT=15
                printf '%s|%s\n' "$_fl_pkg" "$PL_LAYER" > "$LAYER_CACHE" 2>/dev/null
                FL_LAT=$PL_OUT; FL_PREVTS=$PL_LAST; STALE_N=0
            else
                rm -f "$LAYER_CACHE" 2>/dev/null
            fi
        else
            LIST_WAIT=$((LIST_WAIT - 1))
        fi
    fi
    [ -n "$FL_LAT" ]
}

# Cadangan terakhir: statistik frame SurfaceFlinger per layer (--timestats), dipakai RaiRin juga.
# totalFrames tiap layer milik paket dijumlahkan, FPS = selisih per sampel (jeda ~1 detik).
# Hasil di TS_RES ("<fps_x10> <totalFrames>" atau kosong).
ts_fps() {
    TS_RES=""
    _tf_pkg="$1"
    if [ "$TS_ON" -eq 0 ]; then
        dumpsys SurfaceFlinger --timestats -enable >/dev/null 2>&1
        TS_ON=1
    fi
    _tf_out=$(dumpsys SurfaceFlinger --timestats -dump 2>/dev/null)
    [ -n "$_tf_out" ] || return 1
    _tf_max=0
    _tf_in=0
    while IFS= read -r _tf_l; do
        case "$_tf_l" in
            *layerName*) case "$_tf_l" in *"$_tf_pkg"*) _tf_in=1 ;; *) _tf_in=0 ;; esac ;;
            *totalFrames*)
                [ "$_tf_in" -eq 1 ] || continue
                _tf_v=${_tf_l##*=}
                _tf_v=$(printf '%s' "$_tf_v" | tr -cd '0-9')
                [ -n "$_tf_v" ] && [ "$_tf_v" -gt "$_tf_max" ] && _tf_max=$_tf_v
                ;;
        esac
    done <<EOF
$_tf_out
EOF
    [ "$_tf_max" -gt 0 ] || return 1
    _tf_p=$TS_PREV
    TS_PREV=$_tf_max
    [ -n "$_tf_p" ] && [ "$_tf_max" -ge "$_tf_p" ] || return 1
    # lompatan besar = daftar layer berubah (bukan frame sungguhan): buang, jangan tampilkan angka ngawur
    [ $((_tf_max - _tf_p)) -le 500 ] || return 1
    TS_RES="$(( (_tf_max - _tf_p) * 10 )) $_tf_max"
    return 0
}

# Jejak diagnosa: hanya ditulis saat FPS belum terbaca, jarang (tiap 15 sampel), dan dibatasi 64 KB.
dbg_dump() {
    DBG_N=$((DBG_N + 1))
    [ $((DBG_N % 15)) -eq 1 ] || return 0
    _db_sz=$(wc -c < "$DBG_LOG" 2>/dev/null)
    [ -n "$_db_sz" ] && [ "$_db_sz" -gt 65536 ] && return 0
    {
        printf '=== %s pkg=%s cnt_fail=%s layer_fail=%s\n' "$(date '+%H:%M:%S' 2>/dev/null)" "$1" "$CNT_FAIL" "$LAYER_FAIL"
        _db_c=$(layer_candidates "$1" 2>/dev/null)
        printf 'kandidat:\n%s\n' "$_db_c"
        _db_first=$(printf '%s\n' "$_db_c" | head -n 1)
        if [ -n "$_db_first" ]; then
            printf 'latency (4 baris) layer pertama:\n'
            dumpsys SurfaceFlinger --latency "$_db_first" 2>&1 | head -n 4
        fi
        printf 'timestats (baris layerName/totalFrames milik pkg):\n'
        dumpsys SurfaceFlinger --timestats -dump 2>&1 | grep -F -A1 "$1" | head -n 6
    } >> "$DBG_LOG" 2>/dev/null
}

sample() {
    _s_pkg="$1"
    _s_fps=""
    _s_lat=""
    if [ -n "$_s_pkg" ]; then
        if [ "$CNT_FAIL" -lt 3 ]; then
            sf_counter; _s_cnt=$SC_RES
            case "$_s_cnt" in
                "") ;;
                "0 "*)
                    ZERO_RUN=$((ZERO_RUN + 1))
                    if [ "$ZERO_RUN" -ge 3 ]; then
                        # counter diam 3x: coba layer; kalau layer punya frame, counter dianggap tidak dipakai.
                        if fps_layer "$_s_pkg"; then CNT_FAIL=3; _s_lat=$FL_LAT; else _s_fps=$_s_cnt; fi
                        ZERO_RUN=0
                    else
                        _s_fps=$_s_cnt
                    fi
                    ;;
                *) ZERO_RUN=0; _s_fps=$_s_cnt ;;
            esac
        fi
        if [ "$CNT_FAIL" -ge 3 ] && [ -z "$_s_lat" ]; then
            if fps_layer "$_s_pkg"; then
                _s_lat=$FL_LAT
                LAYER_FAIL=0
            else
                LAYER_FAIL=$((LAYER_FAIL + 1))
                # timestats itu berat: dicoba hanya beberapa kali; pencarian layer (ringan) tetap jalan terus,
                # supaya FPS muncul begitu layer game ada (mis. setelah layar loading)
                if [ "$LAYER_FAIL" -ge 3 ] && { [ "$LAYER_FAIL" -le 6 ] || [ $((LAYER_FAIL % 10)) -eq 0 ]; } && [ "$LIGHT" != 1 ]; then
                    ts_fps "$_s_pkg" && _s_fps=$TS_RES
                    [ -n "$_s_fps" ] || dbg_dump "$_s_pkg"
                fi
            fi
        fi
    fi
    set -- $_s_fps
    printf 'fps_x10=%s\nlast_ts=%s\n' "${1:-}" "${2:-}"
    printf 'pkg=%s\n' "$_s_pkg"
    printf 'lat=%s\n' "$_s_lat"
    gp_path   # cache path GPU di shell utama (di $(...) cache hilang tiap sampel)
    printf 'gpu=%s\n' "$(gpu_load || printf '%s' '--')"
    printf 'gpu_freq=%s\n' "$(gpu_freq_mhz || printf '%s' '--')"
    read -r _s_cpu < /proc/stat 2>/dev/null
    printf 'cpu=%s\n' "$_s_cpu"
    printf 'temp_mc=%s\nsoc_mc=%s\n' "$(batt_temp_mc)" "$(soc_temp_mc)"
}

# matikan timestats yang kita nyalakan sendiri (jangan dibiarkan aktif terus di SurfaceFlinger)
# exit $rc: jangan paksa 0, kalau tidak pemanggil tidak bisa tahu --fpsd gagal.
trap 'rc=$?; [ "$TS_ON" = 1 ] && dumpsys SurfaceFlinger --timestats -disable >/dev/null 2>&1; exit $rc' EXIT HUP INT TERM

# Diagnosa FPS: tiap sumber dicoba sekali, hasil ditulis rapi (dipakai tombol Diagnosa FPS di app).
diag() {
    _dg_pkg="$1"
    echo "paket: ${_dg_pkg:-(kosong)}"
    _dg_fb=$(fpsd_bin 2>/dev/null)
    if [ -z "$_dg_fb" ]; then echo "daemon FPS: TIDAK ADA di modul ini (pakai jalur dumpsys)"; else
        echo "daemon FPS: $("$_dg_fb" --selftest 2>&1 | head -n 1)"
        [ -r "$STATE_DIR/fpsd.status" ] && echo "status daemon: $(head -n 1 "$STATE_DIR/fpsd.status")"
        _dg_p=""; [ -r "$STATE_DIR/fpsd.pid" ] && read -r _dg_p < "$STATE_DIR/fpsd.pid"
        if [ -n "$_dg_p" ] && kill -0 "$_dg_p" 2>/dev/null; then echo "proses daemon: jalan (pid $_dg_p)"; else echo "proses daemon: tidak jalan"; fi
    fi
    _dg_a=$(service call SurfaceFlinger 1013 2>&1 | head -n 1)
    case "$_dg_a" in *"Parcel(00000000"*) echo "counter SurfaceFlinger: ADA" ;; *) echo "counter SurfaceFlinger: TIDAK ADA" ;; esac
    _dg_l=$(layer_candidates "$_dg_pkg" 2>/dev/null)
    _dg_n=$(printf '%s\n' "$_dg_l" | grep -c .)
    echo "layer milik paket: $_dg_n"
    printf '%s\n' "$_dg_l" | head -n 6
    _dg_ok=0
    while IFS= read -r _dg_x; do
        [ -n "$_dg_x" ] || continue
        if lat_rows "$_dg_x"; then echo "layer berisi frame ($LR_N): $_dg_x"; _dg_ok=1; fi
    done <<EOF
$_dg_l
EOF
    [ "$_dg_ok" = 1 ] || echo "jalur layer: TIDAK ADA layer yang berisi frame"
    _dg_t=$(dumpsys SurfaceFlinger --timestats -dump 2>/dev/null | grep -c totalFrames)
    echo "timestats: $_dg_t entri totalFrames"
}

case "$1" in
    --diag) diag "$2" ;;
    --once) CNT_FAIL=3; sample "$2" ;;   # satu sampel: counter butuh dua titik, jadi langsung jalur layer
    --loop)
        # "--loop auto [cadangan]": paket diikuti otomatis dari app yang sedang di depan
        # (ditulis monitor.sh ke .hud_foreground_pkg), jadi satu proses cukup untuk game
        # maupun launcher/browser/sosmed. Ganti paket = reset cache layer, tanpa proses baru.
        _lp_pkg="$2"; _lp_auto=0; _lp_fb="$3"; _lp_last=""
        [ "$2" = "auto" ] && _lp_auto=1
        while :; do
            if [ "$_lp_auto" = 1 ]; then
                _lp_pkg=""
                read -r _lp_pkg < "$STATE_DIR/.hud_foreground_pkg" 2>/dev/null
                [ -n "$_lp_pkg" ] || _lp_pkg="$_lp_fb"
                if [ "$_lp_pkg" != "$_lp_last" ]; then
                    _lp_last="$_lp_pkg"
                    CNT_FAIL=3; ZERO_RUN=0; LAYER_FAIL=0; LIST_WAIT=0; TS_PREV=""; _lp_back=0; _lp_slow=0; SRC_DEAD=0; SRC_N=0
                    rm -f "$LAYER_CACHE" 2>/dev/null
                fi
            fi
            # game (ditandai .gh_active) = tiap 1 dtk; app lain = tiap 2 dtk dan ringan,
            # supaya dumpsys SurfaceFlinger tidak membuat Play Store/sosmed tersendat
            LIGHT=1; _lp_slp=2; [ "${_lp_back:-0}" = 1 ] && _lp_slp=5
            read -r _lp_gm < "$STATE_DIR/.gh_active" 2>/dev/null
            [ -n "$_lp_gm" ] && [ "$_lp_gm" = "$_lp_pkg" ] && { LIGHT=0; _lp_slp=1; }
            [ "$_lp_auto" = 1 ] || { LIGHT=0; _lp_slp=1; }
            TICK_S=$_lp_slp
            _lp_u0=""; read -r _lp_u0 _ 2>/dev/null < /proc/uptime
            sample "$_lp_pkg" || exit 0
            echo "--" || exit 0
            # sampel lambat (>=0,6 dtk) = SurfaceFlinger sedang berat: di app non-game mundur ke 5 dtk
            if [ "$LIGHT" = 1 ]; then
                _lp_u1=""; read -r _lp_u1 _ 2>/dev/null < /proc/uptime
                _lp_c0=${_lp_u0%.*}${_lp_u0#*.}; _lp_c1=${_lp_u1%.*}${_lp_u1#*.}
                case "$_lp_c0$_lp_c1" in ''|*[!0-9]*) ;; *)
                    # hanya mundur bila dua sampel berturut-turut lambat (satu sampel lambat = pencarian layer awal, wajar)
                    if [ $((_lp_c1 - _lp_c0)) -ge 100 ]; then
                        _lp_slow=$(( ${_lp_slow:-0} + 1 ))
                        [ "$_lp_slow" -ge 2 ] && { _lp_back=1; _lp_slp=5; }
                    else
                        _lp_slow=0
                    fi ;;
                esac
            fi
            sleep "$_lp_slp"
        done
        ;;
    --fpsd)   # arahkan daemon FPS ke paket ini (dipakai adapt.sh); tanpa sampel lain
        [ -n "${2:-}" ] || { echo "Usage: hud_sample.sh --fpsd <package>"; exit 1; }
        fpsd_ensure || { echo "fpsd tidak aktif"; exit 1; }
        printf '%s' "$2" > "$FPSD_PKG" 2>/dev/null || { echo "gagal tulis $FPSD_PKG"; exit 1; }
        echo "OK: fpsd -> $2"
        ;;
    *) echo "Usage: hud_sample.sh --once|--loop|--fpsd <package|auto>"; exit 1 ;;
esac
