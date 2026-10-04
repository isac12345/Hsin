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
export PATH="$B:$PATH" HSIN_SYS="$S" HSIN_PROC="$P" HSIN_DATA="$D" HSIN_MODULE_PATH="$ROOT/module"
A() { $SH "$ROOT/module/action.sh" "$@"; }
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "PASS: $1"; }
bad() { FAIL=$((FAIL+1)); echo "FAIL: $1 -> $2"; }
chk() { # nama, perintah-hasil, pola
  case "$2" in *"$3"*) ok "$1";; *) bad "$1" "$2";; esac; }
jv() { python3 -c "import json,sys;json.loads(sys.stdin.read())" <<<"$1" 2>/dev/null; }

r=$(A ping); chk "ping" "$r" "pong v5.0.0"
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
r=$(A guard); chk "guard" "$r" '"safe_mode":0'
echo 3 > $D/boot_count; : > $D/safe_mode; r=$(A status); chk "status safe" "$r" '"safe_mode":1'
r=$(A guard-reset); chk "guard-reset" "$r" '"ok":1'; [ ! -f $D/safe_mode ] && ok "safe_mode dihapus" || bad safe x
# service.sh jalan (boot) tanpa tunggu lama: ganti sleep
sed 's/sleep [0-9]*/sleep 0/' "$ROOT/module/service.sh" > "$T/service_t.sh"; cp "$T/service_t.sh" "$ROOT/module/service_t.sh"
A set-many vm.swappiness=25 >/dev/null; printf '60\n' > $P/sys/vm/swappiness
$SH "$ROOT/module/service_t.sh"; sleep 2; rm -f "$ROOT/module/service_t.sh"
[ "$(cat $P/sys/vm/swappiness)" = 25 ] && ok "service.sh menerapkan override saat boot" || bad service "$(cat $P/sys/vm/swappiness)"
[ "$(cat $D/boot_count)" = 0 ] && ok "boot counter reset" || bad counter "$(cat $D/boot_count)"
echo "--- $SH: PASS=$PASS FAIL=$FAIL"
rm -rf "$T"
[ $FAIL -eq 0 ]
