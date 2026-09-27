#!/system/bin/sh
# Sandbox test STEP 9 (PQ Step 9): core/load_overrides.sh.
# TANPA menyentuh sysfs asli, TANPA mengubah detector.sh.
# Skenario: (1) capability match signature, (2) tidak match -> fallback
# + log wajib, (3) data cacat/hilang sebagian -> aman tanpa crash,
# (4) device.txt hilang total, (5) bukti loader TAK PERNAH tulis sysfs.
#
# Cara pakai: sh tests/sandbox_overrides.sh
# Keluar 0 = semua PASS, 1 = ada FAIL.

_HSIN_REPO=$(cd "${0%/*}/.." 2>/dev/null && pwd)
HSIN_SANDBOX_DIR="${HSIN_SANDBOX_DIR:-/data/data/com.termux/files/usr/tmp/opencode/hsin-ovr-test}"
export HSIN_MODULE_PATH="$_HSIN_REPO"
export HSIN_DATA="$HSIN_SANDBOX_DIR/data"
export HSIN_DEVICE_TXT="$HSIN_DATA/device.txt"
export HSIN_OVERRIDES_FILE="$_HSIN_REPO/capability/capability_overrides.json"
export HSIN_SYSFS_DEVFREQ="$HSIN_SANDBOX_DIR/sys/devfreq"

# shellcheck disable=SC1091
. "$_HSIN_REPO/core/load_overrides.sh" 2>/dev/null

_PASS=0
_FAIL=0

_ok() {
    _PASS=$((_PASS + 1))
    echo "PASS: $1"
}

_bad() {
    _FAIL=$((_FAIL + 1))
    echo "FAIL: $1"
}

_mkdevfreq() {
    # $1 = 1 bila max_freq/governor writable, 0 bila read-only/absen.
    rm -rf "$HSIN_SYSFS_DEVFREQ"
    mkdir -p "$HSIN_SYSFS_DEVFREQ/mali0"
    printf 'performance\n' > "$HSIN_SYSFS_DEVFREQ/mali0/governor"
    printf '850000000\n' > "$HSIN_SYSFS_DEVFREQ/mali0/max_freq"
    if [ "$1" = "0" ]; then
        chmod 444 "$HSIN_SYSFS_DEVFREQ/mali0/governor" "$HSIN_SYSFS_DEVFREQ/mali0/max_freq"
    fi
    return 0
}

rm -rf "$HSIN_SANDBOX_DIR"
mkdir -p "$HSIN_DATA"

# --- S1. Match: 2 policy + performance + devfreq writable + 3 zone ---
mkdir -p "$HSIN_DATA"
printf '%s\n' "CPU_POLICIES=policy0 policy6" "GOVS=performance schedutil powersave" "THERMAL=3" > "$HSIN_DEVICE_TXT"
_mkdevfreq 1
# Catatan: loader di-run dalam subshell command-substitution (agar output
# log tertangkap); variabel export dibaca dalam run yang sama via printf.
_res=$( ( hsin_override_load >/dev/null 2>&1; printf '%s|%s|%s|%s|%s|%s|%s\n' "$HSIN_OV_MATCHED" "$HSIN_OV_SOURCE" "$HSIN_OV_CPU_GOV_PREF" "$HSIN_OV_GPU_PCT_BATTERY" "$HSIN_OV_GPU_PCT_BALANCED" "$HSIN_OV_GPU_PCT_PERFORMANCE" "$HSIN_OV_THERMAL_CLASS" ) )
if [ "$_res" = "1|signature:managed-performance|performance schedutil|60|85|100|managed" ]; then
    _ok "1. match managed-performance + hints logis (60/85/100, managed)"
else
    _bad "1. match managed-performance (dapat: $_res)"
fi
unset _res _out

# --- S2. Tidak match apa pun: capability minim tak dikenal -> default + log ---
printf '%s\n' "CPU_POLICIES=" "GOVS=" "THERMAL=" > "$HSIN_DEVICE_TXT"
rm -rf "$HSIN_SYSFS_DEVFREQ"
_out=$(hsin_override_load 2>&1)
_res=$( ( hsin_override_load >/dev/null 2>&1; printf '%s|%s|%s|%s|%s|%s|%s\n' "$HSIN_OV_MATCHED" "$HSIN_OV_SOURCE" "$HSIN_OV_CPU_GOV_PREF" "$HSIN_OV_GPU_PCT_BATTERY" "$HSIN_OV_GPU_PCT_BALANCED" "$HSIN_OV_GPU_PCT_PERFORMANCE" "$HSIN_OV_THERMAL_CLASS" ) )
if [ "$_res" = "0|default_fallback|schedutil|50|65|80|unmanaged" ]; then
    _ok "2. no-match -> default_fallback paling konservatif (50/65/80)"
