#!/system/bin/sh
# Sandbox test Step 6: core/safe_apply.sh + migrasi engine/io/readahead.sh.
# TANPA menyentuh sysfs asli. Skenario: node hilang, read-only, value tak
# didukung (tanpa/dengan alternatif), write sukses, write gagal — tiap
# skenario WAJIB menghasilkan kategori yang benar:
#   APPLIED=0 SKIPPED=2 UNAVAILABLE=3 FALLBACK=4 FAILED=1.
#
# Cara pakai: sh tests/sandbox_safe_apply.sh
# Keluar 0 = semua PASS, 1 = ada FAIL.
# Scratch HANYA di $HSIN_SANDBOX_DIR (default usr/tmp/opencode).

_HSIN_REPO=$(cd "${0%/*}/.." 2>/dev/null && pwd)
HSIN_SANDBOX_DIR="${HSIN_SANDBOX_DIR:-/data/data/com.termux/files/usr/tmp/opencode/hsin-safe-test}"
export HSIN_MODULE_PATH="$_HSIN_REPO"
export HSIN_DATA="$HSIN_SANDBOX_DIR/data"
export HSIN_SYSFS_BLOCK="$HSIN_SANDBOX_DIR/sys/block"

# shellcheck disable=SC1091
. "$_HSIN_REPO/core/sysfs.sh" 2>/dev/null
# shellcheck disable=SC1091
. "$_HSIN_REPO/core/safe_apply.sh" 2>/dev/null

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

rm -rf "$HSIN_SANDBOX_DIR"
mkdir -p "$HSIN_DATA" "$HSIN_SYSFS_BLOCK"

# --- 1. APPLIED: file rw biasa ---
printf '128\n' > "$HSIN_DATA/n_ok"
hsin_safe_apply "$HSIN_DATA/n_ok" "512" "TEST" >/dev/null 2>&1
_rc=$?
if [ "$_rc" -eq 0 ] && [ "$(cat "$HSIN_DATA/n_ok")" = "512" ]; then
    _ok "1. write sukses -> APPLIED (rc=0), read-back cocok"
else
    _bad "1. write sukses -> APPLIED (rc=$_rc, isi=$(cat "$HSIN_DATA/n_ok" 2>/dev/null))"
fi

# --- 2. SKIPPED: node tidak ada ---
hsin_safe_apply "$HSIN_DATA/n_hilang" "512" "TEST" >/dev/null 2>&1
if [ "$?" -eq 2 ]; then
    _ok "2. node hilang -> SKIPPED (rc=2)"
else
    _bad "2. node hilang -> SKIPPED (rc=$?)"
fi

# --- 3. SKIPPED: node read-only ---
printf '128\n' > "$HSIN_DATA/n_ro"
chmod 444 "$HSIN_DATA/n_ro"
hsin_safe_apply "$HSIN_DATA/n_ro" "512" "TEST" >/dev/null 2>&1
if [ "$?" -eq 2 ] && [ "$(cat "$HSIN_DATA/n_ro")" = "128" ]; then
    _ok "3. node read-only -> SKIPPED (rc=2), nilai utuh tak tertimpa"
else
    _bad "3. node read-only -> SKIPPED (rc=$?)"
fi
chmod 644 "$HSIN_DATA/n_ro"

# --- 4. FAILED: node writable tapi write ditolak (direktori sebagai node) ---
mkdir -p "$HSIN_DATA/n_dir"
hsin_safe_apply "$HSIN_DATA/n_dir" "512" "TEST" >/dev/null 2>&1
if [ "$?" -eq 1 ]; then
    _ok "4. write ditolak -> FAILED (rc=1)"
else
    _bad "4. write ditolak -> FAILED (rc=$?)"
fi

# --- 5. UNAVAILABLE: value tak didukung + tanpa alternatif ---
printf 'schedutil\n' > "$HSIN_DATA/n_gov"
hsin_safe_apply_validated "$HSIN_DATA/n_gov" "supergov" "" "TEST" >/dev/null 2>&1
if [ "$?" -eq 3 ] && [ "$(cat "$HSIN_DATA/n_gov")" = "schedutil" ]; then
    _ok "5. value ngawur tanpa alternatif -> UNAVAILABLE (rc=3), node utuh"
else
    _bad "5. value ngawur tanpa alternatif -> UNAVAILABLE (rc=$?)"
fi

# --- 6. FALLBACK: value tak didukung + ada alternatif valid ---
hsin_safe_apply_validated "$HSIN_DATA/n_gov" "supergov" "powersave schedutil" "TEST" >/dev/null 2>&1
if [ "$?" -eq 4 ] && [ "$(cat "$HSIN_DATA/n_gov")" = "powersave" ]; then
    _ok "6. value ngawur + alternatif -> FALLBACK (rc=4), alternatif pertama dipakai"
