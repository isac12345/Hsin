#!/system/bin/sh
# core/thermal_check.sh — Step 10 thermal safety guardrail.
# BANGUN DI ATAS detector.sh: THERMAL (count|writable), THERMAL_W,
# THERMAL_PATH (zone pertama bertipe cpu/gpu/soc, fallback zone pertama).
# Prinsip alpha-hsin-engineering: guardrail BUKAN primary limiter;
# 4 state (NORMAL/HIGH/VERY HIGH/CRITICAL); threshold BERBASIS data
# thermal_zone yang terdeteksi (trip_point kernel, bukan angka fix
# universal); TIDAK menyebut vendor/chipset.
# Return state ke caller (bukan langsung nulis sysfs dari file ini,
# kecuali SATU intervensi CRITICAL via hsin_safe_apply).

[ -z "$HSIN_MODULE_PATH" ] && HSIN_MODULE_PATH="/data/adb/modules/hsin"
HSIN_DATA="${HSIN_DATA:-/data/adb/hsin}"
[ -n "$HSIN_SYSFS_THERMAL" ] || HSIN_SYSFS_THERMAL="${SYSFS_THERMAL_PREFIX:-/sys/class/thermal}"
[ -n "$HSIN_SYSFS_CPU" ] || HSIN_SYSFS_CPU="${SYSFS_CPU_PREFIX:-/sys/devices/system/cpu}"
# source detector cache/global jika ada; tanpa crash jika hilang
if [ -f "${HSIN_MODULE_PATH}/core/detector.sh" ]; then
    if [ -f "$HSIN_DATA/detected.conf" ]; then
        . "$HSIN_DATA/detected.conf" 2>/dev/null || true
    fi
fi

# State untuk caller. Di-reset tiap source agar baca selalu segar.
HSIN_THERMAL_CHECK_STATE="UNKNOWN"
THERMAL_MAX_TEMP=0
THERMAL_ZONE_COUNT=0
HSIN_THERMAL_CHECK_INTERVENED="0"
HSIN_THERMAL_CHECK_RC=4
# Basis threshold device-specific (dari trip_point kernel); 0 = fallback.
HSIN_THERMAL_CHECK_BASIS="fallback"

# Baca suhu max satu pass atas zona terdeteksi (pola detector 1-pass).
_read_thermal_max() {
    _max=0
    _base="$HSIN_SYSFS_THERMAL"
    if [ -n "$THERMAL_PATH" ] && [ -f "$THERMAL_PATH" ]; then
        IFS= read -r _t < "$THERMAL_PATH" 2>/dev/null || _t=""
        case "$_t" in ''|*[!0-9]*) _t=0 ;; esac
        [ "$_t" -gt "$_max" ] 2>/dev/null && _max="$_t"
    fi
    for _z in ${_base}/thermal_zone*; do
        [ -f "$_z/temp" ] || continue
        IFS= read -r _t < "$_z/temp" 2>/dev/null || _t=""
        case "$_t" in ''|*[!0-9]*) continue ;; esac
        THERMAL_ZONE_COUNT=$((THERMAL_ZONE_COUNT + 1))
        [ "$_t" -gt "$_max" ] 2>/dev/null && _max="$_t"
    done
    THERMAL_MAX_TEMP="$_max"
}

