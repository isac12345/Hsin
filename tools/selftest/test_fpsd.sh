#!/bin/sh
# Uji monitor_fps_stat: data fpsd.out milik app lain tidak boleh dipakai: sh test_fpsd.sh
D="$(cd "$(dirname "$0")" && pwd)"
C="${COMMON_DIR:-$D/../../module/common}"
T=$(mktemp -d "${TMPDIR:-/tmp}/fpsd.XXXXXX"); trap 'rm -rf "$T"' EXIT
PASS=0; FAIL=0
chk() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; else FAIL=$((FAIL+1)); printf '  FAIL %s (dapat=[%s] harap=[%s])\n' "$1" "$2" "$3"; fi; }
# ambil hanya fungsi yang diuji dari monitor.sh
sed -n '/^monitor_fps_stat() {/,/^}/p' "$C/monitor.sh" > "$T/fn.sh"
. "$T/fn.sh"
LAT="1000000000 1016666667 1033333334 1050000001 1066666668"
printf 'pkg=com.termux\nlat=%s\n' "$LAT" > "$T/a.out"
printf 'pkg=com.game.a\nlat=%s\n' "$LAT" > "$T/b.out"
chk "paket lain ditolak" "$(monitor_fps_stat "$T/a.out" com.game.a; echo "rc=$?")" "rc=1"
chk "paket sama dipakai" "$(monitor_fps_stat "$T/b.out" com.game.a | cut -d' ' -f1 | grep -c '^[0-9]')" "1"
chk "tanpa paket harapan tetap dibaca" "$(monitor_fps_stat "$T/a.out" | grep -c '^[0-9]')" "1"
cp "$T/b.out" "$T/old.out"; touch -t 202001010000 "$T/old.out"
chk "berkas basi (daemon mati) ditolak" "$(monitor_fps_stat "$T/old.out" com.game.a; echo "rc=$?")" "rc=1"
echo "== hud_sample --fpsd: arahkan daemon ke game (tanpa ini sampel game ditolak)"
mkdir -p "$T/modfake/bin" "$T/st"
for a in arm64 arm32; do
    printf '#!/bin/sh\n[ "$1" = "--selftest" ] && exit 0\nexit 0\n' > "$T/modfake/bin/hsin-fpsd-$a"
    chmod +x "$T/modfake/bin/hsin-fpsd-$a"
done
HSIN_STATE_DIR="$T/st" HSIN_MODDIR="$T/modfake" sh "$C/hud_sample.sh" --fpsd com.game.a >/dev/null 2>&1
chk "fpsd.pkg berisi game" "$(cat "$T/st/fpsd.pkg" 2>/dev/null)" "com.game.a"
printf 'com.termux' > "$T/st/fpsd.pkg"
HSIN_STATE_DIR="$T/st" HSIN_MODDIR="$T/modfake" HSIN_FPSD=0 sh "$C/hud_sample.sh" --fpsd com.game.a >/dev/null 2>&1
chk "daemon mati: gagal (rc 1)" "$?" "1"
chk "daemon mati: pkg tidak ditimpa" "$(cat "$T/st/fpsd.pkg")" "com.termux"
chk "tanpa paket: ditolak" "$(HSIN_STATE_DIR="$T/st" HSIN_MODDIR="$T/modfake" sh "$C/hud_sample.sh" --fpsd >/dev/null 2>&1; echo $?)" "1"

# --- diet fork: pembantu tanpa proses anak ---
sed -n '/^monitor_rd() {/,/^}/p;/^monitor_uptime() {/,/^}/p;/^monitor_epoch_now() {/,/^}/p' "$C/monitor.sh" > "$T/fn2.sh"
. "$T/fn2.sh"
monitor_epoch_now; _a=$MONITOR_NOW; _b=$(date +%s)
chk "monitor_epoch_now dekat date" "$((_b - _a <= 1 && _a - _b <= 1))" "1"
monitor_epoch_now; _a2=$MONITOR_NOW
chk "monitor_epoch_now konsisten" "$((_a2 - _a <= 1))" "1"
sed -n '/^first_int() {/,/^}/p' "$C/hud_sample.sh" > "$T/fn3.sh"; . "$T/fn3.sh"
printf '  1234 kHz\nabc\n' > "$T/fi1"; printf 'x=77 9\n' > "$T/fi2"; printf 'none\n' > "$T/fi3"
# first_int mengisi FI (bukan mencetak): printf di HP adalah proses baru, ~10 ms.
FI=""; first_int "$T/fi1"; chk "first_int awalan spasi" "$FI" "1234"
FI=""; first_int "$T/fi2"; chk "first_int dengan awalan teks" "$FI" "77"
FI=""; first_int "$T/fi3"; chk "first_int tanpa angka gagal" "rc=$?" "rc=1"
# jalur cepat layar: backlight > 0 = ON tanpa dumpsys
sed -n '/^monitor_screen_fast_on() {/,/^}/p' "$C/monitor.sh" > "$T/fn4.sh"; . "$T/fn4.sh"
mkdir -p "$T/bl/x"; printf '120\n' > "$T/bl/x/brightness"
SYSFS_BACKLIGHT_PREFIX="$T/bl" monitor_screen_fast_on; chk "backlight 120 = ON" "$?" "0"
printf '0\n' > "$T/bl/x/brightness"
SYSFS_BACKLIGHT_PREFIX="$T/bl" monitor_screen_fast_on; chk "backlight 0 = tidak yakin (dumpsys)" "$?" "1"
printf '120\n' > "$T/bl/x/brightness"
HSIN_SCREEN_FAST=0 SYSFS_BACKLIGHT_PREFIX="$T/bl" monitor_screen_fast_on; chk "HSIN_SCREEN_FAST=0 mematikan" "$?" "1"
SYSFS_BACKLIGHT_PREFIX="$T/none" monitor_screen_fast_on; chk "tanpa node backlight" "$?" "1"
echo
echo "HASIL: $PASS lolos, $FAIL gagal"
[ "$FAIL" -eq 0 ]
