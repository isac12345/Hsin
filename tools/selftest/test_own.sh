#!/bin/sh
# Uji Adapt memegang frekuensi CPU/GPU (adapt.sh: ad_own_*) dengan sysfs palsu: sh test_own.sh
D="$(cd "$(dirname "$0")" && pwd)"
C="${COMMON_DIR:-$D/../../module/common}"
T=$(mktemp -d "${TMPDIR:-/tmp}/own.XXXXXX")
trap 'kill $(cat "$T"/sleep.pid 2>/dev/null) 2>/dev/null; rm -rf "$T"' EXIT
PASS=0; FAIL=0
chk() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; else FAIL=$((FAIL+1)); printf '  FAIL %s (dapat=[%s] harap=[%s])\n' "$1" "$2" "$3"; fi; }

mkdir -p "$T/state" "$T/cf/policy0" "$T/cf/policy6" "$T/df/gpu" "$T/power/battery" "$T/thermal/thermal_zone0" "$T/bin"
# daftar frekuensi palsu (sengaja bukan angka HP tertentu)
for p in policy0 policy6; do
    d="$T/cf/$p"
    if [ "$p" = policy0 ]; then printf '500000 800000 1000000 1300000 1600000 \n' > "$d/scaling_available_frequencies"; mx=1600000
    else printf '700000 1100000 1500000 1900000 2300000\n' > "$d/scaling_available_frequencies"; mx=2300000; fi
    printf '%s\n' "$mx" > "$d/cpuinfo_max_freq"
    printf '%s\n' "$(cut -d' ' -f1 "$d/scaling_available_frequencies")" > "$d/cpuinfo_min_freq"
    cp "$d/cpuinfo_min_freq" "$d/scaling_min_freq"
    printf '%s\n' "$mx" > "$d/scaling_max_freq"
done
printf '200000000 300000000 400000000 500000000 600000000\n' > "$T/df/gpu/available_frequencies"
printf '200000000\n' > "$T/df/gpu/min_freq"; printf '600000000\n' > "$T/df/gpu/max_freq"
printf '361\n' > "$T/power/battery/temp"; printf '80\n' > "$T/power/battery/capacity"
printf '45000\n' > "$T/thermal/thermal_zone0/temp"
# uperf/fas-rs palsu: proses sleep sungguhan supaya SIGSTOP/SIGCONT bisa diperiksa
sleep 300 & echo $! > "$T/sleep.pid"
cat > "$T/bin/pidof" <<EOP
#!/bin/sh
case "\$1" in fas-rs) cat "$T/sleep.pid" ;; esac
EOP
chmod +x "$T/bin/pidof"; PATH="$T/bin:$PATH"
st() { sed 's/.*) //' "/proc/$(cat "$T/sleep.pid")/stat" 2>/dev/null | cut -c1; }

export HSIN_CONF_DIR="$T/state" HSIN_LOG_FILE="$T/log" AD_DIR="$T/state/adapt" AD_STATE="$T/state"
export HSIN_STATE_DIR="$T/state" HSIN_SYS_CPUFREQ="$T/cf" HSIN_SYS_DEVFREQ="$T/df"
export SYSFS_POWER_PREFIX="$T/power" SYSFS_THERMAL_PREFIX="$T/thermal" SYSFS_MODULE_PREFIX="$T/mod"
mkdir -p "$T/mod"
. "$C/gameboost.sh" 2>/dev/null
. "$C/adapt.sh"
AD_WARM_SECS=0
ad_psi() { printf '%s' "${T_PSI:-5}"; }
ad_memavail_kb() { printf '2000000'; }
monitor_fps_stat() { printf '%s' "${T_FPS:-60 60 16}"; }
get_game_profile() { case "$1" in com.game.*) printf 'performance' ;; *) : ;; esac; }
ad_in_call() { return 1; }
date() { if [ -n "$T_NOW" ]; then printf '%s\n' "$T_NOW"; else command date "$@"; fi; }
ad_tier_beban() { printf '1'; }
printf 'balanced\n' > "$AD_STATE/active_profile"
ad_auto_tune() { :; }
ad_preset_learn() { :; }
ad_saran() { :; }
mn() { cat "$T/cf/$1/scaling_min_freq"; }
mx() { cat "$T/cf/$1/scaling_max_freq"; }
in_list() { for _x in $2; do [ "$_x" = "$1" ] && return 0; done; return 1; }

echo "== ad_own_floor: hasil selalu ada di daftar dan >= target"
okall=1
for pct in 0 10 25 50 70 90 100; do
    for p in policy0 policy6; do
        f=$(ad_own_floor $pct "$T/cf/$p"); L=$(cat "$T/cf/$p/scaling_available_frequencies"); M=$(cat "$T/cf/$p/cpuinfo_max_freq")
        tgt=$(( (M / 100) * pct ))
        in_list "$f" "$L" || okall=0
        [ "$f" -ge "$tgt" ] || okall=0
    done