# Threshold dari trip_point kernel yang terdeteksi (max semua zona).
# Ini data device-specific — bukan angka fix universal. Tanpa trip data,
# fallback konservatif + log jelas bahwa fallback dipakai.
_read_thermal_basis() {
    _crit=0
    _base="$HSIN_SYSFS_THERMAL"
    for _z in ${_base}/thermal_zone*; do
        for _tp in "$_z"/trip_point_*_temp; do
            [ -f "$_tp" ] || continue
            IFS= read -r _tv < "$_tp" 2>/dev/null || _tv=""
            case "$_tv" in ''|*[!0-9]*) continue ;; esac
            # Abaikan trip absurd (<40C / >125C = sensor rusak)
            [ "$_tv" -lt 40000 ] 2>/dev/null && continue
            [ "$_tv" -gt 125000 ] 2>/dev/null && continue
            [ "$_tv" -gt "$_crit" ] 2>/dev/null && _crit="$_tv"
        done
    done
    if [ "$_crit" -gt 0 ] 2>/dev/null; then
        HSIN_THERMAL_CRIT="$_crit"
        HSIN_THERMAL_CHECK_BASIS="trip_point:${_crit}"
    else
        HSIN_THERMAL_CRIT=95000
        HSIN_THERMAL_CHECK_BASIS="fallback:95000"
    fi
    HSIN_THERMAL_VHIGH=$((HSIN_THERMAL_CRIT * 84 / 100))
    HSIN_THERMAL_HIGH=$((HSIN_THERMAL_CRIT * 68 / 100))
}

_classify_thermal() {
    _max="$THERMAL_MAX_TEMP"
    # Tanpa data sama sekali -> UNKNOWN (paling aman: tidak block tuning
    # normal, tapi tidak ada guardrail tambahan).
    if [ -z "$_max" ] || [ "$_max" -le 0 ] 2>/dev/null; then
        HSIN_THERMAL_CHECK_STATE="UNKNOWN"
        echo "[thermal_check] UNKNOWN (no thermal data; zones=${THERMAL_ZONE_COUNT:-0})" >&2
        return 0
    fi

    if [ "$_max" -ge "$HSIN_THERMAL_CRIT" ] 2>/dev/null; then
        HSIN_THERMAL_CHECK_STATE="CRITICAL"
    elif [ "$_max" -ge "$HSIN_THERMAL_VHIGH" ] 2>/dev/null; then
        HSIN_THERMAL_CHECK_STATE="VERY HIGH"
    elif [ "$_max" -ge "$HSIN_THERMAL_HIGH" ] 2>/dev/null; then
        HSIN_THERMAL_CHECK_STATE="HIGH"
    else
        HSIN_THERMAL_CHECK_STATE="NORMAL"
    fi
    case "$HSIN_THERMAL_CHECK_STATE" in
        NORMAL)
            echo "[thermal_check] NORMAL max=${_max}mC zones=${THERMAL_ZONE_COUNT} basis=${HSIN_THERMAL_CHECK_BASIS}" >&2
            ;;
        HIGH)
            echo "[thermal_check] HIGH max=${_max}mC zones=${THERMAL_ZONE_COUNT} basis=${HSIN_THERMAL_CHECK_BASIS} — monitor only, NO intervention" >&2
            ;;
        "VERY HIGH")
            echo "[thermal_check] VERY HIGH max=${_max}mC zones=${THERMAL_ZONE_COUNT} basis=${HSIN_THERMAL_CHECK_BASIS} — monitor, limited intervention only if justified" >&2
            ;;
        CRITICAL)
            echo "[thermal_check] CRITICAL max=${_max}mC zones=${THERMAL_ZONE_COUNT} basis=${HSIN_THERMAL_CHECK_BASIS} — emergency thermal intervention allowed" >&2
            ;;
    esac
}

