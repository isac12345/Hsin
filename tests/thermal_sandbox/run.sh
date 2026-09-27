#!/system/bin/sh
# Sandbox test Step 10: core/thermal_check.sh — TANPA sensor device asli.
# Mensimulasikan pohon thermal_zone + policy CPU palsu (mirip Step 5 yang
# mensimulasikan boot fail tanpa reboot asli): semua baca tulis lewat
# jalur asli file (HSIN_SYSFS_THERMAL/HSIN_SYSFS_CPU + THERMAL_PATH),
# BUKAN angka hardcode di test.
#
# Cara pakai: sh tests/thermal_sandbox/run.sh
# Keluar 0 = semua skenario PASS, 1 = ada yang FAIL.
# Scratch HANYA di $HSIN_SANDBOX_DIR — tidak menyentuh /data/adb/hsin.

_HSIN_REPO=$(cd "${0%/*}/../.." 2>/dev/null && pwd)
HSIN_SANDBOX_DIR="${HSIN_SANDBOX_DIR:-/data/data/com.termux/files/usr/tmp/opencode/hsin-thermal-test}"
export HSIN_MODULE_PATH="$_HSIN_REPO"
export HSIN_DATA="$HSIN_SANDBOX_DIR/data"
export HSIN_SYSFS_THERMAL="$HSIN_SANDBOX_DIR/sys/thermal"
export HSIN_SYSFS_CPU="$HSIN_SANDBOX_DIR/sys/cpu"
export SYSFS_THERMAL_PREFIX="$HSIN_SYSFS_THERMAL"
export SYSFS_CPU_PREFIX="$HSIN_SYSFS_CPU"

_PASS=0
_FAIL=0
_ok() { _PASS=$((_PASS + 1)); echo "PASS: $1"; }
_bad() { _FAIL=$((_FAIL + 1)); echo "FAIL: $1"; }

# Bangun pohon palsu: 1 zone (type+temp+trip) + 1 policy CPU.
# $1=temp_mC $2=trip_mC $3=max_freq $4=min_freq
_mk_tree() {
    rm -rf "$HSIN_SANDBOX_DIR"
    mkdir -p "$HSIN_SYSFS_THERMAL/thermal_zone0" "$HSIN_SYSFS_CPU/cpufreq/policy0" "$HSIN_DATA"
    echo "cpu-thermal" > "$HSIN_SYSFS_THERMAL/thermal_zone0/type"
    echo "$1" > "$HSIN_SYSFS_THERMAL/thermal_zone0/temp"
    echo "$2" > "$HSIN_SYSFS_THERMAL/thermal_zone0/trip_point_0_temp"
    echo "$3" > "$HSIN_SYSFS_CPU/cpufreq/policy0/scaling_max_freq"
    echo "$4" > "$HSIN_SYSFS_CPU/cpufreq/policy0/scaling_min_freq"
    echo "300000 600000 1200000 1800000" > "$HSIN_SYSFS_CPU/cpufreq/policy0/scaling_available_frequencies"
    unset THERMAL_PATH
}

# Source thermal_check di subshell (return di file = rc subshell lanjutan),
# lalu laporkan "STATE|RC|INTERVENED|SAFE_APPLIED|MAXFREQ".
_run_check() {
    (
        . "$_HSIN_REPO/core/thermal_check.sh" 2>"$HSIN_SANDBOX_DIR/stderr.log"
        _rc=$?
        echo "${HSIN_THERMAL_CHECK_STATE}|${_rc}|${HSIN_THERMAL_CHECK_INTERVENED}|${HSIN_SAFE_APPLIED:-0}|$(cat "$HSIN_SYSFS_CPU/cpufreq/policy0/scaling_max_freq" 2>/dev/null)|${HSIN_THERMAL_CHECK_BASIS}"
    )
}

rm -rf "$HSIN_SANDBOX_DIR"; mkdir -p "$HSIN_DATA"

