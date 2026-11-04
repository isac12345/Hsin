#!/system/bin/sh
# HSIN - screenrec: rekam layar lewat `screenrecord` bawaan Android (root, tanpa dialog izin).
#
#   screenrec.sh start     mulai merekam (satu file per sesi; baru dipotong bila batas waktu perangkat tercapai)
#   screenrec.sh stop      berhenti dan tutup file dengan benar
#   screenrec.sh status    running=1|0, file=<potongan sekarang>, dir=<folder>
#   screenrec.sh list [N]  N file rekaman terbaru
#
# Hasil: /sdcard/Movies/HSIN/HSIN_<tanggal>_<jam>.mp4 (potongan lanjutan: _p2, _p3 ...) (tanpa audio; screenrecord tidak
# bisa merekam audio internal). Bitrate dari conf REC_BITRATE_MBPS (default 8, rentang 2-40).
# Ada jeda sekitar setengah detik antar potongan.

STATE_DIR="${HSIN_STATE_DIR:-/data/adb/hsin}"
CONF_FILE="$STATE_DIR/app.conf"
PID_FILE="$STATE_DIR/.rec_pid"
STOP_FILE="$STATE_DIR/.rec_stop"
CUR_FILE="$STATE_DIR/.rec_file"
OUT_DIR="${HSIN_REC_DIR:-/sdcard/Movies/HSIN}"
SEG_SECS="${HSIN_REC_SEG:-3600}"
SELF="$(readlink -f "$0")"

rec_alive() {
    [ -f "$PID_FILE" ] || return 1
    _ra=$(tr -d '[:space:]' < "$PID_FILE" 2>/dev/null)
    [ -n "$_ra" ] || return 1
    kill -0 "$_ra" 2>/dev/null || return 1
    [ -r "/proc/$_ra/cmdline" ] || return 1
    case "$(tr '\000' ' ' < "/proc/$_ra/cmdline" 2>/dev/null)" in *screenrec.sh*) return 0 ;; esac
    return 1
}

bitrate() {
    _b=""
    [ -f "$CONF_FILE" ] && _b=$(sed -n 's/^REC_BITRATE_MBPS=//p' "$CONF_FILE" 2>/dev/null | tail -n 1)
    case "$_b" in ''|*[!0-9]*) _b=8 ;; esac
    [ "$_b" -ge 2 ] 2>/dev/null && [ "$_b" -le 40 ] 2>/dev/null || _b=8
    printf '%s' $((_b * 1000000))
}

conf_get() {
    [ -f "$CONF_FILE" ] && sed -n "s/^$1=//p" "$CONF_FILE" 2>/dev/null | tail -n 1
}

# Argumen --size untuk REC_SIZE=720|1080 (sisi pendek). Kosong = ukuran asli layar. Tidak pernah memperbesar.
size_arg() {
    _sz=$(conf_get REC_SIZE)
    case "$_sz" in 720|1080) ;; *) return 0 ;; esac
    _ws=$(wm size 2>/dev/null | sed -n 's/^[A-Za-z ]*size: *//p' | tail -n 1)
    _w=${_ws%x*}; _h=${_ws#*x}
    case "$_w$_h" in ''|*[!0-9]*) return 0 ;; esac
    if [ "$_w" -lt "$_h" ]; then _sh=$_w; _lg=$_h; else _sh=$_h; _lg=$_w; fi
    [ "$_sz" -lt "$_sh" ] || return 0
    _lg2=$(( _lg * _sz / _sh )); _lg2=$(( _lg2 / 2 * 2 ))
    _rot=$(dumpsys input 2>/dev/null | sed -n 's/.*[Ss]urface[Oo]rientation: *\([0-3]\).*/\1/p' | head -n 1)
    case "$_rot" in 1|3) printf '%s' "--size ${_lg2}x${_sz}" ;; *) printf '%s' "--size ${_sz}x${_lg2}" ;; esac
}

TOUCH_ORIG="$STATE_DIR/.rec_touch_orig"
touch_on() {
    [ "$(conf_get REC_TOUCH)" = 1 ] || return 0
    settings get system show_touches > "$TOUCH_ORIG" 2>/dev/null
    settings put system show_touches 1 2>/dev/null
}
touch_restore() {
    [ -f "$TOUCH_ORIG" ] || return 0
    _to=$(cat "$TOUCH_ORIG" 2>/dev/null)
    case "$_to" in 1) ;; *) _to=0 ;; esac
    settings put system show_touches "$_to" 2>/dev/null
    rm -f "$TOUCH_ORIG"
}