else
    _bad "6. value ngawur + alternatif -> FALLBACK (rc=$?, isi=$(cat "$HSIN_DATA/n_gov" 2>/dev/null))"
fi

# --- 7. Validated + requested didukung -> APPLIED biasa ---
hsin_safe_apply_validated "$HSIN_DATA/n_gov" "schedutil" "powersave schedutil" "TEST" >/dev/null 2>&1
if [ "$?" -eq 0 ] && [ "$(cat "$HSIN_DATA/n_gov")" = "schedutil" ]; then
    _ok "7. value didukung -> APPLIED (rc=0)"
else
    _bad "7. value didukung -> APPLIED (rc=$?)"
fi

# --- 8. Log sejelas boot_guard: node + value + hasil + alasan ---
_logline=$(hsin_safe_apply "$HSIN_DATA/n_hilang2" "512" "TESTCAT" 2>&1)
case "$_logline" in
    *"TESTCAT"*"$HSIN_DATA/n_hilang2"*"512"*"SKIPPED"*)
        _ok "8. log jelas: kategori + node + value + alasan"
        ;;
    *)
        _bad "8. log jelas (dapat: $_logline)"
        ;;
esac

# --- 9. Counter sesi + summary ---
HSIN_SAFE_APPLIED=0; HSIN_SAFE_SKIPPED=0; HSIN_SAFE_UNAVAIL=0
HSIN_SAFE_FALLBACK=0; HSIN_SAFE_FAILED=0
hsin_safe_apply "$HSIN_DATA/n_ok" "1" "T" >/dev/null 2>&1
hsin_safe_apply "$HSIN_DATA/n_x" "1" "T" >/dev/null 2>&1
_sum=$(hsin_safe_apply_summary "unittest" 2>&1)
if [ "$HSIN_SAFE_APPLIED" -eq 1 ] && [ "$HSIN_SAFE_SKIPPED" -eq 1 ] \
    && echo "$_sum" | grep -q "APPLIED=1 SKIPPED=1"; then
    _ok "9. counter sesi + summary 1 baris benar"
else
    _bad "9. counter sesi + summary (dapat: $_sum)"
fi

# --- 10. Migrasi engine terbukti: readahead di sysfs palsu ---
# Daftar block di-seed langsung (bypass discovery): scan_cache.sh:47
# menimpa HSIN_SYSFS_BLOCK tanpa guard (bug sandbox terpisah, di luar
# scope Step 6 — dilaporkan susulan). Yang dibuktikan di sini = jalur
# tulis migrasi (gateway), bukan discovery.
# Simpan prefix palsu di var sendiri SEBELUM source (rantai source
# scheduler.sh -> scan_cache.sh:47 menimpa HSIN_SYSFS_BLOCK tanpa guard).
_FAKE_BLOCK="$HSIN_SYSFS_BLOCK"
mkdir -p "$_FAKE_BLOCK/sda/queue"
printf '128\n' > "$_FAKE_BLOCK/sda/queue/read_ahead_kb"
# shellcheck disable=SC1091
. "$_HSIN_REPO/engine/io/readahead.sh" 2>/dev/null
# Seed SESUDAH source (scheduler.sh me-reset kedua var saat di-source).
export HSIN_IO_BLOCKS="$_FAKE_BLOCK/sda"
export HSIN_IO_BLOCKS_READY=1
hsin_io_apply_readahead balanced >/dev/null 2>&1
if [ "$(cat "$_FAKE_BLOCK/sda/queue/read_ahead_kb")" = "512" ]; then
    _ok "10. engine readahead via gateway: sda=512 (balanced) di sysfs palsu"
else
    _bad "10. engine readahead via gateway (isi=$(cat "$_FAKE_BLOCK/sda/queue/read_ahead_kb" 2>/dev/null))"
fi

# --- 11. Jalur logger: hasil masuk boot.log ---
# shellcheck disable=SC1091
. "$_HSIN_REPO/core/logger.sh" 2>/dev/null
hsin_safe_apply "$HSIN_DATA/n_ok" "777" "LOGTEST" >/dev/null 2>&1
if grep -q "LOGTEST.*APPLIED" "$HSIN_DATA/logs/boot.log" 2>/dev/null; then
    _ok "11. jalur logger: APPLIED tercatat di boot.log"
else
    _bad "11. jalur logger: APPLIED tercatat di boot.log"
fi

echo "---"
echo "sandbox_safe_apply: PASS=$_PASS FAIL=$_FAIL"
rm -rf "$HSIN_SANDBOX_DIR"
[ "$_FAIL" -eq 0 ]
