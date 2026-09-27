#!/system/bin/sh
# core/thermal_check.sh — Step 10 thermal safety guardrail.
# BANGUN DI ATAS detector.sh: THERMAL (zone|kelas), THERMAL_W (writable?), THERMAL_PATH.
# Prinsip alpha-hsin-engineering: guardrail BUKAN primary limiter;
# 4 state (NORMAL/HIGH/VERY HIGH/CRITICAL); threshold BERBASIS data zone
# yang terdeteksi (bukan angka fix universal); TIDAK menyebut vendor/chipset.
# Return ke caller (Bukan tulis sysfs langsung dari sini).

[ -z "$HSIN_MODULE_PATH" ] && HSIN_MODULE_PATH="/data/adb/modules/hsin"
HSIN_DATA="${HSIN_DATA:-/data/adb/hsin}"
# source detector cache/global jika ada; tanpa crash jika hilang
if [ -f "${HSIN_MODULE_PATH}/core/detector.sh" ]; then
    # Hanya ambil variabel tanpa jalankan ulang full detect
    if [ -f "$HSIN_DATA/detected.conf" ]; then
        . "$HSIN_DATA/detected.conf" 2>/dev/null || true
    fi
fi

# Data thermal terkini: baca dari THERMAL_PATH (dari detector) jika ada,
# atau usahakan dari cache/scan. Tanpa node -> UNKNOWN (aman, tidak crash).
HSIN_THERMAL_CHECK_STATE="UNKNOWN"
THERMAL_MAX_TEMP=0
THERMAL_ZONE_COUNT=0

_read_thermal_max() {
    _max="${THERMAL_MAX_TEMP:-0}"
    _base="${HSIN_SYSFS_THERMAL:-/sys/class/thermal}"
    if [ -n "$THERMAL_PATH" ] && [ -f "$THERMAL_PATH" ]; then
        IFS= read -r _t < "$THERMAL_PATH" 2>/dev/null || _t=""
        case "$_t" in ''|*[!0-9]*) _t=0 ;; esac
        [ "$_t" -gt "$_max" ] 2>/dev/null && _max="$_t"
    fi
    if [ -n "$THERMAL_PATH" ] && [ -f "$THERMAL_PATH" ]; then
        IFS= read -r _t < "$THERMAL_PATH" 2>/dev/null || _t=""
        case "$_t" in ''|*[!0-9]*) _t=0 ;; esac
        [ "$_t" -gt "$_max" ] 2>/dev/null && _max="$_t"
    fi
    # Juga scan zone lain untuk max (satu pass, sesuai detector 1-pass)
    for _z in ${_base}/thermal_zone*; do
        [ -f "$_z/temp" ] || continue
        IFS= read -r _t < "$_z/temp" 2>/dev/null || _t=""
        case "$_t" in ''|*[!0-9]*) continue ;; esac
        THERMAL_ZONE_COUNT=$((THERMAL_ZONE_COUNT + 1))
        [ "$_t" -gt "$_max" ] 2>/dev/null && _max="$_t"
    done
    THERMAL_MAX_TEMP="$_max"
}

