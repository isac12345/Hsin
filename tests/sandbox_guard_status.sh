#!/system/bin/sh
# Sandbox harness untuk guard-status (M2)
# Tanpa sentuh /sys atau /proc asli; menggunakan sysfs palsu bila diperlukan.

set -e

HSIN_MODULE_PATH="${HSIN_MODULE_PATH:-/data/adb/modules/hsin}"
HSIN_DATA="${HSIN_DATA:-~/Hsin/test_guard_m2}"

# Hapus data lama
rm -rf "$HSIN_DATA"
mkdir -p "$HSIN_DATA"

# Export env untuk file baru
export HSIN_DATA HSIN_MODULE_PATH HSIN_GUARD_FILE="${HSIN_DATA}/.boot_fail_count"
export HSIN_GUARD_THRESHOLD="2"
export HSIN_GUARD_COOLDOWN="86400"

# Salin modul ke path sementara jika belum ada
if [ ! -f "$HSIN_MODULE_PATH/core/guard_status.sh" ]; then
    # Untuk sandbox, salin file yang baru dibuat
    cp "~/work/m2-guard/core/guard_status.sh" /tmp/guard_status_tmp.sh 2>/dev/null || true
fi

# Gunakan file dari worktree
GUARD_STATUS="~/work/m2-guard/core/guard_status.sh"

# Fungsi snapshot: md5 semua file di HSIN_DATA (kecuali harness)
_snapshot() {
    find "$HSIN_DATA" -type f 2>/dev/null | sort | xargs md5sum 2>/dev/null || echo "empty"
    return 0
}

# Kondisi 1: AKTIF (count >= threshold)
echo "=== Kondisi 1: AKTIF ==="
rm -rf "$HSIN_DATA"
mkdir -p "$HSIN_DATA"
export HSIN_GUARD_FILE="$HSIN_DATA/.boot_fail_count"
echo "$(date +%s):3" > "$HSIN_GUARD_FILE"
_before=$(_snapshot)
output=$(bash "$GUARD_STATUS" 2>/dev/null)
_after=$(_snapshot)
echo "Output:"
echo "$output"
echo "RC: $?"
echo "JSON valid?"
echo "$output" | tail -n 1 | python3 -c "import sys, json; json.load(sys.stdin); print('valid')" || echo "invalid"
if [ "$_before" = "$_after" ]; then echo "Snapshot IDENTIK (tidak ada penulisan)"; else echo "SNAPSHOT BERBEDA"; fi

# Kondisi 2: TIDAK AKTIF (count < threshold)
echo "=== Kondisi 2: TIDAK AKTIF ==="
rm -rf "$HSIN_DATA"
mkdir -p "$HSIN_DATA"
export HSIN_GUARD_FILE="$HSIN_DATA/.boot_fail_count"
echo "$(date +%s):1" > "$HSIN_GUARD_FILE"
_before=$(_snapshot)
output=$(bash "$GUARD_STATUS" 2>/dev/null)
_after=$(_snapshot)
echo "Output:"
echo "$output"
echo "JSON valid?"
echo "$output" | tail -n 1 | python3 -c "import sys, json; json.load(sys.stdin); print('valid')" || echo "invalid"
if [ "$_before" = "$_after" ]; then echo "Snapshot IDENTIK"; else echo "SNAPSHOT BERBEDA"; fi

# Kondisi 3: HILANG (file absen)
echo "=== Kondisi 3: HILANG ==="
rm -rf "$HSIN_DATA"
mkdir -p "$HSIN_DATA"
export HSIN_GUARD_FILE="$HSIN_DATA/.boot_fail_count"
_before=$(_snapshot)
output=$(bash "$GUARD_STATUS" 2>/dev/null)
_after=$(_snapshot)
echo "Output:"
echo "$output"
echo "JSON valid?"
echo "$output" | tail -n 1 | python3 -c "import sys, json; json.load(sys.stdin); print('valid')" || echo "invalid"
if [ "$_before" = "$_after" ]; then echo "Snapshot IDENTIK"; else echo "SNAPSHOT BERBEDA"; fi

# Kondisi 4: RUSAK (isi "abc" atau kosong atau ":::")
echo "=== Kondisi 4: RUSAK ==="
rm -rf "$HSIN_DATA"
mkdir -p "$HSIN_DATA"
export HSIN_GUARD_FILE="$HSIN_DATA/.boot_fail_count"
echo "abc" > "$HSIN_GUARD_FILE"
_before=$(_snapshot)
output=$(bash "$GUARD_STATUS" 2>/dev/null)
_after=$(_snapshot)
echo "Output:"
echo "$output"
echo "JSON valid?"
echo "$output" | tail -n 1 | python3 -c "import sys, json; json.load(sys.stdin); print('valid')" || echo "invalid"
if [ "$_before" = "$_after" ]; then echo "Snapshot IDENTIK"; else echo "SNAPSHOT BERBEDA"; fi

echo "=== SEMUA KONDISI SELESAI ==="