# 1. NORMAL (45C, trip 95C): full profile tetap jalan -> node TAK tersentuh.
_mk_tree 45000 95000 1800000 300000
_r=$(_run_check)
if [ "$_r" = "NORMAL|0|0|0|1800000|trip_point:95000" ]; then
    _ok "1. NORMAL (temp file 45000): state+rc0, max_freq utuh 1800000, basis trip device"
else
    _bad "1. NORMAL (dapat: $_r | log: $(cat "$HSIN_SANDBOX_DIR/stderr.log"))"
fi

# 2. HIGH (70C, trip 95C): hanya monitor, TIDAK intervensi.
_mk_tree 70000 95000 1800000 300000
_r=$(_run_check)
if [ "$_r" = "HIGH|1|0|0|1800000|trip_point:95000" ] && grep -q "monitor only, NO intervention" "$HSIN_SANDBOX_DIR/stderr.log"; then
    _ok "2. HIGH (temp file 70000): log monitor-only, max_freq utuh"
else
    _bad "2. HIGH (dapat: $_r | log: $(cat "$HSIN_SANDBOX_DIR/stderr.log"))"
fi

# 3. VERY HIGH (85C, trip 95C): monitor, intervensi terbatas -> node utuh.
_mk_tree 85000 95000 1800000 300000
_r=$(_run_check)
if [ "$_r" = "VERY HIGH|2|0|0|1800000|trip_point:95000" ] && grep -q "limited intervention only if justified" "$HSIN_SANDBOX_DIR/stderr.log"; then
    _ok "3. VERY HIGH (temp file 85000): log-only, max_freq utuh"
else
    _bad "3. VERY HIGH (dapat: $_r | log: $(cat "$HSIN_SANDBOX_DIR/stderr.log"))"
fi

# 4. CRITICAL (97C, trip 95C): intervensi via safe_apply, kategori TERBUKTI.
_mk_tree 97000 95000 1800000 300000
_r=$(_run_check)
if [ "$_r" = "CRITICAL|3|1|1|300000|trip_point:95000" ] \
    && grep -q "CRITICAL intervention via safe_apply" "$HSIN_SANDBOX_DIR/stderr.log" \
    && grep -q "scaling_max_freq value=300000 -> APPLIED" "$HSIN_SANDBOX_DIR/stderr.log"; then
    _ok "4. CRITICAL (temp file 97000): hsin_safe_apply APPLIED, max_freq 1800000->300000, rc=3"
else
    _bad "4. CRITICAL (dapat: $_r | log: $(cat "$HSIN_SANDBOX_DIR/stderr.log"))"
fi

# 4b. Threshold RELATIF device (bukti tidak hardcode universal): suhu SAMA
# 85C = VERY HIGH di device trip 95C, tapi HIGH di device trip 105C.
_mk_tree 85000 105000 1800000 300000
_r=$(_run_check)
if [ "$_r" = "HIGH|1|0|0|1800000|trip_point:105000" ]; then
    _ok "4b. 85000mC: HIGH di trip 105C vs VERY HIGH di trip 95C (relatif device, bukan angka fix)"
else
    _bad "4b. relativitas device (dapat: $_r)"
fi

# 5. Data thermal hilang -> UNKNOWN, tidak crash, tidak block (rc=4 aman).
rm -rf "$HSIN_SANDBOX_DIR"; mkdir -p "$HSIN_SYSFS_THERMAL" "$HSIN_DATA"
unset THERMAL_PATH
_r=$(_run_check)
if [ "$_r" = "UNKNOWN|4|0|0||fallback:95000" ] && grep -q "UNKNOWN" "$HSIN_SANDBOX_DIR/stderr.log"; then
    _ok "5. hilang (dir kosong): UNKNOWN rc=4, no-crash, basis fallback tercatat"
else
    _bad "5. hilang (dapat: $_r | log: $(cat "$HSIN_SANDBOX_DIR/stderr.log"))"
fi

echo "=== SANDBOX RESULTS: PASS=$_PASS FAIL=$_FAIL ==="
[ "$_FAIL" -eq 0 ]
