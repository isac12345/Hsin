#!/bin/sh
# Uji beban adaptif global (adapt.sh):  sh test_adapt.sh
# Aturan yang diuji: tersendat -> naik; lancar -> turun; app diam (fps rendah)
# tidak dihitung; suhu >= 50 C dan baterai <= 10% menahan kenaikan; aplikasi
# bank/kamera dilewati; pindah aplikasi memulihkan kbase; catatan digabung
# (bukan per sesi); batas beban app biasa 2, game 3.
D="$(cd "$(dirname "$0")" && pwd)"
C="${COMMON_DIR:-$D/../../module/common}"
T=$(mktemp -d "${TMPDIR:-/tmp}/adapt.XXXXXX"); trap 'rm -rf "$T"' EXIT
PASS=0; FAIL=0
chk() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; else FAIL=$((FAIL+1)); printf '  FAIL %s (dapat=[%s] harap=[%s])\n' "$1" "$2" "$3"; fi; }

mkdir -p "$T/state" "$T/mod/mali_kbase/parameters" "$T/psi" "$T/power/battery"
P="$T/mod/mali_kbase/parameters"
printf '0\n' > "$P/gpu_boost_level2"; printf '8\n' > "$P/gpu_pollingtime"; printf '88\n' > "$P/gpu_upthreshold"
printf '361\n' > "$T/power/battery/temp"; printf '80\n' > "$T/power/battery/capacity"
# fpsd palsu: 1% low, fps rata-rata, jeda -- diisi ulang tiap uji
printf 'pkg=x\n' > "$T/fpsd.out"
# PSI/RAM dari berkas uji supaya hasilnya tetap
mkdir -p "$T/proc"

export HSIN_CONF_DIR="$T/state" HSIN_LOG_FILE="$T/log" AD_DIR="$T/state/adapt"
export SYSFS_MODULE_PREFIX="$T/mod" SYSFS_POWER_PREFIX="$T/power"
export AD_STATE="$T/state"
. "$C/gameboost.sh" 2>/dev/null
. "$C/adapt.sh"
AD_NONGAME_MAX=2; AD_RAISE_SECS=15; AD_TEMP_MAX=50000

# ganti pembacaan PSI/RAM dengan nilai uji
ad_psi() { printf '%s' "${T_PSI:-5}"; }
ad_memavail_kb() { printf '%s' "${T_MEM:-2000000}"; }
monitor_fps_stat() { printf '%s' "${T_FPS:-60 60 16}"; }
get_game_profile() { case "$1" in com.game.*) printf 'performance' ;; *) : ;; esac; }
ad_in_call() { return 1; }
date() { if [ -n "$T_NOW" ]; then printf '%s\n' "$T_NOW"; else command date "$@"; fi; }

kb() { printf '%s/%s/%s' "$(cat "$P/gpu_boost_level2")" "$(cat "$P/gpu_pollingtime")" "$(cat "$P/gpu_upthreshold")"; }
tick() { T_NOW=$((T_NOW + ${2:-7})); ad_tick "$1"; }
conf() { sed -n "s/^$2=//p" "$AD_DIR/$1.conf" 2>/dev/null | tail -1; }

echo "== app sosial tersendat 16 dtk: beban 0 -> 1"
T_NOW=1000; T_FPS="6 60 900"; T_PSI=70; T_MEM=2000000
ad_tick com.sosmed.a
chk "beban awal 0" "$AD_BEBAN" "0"
chk "belum naik di tick pertama" "$(conf com.sosmed.a beban)" ""
tick com.sosmed.a 8; tick com.sosmed.a 8
chk "beban jadi 1" "$(conf com.sosmed.a beban)" "1"
chk "kbase terpasang" "$(kb)" "0/4/75"

echo "== lanjut tersendat: naik ke 2 (batas app biasa)"
tick com.sosmed.a 8; tick com.sosmed.a 8; tick com.sosmed.a 8
chk "beban 2" "$(conf com.sosmed.a beban)" "2"
chk "kbase beban 2" "$(kb)" "1/2/55"
tick com.sosmed.a 8; tick com.sosmed.a 8; tick com.sosmed.a 8
chk "tidak lewat 2" "$(conf com.sosmed.a beban)" "2"

echo "== suhu 50 C menahan kenaikan"
printf '500\n' > "$T/power/battery/temp"
rm -f "$AD_DIR/com.sosmed.a.conf"; printf 'beban=1\n' > "$AD_DIR/com.sosmed.a.conf"
AD_OPEN=0
T_NOW=2000
tick com.sosmed.a 8; tick com.sosmed.a 8; tick com.sosmed.a 8
chk "tetap 1 karena suhu" "$(conf com.sosmed.a beban)" "1"

echo "== baterai 10% menahan kenaikan"
printf '361\n' > "$T/power/battery/temp"; printf '10\n' > "$T/power/battery/capacity"
rm -f "$AD_DIR/com.sosmed.a.conf"; printf 'beban=1\n' > "$AD_DIR/com.sosmed.a.conf"
AD_OPEN=0; T_NOW=3000
tick com.sosmed.a 8; tick com.sosmed.a 8; tick com.sosmed.a 8
chk "tetap 1 karena baterai" "$(conf com.sosmed.a beban)" "1"
printf '80\n' > "$T/power/battery/capacity"