done
chk "semua persen snap ke daftar" "$okall" "1"
chk "50% policy0" "$(ad_own_floor 50 "$T/cf/policy0")" "800000"
chk "100% = frekuensi tertinggi" "$(ad_own_floor 100 "$T/cf/policy6")" "2300000"
chk "GPU 70%" "$(ad_own_floor 70 "$T/df/gpu")" "500000000"
printf '9999999\n' > "$T/cf/policy0/cpuinfo_max_freq"
chk "amplop: tidak melewati cpuinfo_max" "$(ad_own_floor 100 "$T/cf/policy0")" "1600000"
printf '1600000\n' > "$T/cf/policy0/cpuinfo_max_freq"

echo "== ad_own_on / ad_own_off memulihkan persis"
T_NOW=1000
ad_own_on com.game.a; r=$?
chk "ad_own_on berhasil" "$r" "0"
chk "penanda ada" "$([ -f "$AD_OWN_FILE" ] && echo ada)" "ada"
chk "fas-rs dibekukan (T)" "$(st)" "T"
AD_BEBAN=3; AD_PKG=com.game.a; ad_own_apply
chk "beban 3: min policy0 90%" "$(mn policy0)" "1600000"
chk "beban 3: min policy6 90%" "$(mn policy6)" "2300000"
chk "beban 3: min GPU 90%" "$(cat "$T/df/gpu/min_freq")" "600000000"
ad_own_off selesai
chk "min policy0 kembali" "$(mn policy0)" "500000"
chk "max policy0 kembali" "$(mx policy0)" "1600000"
chk "min GPU kembali" "$(cat "$T/df/gpu/min_freq")" "200000000"
chk "penanda hilang" "$([ -f "$AD_OWN_FILE" ] || [ -f "$AD_OWN_PREV" ] || [ -f "$AD_OWN_STOP" ] && echo ada || echo hilang)" "hilang"
chk "fas-rs dilanjutkan" "$([ "$(st)" = T ] && echo beku || echo jalan)" "jalan"

echo "== urutan tulis: naik max dulu lalu min; turun min saja"
printf '800000\n' > "$T/cf/policy0/scaling_max_freq"   # max sedang diturunkan (mis. thermal)
ad_own_on com.game.b
WL="$T/wr.log"; : > "$WL"
ad_wr() { printf '%s %s\n' "$1" "$2" >> "$WL"; printf '%s' "$2" > "$1" 2>/dev/null; }
AD_BEBAN=2; AD_OWN_LAST=0; ad_own_apply
L=$(grep policy0 "$WL" | sed 's#.*/##' | cut -d' ' -f1 | tr '\n' ' ')
chk "naik: max lalu min" "$L" "scaling_max_freq scaling_min_freq "
: > "$WL"; T_NOW=1100; AD_BEBAN=1; ad_own_apply
L=$(grep policy0 "$WL" | sed 's#.*/##' | cut -d' ' -f1 | tr '\n' ' ')
chk "turun: hanya min" "$L" "scaling_min_freq "
ad_own_off selesai
chk "max asli (800000) dipulihkan" "$(mx policy0)" "800000"
printf '1600000\n' > "$T/cf/policy0/scaling_max_freq"
ad_wr() { printf '%s' "$2" > "$1" 2>/dev/null; }

echo "== suhu dan baterai menahan kenaikan"
T_NOW=2000; ad_own_on com.game.c; AD_BEBAN=1; AD_OWN_LAST=0; ad_own_apply
printf '490\n' > "$T/power/battery/temp"     # 49 C
T_NOW=2100; AD_BEBAN=3; ad_own_apply
chk "49 C: lantai tidak naik" "$(mn policy0)" "800000"
printf '361\n' > "$T/power/battery/temp"
printf '71000\n' > "$T/thermal/thermal_zone0/temp"
T_NOW=2200; ad_own_apply
chk "SoC 71 C: lantai tidak naik" "$(mn policy0)" "800000"
printf '45000\n' > "$T/thermal/thermal_zone0/temp"
printf '10\n' > "$T/power/battery/capacity"
T_NOW=2300; ad_own_apply
chk "baterai 10%: lantai tidak naik" "$(mn policy0)" "800000"
printf '80\n' > "$T/power/battery/capacity"
T_NOW=2400; ad_own_apply
chk "normal lagi: naik ke 90%" "$(mn policy0)" "1600000"
printf '510\n' > "$T/power/battery/temp"     # 51 C: turun selalu boleh
T_NOW=2401; AD_BEBAN=1; ad_own_apply
chk "51 C: turun tidak ditahan" "$(mn policy0)" "800000"
printf '361\n' > "$T/power/battery/temp"
T_NOW=2405; AD_BEBAN=3; ad_own_apply
chk "jeda <20 dtk menahan" "$(mn policy0)" "800000"
T_NOW=2425; ad_own_apply
chk "jeda terpenuhi: naik" "$(mn policy0)" "1600000"
ad_own_off selesai

