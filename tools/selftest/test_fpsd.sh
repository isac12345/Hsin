#!/bin/sh
# Uji monitor_fps_stat: data fpsd.out milik app lain tidak boleh dipakai: sh test_fpsd.sh
D="$(cd "$(dirname "$0")" && pwd)"
C="${COMMON_DIR:-$D/../../module/common}"
T=$(mktemp -d "${TMPDIR:-/tmp}/fpsd.XXXXXX"); trap 'rm -rf "$T"' EXIT
PASS=0; FAIL=0
chk() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; else FAIL=$((FAIL+1)); printf '  FAIL %s (dapat=[%s] harap=[%s])\n' "$1" "$2" "$3"; fi; }
# ambil hanya fungsi yang diuji dari monitor.sh
sed -n '/^monitor_fps_stat_core() {/,/^}/p;/^monitor_fps_stat() {/,/^}/p' "$C/monitor.sh" > "$T/fn.sh"
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
monitor_fps_stat_core() { echo c >> "$T/fs.calls"; MONITOR_FS="30 60 90"; return 0; }
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

# --- check_fpsd_alive: daemon mati dihidupkan lagi, terbatas ---
sed -n '/^fpsd_pid_ok() {/,/^}/p;/^check_fpsd_alive() {/,/^}/p' "$C/monitor.sh" > "$T/fn8.sh"; . "$T/fn8.sh"
FA="$T/fa"; mkdir -p "$FA/common" "$FA/bin"; : > "$FA/bin/hsin-fpsd-arm64"; chmod +x "$FA/bin/hsin-fpsd-arm64"
printf '#!/bin/sh\necho "$*" >> "%s/fa.calls"\nexit 0\n' "$T" > "$FA/common/hud_sample.sh"
MODDIR="$FA/common"; STATE_DIR="$FA/state"; mkdir -p "$STATE_DIR"; rm -f "$T/fa.calls"; : > "$T/fa.log"
monitor_log() { printf '%s %s\n' "$1" "$2" >> "$T/fa.log"; }
echo 999999 > "$STATE_DIR/fpsd.pid"             # pid tidak ada
check_fpsd_alive com.g                             # tick 1: dicek, dihidupkan
for i in 2 3 4 5 6 7 8 9 10; do check_fpsd_alive com.g; done
chk "tidak dicek di tick 2-10" "$(wc -l < "$T/fa.calls" | tr -d ' ')" "1"
for n in 1 2 3 4 5 6 7 8; do for i in 1 2 3 4 5 6 7 8 9 10; do check_fpsd_alive com.g; done; done
chk "paling banyak 5 kali per game" "$(wc -l < "$T/fa.calls" | tr -d ' ')" "5"
# PID dipakai ulang proses lain (bukan hsin-fpsd): harus dianggap mati dan dihidupkan lagi
sleep 30 & echo $! > "$STATE_DIR/fpsd.pid"
rm -f "$T/fa.calls"; FPSD_REV_PKG=""; FPSD_CHK_N=0
check_fpsd_alive com.h
chk "pid dipakai proses lain: dihidupkan ulang" "$([ -f "$T/fa.calls" ] && echo ya || echo tidak)" "ya"
kill %1 2>/dev/null
# proses benar-benar hsin-fpsd: tidak dihidupkan ulang
cp "$(command -v sleep)" "$T/hsin-fpsd"; "$T/hsin-fpsd" 30 & echo $! > "$STATE_DIR/fpsd.pid"
rm -f "$T/fa.calls"; FPSD_REV_PKG=""; FPSD_CHK_N=0
check_fpsd_alive com.i
chk "pid hsin-fpsd hidup: tidak dihidupkan ulang" "$([ -f "$T/fa.calls" ] && echo ya || echo tidak)" "tidak"
kill %2 2>/dev/null