echo "== lancar lama: beban turun"
T_FPS="60 60 16"; T_PSI=5; T_MEM=2000000
AD_OPEN=0; T_NOW=4000
tick com.sosmed.a 25; tick com.sosmed.a 25; tick com.sosmed.a 25
chk "turun ke 0" "$(conf com.sosmed.a beban)" "0"
chk "kbase dipulihkan" "$(kb)" "0/8/88"

echo "== aplikasi diam (fps 4) tidak dihitung tersendat"
T_FPS="4 4 900"; T_PSI=5; T_MEM=2000000
AD_OPEN=0; T_NOW=5000
tick com.baca.b 8; tick com.baca.b 8; tick com.baca.b 8
chk "dipantau tapi tanpa bantuan" "$(conf com.baca.b beban)" ""
chk "kbase tidak diubah" "$(kb)" "0/8/88"

echo "== PSI tinggi walau layar diam: dianggap perlu ditolong"
T_FPS=""; T_PSI=70
AD_OPEN=0; T_NOW=6000
tick com.sosmed.c 8; tick com.sosmed.c 8; tick com.sosmed.c 8
chk "naik jadi 1" "$(conf com.sosmed.c beban)" "1"

echo "== bank dan kamera tidak disentuh"
T_FPS="6 60 900"; T_PSI=70
for p in com.bca.bank com.android.camera2 id.co.bri.brimo; do
    AD_OPEN=0; T_NOW=$((T_NOW + 100))
    tick "$p"
    chk "lewati $p" "$([ -f "$AD_DIR/$p.conf" ] && echo ada || echo tidak)" "tidak"
done

echo "== pindah aplikasi: kbase pulih, catatan per app terpisah"
T_FPS="6 60 900"; T_PSI=70
AD_OPEN=0; T_NOW=9000
tick com.sosmed.d 8; tick com.sosmed.d 8; tick com.sosmed.d 8
chk "beban d" "$(conf com.sosmed.d beban)" "1"
chk "kbase dipasang" "$(kb)" "0/4/75"
T_FPS="60 60 16"; T_PSI=5
tick com.sosmed.e
chk "kbase pulih saat pindah" "$(kb)" "0/8/88"
chk "catatan e ada" "$([ -f "$AD_DIR/com.sosmed.e.conf" ] && echo ada || echo tidak)" "ada"

echo "== catatan digabung, bukan per sesi"
AD_OPEN=0; T_NOW=20000
rm -f "$AD_DIR/com.gabung.conf"
T_FPS="30 60 100"
tick com.gabung; tick com.gabung; ad_end
n1=$(conf com.gabung n)
AD_OPEN=0; T_NOW=30000
tick com.gabung; tick com.gabung; ad_end
n2=$(conf com.gabung n)
chk "jumlah sampel bertambah" "$([ "$n2" -gt "$n1" ] 2>/dev/null && echo ya || echo tidak)" "ya"
chk "jumlah sesi 2" "$(conf com.gabung sesi)" "2"
chk "satu berkas per app" "$(ls "$AD_DIR" | grep -c '^com.gabung.conf$')" "1"

echo "== game: batas beban 3, kbase ditulis gameboost"
T_FPS="6 60 900"; T_PSI=70; DEVICE_TIER=low
AD_OPEN=0; T_NOW=40000
ad_tick com.game.x
chk "beban awal game (selalu 2)" "$AD_BEBAN" "2"
chk "game tidak menulis kbase sendiri" "$(kb)" "0/8/88"

echo "== RAM sempit saja tidak menaikkan beban GPU"
T_FPS="60 60 16"; T_PSI=5; T_MEM=300000
rm -f "$AD_DIR/com.ram.conf"
AD_OPEN=0; T_NOW=60000
tick com.ram 8; tick com.ram 8; tick com.ram 8
chk "tetap tanpa bantuan" "$(conf com.ram beban)" ""
chk "kbase tidak berubah" "$(kb)" "0/8/88"

echo "== ad_release (layar mati/tutup app) memulihkan kbase"
T_FPS="6 60 900"; T_PSI=70; T_MEM=2000000
rm -f "$AD_DIR/com.lepas.conf"
AD_OPEN=0; T_NOW=50000
tick com.lepas 8; tick com.lepas 8; tick com.lepas 8
chk "beban naik dulu" "$(conf com.lepas beban)" "1"
ad_release
chk "kbase pulih" "$(kb)" "0/8/88"
chk "sesi ditutup" "$AD_OPEN" "0"

echo "== jank_pct tidak lebih dari 100 (data lama korup)"
mkdir -p "$AD_DIR"
printf 'n=2
sum_p1=24
jank_n=5
' > "$AD_DIR/com.korup.conf"
AD_PKG=com.korup; AD_SN=0; AD_SS=0; AD_SJ=0; AD_SMIN=""; AD_SSTALL=0
ad_save
chk "jank_pct maksimal 100" "$(conf com.korup jank_pct)" "100"
AD_PKG=""

echo
echo "HASIL: $PASS lolos, $FAIL gagal"
[ "$FAIL" -eq 0 ]
