#!/system/bin/sh
# HSIN v5 boot: simpan baseline (nilai bawaan), lalu terapkan ulang override user.
MODDIR=${0%/*}
. "$MODDIR/core/lib.sh" || exit 0
(
    trim_log boot 200; trim_log apply 400
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
        exit 0
    fi
    apply_overrides
    sleep 30
    echo 0 > "$CNTF"
    log INFO boot "boot stabil, counter direset"
    sleep 30
    apply_overrides
) >/dev/null 2>&1 &