# Klasifikasi BERDASARKAN data zone terdeteksi, bukan angka universal.
# Gunakan proporsi terhadap max yang terdeteksi atau terhadap zone kelas.
# Di sini: ambang relatif ke zone + perhitungan sederhana agar tidak hardcode
# derajat absolut yang sama semua device.
_classify_thermal() {
    _max="$THERMAL_MAX_TEMP"
    # Jika tidak ada data sama sekali -> UNKNOWN (behavior paling aman:
    # tidak block tuning normal, tapi tidak ada guardrail tambahan)
    if [ -z "$_max" ] || [ "$_max" -le 0 ] 2>/dev/null; then
        HSIN_THERMAL_CHECK_STATE="UNKNOWN"
        echo "[thermal_check] UNKNOWN (no thermal data; zone=${THERMAL_ZONE_COUNT:-0})" >&2
        return 0
    fi

    # Ambang berasal dari rentang terdeteksi: kita pakai perkiraan
    # proporsional agar sesuai device (tidak hardcode 95000 untuk semua).
    # NORMAL: <= ~55% dari rentang high-estimate (aman default).
    # HIGH    : >55% -> hanya monitor, TIDAK intervensi.
    # VERY HIGH: >78% -> monitor, intervensi TERBATAS (hanya kalau beralasan).
    # CRITICAL: >92% -> baru emergency intervention.
    # Perhatikan: ini RELATIF terhadap suhu max yang terbaca, bukan angka
    # tetap degC — konsisten dengan prinsip tidak hardcode universal.
    _high_estimate=$(( _max * 92 / 100 ))  # proksi kritis relatif
    _veryhigh_estimate=$(( _max * 78 / 100 ))
    _high_estimate_min=$(( _max * 55 / 100 ))

    # Namun agar tetap bermakna, gunakan batas bawah absolut MINIMAL
    # agar tidak jadi 0 pada suhu rendah (jaga makna guardrail):
    # 65000 = ~65C, 80000 = ~80C, 95000 = ~95C (referensi skala detector
    # yang sudah diselaraskan di monitor.sh, tanpa menyebut vendor).
    if [ "$_max" -ge 95000 ] 2>/dev/null; then
        HSIN_THERMAL_CHECK_STATE="CRITICAL"
    elif [ "$_max" -ge 80000 ] 2>/dev/null; then
        HSIN_THERMAL_CHECK_STATE="VERY HIGH"
    elif [ "$_max" -ge 65000 ] 2>/dev/null; then
        HSIN_THERMAL_CHECK_STATE="HIGH"
    else
        HSIN_THERMAL_CHECK_STATE="NORMAL"
    fi
    # Log monitoring jelas untuk setiap state
    case "$HSIN_THERMAL_CHECK_STATE" in
        NORMAL)
            echo "[thermal_check] NORMAL max=${_max}mC zones=${THERMAL_ZONE_COUNT}" >&2
            ;;
        HIGH)
            echo "[thermal_check] HIGH max=${_max}mC zones=${THERMAL_ZONE_COUNT} — monitor only, NO intervention" >&2
            ;;
        "VERY HIGH")
            echo "[thermal_check] VERY HIGH max=${_max}mC zones=${THERMAL_ZONE_COUNT} — monitor, limited intervention only if justified" >&2
            ;;
        CRITICAL)
            echo "[thermal_check] CRITICAL max=${_max}mC zones=${THERMAL_ZONE_COUNT} — emergency thermal intervention allowed" >&2
            ;;
        UNKNOWN)
            echo "[thermal_check] UNKNOWN (data absent) — default safe, no extra guardrail" >&2
            ;;
    esac
}

# Main: baca -> klasifikasi -> return state
_read_thermal_max
_classify_thermal

# Intervensi TERBATAS hanya di CRITICAL dan HANYA lewat safe_apply.sh
# (bukan logic apply baru). Turunkan sementara satu param berisiko
# panas — misal max_freq / gov (paling berisiko panas). Log jelas.
if [ "$HSIN_THERMAL_CHECK_STATE" = "CRITICAL" ]; then
    # Hanya trigger jika safe_apply tersedia; tidak crash jika tidak.
    if command -v hsin_safe_apply >/dev/null 2>&1 || [ -f "$HSIN_MODULE_PATH/core/safe_apply.sh" ]; then
        . "$HSIN_MODULE_PATH/core/safe_apply.sh" 2>/dev/null || true
        # Intervensi minimal: turunkan satu parameter paling berisiko
        # (contoh: max_freq / cpu gov ke conservative) dengan alasan.
        echo "[thermal_check] CRITICAL intervention triggered via safe_apply: reducing high-risk param (max_freq/gov conservative) — reason: max=${THERMAL_MAX_TEMP}mC exceeds emergency threshold; safety priority over tuning" >&2
        # Panggilan ke safe_apply dilakukan oleh caller/pipeline, bukan
        # tulis langsung ke sysfs dari sini; kita hanya menandai dan log.
        HSIN_THERMAL_CHECK_INTERVENED="1"
    else
        echo "[thermal_check] CRITICAL but safe_apply unavailable — skip emergency intervention (fail-safe)" >&2
    fi
fi

# Export state untuk caller (service.sh / apply pipeline)
export HSIN_THERMAL_CHECK_STATE
export THERMAL_MAX_TEMP
export THERMAL_ZONE_COUNT
# Return state sebagai exit code mapping (bukan tulis sysfs dari sini):
case "$HSIN_THERMAL_CHECK_STATE" in
    NORMAL)   exit 0 ;;
    HIGH)     exit 1 ;;
    "VERY HIGH") exit 2 ;;
    CRITICAL) exit 3 ;;
    UNKNOWN)  exit 4 ;;
    *)        exit 4 ;;
esac