# --- kill-switch pause: monitor_paused melepas sekali lalu menunggu ---
sed -n '/^monitor_paused() {/,/^}/p' "$C/monitor.sh" > "$T/fn9.sh"; . "$T/fn9.sh"
PZ="$T/pz"; mkdir -p "$PZ"; STATE_DIR="$PZ"; GB_ACTIVE_FILE="$PZ/.gb_active"; rm -f "$T/pz.calls"
monitor_log() { echo "log:$1" >> "$T/pz.calls"; }
gb_restore() { echo gb >> "$T/pz.calls"; }; gh_recover() { echo gh >> "$T/pz.calls"; }; ad_own_recover() { echo ad >> "$T/pz.calls"; }
ad_end() { echo end >> "$T/pz.calls"; }; AD_OPEN=1
monitor_paused; chk "tanpa .paused: jalan normal" "$?" "1"
: > "$PZ/.paused"; : > "$PZ/.game_t0"
monitor_paused; chk "dijeda" "$?" "0"
monitor_paused; monitor_paused
chk "pelepasan hanya sekali" "$(tr '\n' ' ' < "$T/pz.calls")" "end gb gh ad log:PAUSE "
chk ".game_t0 dibuang" "$([ -f "$PZ/.game_t0" ] && echo ada || echo tidak)" "tidak"
rm -f "$PZ/.paused"; monitor_paused; chk "dilanjutkan" "$?" "1"
: > "$PZ/.paused"; rm -f "$T/pz.calls"; monitor_paused
chk "jeda kedua melepas lagi" "$(grep -c log:PAUSE "$T/pz.calls")" "1"

# --- event stream: parse paket tanpa fork, hitungan, verifikasi stream sepi ---
sed -n '/^event_line_package() {/,/^}/p;/^event_count_inc() {/,/^}/p;/^event_count_get() {/,/^}/p;/^event_verify_quiet() {/,/^}/p' "$C/monitor.sh" > "$T/fn10.sh"; . "$T/fn10.sh"
event_line_package "wm_set_resumed_activity: [0,com.tencent.ig/com.epicgames.ue4.GameActivity,resume]"; chk "paket dari event" "$EVENT_PKG" "com.tencent.ig"
event_line_package "[0,com.a.b/.Main,x]"; chk "paket dengan .Main" "$EVENT_PKG" "com.a.b"
event_line_package "I/wm_set_resumed_activity: [0,com.tencent.ig/com.epicgames.ue4.GameActivity,resume]"; chk "format -v tag" "$EVENT_PKG" "com.tencent.ig"
event_line_package "I/wm_task_moved: [1,2,3]"; chk "baris bertag tanpa paket: kosong" "$EVENT_PKG" ""
event_line_package "[0,12345,x]"; chk "tanpa slash: kosong" "$EVENT_PKG" ""
event_line_package "Focus entering abc u0 com.x.y/com.x.y.Main"; chk "Focus entering" "$EVENT_PKG" "com.x.y"
EV="$T/ev"; mkdir -p "$EV"; EVENT_COUNT_FILE="$EV/count"; EVENT_N=0
event_count_inc; event_count_inc; event_count_inc; event_count_get; chk "hitungan event" "$EVENT_PARSED" "3"
rm -f "$EVENT_COUNT_FILE"; event_count_get; chk "tanpa berkas: 0" "$EVENT_PARSED" "0"
HUD_FOREGROUND_FILE="$EV/fg"; rm -f "$EV/calls"
get_foreground_package() { echo "$EV_TRUTH"; }
is_transient_package() { return 1; }
handle_foreground_event() { echo "$1" >> "$EV/calls"; echo "$1" > "$HUD_FOREGROUND_FILE"; }
EVENT_BOOTSTRAPPED=0; EV_TRUTH=com.g1; echo com.stale > "$HUD_FOREGROUND_FILE"
event_verify_quiet; chk "verifikasi pertama: bootstrap, sehat" "$?" "0"
event_verify_quiet; chk "sama dengan dumpsys: sehat" "$?" "0"
EV_TRUTH=com.g2; event_verify_quiet; chk "app berpindah tanpa event: tuli" "$?" "1"
chk "keadaan diperbaiki dari dumpsys" "$(tr '\n' ' ' < "$EV/calls")" "com.g1 com.g2 "
get_foreground_package() { return 1; }; event_verify_quiet; chk "dumpsys gagal: tak dipastikan, sehat" "$?" "0"

