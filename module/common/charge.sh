#!/system/bin/sh
# HSIN - batas pengisian baterai (opsional, tergantung kernel HP).
#   charge.sh caps          jenis kontrol yang tersedia di HP ini
#   charge.sh status        limit, level, status pengisian
#   charge.sh set <50-100>  batasi pengisian (100 = tanpa batas)
#   charge.sh off           matikan batas dan nyalakan pengisian normal
#   charge.sh loop          (internal) penjaga untuk HP tanpa node batas persen
#
# Urutan yang dicoba: node batas persen (paling aman) -> saklar charging aktif/mati dengan penjaga.
STATE="${HSIN_STATE_DIR:-/data/adb/hsin}"
PS="${SYSFS_POWER_PREFIX:-/sys/class/power_supply}"
LIMIT_FILE="$STATE/charge_limit"
PID_FILE="$STATE/.charge_pid"

rd() { [ -r "$1" ] && { read -r _v < "$1"; printf '%s' "$_v"; }; }

# Hasil: CH_KIND (thr|en|susp|none), CH_NODE
detect() {
    CH_KIND=none; CH_NODE=""
    for n in "$PS/battery/charge_control_end_threshold" "$PS/battery/charge_stop_level" "$PS/battery/charge_control_limit_max"; do
        [ -w "$n" ] && { CH_KIND=thr; CH_NODE="$n"; return 0; }
    done
    for n in "$PS/battery/charging_enabled" "$PS/battery/battery_charging_enabled" "$PS/battery/charge_enable" "$PS/usb/charging_enabled"; do
        [ -w "$n" ] && { CH_KIND=en; CH_NODE="$n"; return 0; }
    done
    for n in "$PS/battery/input_suspend" "$PS/usb/input_suspend"; do
        [ -w "$n" ] && { CH_KIND=susp; CH_NODE="$n"; return 0; }
    done
    return 1
}

chg_on()  { case "$CH_KIND" in en) printf '1' > "$CH_NODE" ;; susp) printf '0' > "$CH_NODE" ;; esac; }
chg_off() { case "$CH_KIND" in en) printf '0' > "$CH_NODE" ;; susp) printf '1' > "$CH_NODE" ;; esac; }

level() { rd "$PS/battery/capacity"; }

stop_loop() {
    [ -r "$PID_FILE" ] && { read -r _p < "$PID_FILE"; [ -n "$_p" ] && kill "$_p" 2>/dev/null; }
    rm -f "$PID_FILE"
}

do_loop() {
    echo "$$" > "$PID_FILE"
    detect || exit 0
    while :; do
        [ -f "$LIMIT_FILE" ] || { chg_on; rm -f "$PID_FILE"; exit 0; }
        read -r _lim < "$LIMIT_FILE"
        _lv=$(level)
        case "$_lim$_lv" in ''|*[!0-9]*) sleep 30; continue ;; esac
        if [ "$_lv" -ge "$_lim" ]; then chg_off
        elif [ "$_lv" -le $((_lim - 3)) ]; then chg_on
        fi
        sleep 30
    done
}

case "$1" in
    caps)
        detect
        echo "kind=$CH_KIND"
        echo "node=$CH_NODE"
        ;;
    status)
        detect
        _lim=100; [ -f "$LIMIT_FILE" ] && read -r _lim < "$LIMIT_FILE"
        echo "kind=$CH_KIND"
        echo "limit=$_lim"
        echo "level=$(level)"
        echo "status=$(rd "$PS/battery/status")"
        ;;
    set)
        case "$2" in ''|*[!0-9]*) echo "ERROR: angka 50-100"; exit 1 ;; esac
        [ "$2" -ge 50 ] && [ "$2" -le 100 ] || { echo "ERROR: rentang 50-100"; exit 1; }
        detect || { echo "ERROR: HP ini tidak punya node kontrol pengisian"; exit 2; }
        if [ "$2" = 100 ]; then exec sh "$0" off; fi
        stop_loop
        if [ "$CH_KIND" = thr ]; then
            printf '%s' "$2" > "$CH_NODE" 2>/dev/null || { echo "ERROR: kernel menolak"; exit 3; }
            printf '%s\n' "$2" > "$LIMIT_FILE"
            echo "OK: batas $2% (node kernel)"
        else
            printf '%s\n' "$2" > "$LIMIT_FILE"
            ( sh "$0" loop >/dev/null 2>&1 & )
            echo "OK: batas $2% (penjaga HSIN)"
        fi
        ;;
    off)
        stop_loop
        detect
        rm -f "$LIMIT_FILE"
        case "$CH_KIND" in thr) printf '100' > "$CH_NODE" 2>/dev/null ;; en|susp) chg_on ;; esac
        echo "OK: pengisian normal"
        ;;
    loop) do_loop ;;
    *) echo "Usage: charge.sh caps|status|set <50-100>|off"; exit 1 ;;
esac