echo "== maksimal 3 perubahan naik per sesi"
T_NOW=3000; ad_own_on com.game.d; AD_BEBAN=1; AD_OWN_LAST=0; ad_own_apply
for i in 1 2 3 4 5 6; do
    T_NOW=$((T_NOW + 50)); AD_BEBAN=2; ad_own_apply
    T_NOW=$((T_NOW + 50)); AD_BEBAN=3; ad_own_apply
    T_NOW=$((T_NOW + 50)); AD_BEBAN=1; ad_own_apply
done
chk "perubahan tercatat <= batas+turun" "$([ "$AD_OWN_N" -ge 3 ] && echo ok)" "ok"
T_NOW=$((T_NOW + 50)); AD_BEBAN=3; ad_own_apply
chk "batas tercapai: tidak naik lagi" "$(mn policy0)" "800000"
ad_own_off selesai

echo "== kernel menolak: jatuh ke perilaku lama"
T_NOW=4000; ad_own_on com.game.e; AD_BEBAN=2; AD_OWN_LAST=0
ad_wr() { :; }
ad_own_apply
chk "AD_OWN mati" "$AD_OWN" "0"
chk "penanda hilang" "$([ -f "$AD_OWN_FILE" ] && echo ada || echo hilang)" "hilang"
chk "fas-rs dilanjutkan" "$([ "$(st)" = T ] && echo beku || echo jalan)" "jalan"
chk "log mencatat" "$(grep -c 'kernel menolak lantai' "$T/log")" "1"
ad_wr() { printf '%s' "$2" > "$1" 2>/dev/null; }

echo "== sakelar ADAPT_OWN=off"
printf 'off\n' > "$AD_STATE/ADAPT_OWN"
ad_own_on com.game.f; r=$?
chk "ad_own_on ditolak" "$r" "1"
chk "tidak ada penanda" "$([ -f "$AD_OWN_FILE" ] && echo ada || echo tidak)" "tidak"
chk "fas-rs tidak dibekukan" "$(st)" "S"
rm -f "$AD_STATE/ADAPT_OWN"

echo "== penanda ada: gameboost dan engine tidak menyentuh frekuensi"
ad_own_on com.game.g
printf '1\n' > "$T/x_node"
mkdir -p "$T/n/cpufreq/policy0"; printf '500000\n' > "$T/n/cpufreq/policy0/scaling_min_freq"
: > "$T/log"
_gb_log() { printf '%s %s\n' "$1" "$2" >> "$T/gblog"; }
_gb_write "$T/n/cpufreq/policy0/scaling_min_freq" 900000 cpu
chk "gameboost tidak menulis" "$(cat "$T/n/cpufreq/policy0/scaling_min_freq")" "500000"
chk "gameboost mencatat SKIPPED" "$(grep -c 'Adapt memegang' "$T/gblog")" "1"
if ( . "$C/engine.sh" >/dev/null 2>&1; type apply_tweak >/dev/null 2>&1 ); then
    ( . "$C/engine.sh" >/dev/null 2>&1; LOG_FILE="$T/elog"; log_msg() { printf '%s %s %s\n' "$1" "$2" "$3" >> "$T/elog"; }
      apply_tweak cpu "$T/n/cpufreq/policy0/scaling_min_freq" 900000 >/dev/null 2>&1 )
    chk "engine tidak menulis" "$(cat "$T/n/cpufreq/policy0/scaling_min_freq")" "500000"
    chk "engine mencatat SKIPPED" "$(grep -c 'Adapt memegang' "$T/elog" 2>/dev/null)" "1"
fi
ad_own_off selesai

echo "== sesi lewat ad_tick: mulai, Puncak menang, selesai"
T_NOW=5000; T_FPS="60 60 16"
ad_tick com.game.h
chk "penanda ada setelah ad_tick" "$([ -f "$AD_OWN_FILE" ] && echo ada || echo tidak)" "ada"
chk "lantai awal 50%" "$(mn policy0)" "800000"
: > "$AD_STATE/.ovd_active"
T_NOW=5010; ad_tick com.game.h
chk "Puncak: penanda hilang" "$([ -f "$AD_OWN_FILE" ] && echo ada || echo hilang)" "hilang"
chk "Puncak: nilai asli kembali" "$(mn policy0)" "500000"
rm -f "$AD_STATE/.ovd_active"
T_NOW=5100; ad_tick com.game.h
chk "sesi baru setelah Puncak" "$([ -f "$AD_OWN_FILE" ] && echo ada || echo tidak)" "ada"
ad_tick com.other.app
chk "pindah app: selesai" "$([ -f "$AD_OWN_FILE" ] && echo ada || echo hilang)" "hilang"
chk "nilai asli kembali" "$(mn policy6)" "700000"
echo "== sisa penanda lama (crash) dipulihkan"
ad_own_on com.game.i; AD_OWN=0; AD_OPEN=0
printf '1100000\n' > "$T/cf/policy0/scaling_min_freq"
ad_own_recover
chk "recover: penanda hilang" "$([ -f "$AD_OWN_FILE" ] && echo ada || echo hilang)" "hilang"
chk "recover: nilai asli" "$(mn policy0)" "500000"

echo
echo "HASIL: $PASS lolos, $FAIL gagal"
[ "$FAIL" -eq 0 ]