# --- profil per fase: mati tanpa .profile, mencatat bila .profile ada ---
sed -n '/^prof_lap() {/,/^}/p' "$C/monitor.sh" > "$T/fn11.sh"; . "$T/fn11.sh"
PF="$T/pf"; mkdir -p "$PF"; STATE_DIR="$PF"; PROF_FLUSH_N=3; PROF_N=0; PROF_ON=0; PROF_LABELS=""; PROF_LAST=""
monitor_log() { echo "$1 $2" >> "$PF/log"; }
for i in 1 2 3 4; do prof_lap head; prof_lap gb; prof_lap fps; prof_lap adapt; prof_lap snap; done
chk "tanpa .profile: tidak mencatat" "$([ -f "$PF/log" ] && echo ada || echo tidak)" "tidak"
: > "$PF/.profile"
for i in 1 2 3 4 5; do prof_lap head; for j in 1 2 3; do ls / >/dev/null; done; prof_lap gb; prof_lap fps; prof_lap adapt; prof_lap snap; done
chk "dengan .profile: baris PROFIL" "$(grep -c "^PROFIL 3 tick, ticks(10ms):" "$PF/log")" "1"
rm -f "$PF/.profile"; prof_lap head; chk "dimatikan lagi" "$PROF_ON" "0"

# --- cache mitigasi gamehooks: sekali pindai per 300 dtk ---
sed -n '/^gh_mit_hit() {/,/^_gh_mit_scan() {/p' "$C/gamehooks.sh" | sed '$d' > "$T/fn12.sh"; . "$T/fn12.sh"
GH_MIT="$T/mit.conf"; : > "$GH_MIT"; MONITOR_NOW=1000; monitor_epoch_now() { :; }
SCANS=0; SCAN_RC=0; _gh_mit_scan() { SCANS=$((SCANS + 1)); return $SCAN_RC; }
gh_mit_hit memclean; r1=$?; gh_mit_hit memclean; r2=$?
chk "mitigasi: hasil sama, dipindai sekali" "$r1$r2$SCANS" "001"
MONITOR_NOW=1301; gh_mit_hit memclean; chk "mitigasi: pindai ulang setelah 300 dtk" "$SCANS" "2"
SCAN_RC=1; MONITOR_NOW=1700; gh_mit_hit prio; r3=$?; gh_mit_hit prio; r4=$?
chk "mitigasi: tidak kena (1), dicache per fitur" "$r3$r4$SCANS" "113"

# --- fps_drop_cause harus ada dan jalan tanpa fork ---
sed -n '/^fps_drop_cause() {/,/^}/p' "$C/monitor.sh" > "$T/fn13.sh"; chk "fps_drop_cause terdefinisi" "$([ -s "$T/fn13.sh" ] && echo ada || echo hilang)" "ada"
. "$T/fn13.sh"; FD="$T/fd"; mkdir -p "$FD/cpufreq/policy0" "$FD/gpu"
echo 1900000 > "$FD/cpufreq/policy0/scaling_cur_freq"; echo 2000000 > "$FD/cpufreq/policy0/cpuinfo_max_freq"
echo 300000 > "$FD/gpu/cur_freq"; echo 800000 > "$FD/gpu/max_freq"
echo "some avg10=0.00 avg60=0.00 avg300=0.00 total=0" > "$FD/psi_io"; PSI_IO_FILE="$FD/psi_io"
CPU_POLICIES=policy0; SYSFS_CPU_PREFIX="$FD"; GPU_DEVFREQ_PATH="$FD/gpu"
chk "penyebab: cpu saja" "$(fps_drop_cause)" "cpu"
echo 790000 > "$FD/gpu/cur_freq"; chk "penyebab: cpu+gpu" "$(fps_drop_cause)" "cpu+gpu"
echo 100000 > "$FD/cpufreq/policy0/scaling_cur_freq"; chk "penyebab: gpu saja" "$(fps_drop_cause)" "gpu"
echo 100000 > "$FD/gpu/cur_freq"; chk "penyebab: tak jelas" "$(fps_drop_cause)" "tak jelas"

