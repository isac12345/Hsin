#!/system/bin/sh
# Sandbox test PQ Step 12: graceful degradation — TANPA preset counter.
# Kegagalan disimulasikan lewat KONDISI NYATA (node hilang + file
# read-only chmod 444), dibaca/ditulis lewat jalur asli hsin_safe_apply
# (counter bertambah karena write_verify beneran, bukan karena test
# mengarang angka). Pola sama seperti sandbox thermal Step 10.
#
# Cara pakai: sh tests/sandbox_degrade.sh
# Keluar 0 = semua skenario PASS, 1 = ada yang FAIL.
# Scratch HANYA di $HSIN_SANDBOX_DIR — tidak menyentuh /data/adb/hsin.

_HSIN_REPO=$(cd "${0%/*}/.." 2>/dev/null && pwd)
HSIN_SANDBOX_DIR="${HSIN_SANDBOX_DIR:-/usr/tmp/opencode/hsin-degrade-test}"
export HSIN_MODULE_PATH="$_HSIN_REPO"
export HSIN_DATA="$HSIN_SANDBOX_DIR/data"
_SB_NODES="$HSIN_SANDBOX_DIR/nodes"

# shellcheck disable=SC1091
. "$_HSIN_REPO/core/logger.sh" 2>/dev/null || true
# shellcheck disable=SC1091
. "$_HSIN_REPO/core/engine_guard.sh" 2>/dev/null || true

_PASS=0
_FAIL=0
_ok() { _PASS=$((_PASS + 1)); echo "PASS: $1"; }
_bad() { _FAIL=$((_FAIL + 1)); echo "FAIL: $1"; }

# Pohon node nyata: 2 writable + 1 read-only + 1 hilang.
_mk_nodes() {
    rm -rf "$HSIN_SANDBOX_DIR"
    mkdir -p "$_SB_NODES" "$HSIN_DATA/logs"
    echo "0" > "$_SB_NODES/ok1"
    echo "0" > "$_SB_NODES/ok2"
    echo "0" > "$_SB_NODES/ro1"
    chmod 444 "$_SB_NODES/ro1"
    # $_SB_NODES/miss1 sengaja TIDAK dibuat (node hilang)
}

# Stub engine: semua tulis via hsin_safe_apply asli (kategori
# APPLIED/SKIPPED/FALLBACK/FAILED yang sudah ada — tanpa kategori baru).
_stub_all_ok() {
    hsin_safe_apply "$_SB_NODES/ok1" "111" "DEGRADE" >/dev/null 2>&1
    hsin_safe_apply "$_SB_NODES/ok2" "222" "DEGRADE" >/dev/null 2>&1
    return 0
}
_stub_all_fail() {
    hsin_safe_apply "$_SB_NODES/miss1" "111" "DEGRADE" >/dev/null 2>&1
    hsin_safe_apply "$_SB_NODES/ro1" "111" "DEGRADE" >/dev/null 2>&1
    return 0
}
_stub_partial() {
    hsin_safe_apply "$_SB_NODES/ok1" "333" "DEGRADE" >/dev/null 2>&1
    hsin_safe_apply "$_SB_NODES/miss1" "333" "DEGRADE" >/dev/null 2>&1
    hsin_safe_apply "$_SB_NODES/ro1" "333" "DEGRADE" >/dev/null 2>&1
    return 0
}
_stub_fallback() {
    hsin_safe_apply_validated "$_SB_NODES/ok2" "999" "444" "DEGRADE" >/dev/null 2>&1
    return 0
}

# Emulasi blok service.sh section 7 untuk satu engine (pola asli:
# gagal -> warning + lanjut, bukan abort).
_svc_one() {
    _svc_name="$1"; _svc_func="$2"
    if hsin_engine_run "$_svc_name" "$_svc_func"; then
        hsin_log_ok "main" "$_svc_name engine applied"
    else
        _apply_failed=$((_apply_failed + 1))
        hsin_log_warn "main" "$_svc_name engine failed — lanjut engine berikut (module tidak abort)"
    fi
}

# 0. Self-check: test ini TIDAK PERNAH preset counter langsung.
if grep -qE 'HSIN_SAFE_(APPLIED|SKIPPED|UNAVAIL|FALLBACK|FAILED)=' "$0"; then
    _bad "0. test mem-preset counter (dilarang)"
else
    _ok "0. test tidak mem-preset counter (kondisi nyata saja)"
fi

# 1. Satu engine total-gagal -> rc=1 + warning, applied=0.
_mk_nodes
HSIN_ENGINE_SUMMARY=""
hsin_engine_run "GPU" _stub_all_fail >/dev/null 2>&1
if [ "$?" -eq 1 ] && [ "$(cat "$_SB_NODES/ok1")" = "0" ] \
    && grep -q "GPU: applied=0" "$HSIN_DATA/logs/boot.log" 2>/dev/null; then
    _ok "1. total-gagal: rc=1, node utuh, counts di log"
