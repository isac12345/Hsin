#!/system/bin/sh
# core/engine_guard.sh — PQ Step 12 graceful degradation contract.
# Kontrak eksplisit: engine gagal != module gagal.
# - Tiap engine dihitung applied/failed-nya dari counter safe_apply
#   (Step 7): APPLIED + FALLBACK = applied; FAILED = failed;
#   SKIPPED + UNAVAILABLE = skipped (alasan per node sudah di-log
#   safe_apply: node missing / read-only / mismatch).
# - Return 0 bila applied_count > 0 (partial success OK, termasuk
#   partial DI DALAM satu engine); return 1 hanya bila nol applied.
# - Func dipanggil LANGSUNG (bukan $( )), agar counter global terbaca.
# - Kategori safe_apply yang sudah ada dipakai apa adanya — TIDAK ada
#   sistem kategori baru.

[ -z "$HSIN_MODULE_PATH" ] && HSIN_MODULE_PATH="/data/adb/modules/hsin"
# shellcheck disable=SC1091
. "$HSIN_MODULE_PATH/core/sysfs.sh" 2>/dev/null || true
# shellcheck disable=SC1091
. "$HSIN_MODULE_PATH/core/safe_apply.sh" 2>/dev/null || true

# Ringkasan semua engine: "nama:applied=X,failed=Y,skipped=Z,rc=R;..."
HSIN_ENGINE_SUMMARY=""

_eg_log() {
    if command -v hsin_log_info >/dev/null 2>&1; then
        hsin_log_info "engine_guard" "$2: $3"
    else
        echo "[engine_guard] $2: $3" >&2
    fi
    return 0
}

# hsin_engine_run <name> <func> [args...]
# Snapshot counter -> panggil func langsung -> delta per-engine ->
# log counts -> return 0 bila applied>0, else 1. TIDAK PERNAH abort.
hsin_engine_run() {
    _eg_name="$1"
    _eg_func="$2"
    shift 2 || true
    _eg_a0="${HSIN_SAFE_APPLIED:-0}"
    _eg_f0="${HSIN_SAFE_FALLBACK:-0}"
    _eg_e0="${HSIN_SAFE_FAILED:-0}"
    _eg_s0="${HSIN_SAFE_SKIPPED:-0}"
    _eg_u0="${HSIN_SAFE_UNAVAIL:-0}"
    if ! command -v "$_eg_func" >/dev/null 2>&1; then
        _eg_log "SKIP" "$_eg_name" "applied=0 failed=0 skipped=0 rc=1 (reason: apply function missing — engine not loaded)"
        HSIN_ENGINE_SUMMARY="${HSIN_ENGINE_SUMMARY}${_eg_name}:applied=0,failed=0,skipped=0,rc=1;"
        return 1
    fi
    "$_eg_func" "$@" >/dev/null 2>&1
    _eg_frc=$?
    _eg_applied=$(( ${HSIN_SAFE_APPLIED:-0} - _eg_a0 + ${HSIN_SAFE_FALLBACK:-0} - _eg_f0 ))
    _eg_failed=$(( ${HSIN_SAFE_FAILED:-0} - _eg_e0 ))
    _eg_skipped=$(( ${HSIN_SAFE_SKIPPED:-0} - _eg_s0 + ${HSIN_SAFE_UNAVAIL:-0} - _eg_u0 ))
    [ "$_eg_applied" -lt 0 ] 2>/dev/null && _eg_applied=0
    [ "$_eg_failed" -lt 0 ] 2>/dev/null && _eg_failed=0
    [ "$_eg_skipped" -lt 0 ] 2>/dev/null && _eg_skipped=0
    if [ "$_eg_applied" -gt 0 ] 2>/dev/null; then
        _eg_rc=0
    else
        _eg_rc=1
    fi
    _eg_log "COUNT" "$_eg_name" "applied=$_eg_applied failed=$_eg_failed skipped=$_eg_skipped func_rc=$_eg_frc rc=$_eg_rc"
    HSIN_ENGINE_SUMMARY="${HSIN_ENGINE_SUMMARY}${_eg_name}:applied=$_eg_applied,failed=$_eg_failed,skipped=$_eg_skipped,rc=$_eg_rc;"
    return "$_eg_rc"
}

# Satu blok ringkasan status SEMUA engine ke log (dipanggil service.sh
# di status report akhir — bukan cuma engine terakhir).
hsin_engine_summary() {
    if [ -z "$HSIN_ENGINE_SUMMARY" ]; then
        _eg_log "SUMMARY" "engines" "no engine ran"
        return 0
    fi
    _eg_rest="$HSIN_ENGINE_SUMMARY"
    while [ -n "$_eg_rest" ]; do
        _eg_one="${_eg_rest%%;*}"
        _eg_rest="${_eg_rest#*;}"
        [ -z "$_eg_one" ] && continue
        [ "$_eg_one" = "$_eg_rest" ] && _eg_rest=""
        _eg_log "SUMMARY" "engine" "$_eg_one"
    done
    return 0
}

return 0 2>/dev/null || true