# --- nice dari /proc/<tid>/stat tanpa fork; varian _v memfx ---
sed -n '/^_gh_nice_v() {/,/^}/p;/^_gh_nice_of() {/p' "$C/gamehooks.sh" > "$T/fn14.sh"; . "$T/fn14.sh"
echo "4242 (Render) Thread) S 1 2 3 0 -1 4194560 100 0 0 0 5 6 0 0 20 -8 90 0 12345" > "$T/stat1"
_gh_nice_v "$T/stat1"; chk "nice dari stat (comm berkurung)" "$_GHN" "-8"
echo "7 (x) S 1 2 3 0 -1 4 5 6 7 8 9 10 11 12 20 0 1" > "$T/stat2"; _gh_nice_v "$T/stat2"; chk "nice 0" "$_GHN" "0"
echo "garbage" > "$T/stat3"; _gh_nice_v "$T/stat3"; chk "stat rusak: gagal" "$?" "1"
sed -n '/^_mf_num() {/p;/^_mf_x100_v() {/,/^}/p;/^_mf_x100() {/p;/^mf_psi_x100_v() {/,/^}/p;/^mf_psi_x100() {/p' "$C/memfx.sh" > "$T/fn15.sh"; . "$T/fn15.sh"
MF_PSI="$T/psi"; printf 'some avg10=12.34 avg60=1.50 avg300=0.00 total=1\nfull avg10=0.00 avg60=0.00 avg300=0.00 total=0\n' > "$MF_PSI"
mf_psi_x100_v some avg10; chk "psi some avg10 x100" "$MF_R" "1234"
mf_psi_x100_v full avg10; chk "psi full x100" "$MF_R" "0"
chk "pembungkus echo" "$(mf_psi_x100 some avg60)" "150"
rm -f "$MF_PSI"; mf_psi_x100_v some avg10; chk "tanpa berkas: gagal" "$?" "1"

# --- stat dipakai ulang 6 dtk; berkas basi tetap ditolak setelahnya ---
. "$T/fn.sh"; cp "$T/b.out" "$T/c.out"; unset MFS_MT_IN; MFS_CHK_OK=0; MFS_CHK_AT=0
monitor_epoch_now() { MONITOR_NOW=$FAKE_NOW; }
FAKE_NOW=$(date +%s); monitor_fps_stat_core "$T/c.out" com.game.a; chk "stat: berkas segar diterima" "$?" "0"
touch -d '1 hour ago' "$T/c.out"; FAKE_NOW=$((FAKE_NOW + 3)); monitor_fps_stat_core "$T/c.out" com.game.a; chk "stat: dalam 6 dtk memakai hasil lama" "$?" "0"
FAKE_NOW=$((FAKE_NOW + 4)); monitor_fps_stat_core "$T/c.out" com.game.a; chk "stat: lewat 6 dtk berkas basi ditolak" "$?" "1"

