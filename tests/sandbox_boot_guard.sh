#!/system/bin/sh
# Sandbox test Step 5: core/boot_guard.sh — TANPA reboot device asli.
# Mensimulasikan boot fail berturut-turut, membuktikan guard aktif dan
# modul skip semua tuning saat itu, lalu pulih setelah boot sukses.
#
# Cara pakai: sh tests/sandbox_boot_guard.sh
# Keluar 0 = semua skenario PASS, 1 = ada yang FAIL.
# Scratch HANYA di $HSIN_SANDBOX_DIR (default usr/tmp/opencode) —
# tidak pernah menyentuh /data/adb/hsin asli.

# Lokasi repo = direktori di atas tests/
_HSIN_REPO=$(cd "${0%/*}/.." 2>/dev/null && pwd)
HSIN_SANDBOX_DIR="${HSIN_SANDBOX_DIR:-/usr/tmp/opencode/hsin-guard-test}"
export HSIN_DATA="$HSIN_SANDBOX_DIR/data"
export HSIN_GUARD_THRESHOLD=2
export HSIN_GUARD_COOLDOWN=86400

# shellcheck disable=SC1091
. "$_HSIN_REPO/core/boot_guard.sh"

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

# Simulasi alur service.sh: check guard -> skip/terapkan tuning.
# Membuat marker TUNING_APPLIED bila tuning "jalan".
_sim_boot() {
    _sim_reason="$1"
    rm -f "$HSIN_DATA/TUNING_APPLIED"
    if hsin_boot_guard_check 2>/dev/null; then
        : > "$HSIN_DATA/TUNING_APPLIED"
        echo "applied"
    else
        echo "skipped"
    fi
    return 0
}

rm -rf "$HSIN_SANDBOX_DIR"
mkdir -p "$HSIN_DATA"

# 1. Fresh boot (tanpa state) -> guard tidak aktif, tuning jalan.
if [ "$(_sim_boot fresh)" = "applied" ] && [ -f "$HSIN_DATA/TUNING_APPLIED" ]; then
    _ok "1. fresh boot: tuning applied"
else
    _bad "1. fresh boot: tuning applied"
fi

# 2. Boot gagal 1x (di bawah threshold 2) -> belum aktif, tuning tetap jalan.
hsin_boot_guard_on_boot_failed "sim-fail-1" >/dev/null 2>&1
_rc=$?
if [ "$_rc" -eq 0 ] && [ "$(_sim_boot after-fail-1)" = "applied" ]; then
    _ok "2. fail 1x: guard belum aktif (rc=0), tuning applied"
else
    _bad "2. fail 1x: guard belum aktif (rc=0), tuning applied (rc=$rc)"
fi

# 3. Counter persisten di file (bukan variabel hilang): format timestamp:count.
if grep -qE '^[0-9]+:1$' "$HSIN_DATA/.boot_fail_count" 2>/dev/null; then
    _ok "3. counter persisten di file (format ts:count, count=1)"
else
    _bad "3. counter persisten di file (isi: $(cat "$HSIN_DATA/.boot_fail_count" 2>/dev/null))"
fi

# 4. Boot gagal 2x berturut-turut -> guard AKTIF (rc=1).
hsin_boot_guard_on_boot_failed "sim-fail-2" >/dev/null 2>&1
_rc=$?
if [ "$_rc" -eq 1 ]; then
    _ok "4. fail 2x: guard AKTIF (rc=1)"
else
    _bad "4. fail 2x: guard AKTIF (rc=1, dapat rc=$rc)"
fi

# 5. Saat guard aktif: check -> skip, marker tuning TIDAK dibuat.
if [ "$(_sim_boot guard-active)" = "skipped" ] && [ ! -f "$HSIN_DATA/TUNING_APPLIED" ]; then
    _ok "5. guard aktif: semua tuning di-skip (tanpa marker)"
else
    _bad "5. guard aktif: semua tuning di-skip"
fi

# 6. Log jelas kapan guard aktif dan kenapa (kata AKTIF + alasan).
if hsin_boot_guard_check 2>&1 | grep -q "AKTIF" && hsin_boot_guard_on_boot_failed "sim-fail-3" 2>&1 | grep -q "sim-fail-3"; then
    _ok "6. log jelas: kata AKTIF + alasan kegagalan tercatat"
else
    _bad "6. log jelas: kata AKTIF + alasan kegagalan tercatat"
fi

# 7. Boot sukses + modul normal -> counter reset otomatis.
hsin_boot_guard_on_boot_ok >/dev/null 2>&1
if [ ! -f "$HSIN_DATA/.boot_fail_count" ] && [ "$(_sim_boot recovered)" = "applied" ]; then
    _ok "7. boot sukses: counter reset, tuning jalan lagi"
else
    _bad "7. boot sukses: counter reset, tuning jalan lagi"
fi

# 8. State korup ("abc") -> disanitasi jadi 0, tidak crash, tuning jalan.
printf 'abc\n' > "$HSIN_DATA/.boot_fail_count"
if [ "$(_sim_boot corrupt)" = "applied" ]; then
    _ok "8. state korup: disanitasi, tuning tetap jalan"
else
    _bad "8. state korup: disanitasi, tuning tetap jalan"
fi
rm -f "$HSIN_DATA/.boot_fail_count"

# 9. Threshold bisa di-override via env (mis. 3): 2x gagal belum aktif.
HSIN_GUARD_THRESHOLD=3
export HSIN_GUARD_THRESHOLD
hsin_boot_guard_on_boot_failed "sim-t3-1" >/dev/null 2>&1
hsin_boot_guard_on_boot_failed "sim-t3-2" >/dev/null 2>&1
_rc=$?
if [ "$_rc" -eq 0 ] && [ "$(_sim_boot threshold-3)" = "applied" ]; then
    _ok "9. threshold=3: 2x gagal belum aktif"
else
    _bad "9. threshold=3: 2x gagal belum aktif (rc=$rc)"
fi
hsin_boot_guard_on_boot_failed "sim-t3-3" >/dev/null 2>&1
if [ "$?" -eq 1 ]; then
    _ok "9b. threshold=3: 3x gagal baru aktif"
else
    _bad "9b. threshold=3: 3x gagal baru aktif"
fi

echo "---"
echo "sandbox_boot_guard: PASS=$_PASS FAIL=$_FAIL"
rm -rf "$HSIN_SANDBOX_DIR"
[ "$_FAIL" -eq 0 ]