# Dijalankan di latar belakang oleh `start`.
rec_loop() {
    echo "$$" > "$PID_FILE"
    mkdir -p "$OUT_DIR" 2>/dev/null
    _n=1
    _br=$(bitrate)
    _fail=0
    _sid=$(date '+%Y%m%d_%H%M%S')
    _seg="$SEG_SECS"
    touch_on
    while [ ! -f "$STOP_FILE" ]; do
        # satu sesi = satu nama dasar; potongan hanya muncul kalau batas waktu tercapai
        if [ "$_n" -eq 1 ]; then _f="$OUT_DIR/HSIN_${_sid}.mp4"; else _f="$OUT_DIR/HSIN_${_sid}_p$_n.mp4"; fi
        printf '%s\n' "$_f" > "$CUR_FILE"
        _t0=$(cut -d. -f1 /proc/uptime 2>/dev/null)
        _sa=$(size_arg)
        # shellcheck disable=SC2086
        screenrecord --bit-rate "$_br" --time-limit "$_seg" $_sa "$_f" >/dev/null 2>&1
        _t1=$(cut -d. -f1 /proc/uptime 2>/dev/null)
        am broadcast -a android.intent.action.MEDIA_SCANNER_SCAN_FILE -d "file://$_f" >/dev/null 2>&1
        # screenrecord langsung gagal (mis. layar terkunci / DRM / binary tidak ada): jangan putar tanpa henti
        if [ -n "$_t0" ] && [ -n "$_t1" ] && [ $((_t1 - _t0)) -lt 2 ]; then
            rm -f "$_f"
            # versi lama menolak batas > 180 dtk: turun ke 180 lalu coba lagi
            if [ "$_seg" -gt 180 ]; then _seg=180; continue; fi
            _fail=$((_fail + 1))
            [ "$_fail" -ge 3 ] && break
            sleep 1
        else
            _fail=0
        fi
        _n=$((_n + 1))
    done
    touch_restore
    rm -f "$PID_FILE" "$STOP_FILE" "$CUR_FILE"
}

rec_start() {
    command -v screenrecord >/dev/null 2>&1 || { echo "ERROR: screenrecord tidak ada di perangkat ini"; return 1; }
    if rec_alive; then echo "OK: sudah merekam"; return 0; fi
    rm -f "$STOP_FILE" "$PID_FILE"
    nohup sh "$SELF" _loop >/dev/null 2>&1 &
    sleep 1
    if rec_alive; then echo "OK: merekam ke $OUT_DIR"; else echo "ERROR: gagal memulai rekaman"; return 1; fi
}

rec_sig() {
    # Hanya anak screenrecord milik loop ini (PPID = PID di PID_FILE), bukan
    # semua screenrecord di perangkat (pidof global).
    _rs_loop=$(tr -d '[:space:]' < "$PID_FILE" 2>/dev/null)
    [ -n "$_rs_loop" ] || return 0
    for _p in $(pidof screenrecord 2>/dev/null); do
        _rs_ppid=$(sed 's/^.*) //' "/proc/$_p/stat" 2>/dev/null | cut -d' ' -f2)
        [ "$_rs_ppid" = "$_rs_loop" ] || continue
        kill "-$1" "$_p" 2>/dev/null
    done
}

rec_wait_exit() {
    _i=0
    while rec_alive && [ "$_i" -lt "$1" ]; do sleep 0.5; _i=$((_i + 1)); done
}

rec_stop() {
    if ! rec_alive; then
        rm -f "$PID_FILE" "$STOP_FILE" "$CUR_FILE"
        echo "OK: tidak sedang merekam"
        return 0
    fi
    : > "$STOP_FILE"
    # screenrecord menutup mp4 dengan benar hanya lewat SIGINT/SIGHUP (bukan SIGTERM)
    rec_sig 2
    rec_wait_exit 6
    if rec_alive; then rec_sig 1; rec_wait_exit 6; fi
    # SIGKILL ke anak screenrecord yang masih hidup (jangan yatim), tunggu 3 dtk
    if rec_alive; then rec_sig 9; rec_wait_exit 6; fi
    if rec_alive; then kill "$(tr -d '[:space:]' < "$PID_FILE")" 2>/dev/null; rec_wait_exit 6; fi
    if rec_alive; then kill -9 "$(tr -d '[:space:]' < "$PID_FILE")" 2>/dev/null; rec_wait_exit 6; fi
    rm -f "$PID_FILE" "$STOP_FILE" "$CUR_FILE"
    echo "OK: rekaman berhenti, folder $OUT_DIR"
}

rec_status() {
    if rec_alive; then echo "running=1"; else echo "running=0"; fi
    printf 'file=%s\n' "$(cat "$CUR_FILE" 2>/dev/null)"
    printf 'dir=%s\n' "$OUT_DIR"
}

rec_list() {
    _n="${1:-10}"
    case "$_n" in ''|*[!0-9]*) _n=10 ;; esac
    [ -d "$OUT_DIR" ] || return 0
    ls -t "$OUT_DIR" 2>/dev/null | head -n "$_n"
}

case "$1" in
    start) rec_start ;;
    stop) rec_stop ;;
    status) rec_status ;;
    list) rec_list "$2" ;;
    _loop) rec_loop ;;
    *) sed -n '2,12p' "$0" ;;
esac
