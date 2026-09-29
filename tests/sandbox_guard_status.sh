#!/system/bin/sh
# Sandbox test M2: action.sh guard-status — TANPA sentuh device asli.
# Menguji 4 kondisi (aktif, tidak-aktif, hilang, rusak) lewat dispatcher
# action.sh yang sama dengan APK, membuktikan rc=0 + JSON valid + NOL
# penulisan (snapshot HSIN_DATA byte-identik sebelum/sesudah).
#
# Cara pakai: sh tests/sandbox_guard_status.sh
# Keluar 0 = semua PASS, 1 = ada FAIL.
# Scratch HANYA di $HSIN_SANDBOX_DIR (default usr/tmp/opencode) —
# tidak pernah menyentuh /data/adb/hsin asli.

# Lokasi repo = direktori di atas tests/
_HSIN_REPO=$(cd "${0%/*}/.." 2>/dev/null && pwd)
HSIN_SANDBOX_DIR="${HSIN_SANDBOX_DIR:-/data/data/com.termux/files/usr/tmp/opencode/hsin-guard-status-test}"
export HSIN_MODULE_PATH="$_HSIN_REPO"
export HSIN_DATA="$HSIN_SANDBOX_DIR/data"
export HSIN_CONF="$HSIN_DATA/hsin.conf"
export HSIN_GUARD_FILE="$HSIN_DATA/.boot_fail_count"
export HSIN_GUARD_THRESHOLD=2
export HSIN_GUARD_COOLDOWN=86400
export HSIN_SANDBOX=1

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

# Snapshot: daftar md5 semua file di HSIN_DATA (urut). Kosong = "empty".
_snapshot() {
    find "$HSIN_DATA" -type f 2>/dev/null | sort | xargs -r md5sum 2>/dev/null || echo "empty"
    return 0
}

# $1 = nama kondisi. Menjalankan guard-status via action.sh, cek rc=0,
# 6 baris output (5 key=value + 1 JSON), JSON valid, snapshot identik.
_check() {
    _name="$1"
    _before=$(_snapshot)
    _out=$(sh "$_HSIN_REPO/action.sh" guard-status 2>"$HSIN_SANDBOX_DIR/stderr.txt")
    _rc=$?
    _after=$(_snapshot)
    _lines=$(printf '%s\n' "$_out" | wc -l)
    if [ "$_rc" -eq 0 ]; then
        _ok "$_name: rc=0"
    else
        _bad "$_name: rc=0 (dapat rc=$_rc, stderr: $(cat "$HSIN_SANDBOX_DIR/stderr.txt" 2>/dev/null))"
    fi
    if [ "$_lines" -eq 6 ]; then
        _ok "$_name: 6 baris (5 key=value + JSON)"
    else
        _bad "$_name: 6 baris (dapat $_lines)"
    fi
    if printf '%s' "$_out" | tail -n 1 | python3 -c "import sys,json; json.load(sys.stdin)" 2>/dev/null; then
        _ok "$_name: JSON terakhir valid"
    else
        _bad "$_name: JSON terakhir valid"
    fi
    if [ "$_before" = "$_after" ]; then
        _ok "$_name: snapshot identik (nol penulisan)"
    else
        _bad "$_name: snapshot identik (sebelum: [$_before] sesudah: [$_after])"
    fi
    echo "--- output $_name ---"
    printf '%s\n' "$_out"
    echo "--- akhir output ---"
    return 0
}

rm -rf "$HSIN_SANDBOX_DIR"
mkdir -p "$HSIN_DATA"

# 1. Aktif (count >= threshold).
printf '%s:3\n' "$(date +%s)" > "$HSIN_GUARD_FILE"
_check "1-aktif"
printf '%s' "$_out" | grep -q '^active=1$' && _ok "1-aktif: active=1" || _bad "1-aktif: active=1"

# 2. Tidak aktif (count < threshold).
printf '%s:1\n' "$(date +%s)" > "$HSIN_GUARD_FILE"
_check "2-tidak-aktif"
printf '%s' "$_out" | grep -q '^active=0$' && _ok "2-tidak-aktif: active=0" || _bad "2-tidak-aktif: active=0"

# 3. State hilang (file absen).
rm -f "$HSIN_GUARD_FILE"
_check "3-hilang"
printf '%s' "$_out" | grep -q 'tidak ada state' && _ok "3-hilang: reason tidak ada state" || _bad "3-hilang: reason tidak ada state"

# 4. State rusak (isi bukan angka).
printf 'abc\n' > "$HSIN_GUARD_FILE"
_check "4-rusak"
printf '%s' "$_out" | grep -q 'tidak ada state' && _ok "4-rusak: reason tidak ada state" || _bad "4-rusak: reason tidak ada state"

echo "---"
echo "sandbox_guard_status: PASS=$_PASS FAIL=$_FAIL"
rm -rf "$HSIN_SANDBOX_DIR"
[ "$_FAIL" -eq 0 ]
