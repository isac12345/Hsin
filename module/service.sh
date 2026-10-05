#!/system/bin/sh
# HSIN v5 boot: simpan baseline (nilai bawaan), terapkan ulang override user, lalu jalankan daemon.
MODDIR=${0%/*}
. "$MODDIR/core/lib.sh" || exit 0
(
    trim_log boot 200; trim_log apply 400; trim_log game 200; trim_log thermal 100
    rm -f "$TRIPF" "$ACTF"
    n=$(rd "$CNTF"); isint "$n" || n=0
    n=$((n + 1)); echo "$n" > "$CNTF"
    log INFO boot "boot ke-$n sejak terakhir stabil"
    if [ "$n" -ge 3 ] && [ ! -f "$SAFEF" ]; then
        : > "$SAFEF"
        log WARN boot "mode aman aktif: boot tidak selesai $n kali berturut-turut"
    fi
    until [ "$(gp sys.boot_completed)" = 1 ]; do sleep 3; done
    sleep 20
    snapshot_baseline
    log INFO boot "baseline bawaan tersimpan"
    if [ -f "$SAFEF" ]; then
        log WARN boot "mode aman: override TIDAK diterapkan (matikan lewat app)"
    else
        apply_overrides
    fi
    sh "$MODDIR/daemon.sh" &
    sleep 30
    echo 0 > "$CNTF"
    log INFO boot "boot stabil, counter direset"
    if [ ! -f "$SAFEF" ]; then sleep 30; apply_overrides; fi
) >/dev/null 2>&1 &