else
    _bad "1. total-gagal (summary=$HSIN_ENGINE_SUMMARY)"
fi

# 2. Gagal satu -> engine berikut tetap jalan (module tidak abort).
_mk_nodes
HSIN_ENGINE_SUMMARY=""
_apply_failed=0
_svc_one "GPU" _stub_all_fail
_svc_one "CPU" _stub_all_ok
_svc_one "IO" _stub_partial
if [ "$(cat "$_SB_NODES/ok1")" = "333" ] && [ "$(cat "$_SB_NODES/ok2")" = "222" ] \
    && [ "$_apply_failed" -eq 1 ] \
    && grep -q "GPU.*rc=1" "$HSIN_DATA/logs/boot.log" \
    && grep -q "lanjut engine berikut" "$HSIN_DATA/logs/boot.log"; then
    _ok "2. 1 gagal: CPU+IO tetap APPLIED, warning + lanjut tercatat"
else
    _bad "2. 1 gagal (ok1=$(cat "$_SB_NODES/ok1") ok2=$(cat "$_SB_NODES/ok2") fail=$_apply_failed summary=$HSIN_ENGINE_SUMMARY)"
fi

# 3. SEMUA engine gagal -> service tetap selesai (tidak abort di tengah).
_mk_nodes
HSIN_ENGINE_SUMMARY=""
_apply_failed=0
_svc_one "CPU" _stub_all_fail
_svc_one "GPU" _stub_all_fail
_svc_one "IO" _stub_all_fail
echo "SERVICE_END reached"
if [ "$_apply_failed" -eq 3 ] \
    && [ "$(hsin_engine_summary 2>/dev/null; grep -c "engine.*rc=1" "$HSIN_DATA/logs/boot.log")" -ge 3 ]; then
    _ok "3. semua gagal: sampai SERVICE_END, 3 warning + summary rc=1 semua"
else
    _bad "3. semua gagal (fail=$_apply_failed summary=$HSIN_ENGINE_SUMMARY)"
fi

# 4. Partial DALAM satu engine (applied>0 + skip) -> rc=0, bukan FAILED.
_mk_nodes
HSIN_ENGINE_SUMMARY=""
hsin_engine_run "IO" _stub_partial >/dev/null 2>&1
if [ "$?" -eq 0 ] && [ "$(cat "$_SB_NODES/ok1")" = "333" ] \
    && grep -q "IO: applied=1" "$HSIN_DATA/logs/boot.log"; then
    _ok "4. partial 1 engine (1 applied + 2 skip): rc=0, node writable berubah"
else
    _bad "4. partial 1 engine (summary=$HSIN_ENGINE_SUMMARY ok1=$(cat "$_SB_NODES/ok1"))"
fi

# 5. FALLBACK dihitung applied -> rc=0 (kategori lama, tanpa kategori baru).
_mk_nodes
HSIN_ENGINE_SUMMARY=""
hsin_engine_run "MEM" _stub_fallback >/dev/null 2>&1
if [ "$?" -eq 0 ] && [ "$(cat "$_SB_NODES/ok2")" = "444" ]; then
    _ok "5. FALLBACK (req 999 -> alt 444): applied, rc=0"
else
    _bad "5. FALLBACK (summary=$HSIN_ENGINE_SUMMARY ok2=$(cat "$_SB_NODES/ok2"))"
fi

# 6. Tiap skip mencantumkan ALASAN (bukan skip diam-diam).
_mk_nodes
HSIN_ENGINE_SUMMARY=""
hsin_engine_run "GPU" _stub_all_fail >/dev/null 2>&1
if grep -q "node missing" "$HSIN_DATA/logs/boot.log" \
    && grep -q "read-only" "$HSIN_DATA/logs/boot.log"; then
    _ok "6. skip beralasan (node missing + read-only di log)"
else
    _bad "6. skip beralasan (log: $(cat "$HSIN_DATA/logs/boot.log" 2>/dev/null | head -n 5))"
fi

# 7. Wiring statis service.sh + runtime list (pola service_guard).
_w7=0
[ "$(grep -c 'hsin_engine_run "' "$_HSIN_REPO/service.sh")" -eq 6 ] || _w7=1
grep -q 'hsin_engine_summary' "$_HSIN_REPO/service.sh" || _w7=1
grep -q '\. "\$MODPATH/core/engine_guard.sh"' "$_HSIN_REPO/service.sh" || _w7=1
grep -q 'core/engine_guard.sh' "$_HSIN_REPO/build_release.sh" || _w7=1
grep -q 'lanjut engine berikut (module tidak abort)' "$_HSIN_REPO/service.sh" || _w7=1
if [ "$_w7" -eq 0 ]; then
    _ok "7. wiring: 6 engine via wrapper + summary + runtime list"
else
    _bad "7. wiring service.sh/build_release.sh"
fi

echo "=== SANDBOX RESULTS: PASS=$_PASS FAIL=$_FAIL ==="
[ "$_FAIL" -eq 0 ]
