#!/system/bin/sh
# Sandbox test STEP 8: guard prefix di core/scan_cache.sh.
# Membuktikan prefix sandbox yang di-export harness SELAMAT saat
# scan_cache.sh + engine/io/scheduler.sh di-source (dulu tertimpa tanpa
# guard -> discovery baca /sys/block asli = false-positive), dan discovery
# IO murni dari prefix palsu TANPA seed manual HSIN_IO_BLOCKS.
#
# Cara pakai: sh tests/sandbox_scan_prefix.sh
# Keluar 0 = semua PASS, 1 = ada FAIL.

_HSIN_REPO=$(cd "${0%/*}/.." 2>/dev/null && pwd)
HSIN_SANDBOX_DIR="${HSIN_SANDBOX_DIR:-/data/data/com.termux/files/usr/tmp/opencode/hsin-prefix-test}"
export HSIN_DATA="$HSIN_SANDBOX_DIR/data"
_FAKE_SYS="$HSIN_SANDBOX_DIR/sys"
export HSIN_MODULE_PATH="$_HSIN_REPO"
export HSIN_SYSFS_BLOCK="$_FAKE_SYS/block"
export HSIN_SYSFS_CPU="$_FAKE_SYS/cpu"
export HSIN_SYSFS_THERMAL="$_FAKE_SYS/thermal"

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
mkdir -p "$HSIN_DATA" "$_FAKE_SYS/block/sda/queue" "$_FAKE_SYS/block/sdb/queue"
printf '128\n' > "$_FAKE_SYS/block/sda/queue/read_ahead_kb"
printf '128\n' > "$_FAKE_SYS/block/sdb/queue/read_ahead_kb"

# --- 1. Prefix selamat saat scan_cache.sh di-source ---
# shellcheck disable=SC1091
. "$_HSIN_REPO/core/scan_cache.sh" 2>/dev/null
if [ "$HSIN_SYSFS_BLOCK" = "$_FAKE_SYS/block" ] \
    && [ "$HSIN_SYSFS_CPU" = "$_FAKE_SYS/cpu" ] \
    && [ "$HSIN_SYSFS_THERMAL" = "$_FAKE_SYS/thermal" ]; then
    _ok "1. prefix sandbox selamat (block/cpu/thermal) pasca-source scan_cache.sh"
else
    _bad "1. prefix sandbox selamat (block=$HSIN_SYSFS_BLOCK)"
fi

# --- 2. Prefix selamat saat rantai scheduler.sh di-source ulang ---
# shellcheck disable=SC1091
. "$_HSIN_REPO/engine/io/scheduler.sh" 2>/dev/null
if [ "$HSIN_SYSFS_BLOCK" = "$_FAKE_SYS/block" ]; then
    _ok "2. prefix selamat pasca-source scheduler.sh (tanpa timpa ulang)"
else
    _bad "2. prefix selamat pasca-source scheduler.sh (block=$HSIN_SYSFS_BLOCK)"
fi

# --- 3. Discovery IO murni dari prefix palsu, TANPA seed manual ---
unset HSIN_IO_BLOCKS HSIN_IO_BLOCKS_READY
hsin_io_block_devs
case " $HSIN_IO_BLOCKS " in
    *"$_FAKE_SYS/block/sda"*""*"$_FAKE_SYS/block/sdb"*)
        _ok "3. discovery IO dari prefix palsu (sda+sdb, source=$HSIN_IO_BLOCK_SOURCE)"
        ;;
    *)
        _bad "3. discovery IO dari prefix palsu (dapat: $HSIN_IO_BLOCKS)"
        ;;
esac
case " $HSIN_IO_BLOCKS " in
    *" /sys/block/"*)
        _bad "3b. TIDAK bocor ke /sys/block asli"
        ;;
    *)
        _ok "3b. TIDAK bocor ke /sys/block asli"
        ;;
esac

# --- 4. Default tetap sysfs asli bila prefix TIDAK di-export ---
unset HSIN_SYSFS_BLOCK
# shellcheck disable=SC1091
. "$_HSIN_REPO/core/scan_cache.sh" 2>/dev/null
if [ "$HSIN_SYSFS_BLOCK" = "/sys/block" ]; then
    _ok "4. tanpa export: default tetap /sys/block (perilaku device identik)"
else
    _bad "4. tanpa export: default tetap /sys/block (dapat: $HSIN_SYSFS_BLOCK)"
fi

echo "---"
echo "sandbox_scan_prefix: PASS=$_PASS FAIL=$_FAIL"
rm -rf "$HSIN_SANDBOX_DIR"
[ "$_FAIL" -eq 0 ]
