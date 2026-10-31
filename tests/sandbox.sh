#!/bin/bash
# Tes sandbox modul HSIN v5: pohon sysfs palsu + getprop/setprop palsu.
# Pakai: bash tests/sandbox.sh [dash|sh|bash]   (default dash)
SH="${1:-dash}"
ROOT=$(cd "$(dirname "$0")/.." && pwd)
T=$(mktemp -d)
S="$T/sys"; P="$T/proc"; D="$T/data"; B="$T/bin"; PR="$T/props"
mkdir -p "$B" "$PR" "$D"
mk() { mkdir -p "$(dirname "$1")"; printf '%s\n' "$2" > "$1"; }
for n in 0 6; do
  p="$S/devices/system/cpu/cpufreq/policy$n"
  mk $p/scaling_available_governors "performance schedutil powersave"
  mk $p/scaling_governor schedutil
  mk $p/scaling_available_frequencies "300000 600000 1200000 1800000"
  mk $p/scaling_max_freq 1800000; mk $p/scaling_min_freq 300000
  mk $p/scaling_cur_freq 1200000
done
g="$S/class/devfreq/23100000.gpu"
mk $g/governor simple_ondemand; mk $g/available_governors "simple_ondemand performance"
mk $g/available_frequencies "256000000 384000000 512000000 850000000"
mk $g/max_freq 850000000; mk $g/min_freq 256000000; mk $g/cur_freq 384000000
mk $S/block/sda/queue/scheduler "mq-deadline [none] kyber"; mk $S/block/sda/queue/read_ahead_kb 128
mk $P/sys/vm/swappiness 60; mk $P/sys/vm/vfs_cache_pressure 100; mk $P/sys/vm/dirty_ratio 20
mk $P/sys/vm/dirty_background_ratio 5; mk $P/sys/vm/page-cluster 0
mk $P/sys/net/ipv4/tcp_congestion_control cubic; mk $P/sys/net/ipv4/tcp_available_congestion_control "cubic reno bbr"
mk $P/sys/net/ipv4/tcp_fastopen 1
mk $P/meminfo "MemTotal:        8000000 kB"; printf 'MemAvailable:    5000000 kB\n' >> $P/meminfo
mk $P/loadavg "2.35 1.90 1.50 1/500 1234"
printf 'SwapTotal:       2000000 kB\nSwapFree:        1500000 kB\n' >> $P/meminfo
mk $P/stat "cpu  1000 0 500 8000 500 0 0 0 0 0"
for c in 0 1 2 3 4 5 6 7; do mkdir -p $S/devices/system/cpu/cpu$c; done
mk $S/class/power_supply/battery/status Charging
mkdir -p $T/mods/alpha $T/mods/hsin $T/mods/other; printf 'id=alpha\nname=Alpha Fusion\n' > $T/mods/alpha/module.prop; printf 'id=other\nname=Pemutar Musik\n' > $T/mods/other/module.prop
mkdir -p $T/cpuset/top-app; mkdir -p $P/4242 $P/4300; printf 'com.kurogame.haru\000' > $P/4242/cmdline; printf 'com.android.systemui\000' > $P/4300/cmdline
printf '4300\n' > $T/cpuset/top-app/cgroup.procs
mk $S/class/thermal/thermal_zone0/type "soc-thermal"; mk $S/class/thermal/thermal_zone0/temp 45000
mk $S/class/thermal/thermal_zone1/type "gpu-thermal"; mk $S/class/thermal/thermal_zone1/temp 42000
mk $S/class/power_supply/battery/capacity 77; mk $S/class/power_supply/battery/temp 312
cat > $B/getprop <<EOT
#!/bin/sh
case "\$1" in
 ro.product.model) echo P671L;; ro.product.brand) echo itel;; ro.soc.model) echo T7250;;
 ro.build.version.release) echo 14;; sys.boot_completed) echo 1;;
 *) [ -f "$PR/\$1" ] && cat "$PR/\$1";;