else
    _bad "2. no-match -> default_fallback (dapat: $_res)"
fi
case "$_out" in
    *"no signature match, using default fallback"*)
        _ok "2b. log wajib fallback tercetak eksplisit"
        ;;
    *)
        _bad "2b. log wajib fallback (dapat: $_out)"
        ;;
esac
unset _res _out

# --- S3. Data cacat sebagian: GOVS hilang + THERMAL=abc, cpu dikenal ---
printf '%s\n' "CPU_POLICIES=policy0 policy6" "THERMAL=abc" "GARBAGE-BINARY-###" > "$HSIN_DEVICE_TXT"
rm -rf "$HSIN_SYSFS_DEVFREQ"
_res=$( ( hsin_override_load >/dev/null 2>&1; printf '%s|%s|%s\n' "$?" "$HSIN_OV_SOURCE" "$HSIN_OV_THERMAL_CLASS" ) )
if [ "$_res" = "0|signature:light-touch|unmanaged" ]; then
    _ok "3. data cacat: tanpa crash, degradasi ke light-touch konservatif"
else
    _bad "3. data cacat: tanpa crash, degradasi aman (dapat: $_res)"
fi
unset _res

# --- S4. device.txt hilang total -> default aman ---
rm -f "$HSIN_DEVICE_TXT"
_out=$(hsin_override_load 2>&1)
_res=$( ( hsin_override_load >/dev/null 2>&1; printf '%s|%s\n' "$HSIN_OV_MATCHED" "$HSIN_OV_SOURCE" ) )
if [ "$_res" = "0|default_fallback" ]; then
    _ok "4. device.txt hilang -> default_fallback"
else
    _bad "4. device.txt hilang -> default_fallback (dapat: $_res)"
fi
case "$_out" in
    *"no signature match, using default fallback"*)
        _ok "4b. log fallback tetap tercetak saat input hilang"
        ;;
    *)
        _bad "4b. log fallback saat input hilang (dapat: $_out)"
        ;;
esac
unset _res _out

# --- S5. Loader TAK PERNAH tulis sysfs (statis + runtime checksum) ---
if grep -E '>[[:space:]]*"[^"]*\$(HSIN_SYSFS|HSIN_PROC|HSIN_DATA)' "$_HSIN_REPO/core/load_overrides.sh" 2>/dev/null | grep -v '2>/dev/null' | grep -q .; then
    _bad "5. tidak ada redirect tulis ke sysfs/proc/data di loader"
else
    _ok "5. statis: nol redirect tulis ke sysfs/proc/data di loader"
fi
_mkdevfreq 1
printf '%s\n' "CPU_POLICIES=policy0 policy6" "GOVS=performance schedutil" "THERMAL=2" > "$HSIN_DEVICE_TXT"
_before=$(find "$HSIN_SANDBOX_DIR/sys" -type f -exec cksum {} + 2>/dev/null | sort)
hsin_override_load >/dev/null 2>&1
_after=$(find "$HSIN_SANDBOX_DIR/sys" -type f -exec cksum {} + 2>/dev/null | sort)
if [ "$_before" = "$_after" ] && [ -n "$_before" ]; then
    _ok "5b. runtime: checksum sysfs palsu identik sebelum/sesudah load"
else
    _bad "5b. runtime: sysfs palsu berubah saat load"
fi

# --- S6. detector.sh TIDAK tersentuh step ini (kontrak stabil) ---
if [ -z "$(git -C "$_HSIN_REPO" status --short core/detector.sh)" ]; then
    _ok "6. core/detector.sh utuh (git status bersih)"
else
    _bad "6. core/detector.sh utuh"
fi

echo "---"
echo "sandbox_overrides: PASS=$_PASS FAIL=$_FAIL"
rm -rf "$HSIN_SANDBOX_DIR"
[ "$_FAIL" -eq 0 ]
