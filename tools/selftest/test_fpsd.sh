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

# --- penyapu startup monitor: sisa boost dipulihkan ---
sed -n '/^monitor_startup_sweep() {/,/^}/p' "$C/monitor.sh" > "$T/fn5.sh"; . "$T/fn5.sh"
SW="$T/sweep"; mkdir -p "$SW"; STATE_DIR="$SW"; GB_ACTIVE_FILE="$SW/.gb_active"; : > "$T/sweep.log"
monitor_log() { printf '%s %s\n' "$1" "$2" >> "$T/sweep.log"; }
gb_restore() { echo gb >> "$T/sweep.calls"; }
gh_recover() { echo gh >> "$T/sweep.calls"; }
ad_own_recover() { echo ad >> "$T/sweep.calls"; }
rm -f "$T/sweep.calls"; monitor_startup_sweep
chk "bersih: tidak ada pemulihan" "$([ -f "$T/sweep.calls" ] && echo ada || echo tidak)" "tidak"
printf '1\n' > "$GB_ACTIVE_FILE"; : > "$SW/.gh_dnd_prev"; : > "$SW/.adapt_stopped"
monitor_startup_sweep
chk "gameboost, gamehooks, adapt dipulihkan" "$(tr '\n' ' ' < "$T/sweep.calls")" "gb gh ad "
chk ".gb_active dinolkan" "$(tr -d '[:space:]' < "$GB_ACTIVE_FILE")" "0"
chk "log SWEEP" "$(grep -c '^SWEEP' "$T/sweep.log")" "1"
echo

# --- gb_safety_check / thermal_kernel_cap: satu proses per panggilan, hasil sama ---
sed -n '/^_gb_zone_vals() {/,/^}/p;/^gb_safety_check() {/,/^}/p;/^_gb_zone_has_critical_trip() {/,/^}/p;/^thermal_kernel_cap() {/,/^}/p' "$C/monitor.sh" > "$T/fn6.sh"
. "$T/fn6.sh"
TH="$T/therm"; mkdir -p "$TH"; SYSFS_THERMAL_PREFIX="$TH"; STATE_DIR="$T/thstate"; mkdir -p "$STATE_DIR"
mkz() { mkdir -p "$TH/thermal_zone$1"; printf '%s\n' "$2" > "$TH/thermal_zone$1/type"; printf '%s\n' "$3" > "$TH/thermal_zone$1/temp"; }
mkz 0 soc-thermal 45000; mkz 1 cpu-thermal 61000; mkz 2 gpu-thermal 52000; mkz 3 battery 38
chk "max termal dari semua zona" "$(gb_safety_check)" "61000"
mkz 4 fake 120000                       # palsu: >95000 dan >median+25000, tanpa trip critical
chk "zona palsu dibuang" "$(gb_safety_check)" "61000"
printf 'critical\n' > "$TH/thermal_zone4/trip_point_0_type"
chk "zona dengan trip critical tetap sah" "$(gb_safety_check)" "120000"
rm -rf "$TH"/thermal_zone*; 
chk "tanpa zona: sentinel 75000" "$(gb_safety_check)" "75000"
mkz 0 soc-thermal 45000
printf '90000\n' > "$TH/thermal_zone0/trip_point_1_temp"; mkz 1 battery 40000; printf '50000\n' > "$TH/thermal_zone1/trip_point_1_temp"
unset TK_CAP_DONE TK_CAP
chk "kernel cap = 95% trip terendah soc/cpu/gpu" "$(thermal_kernel_cap)" "85500"
thermal_kernel_cap >/dev/null
chk "cache terisi di shell utama" "$TK_CAP_DONE:$TK_CAP" "1:85500"
printf '10000\n' > "$TH/thermal_zone0/trip_point_1_temp"
chk "hasil cache tidak berubah (trip statis)" "$(thermal_kernel_cap)" "85500"

# --- monitor_fps_stat_v: satu hitungan per detik dibagi pemanggil ---
sed -n '/^monitor_fps_stat_v() {/,/^}/p' "$C/monitor.sh" > "$T/fn7.sh"; . "$T/fn7.sh"
FSN=0; printf 'x\n' > "$T/fo.out"
monitor_epoch_now() { MONITOR_NOW=5000; }
monitor_fps_stat() { echo c >> "$T/fs.calls"; printf '30 60 90'; }
rm -f "$T/fs.calls"
monitor_fps_stat_v "$T/fo.out" com.g; r1=$?; v1=$MONITOR_FS
monitor_fps_stat_v "$T/fo.out" com.g; r2=$?; v2=$MONITOR_FS
chk "hasil sama untuk dua pemanggil" "$v1|$v2|$r1$r2" "30 60 90|30 60 90|00"
chk "dihitung sekali dalam detik yang sama" "$(wc -l < "$T/fs.calls" | tr -d ' ')" "1"
monitor_epoch_now() { MONITOR_NOW=5001; }
monitor_fps_stat_v "$T/fo.out" com.g
chk "detik berikutnya dihitung ulang" "$(wc -l < "$T/fs.calls" | tr -d ' ')" "2"
monitor_fps_stat_v "$T/fo.out" com.other
chk "paket lain dihitung ulang" "$(wc -l < "$T/fs.calls" | tr -d ' ')" "3"
echo "HASIL: $PASS lolos, $FAIL gagal"
[ "$FAIL" -eq 0 ]