# --- cache profil game per tick: 10 dtk, paket baru langsung dibaca ---
sed -n '/^get_game_profile_c() {/,/^}/p' "$C/monitor.sh" > "$T/fn16.sh"; . "$T/fn16.sh"
rm -f "$T/gc"; get_game_profile() { echo x >> "$T/gc"; [ "$1" = com.g ] && echo balanced; return 0; }; GCALLS() { wc -l < "$T/gc" | tr -d " "; }
FAKE_NOW=5000; monitor_epoch_now() { MONITOR_NOW=$FAKE_NOW; }
_GGPC_PKG=""; _GGPC_VAL=""; _GGPC_AT=0
get_game_profile_c com.g; r1=$GGP_R; FAKE_NOW=5004; get_game_profile_c com.g; r2=$GGP_R
chk "cache profil: nilai sama, satu pindai" "$r1,$r2,$(GCALLS)" "balanced,balanced,1"
FAKE_NOW=5011; get_game_profile_c com.g; chk "cache profil: kedaluwarsa 10 dtk" "$(GCALLS)" "2"
get_game_profile_c com.lain; chk "cache profil: paket lain langsung dipindai, kosong" "$GGP_R|$(GCALLS)" "|3"

# --- umur fpsd.out tanpa stat: berubah sejak tick lalu = segar; tak pernah berubah = basi ---
. "$T/fn.sh"; sed -n '/^monitor_fps_stat_v() {/,/^}/p' "$C/monitor.sh" > "$T/fn7.sh"; . "$T/fn7.sh"
NT="$T/nt"; mkdir -p "$NT"; STATE_DIR="$NT"; cp "$T/b.out" "$NT/o.out"; rm -f "$NT/.fps_ref"
FAKE_NOW=9000; monitor_epoch_now() { MONITOR_NOW=$FAKE_NOW; }; MFS_KEY=""; MFS_LASTCHG=""
touch -d '10 seconds ago' "$NT/o.out"
monitor_fps_stat_v "$NT/o.out" com.game.a; chk "tanpa penanda: dianggap basi" "$?" "1"
FAKE_NOW=9003; MFS_KEY=""; touch -d "5 seconds ago" "$NT/.fps_ref"; touch "$NT/o.out"
monitor_fps_stat_v "$NT/o.out" com.game.a; chk "berubah sejak tick lalu: segar" "$?" "0"
chk "umur dilaporkan 0" "$MFS_AGE" "0"
FAKE_NOW=9006; MFS_KEY=""; touch -d '20 seconds ago' "$NT/.fps_ref"; touch -d '30 seconds ago' "$NT/o.out"
monitor_fps_stat_v "$NT/o.out" com.game.a; chk "tidak berubah 3 dtk: umur 3" "$MFS_AGE" "3"
FAKE_NOW=9030; MFS_KEY=""; touch -d '20 seconds ago' "$NT/.fps_ref"; touch -d '30 seconds ago' "$NT/o.out"
monitor_fps_stat_v "$NT/o.out" com.game.a; chk "tidak berubah 27 dtk: basi ditolak" "$?" "1"

# --- st= dari daemon: dibaca tanpa awk; pkg tetap dicocokkan ---
. "$T/fn.sh"; unset MFS_MT_IN; MFS_CHK_OK=0; MFS_CHK_AT=0; FAKE_NOW=$(date +%s); monitor_epoch_now() { MONITOR_NOW=$FAKE_NOW; }
printf 'pkg=com.game.a\nstatus=ok\nlat= 1 2 3\nst=17 24 120\n' > "$T/st.out"
awk() { echo "AWK DIPANGGIL" >> "$T/awk.calls"; command awk "$@"; }
rm -f "$T/awk.calls"; monitor_fps_stat_core "$T/st.out" com.game.a; chk "st= dibaca" "$?|$MONITOR_FS" "0|17 24 120"
chk "st= tanpa awk" "$([ -f "$T/awk.calls" ] && echo dipanggil || echo tidak)" "tidak"
monitor_fps_stat_core "$T/st.out" com.lain; chk "st= paket beda ditolak" "$?" "1"
printf 'pkg=com.game.a\nlat= 1 2 3\nst=abc\n' > "$T/st2.out"; touch "$T/st2.out"; MFS_CHK_AT=0; monitor_fps_stat_core "$T/st2.out" com.game.a; chk "st= rusak jatuh ke awk (gagal: data kurang)" "$?" "1"
unset -f awk
echo "HASIL: $PASS lolos, $FAIL gagal"
[ "$FAIL" -eq 0 ]