# Intervensi TERBATAS hanya di CRITICAL, HANYA via hsin_safe_apply
# (tanpa logic apply baru). Satu parameter paling berisiko panas:
# scaling_max_freq policy CPU pertama yang writable -> turunkan ke
# scaling_min_freq-nya. Alasan selalu di-log.
_thermal_critical_intervene() {
    # shellcheck disable=SC1091
    . "$HSIN_MODULE_PATH/core/sysfs.sh" 2>/dev/null || true
    # shellcheck disable=SC1091
    . "$HSIN_MODULE_PATH/core/safe_apply.sh" 2>/dev/null || true
    if ! command -v hsin_safe_apply >/dev/null 2>&1; then
        echo "[thermal_check] CRITICAL but safe_apply unavailable — skip emergency intervention (fail-safe)" >&2
        return 1
    fi
    for _p in "$HSIN_SYSFS_CPU"/cpufreq/policy*/scaling_max_freq; do
        [ -e "$_p" ] || continue
        [ -w "$_p" ] || continue
        _dir="${_p%/*}"
        _min=""
        [ -f "$_dir/scaling_min_freq" ] && IFS= read -r _min < "$_dir/scaling_min_freq" 2>/dev/null
        case "$_min" in ''|*[!0-9]*) _min="" ;; esac
        if [ -z "$_min" ]; then
            IFS= read -r _cur < "$_p" 2>/dev/null || _cur=""
            case "$_cur" in ''|*[!0-9]*) continue ;; esac
            _min=$((_cur * 70 / 100))
        fi
        hsin_safe_apply "$_p" "$_min" "THERMAL"
        HSIN_THERMAL_SAFE_RC=$?
        HSIN_THERMAL_CHECK_INTERVENED="1"
        echo "[thermal_check] CRITICAL intervention via safe_apply: node=$_p value=$_min rc=$HSIN_THERMAL_SAFE_RC reason=max=${THERMAL_MAX_TEMP}mC>=crit=${HSIN_THERMAL_CRIT}mC; safety priority over tuning" >&2
        return 0
    done
    echo "[thermal_check] CRITICAL but no writable scaling_max_freq — nothing to reduce (fail-safe, tuning untouched)" >&2
    return 1
}

# --- Eksekusi (fungsi eksplisit, BUKAN auto-exec saat di-source) --------
# Jalankan guardrail: baca -> basis -> klasifikasi -> (CRITICAL: intervensi
# sekali) -> export state untuk caller.
#
# PENTING (insiden 2026-09-30): versi sebelumnya menjalankan blok ini di
# level TOP-LEVEL. build_release.sh menggabungkan semua core/*.sh ke satu
# core/runtime.sh, sehingga blok auto-exec ikut jalan setiap kali
# runtime.sh di-source - yaitu pada SETIAP perintah action.sh termasuk
# polling monitor (mencetak "[thermal_check] <state>" ke stderr), dan
# blok `if [ -f core/thermal_check.sh ]` di service.sh tetap buta karena
# file tidak ada lagi sebagai file terpisah. Sekarang eksplisit: caller
# memanggil hsin_thermal_check_run.
#
# Caller saat ini: service.sh (boot, setelah boot guard, sebelum tuning).
hsin_thermal_check_run() {
    _read_thermal_max
    _read_thermal_basis
    _classify_thermal

    case "$HSIN_THERMAL_CHECK_STATE" in
        NORMAL) HSIN_THERMAL_CHECK_RC=0 ;;
        HIGH) HSIN_THERMAL_CHECK_RC=1 ;;
        "VERY HIGH") HSIN_THERMAL_CHECK_RC=2 ;;
        CRITICAL)
            HSIN_THERMAL_CHECK_RC=3
            _thermal_critical_intervene || true
            ;;
        *) HSIN_THERMAL_CHECK_RC=4 ;;
    esac

    # Export state untuk caller (service.sh / apply pipeline).
    export HSIN_THERMAL_CHECK_STATE
    export THERMAL_MAX_TEMP
    export THERMAL_ZONE_COUNT
    export HSIN_THERMAL_CHECK_INTERVENED
    export HSIN_THERMAL_CHECK_RC
    export HSIN_THERMAL_SAFE_RC
    export HSIN_THERMAL_CHECK_BASIS

    return $HSIN_THERMAL_CHECK_RC
}

# Konvensi repo untuk file yang hanya berisi definisi: tidak melakukan
# apa pun saat di-source (khusunya tidak Cetak ke stderr).
# shellcheck disable=SC2086
return 0 2>/dev/null || true
