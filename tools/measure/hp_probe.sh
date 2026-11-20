#!/system/bin/sh
# HSIN: ukur di HP (root). Jalankan: su -c 'sh hp_probe.sh' > /sdcard/hsin_probe.txt
# Hanya membaca dan mengukur; tidak mengubah setelan. Waktu dalam tick CPU (1 tick = 10 ms).
# Biaya proses = utime+stime+cutime+cstime (field 14-17 /proc/PID/stat; field 12-15 setelah
# nama proses dipotong), jadi anak proses ikut terhitung.

PD=/data/local/tmp; [ -d "$PD" ] && [ -w "$PD" ] || PD=${TMPDIR:-/tmp}

ticks() {   # $1=pid -> jumlah utime+stime+cutime+cstime
    _s=$(cat "/proc/$1/stat" 2>/dev/null) || return 1
    _s=${_s##*) }
    set -- $_s
    # setelah ") ": state ppid pgrp session tty tpgid flags minflt cminflt majflt cmajflt utime stime cutime cstime
    echo $(( ${12} + ${13} + ${14} + ${15} ))
}

# biaya satu perintah dibungkus sh: jalankan N kali, hitung tick sh (induk+anak) per panggilan
cost() {   # $1=N $2..=perintah (string untuk sh -c)
    _n=$1; shift
    sh -c "i=0; while [ \$i -lt $_n ]; do $* >/dev/null 2>&1; i=\$((i+1)); done; cat /proc/\$\$/stat" > "$PD/.hp_cost" 2>/dev/null
    _s=$(cat $PD/.hp_cost); rm -f $PD/.hp_cost
    _s=${_s##*) }
    set -- $_s
    _t=$(( ${12} + ${13} + ${14} + ${15} ))
    echo "$_t $_n"
}

echo "== perangkat"
getprop ro.product.model; getprop ro.build.version.release; getprop ro.board.platform
echo "shell: $(readlink /system/bin/sh) uid=$(id -u)"

echo; echo "== 1. thermal zone yang terbaca root"
tot=0; ok=0; bad=0
for z in /sys/class/thermal/thermal_zone*; do
    [ -d "$z" ] || continue
    tot=$((tot+1))
    t=$(cat "$z/type" 2>/dev/null); v=$(cat "$z/temp" 2>/dev/null)
    if [ -n "$v" ]; then ok=$((ok+1)); else bad=$((bad+1)); fi
    echo "${z##*/} type=$t temp=$v"
done
echo "zona=$tot terbaca=$ok tidak_terbaca=$bad"
echo "trip_point per zona (jumlah berkas trip_point_*_temp):"; ls /sys/class/thermal/thermal_zone*/trip_point_*_temp 2>/dev/null | wc -l
for f in /proc/pressure/cpu /proc/pressure/io /proc/pressure/memory; do
    [ -r "$f" ] && echo "$f terbaca: $(head -n 1 $f)" || echo "$f TIDAK terbaca"
done
for f in /sys/class/backlight/*/brightness; do [ -r "$f" ] && echo "$f = $(cat $f)"; done

echo; echo "== 2. biaya satu fork+exec (20 x /system/bin/true) dan builtin"
echo "true x20 (tick, panggilan): $(cost 20 /system/bin/true)"
echo "echo builtin x20 (tick, panggilan): $(cost 20 'echo x')"
echo "printf eksternal? $(command -v printf) ; type: $(type printf 2>&1 | head -n 1)"

echo; echo "== 3. biaya dumpsys (tick CPU induk+anak per 5 panggilan; dan ukuran keluaran)"
for a in "power" "activity activities" "window windows" "SurfaceFlinger --list" "audio" "deviceidle"; do
    c=$(cost 5 "dumpsys $a")
    b=$(dumpsys $a 2>/dev/null | wc -c)
    echo "dumpsys $a : ticks/5x=${c%% *} bytes=$b"
done

echo; echo "== 4. service call SurfaceFlinger (1013 counter, 1035 refresh)"
for code in 1013 1035; do
    out=$(service call SurfaceFlinger $code 2>&1 | head -n 2 | tr '\n' ' ')
    echo "kode $code -> $out"
    echo "  ticks/20x=$(cost 20 "service call SurfaceFlinger $code")"
done
echo "cmd game list-modes? $(cmd game list-modes com.android.settings 2>&1 | head -n 1)"

echo; echo "== 5. logcat -b events: tag yang dipakai monitor"
logcat -b events -d -t 500 -v tag 2>/dev/null | grep -Eo 'wm_resume_activity|am_focused_activity|wm_set_resumed_activity|am_resume_activity|wm_focused_app' | sort | uniq -c
echo "baris events total: $(logcat -b events -d -t 500 -v tag 2>/dev/null | wc -l)"

echo; echo "== 6. biaya proses HSIN sekarang (sampel 30 dtk, induk+anak)"
for n in monitor.sh hud_sample.sh watchdog.sh hsin-fpsd uperf fas-rs; do
    # Pola "[x]nama" tidak cocok dengan cmdline grep sendiri; satu fork saja, tanpa noise.
    pat="[$(echo "$n" | cut -c1)]$(echo "$n" | cut -c2-)"
    for p in $(pidof $n 2>/dev/null) $(grep -la "$pat" /proc/[0-9]*/cmdline 2>/dev/null | sed 's#/proc/\([0-9]*\)/cmdline#\1#'); do
        [ "$p" = "$$" ] && continue
        a=$(ticks $p) && echo "$n:$p:$a"
    done
done | sort -u > $PD/.hp_a
sleep 30
while IFS=: read -r n p a; do
    b=$(ticks $p) || continue
    d=$((b - a)); echo "$n pid=$p ticks/30dtk=$d => $((d / 30))% satu core"
done < $PD/.hp_a
rm -f $PD/.hp_a
echo; echo "== 7. mode monitor (dari log HSIN)"
HL=/data/adb/hsin/hsin.log
grep -E "MONITOR\] \[(START|EVENT|WARNING)\]" "$HL" 2>/dev/null | grep -E "method=|event stream|polling" | tail -n 6 | cut -c1-200
echo "ragam tag events (500 baris terakhir):"
logcat -b events -d -t 500 -v brief 2>/dev/null | sed -n 's#^I/\([A-Za-z0-9_]*\).*#\1#p' | sort | uniq -c | sort -rn | head -n 12
echo; echo "selesai. Kirim berkas ini ke Claude/agent."