esac
EOT
cat > $B/setprop <<EOT
#!/bin/sh
printf '%s\n' "\$2" > "$PR/\$1"
EOT
chmod +x $B/*
export PATH="$B:$PATH" HSIN_SYS="$S" HSIN_PROC="$P" HSIN_DATA="$D" HSIN_MODULE_PATH="$ROOT/module" HSIN_MODS="$T/mods" HSIN_CPUSET="$T/cpuset"
A() { $SH "$ROOT/module/action.sh" "$@"; }
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "PASS: $1"; }
bad() { FAIL=$((FAIL+1)); echo "FAIL: $1 -> $2"; }
chk() { # nama, perintah-hasil, pola
  case "$2" in *"$3"*) ok "$1";; *) bad "$1" "$2";; esac; }
jv() { python3 -c "import json,sys;json.loads(sys.stdin.read())" <<<"$1" 2>/dev/null; }

r=$(A ping); chk "ping" "$r" "pong v6.0.0"
r=$(A device); jv "$r" && ok "device json" || bad "device json" "$r"; chk "device model" "$r" '"model":"P671L"'
r=$(A status); jv "$r" && ok "status json" || bad "status json" "$r"
chk "status cpu avg" "$r" '"cpu_khz":1200000'; chk "status gpu" "$r" '"gpu_hz":384000000'
chk "status cpu temp" "$r" '"cpu_temp":45'; chk "status gpu temp" "$r" '"gpu_temp":42'
chk "status load" "$r" '"load_x100":235'; chk "status ram used" "$r" '"ram_used_kb":3000000'
chk "status bat" "$r" '"bat_pct":77,"bat_temp":31'
r=$(A knobs); jv "$r" && ok "knobs json" || bad "knobs json" "$r"
chk "knob cpu governor" "$r" '"key":"cpu.p0.governor"'; chk "knob gpu max" "$r" '"key":"gpu.0.max_freq"'
chk "knob io sched cur" "$r" '"key":"io.scheduler","label":"Scheduler sda","type":"choice","unit":"","options":["mq-deadline","none","kyber"],"cur":"none"'
chk "knob swappiness range" "$r" '"min":0,"max":100,"step":1,"cur":"60"'
chk "knob zram locked" "$r" '"type":"locked","reason":"Belum didukung"'
chk "knob renderer" "$r" '"key":"display.renderer"'
A snapshot >/dev/null; [ -s "$D/baseline.env" ] && ok "baseline tersimpan" || bad "baseline" "kosong"
# set-many benar
r=$(A set-many vm.swappiness=40 cpu.p0.governor=performance io.scheduler=kyber net.tcp_cc=bbr); jv "$r" && ok "set-many json" || bad "set-many json" "$r"
chk "set-many ok=4" "$r" '"ok":4,"fail":0'
[ "$(cat $P/sys/vm/swappiness)" = 40 ] && ok "swappiness tertulis" || bad "swappiness" "$(cat $P/sys/vm/swappiness)"
[ "$(cat $S/devices/system/cpu/cpufreq/policy0/scaling_governor)" = performance ] && ok "governor tertulis" || bad governor x
grep -q 'vm.swappiness=40' $D/overrides.env && ok "override tersimpan" || bad override "$(cat $D/overrides.env)"
# validasi
r=$(A set-many vm.swappiness=999); chk "range ditolak" "$r" '"fail":1'; [ "$(cat $P/sys/vm/swappiness)" = 40 ] && ok "nilai tidak berubah" || bad "nilai berubah" x
r=$(A set-many cpu.p0.governor=ngawur); chk "choice ditolak" "$r" 'di luar pilihan'
r=$(A set-many 'vm.swappiness=4;rm'); chk "injeksi ditolak" "$r" 'tidak valid'
r=$(A set-many foo.bar=1); chk "knob asing ditolak" "$r" 'tidak dikenal'
r=$(A set-many mem.zram=lz4); chk "locked ditolak" "$r" 'tidak didukung'
# min/max freq urutan: naikkan min di atas max lama, harus lolos lewat putaran 2
r=$(A set-many cpu.p0.min_freq=1800000 cpu.p0.max_freq=1800000); chk "min>max urutan" "$r" '"ok":2,"fail":0'
r=$(A set-many cpu.p0.max_freq=600000 cpu.p0.min_freq=300000); chk "turun max urutan" "$r" '"ok":2,"fail":0'
# kembali ke baseline menghapus override
r=$(A set-many vm.swappiness=60); grep -q 'vm.swappiness' $D/overrides.env && bad "override harus hilang" "$(cat $D/overrides.env)" || ok "sama baseline -> override dihapus"
# renderer prop
r=$(A set-many display.renderer=skiavk); chk "renderer set" "$r" '"ok":1'; [ "$(cat $PR/debug.hwui.renderer)" = skiavk ] && ok "prop tertulis" || bad prop x
r=$(A set-many display.renderer=system); chk "renderer system" "$r" '"ok":1'
# read-only node
chmod 444 $P/sys/vm/dirty_ratio; r=$(A set-many vm.dirty_ratio=30); chk "read-only ditolak" "$r" 'read-only'; chmod 644 $P/sys/vm/dirty_ratio
# knobs menunjukkan def vs cur
r=$(A set-many vm.swappiness=30); r=$(A knobs); chk "cur 30 def 60" "$r" '"cur":"30","def":"60"'
# apply ulang dari override setelah 'reboot' (nilai sysfs kembali ke bawaan)
printf '60\n' > $P/sys/vm/swappiness; printf 'schedutil\n' > $S/devices/system/cpu/cpufreq/policy0/scaling_governor
r=$(A apply); chk "apply ok" "$r" '"fail":0'; [ "$(cat $P/sys/vm/swappiness)" = 30 ] && ok "apply menulis ulang" || bad apply "$(cat $P/sys/vm/swappiness)"
# restore
r=$(A restore); jv "$r" && ok "restore json" || bad "restore json" "$r"
[ "$(cat $P/sys/vm/swappiness)" = 60 ] && ok "restore swappiness 60" || bad restore "$(cat $P/sys/vm/swappiness)"
[ ! -s "$D/overrides.env" ] && ok "restore kosongkan override" || bad "override sisa" "$(cat $D/overrides.env)"
# logs
r=$(A logs apply 5); [ -n "$r" ] && ok "logs apply ada isi" || bad logs kosong
# guard
r=$(A status); chk "status safe 0" "$r" '"safe_mode":0'
echo 3 > $D/boot_count; : > $D/safe_mode; r=$(A status); chk "status safe" "$r" '"safe_mode":1'
r=$(A guard-reset); chk "guard-reset" "$r" '"ok":1'; [ ! -f $D/safe_mode ] && ok "safe_mode dihapus" || bad safe x

# ---------- status baru ----------
r=$(A status); jv "$r" && ok "status json lengkap" || bad "status json lengkap" "$r"
chk "policies" "$r" '"policies":[{"id":0,"cur":1200000,"min":300000,"max":1800000'
chk "cores" "$r" '"cores":8'; chk "swap used" "$r" '"swap_total_kb":2000000,"swap_used_kb":500000'
chk "cpu stat" "$r" '"cpu_total":10000,"cpu_idle":8500'; chk "charging" "$r" '"bat_charging":1'
chk "gpu max" "$r" '"gpu_max_hz":850000000'
# ---------- modul lain ----------
r=$(A conflicts); jv "$r" && ok "conflicts json" || bad "conflicts json" "$r"
chk "conflict alpha" "$r" 'Alpha Fusion'; case "$r" in *Pemutar*|*hsin*) bad "false positive" "$r";; *) ok "modul lain tidak salah deteksi";; esac
touch $T/mods/alpha/disable; r=$(A conflicts); chk "disable diabaikan" "$r" '"list":[]'; rm $T/mods/alpha/disable
# penolakan write -> pesan menyebut modul lain
r=$(. "$ROOT/module/core/lib.sh"; reject_msg "$P/sys/vm/swappiness"); chk "pesan tolak sebut modul" "$r" 'dipegang modul lain Alpha Fusion'
printf '%s /x tmpfs rw 0 0\n' none >> $P/mounts; sed -i "s#/x#$P/sys/vm/dirty_ratio#" $P/mounts
r=$(. "$ROOT/module/core/lib.sh"; reject_msg "$P/sys/vm/dirty_ratio"); chk "pesan tolak node ditimpa mount" "$r" 'ditimpa mount'
r=$(. "$ROOT/module/core/lib.sh"; reject_msg "$P/sys/vm/lain"); chk "pesan tolak sertakan modul" "$r" 'Alpha Fusion'
mv $T/mods/alpha $T/mods_alpha; r=$(. "$ROOT/module/core/lib.sh"; reject_msg "$P/sys/vm/lain"); chk "tanpa modul lain: ditolak kernel" "$r" 'ditolak kernel'; mv $T/mods_alpha $T/mods/alpha
# ---------- pengaman panas ----------
r=$(A thermal-get); chk "thermal default" "$r" '"on":1,"limit":90,"trip":0'
r=$(A thermal-set 1 500); chk "thermal batas ditolak" "$r" '"ok":0'
r=$(A thermal-set 1 60); chk "thermal set" "$r" '"ok":1'; mk $S/class/thermal/thermal_zone0/temp 65000
A set-many vm.swappiness=20 cpu.p0.governor=performance >/dev/null
HSIN_ONESHOT=1 $SH "$ROOT/module/daemon.sh"
[ -f $D/thermal_trip ] && ok "pengaman panas trip" || bad trip "tidak trip"
[ "$(cat $P/sys/vm/swappiness)" = 60 ] && ok "trip kembalikan ke bawaan" || bad "trip nilai" "$(cat $P/sys/vm/swappiness)"
grep -q 'vm.swappiness=20' $D/overrides.env && ok "override tersimpan saat trip" || bad "override hilang" x
r=$(A status); chk "status trip" "$r" '"thermal_trip":1'
r=$(A thermal-ack); chk "ack menerapkan lagi" "$r" '"fail":0'; [ "$(cat $P/sys/vm/swappiness)" = 20 ] && ok "ack: swappiness 20" || bad ack "$(cat $P/sys/vm/swappiness)"
mk $S/class/thermal/thermal_zone0/temp 45000; A thermal-set 1 90 >/dev/null; HSIN_ONESHOT=1 $SH "$ROOT/module/daemon.sh"; [ ! -f $D/thermal_trip ] && ok "tidak trip di bawah batas" || bad trip2 x
A restore >/dev/null
# ---------- per game ----------
r=$(A detect); chk "detect cpuset" "$r" '"ok":1'
r=$(A game-set com.kurogame.haru vm.swappiness=10 cpu.p0.governor=performance); chk "game-set ok" "$r" '"ok":2,"fail":0'
r=$(A game-set com.kurogame.haru vm.swappiness=999 foo.bar=1); chk "game-set tolak" "$r" '"ok":0,"fail":2'
r=$(A game-set com.kurogame.haru vm.swappiness=10 cpu.p0.governor=performance)
r=$(A game-set bukanpaket x=1); chk "paket invalid" "$r" 'nama paket tidak valid'
r=$(A game-list); jv "$r" && ok "game-list json" || bad "game-list json" "$r"; chk "game terdaftar" "$r" '"pkg":"com.kurogame.haru","n":2'
HSIN_ONESHOT=1 $SH "$ROOT/module/daemon.sh"; [ "$(cat $P/sys/vm/swappiness)" = 60 ] && ok "mode per game mati: tidak diterapkan" || bad gm0 "$(cat $P/sys/vm/swappiness)"
r=$(A game-mode 1); chk "game-mode on" "$r" '"ok":1'
HSIN_ONESHOT=1 $SH "$ROOT/module/daemon.sh"; [ "$(cat $P/sys/vm/swappiness)" = 60 ] && ok "bukan game di depan: tidak diterapkan" || bad nogame x
printf '4242\n' > $T/cpuset/top-app/cgroup.procs
HSIN_ONESHOT=1 $SH "$ROOT/module/daemon.sh"
[ "$(cat $P/sys/vm/swappiness)" = 10 ] && ok "game dibuka: swappiness 10" || bad gameopen "$(cat $P/sys/vm/swappiness)"
[ "$(cat $S/devices/system/cpu/cpufreq/policy0/scaling_governor)" = performance ] && ok "game dibuka: governor performance" || bad gamegov x
r=$(A status); chk "status game aktif" "$r" '"game_active":"com.kurogame.haru"'
grep -q 'vm.swappiness=10' $D/overrides.env && bad "profil game bocor ke override" x || ok "profil game tidak disimpan sebagai global"
printf '4300\n' > $T/cpuset/top-app/cgroup.procs
HSIN_ONESHOT=1 $SH "$ROOT/module/daemon.sh"
[ "$(cat $P/sys/vm/swappiness)" = 60 ] && ok "game ditutup: kembali Global 60" || bad gameclose "$(cat $P/sys/vm/swappiness)"
[ "$(cat $S/devices/system/cpu/cpufreq/policy0/scaling_governor)" = schedutil ] && ok "game ditutup: governor schedutil" || bad gamegov2 x
# Global pakai override user: saat game ditutup kembali ke nilai override user, bukan baseline
A set-many vm.swappiness=35 >/dev/null
printf '4242\n' > $T/cpuset/top-app/cgroup.procs; HSIN_ONESHOT=1 $SH "$ROOT/module/daemon.sh"
[ "$(cat $P/sys/vm/swappiness)" = 10 ] && ok "game override menang atas Global" || bad gameov "$(cat $P/sys/vm/swappiness)"
printf '4300\n' > $T/cpuset/top-app/cgroup.procs; HSIN_ONESHOT=1 $SH "$ROOT/module/daemon.sh"
[ "$(cat $P/sys/vm/swappiness)" = 35 ] && ok "game ditutup: kembali ke Global user 35" || bad gameglob "$(cat $P/sys/vm/swappiness)"
# hapus profil saat game aktif
printf '4242\n' > $T/cpuset/top-app/cgroup.procs; HSIN_ONESHOT=1 $SH "$ROOT/module/daemon.sh"
r=$(A game-del com.kurogame.haru); chk "game-del" "$r" '"ok":1'
[ "$(cat $P/sys/vm/swappiness)" = 35 ] && ok "game-del saat aktif: kembali Global" || bad gamedel "$(cat $P/sys/vm/swappiness)"
[ ! -f $D/game_active ] && ok "game_active dibersihkan" || bad gameact x
# mode aman menghentikan daemon
: > $D/safe_mode; A game-mode 1 >/dev/null; A game-set com.kurogame.haru vm.swappiness=10 >/dev/null
HSIN_ONESHOT=1 $SH "$ROOT/module/daemon.sh"; [ "$(cat $P/sys/vm/swappiness)" = 35 ] && ok "mode aman: daemon diam" || bad safed "$(cat $P/sys/vm/swappiness)"
rm -f $D/safe_mode
# service.sh jalan (boot) tanpa tunggu lama: ganti sleep
sed 's/sleep [0-9]*/sleep 0/' "$ROOT/module/service.sh" > "$T/service_t.sh"; cp "$T/service_t.sh" "$ROOT/module/service_t.sh"
A game-mode 0 >/dev/null; A thermal-set 0 90 >/dev/null; rm -rf $D/games/*; printf "" > $D/overrides.env
A set-many vm.swappiness=25 >/dev/null; printf '60\n' > $P/sys/vm/swappiness
$SH "$ROOT/module/service_t.sh"; sleep 2; rm -f "$ROOT/module/service_t.sh"
[ "$(cat $P/sys/vm/swappiness)" = 25 ] && ok "service.sh menerapkan override saat boot" || bad service "$(cat $P/sys/vm/swappiness)"
[ "$(cat $D/boot_count)" = 0 ] && ok "boot counter reset" || bad counter "$(cat $D/boot_count)"

# ---- mode (v6) ----
A restore >/dev/null; A thermal-set 1 90 >/dev/null; printf "" > $D/overrides.env
CP0="$S/devices/system/cpu/cpufreq/policy0"; GP="$S/class/devfreq/23100000.gpu"
r=$(A mode boost); jv "$r" && ok "mode boost json" || bad "mode boost json" "$r"
[ "$(cat $CP0/scaling_min_freq)" = 1800000 ] && [ "$(cat $CP0/scaling_max_freq)" = 1800000 ] && ok "boost: CPU min=max=tertinggi" || bad boostcpu "$(cat $CP0/scaling_min_freq)/$(cat $CP0/scaling_max_freq)"
[ "$(cat $CP0/scaling_governor)" = performance ] && ok "boost: governor performance" || bad boostgov "$(cat $CP0/scaling_governor)"
[ "$(cat $GP/min_freq)" = 850000000 ] && ok "boost: GPU min=tertinggi" || bad boostgpu "$(cat $GP/min_freq)"
chk "boost: batas panas 100" "$(A thermal-get)" '"limit":100'
chk "mode-get boost" "$(A mode-get)" '"mode":"boost"'
r=$(A mode hemat); jv "$r" && ok "mode hemat json" || bad "mode hemat json" "$r"
[ "$(cat $CP0/scaling_max_freq)" = 1200000 ] && [ "$(cat $CP0/scaling_min_freq)" = 300000 ] && ok "hemat: CPU max 70%, min terendah" || bad hematcpu "$(cat $CP0/scaling_min_freq)/$(cat $CP0/scaling_max_freq)"
[ "$(cat $GP/max_freq)" = 384000000 ] && ok "hemat: GPU max 55%" || bad hematgpu "$(cat $GP/max_freq)"
chk "hemat: batas panas kembali 90" "$(A thermal-get)" '"limit":90'
A mode seimbang >/dev/null
[ "$(cat $CP0/scaling_max_freq)" = 1800000 ] && [ "$(cat $CP0/scaling_min_freq)" = 600000 ] && ok "seimbang: max penuh, min 35%" || bad seimbangcpu "$(cat $CP0/scaling_min_freq)/$(cat $CP0/scaling_max_freq)"
A mode boost >/dev/null; A mode bawaan >/dev/null
[ "$(cat $CP0/scaling_min_freq)" = 300000 ] && [ "$(cat $CP0/scaling_governor)" = schedutil ] && ok "bawaan: kembali ke baseline" || bad bawaan "$(cat $CP0/scaling_min_freq)"
chk "mode salah ditolak" "$(A mode ngawur)" '"ok":0'
r=$(A game-cfg com.kurogame.haru boost 80); chk "game-cfg boost" "$r" '"ok":1'
chk "game-get" "$(A game-get com.kurogame.haru)" '"mode":"boost","res":80'
[ -f $D/games/com.kurogame.haru.env ] && [ "$(cat $D/games/com.kurogame.haru.res)" = 80 ] && ok "game-cfg menulis env dan res" || bad gamecfgfiles "-"
chk "game-cfg res salah" "$(A game-cfg com.kurogame.haru boost 20)" '"ok":0'
A game-cfg com.kurogame.haru bawaan 100 >/dev/null
[ ! -f $D/games/com.kurogame.haru.res ] && ok "res dihapus saat 100" || bad resrm "-"
A game-del com.kurogame.haru >/dev/null; A restore >/dev/null
echo "--- $SH: PASS=$PASS FAIL=$FAIL"
rm -rf "$T"
[ $FAIL -eq 0 ]
