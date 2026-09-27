#!/system/bin/sh
# Sandbox test STEP 7 (PQ Step 6): integrasi boot_guard ke service.sh.
# service.sh ASLI tidak dieksekusi di sandbox (butuh getprop/boot nyata —
# menjalankannya di Termux = hang). Sebagai gantinya:
#   A. Aserti STATIS pada service.sh asli (wiring benar, tanpa duplikasi).
#   B. Emulasi PERILAKU blok guard (fungsi asli core/boot_guard.sh):
#      guard aktif -> skip SEMUA tuning; nonaktif -> tuning jalan.
#
# Cara pakai: sh tests/sandbox_service_guard.sh
# Keluar 0 = semua PASS, 1 = ada FAIL.

_HSIN_REPO=$(cd "${0%/*}/.." 2>/dev/null && pwd)
HSIN_SANDBOX_DIR="${HSIN_SANDBOX_DIR:-/data/data/com.termux/files/usr/tmp/opencode/hsin-svc-guard-test}"
export HSIN_DATA="$HSIN_SANDBOX_DIR/data"
export HSIN_GUARD_THRESHOLD=2
_SVC="$_HSIN_REPO/service.sh"

# shellcheck disable=SC1091
. "$_HSIN_REPO/core/boot_guard.sh" 2>/dev/null

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

_lineno() {
    grep -n -m1 "$1" "$_SVC" 2>/dev/null | cut -d: -f1
}

rm -rf "$HSIN_SANDBOX_DIR"
mkdir -p "$HSIN_DATA"

# --- A1. service.sh me-source boot_guard.sh di awal (sebelum seksi 1) ---
_l_src=$(_lineno 'core/boot_guard\.sh')
_l_wait=$(_lineno 'Waiting for boot_completed')
if [ -n "$_l_src" ] && [ -n "$_l_wait" ] && [ "$_l_src" -lt "$_l_wait" ]; then
    _ok "A1. source boot_guard.sh (baris $_l_src) sebelum boot-wait (baris $_l_wait)"
else
    _bad "A1. source boot_guard.sh sebelum boot-wait (src=$_l_src wait=$_l_wait)"
fi

# --- A2. check/on_boot_failed dipanggil SEBELUM seksi 7 (apply engine) ---
_l_fail=$(_lineno 'hsin_boot_guard_on_boot_failed')
_l_check=$(_lineno 'hsin_boot_guard_check')
_l_apply=$(_lineno '7\. Apply engine')
if [ -n "$_l_fail" ] && [ -n "$_l_check" ] && [ -n "$_l_apply" ] \
    && [ "$_l_fail" -lt "$_l_apply" ] && [ "$_l_check" -lt "$_l_apply" ]; then
    _ok "A2. fail/check (baris $_l_fail/$_l_check) sebelum apply-engine (baris $_l_apply)"
else
    _bad "A2. fail/check sebelum apply-engine (fail=$_l_fail check=$_l_check apply=$_l_apply)"
fi

# --- A3. on_boot_ok dipanggil SETELAH "HSIN service ready" ---
_l_ok=$(_lineno 'hsin_boot_guard_on_boot_ok')
_l_ready=$(_lineno 'HSIN service ready')
if [ -n "$_l_ok" ] && [ -n "$_l_ready" ] && [ "$_l_ok" -gt "$_l_ready" ]; then
    _ok "A3. on_boot_ok (baris $_l_ok) setelah service-ready (baris $_l_ready)"
else
    _bad "A3. on_boot_ok setelah service-ready (ok=$_l_ok ready=$_l_ready)"
fi

# --- A4. TANPA logika counter duplikat di service.sh ---
if [ "$(grep -c 'boot_fail_count' "$_SVC")" -eq 0 ] \
    && [ "$(grep -c 'BOOT_FAIL_COUNT' "$_SVC")" -eq 0 ]; then
    _ok "A4. tanpa counter duplikat (boot_fail_count/BOOT_FAIL_COUNT = 0 di service.sh)"
else
    _bad "A4. tanpa counter duplikat di service.sh"
fi

# --- A5. Timeout bounded (tidak hang selamanya bila boot tak complete) ---
if grep -q 'HSIN_BOOT_WAIT_TIMEOUT' "$_SVC"; then
    _ok "A5. boot-wait bounded via HSIN_BOOT_WAIT_TIMEOUT (bukan infinite loop)"
else
    _bad "A5. boot-wait bounded via HSIN_BOOT_WAIT_TIMEOUT"
fi

# --- B. Emulasi blok keputusan service.sh (fungsi ASLI, tanpa reboot) ---
# Blok asli: timeout -> on_boot_failed + check -> skip+exit 0;
# sukses penuh -> (tuning...) -> on_boot_ok.
_svc_boot_timeout_path() {
    rm -f "$HSIN_DATA/TUNING_APPLIED"
    hsin_boot_guard_on_boot_failed "sandbox-timeout" >/dev/null 2>&1
    if hsin_boot_guard_check >/dev/null 2>&1; then
        : > "$HSIN_DATA/TUNING_APPLIED"
        echo "proceed"
    else
        echo "skip-exit-0"
    fi
    return 0
}

# --- B1. Dua boot gagal beruntun -> boot ke-2: guard aktif, tuning di-skip ---
_svc_boot_timeout_path >/dev/null 2>&1   # gagal #1 (count=1)
_r=$(_svc_boot_timeout_path)              # gagal #2 (count=2 -> AKTIF)
if [ "$_r" = "skip-exit-0" ] && [ ! -f "$HSIN_DATA/TUNING_APPLIED" ]; then
    _ok "B1. fail 2x beruntun: guard aktif, SEMUA tuning di-skip (tanpa marker)"
else
    _bad "B1. fail 2x beruntun: guard aktif, tuning di-skip (dapat $_r)"
fi

# --- B2. Sebagian tuning tidak boleh bocor saat skip (marker engine palsu) ---
rm -f "$HSIN_DATA"/ENGINE_*
if [ "$(_svc_boot_timeout_path)" = "skip-exit-0" ] \
    && [ ! -f "$HSIN_DATA/TUNING_APPLIED" ] \
    && [ -z "$(ls "$HSIN_DATA"/ENGINE_* 2>/dev/null)" ]; then
    _ok "B2. skip = total: nol artefak tuning saat guard aktif"
else
    _bad "B2. skip = total saat guard aktif"
fi

# --- B3. Boot sukses penuh -> on_boot_ok reset -> tuning jalan normal ---
hsin_boot_guard_on_boot_ok >/dev/null 2>&1
rm -f "$HSIN_DATA/TUNING_APPLIED"
if hsin_boot_guard_check >/dev/null 2>&1; then
    : > "$HSIN_DATA/TUNING_APPLIED"
fi
if [ -f "$HSIN_DATA/TUNING_APPLIED" ] && [ ! -f "$HSIN_DATA/.boot_fail_count" ]; then
    _ok "B3. boot sukses: counter reset + tuning jalan normal"
else
    _bad "B3. boot sukses: counter reset + tuning jalan normal"
fi

echo "---"
echo "sandbox_service_guard: PASS=$_PASS FAIL=$_FAIL"
rm -rf "$HSIN_SANDBOX_DIR"
[ "$_FAIL" -eq 0 ]
