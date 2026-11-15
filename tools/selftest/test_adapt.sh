#!/bin/sh
# Uji beban adaptif global (adapt.sh): sh test_adapt.sh
# Diuji dengan nilai BAWAAN modul (bukan override), sesuai keputusan pengguna:
# tersendat -> naik maksimal 2 kali per sesi; lancar 60 dtk -> turun satu tingkat;
# suhu 48 C menahan kenaikan, 50 C memaksa turun; baterai <= 15% menahan;
# jeda 30 dtk antar perubahan; app diam tidak dihitung; bank/kamera dilewati;
# pindah app memulihkan kbase; catatan gabungan; batas app biasa 1, game 3;
# mode Puncak mematikan Adapt; sisa tingkat boost dibersihkan saat beban 0.
D="$(cd "$(dirname "$0")" && pwd)"
C="${COMMON_DIR:-$D/../../module/common}"
T=$(mktemp -d "${TMPDIR:-/tmp}/adapt.XXXXXX"); trap 'rm -rf "$T"' EXIT
PASS=0; FAIL=0
chk() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; else FAIL=$((FAIL+1)); printf '  FAIL %s (dapat=[%s] harap=[%s])\n' "$1" "$2" "$3"; fi; }

mkdir -p "$T/state" "$T/mod/mali_kbase/parameters" "$T/psi" "$T/power/battery" "$T/thermal/thermal_zone0"
P="$T/mod/mali_kbase/parameters"
printf '0\n' > "$P/gpu_boost_level2"; printf '8\n' > "$P/gpu_pollingtime"; printf '88\n' > "$P/gpu_upthreshold"
printf '361\n' > "$T/power/battery/temp"; printf '80\n' > "$T/power/battery/capacity"
printf '45000\n' > "$T/thermal/thermal_zone0/temp"
printf 'pkg=x\n' > "$T/fpsd.out"

export HSIN_CONF_DIR="$T/state" HSIN_LOG_FILE="$T/log" AD_DIR="$T/state/adapt"
export SYSFS_MODULE_PREFIX="$T/mod" SYSFS_POWER_PREFIX="$T/power"
export SYSFS_THERMAL_PREFIX="$T/thermal"
export AD_STATE="$T/state"
. "$C/gameboost.sh" 2>/dev/null
. "$C/adapt.sh"
AD_WARM_SECS=0   # uji lain tidak perlu menunggu pemanasan; diuji khusus di bawah

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
jank() { T_FPS="6 60 900"; T_PSI=5; T_MEM=2000000; }
lancar() { T_FPS="60 60 16"; T_PSI=5; T_MEM=2000000; }

echo "== app biasa tersendat: beban 0 -> 1"
T_NOW=1000; T_FPS="6 60 900"; T_PSI=70; T_MEM=2000000
ad_tick com.sosmed.a
chk "beban awal 0" "$AD_BEBAN" "0"
chk "belum naik di tick pertama" "$(conf com.sosmed.a beban)" ""
tick com.sosmed.a 8; tick com.sosmed.a 8
chk "beban jadi 1" "$(conf com.sosmed.a beban)" "1"
chk "kbase terpasang" "$(kb)" "0/4/75"

echo "== batas app biasa = 1"
tick com.sosmed.a 10; tick com.sosmed.a 10; tick com.sosmed.a 10
_b=$(conf com.sosmed.a beban)
chk "tidak lewat 1" "$([ "${_b:-0}" -le 1 ] && echo ya || echo tidak)" "ya"

echo "== suhu 48,5 C menahan kenaikan"
printf '485\n' > "$T/power/battery/temp"
rm -f "$AD_DIR/com.sosmed.a.conf"; printf 'beban=1\n' > "$AD_DIR/com.sosmed.a.conf"
AD_OPEN=0; T_NOW=2000; T_FPS="6 60 900"; T_PSI=70
tick com.sosmed.a 8; tick com.sosmed.a 8; tick com.sosmed.a 8
chk "tetap 1 karena suhu" "$(conf com.sosmed.a beban)" "1"

echo "== suhu 50,5 C memaksa turun"
printf '505\n' > "$T/power/battery/temp"
AD_OPEN=0; T_NOW=2500
tick com.sosmed.a 8
chk "turun ke 0 karena suhu kritis" "$(conf com.sosmed.a beban)" "0"
printf '361\n' > "$T/power/battery/temp"

echo "== baterai 10% menahan kenaikan (batas 15%)"
printf '10\n' > "$T/power/battery/capacity"
rm -f "$AD_DIR/com.sosmed.a.conf"; printf 'beban=1\n' > "$AD_DIR/com.sosmed.a.conf"
AD_OPEN=0; T_NOW=3000
tick com.sosmed.a 8; tick com.sosmed.a 8; tick com.sosmed.a 8
chk "tetap 1 karena baterai" "$(conf com.sosmed.a beban)" "1"
printf '80\n' > "$T/power/battery/capacity"

echo "== suhu otak HP 71 C menahan kenaikan"
AD_CHG_GAP=0
printf '71000\n' > "$T/thermal/thermal_zone0/temp"
rm -f "$AD_DIR/com.sosmed.h.conf"; printf 'beban=1\n' > "$AD_DIR/com.sosmed.h.conf"
T_FPS="6 60 900"; T_PSI=70
AD_OPEN=0; T_NOW=3500
tick com.sosmed.h 8; tick com.sosmed.h 8; tick com.sosmed.h 8
chk "tetap 1 karena panas otak" "$(conf com.sosmed.h beban)" "1"

echo "== suhu otak HP 76 C memaksa turun"
printf '76000\n' > "$T/thermal/thermal_zone0/temp"
AD_OPEN=0; T_NOW=3800
tick com.sosmed.h 8
chk "turun ke 0 karena panas otak" "$(conf com.sosmed.h beban)" "0"
printf '45000\n' > "$T/thermal/thermal_zone0/temp"
AD_CHG_GAP=30

echo "== lancar 60 detik: turun satu tingkat"
T_FPS="60 60 16"; T_PSI=5; T_MEM=2000000
AD_OPEN=0; T_NOW=4000
tick com.sosmed.a 30; tick com.sosmed.a 30; tick com.sosmed.a 30
chk "turun ke 0" "$(conf com.sosmed.a beban)" "0"
chk "kbase dipulihkan" "$(kb)" "0/8/88"

echo "== frame pacing patah walau FPS rata-rata 30 (30 -> 15)"
rm -f "$AD_DIR/com.pacing.conf"
T_FPS="15 30 40"; T_PSI=5; T_MEM=2000000
AD_OPEN=0; T_NOW=4500
tick com.pacing 8; tick com.pacing 8; tick com.pacing 8
chk "naik jadi 1" "$(conf com.pacing beban)" "1"

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
T_FPS="55 60 16"; T_PSI=5
tick com.gabung; tick com.gabung; ad_end
n1=$(conf com.gabung n)
AD_OPEN=0; T_NOW=30000
tick com.gabung; tick com.gabung; ad_end
n2=$(conf com.gabung n)
chk "jumlah sampel bertambah" "$([ "$n2" -gt "$n1" ] 2>/dev/null && echo ya || echo tidak)" "ya"
chk "jumlah sesi 2" "$(conf com.gabung sesi)" "2"
chk "satu berkas per app" "$(ls "$AD_DIR" | grep -c '^com.gabung.conf$')" "1"

echo "== catatan lama patah parah (jank >= 60%) dibuang seluruhnya"
rm -f "$AD_DIR/com.buruk.conf"
printf 'n=10\nsum_p1=150\njank_n=8\njank_pct=80\nbeban=1\n' > "$AD_DIR/com.buruk.conf"
AD_OPEN=0; T_NOW=35000
tick com.buruk
chk "jank_pct dihapus" "$(conf com.buruk jank_pct)" ""
chk "n dihapus" "$(conf com.buruk n)" ""

echo "== game: mulai beban 1, batas 3, kbase ditulis gameboost"
T_FPS="6 60 900"; T_PSI=70; DEVICE_TIER=low
AD_OPEN=0; T_NOW=40000
ad_tick com.game.x
chk "beban awal game 1" "$AD_BEBAN" "1"
chk "game tidak menulis kbase sendiri" "$(kb)" "0/8/88"

echo "== game: kenaikan yang menolong dipertahankan (boleh sampai 3)"
AD_CHG_GAP=0
rm -f "$AD_DIR/com.game.good.conf"
jank
AD_OPEN=0; T_NOW=41000
ad_tick com.game.good
chk "mulai beban 1" "$AD_BEBAN" "1"
tick com.game.good 30
chk "naik ke 2 karena tersendat" "$(conf com.game.good beban)" "2"
tick com.game.good 30                   # jendela baru: 1 sampel, belum dinilai
lancar; tick com.game.good 30
jank;   tick com.game.good 30           # 3 sampel, masih menunggu
lancar; tick com.game.good 30
jank;   tick com.game.good 30           # 5 sampel, 3 tersendat = 600/1000
chk "naik ke 2 menolong: tetap 2" "$(conf com.game.good beban)" "2"
chk "tingkat 2 dicatat menolong" "$AD_HELP_LVL" "2"
jank; tick com.game.good 30
chk "masih boleh naik ke 3" "$(conf com.game.good beban)" "3"
lancar; tick com.game.good 30; tick com.game.good 30
chk "lancar setelah naik = menolong: tetap 3" "$AD_HELP_LVL" "3"
chk "jatah naik habis" "$AD_RAISE_N" "2"
jank; for _i in 1 2 3; do tick com.game.good 30; done
chk "tersendat tapi tidak turun dari tingkat yang menolong" "$(conf com.game.good beban)" "3"

echo "== game: kenaikan yang tidak menolong tidak dicoba lagi"
rm -f "$AD_DIR/com.game.bad.conf"
T_FPS="6 60 900"; T_PSI=70; T_MEM=2000000
AD_OPEN=0; T_NOW=60000
ad_tick com.game.bad
tick com.game.bad 30
chk "naik ke 2 dulu" "$(conf com.game.bad beban)" "2"
tick com.game.bad 30; tick com.game.bad 30; tick com.game.bad 30; tick com.game.bad 30
chk "tidak menolong: balik ke 1" "$(conf com.game.bad beban)" "1"
chk "tingkat 2 dilewati" "$AD_BAD_LVL" "2"
chk "batas atas jadi 1" "$(ad_max_beban)" "1"
for _i in 1 2 3 4 5; do tick com.game.bad 30; done
chk "tidak naik ke 2 lagi" "$(conf com.game.bad beban)" "1"
chk "tidak ikut turun ke 0" "$(conf com.game.bad beban)" "1"

echo "== game tidak turun ke 0 saat lancar"
rm -f "$AD_DIR/com.game.one.conf"
T_FPS="60 60 16"; T_PSI=5; T_MEM=2000000
AD_OPEN=0; T_NOW=65000
ad_tick com.game.one
chk "mulai beban 1" "$AD_BEBAN" "1"
tick com.game.one 30; tick com.game.one 30; tick com.game.one 30
chk "lancar lama tetap di 1" "$AD_BEBAN" "1"

echo "== jeda minimal 30 detik antar perubahan"
AD_CHG_GAP=30
T_FPS="6 60 900"; T_PSI=70; T_MEM=2000000
rm -f "$AD_DIR/com.game.w.conf"
AD_OPEN=0; T_NOW=50000
ad_tick com.game.w
tick com.game.w 10; tick com.game.w 10
chk "naik ke 2" "$(conf com.game.w beban)" "2"
T_FPS="6 60 900"; T_PSI=70
tick com.game.w 10; tick com.game.w 10
chk "belum naik lagi (jeda)" "$(conf com.game.w beban)" "2"

echo "== awal sesi game: 90 detik pemanasan tidak memakai jatah"
AD_WARM_SECS=90
AD_CHG_GAP=0
rm -f "$AD_DIR/com.game.warm.conf"
T_FPS="6 60 900"; T_PSI=70; T_MEM=2000000
AD_OPEN=0; T_NOW=250000
ad_tick com.game.warm
tick com.game.warm 15; tick com.game.warm 15; tick com.game.warm 15
chk "belum naik saat pemanasan" "$AD_BEBAN" "1"
chk "jatah belum terpakai" "$AD_RAISE_N" "0"
tick com.game.warm 15; tick com.game.warm 15; tick com.game.warm 15
chk "naik setelah pemanasan" "$(conf com.game.warm beban)" "2"
AD_WARM_SECS=0
AD_CHG_GAP=30

echo "== sesi panjang: jatah naik diisi ulang tiap 10 menit main"
AD_CHG_GAP=0
rm -f "$AD_DIR/com.game.long.conf"
T_FPS="6 60 900"; T_PSI=70; T_MEM=2000000
AD_OPEN=0; T_NOW=200000
ad_tick com.game.long
chk "mulai beban 1" "$AD_BEBAN" "1"
# simulasi: jatah sudah habis dan sudah 10 menit main; dibuat lancar supaya
# tick ini hanya menguji pengisian ulang.
T_FPS="60 60 16"; T_PSI=5
AD_RAISE_N=2; AD_BAD_LVL=2; AD_LAST_RESET=$((T_NOW - 601))
tick com.game.long 30
chk "jatah naik diisi ulang" "$AD_RAISE_N" "0"
chk "tingkat sia-sia boleh dicoba lagi" "$AD_BAD_LVL" "0"
T_FPS="6 60 900"; T_PSI=70
tick com.game.long 30; tick com.game.long 30
chk "bisa naik lagi setelah 10 menit" "$(conf com.game.long beban)" "2"
AD_CHG_GAP=30

echo "== game boleh turun saat sudah lancar lama"
T_FPS="60 60 16"; T_PSI=5; T_MEM=2000000
AD_OPEN=0; T_NOW=60000
tick com.game.v 1
rm -f "$AD_DIR/com.game.v.conf"; printf 'beban=2\n' > "$AD_DIR/com.game.v.conf"
AD_OPEN=0; T_NOW=70000
tick com.game.v 30; tick com.game.v 30; tick com.game.v 30
chk "game turun ke 1" "$(conf com.game.v beban)" "1"

echo "== mode Puncak mematikan Adapt"
printf 'performance\n' > "$T/state/active_profile"
AD_OPEN=0; T_NOW=80000; T_FPS="6 60 900"; T_PSI=70
tick com.puncak.a 8; tick com.puncak.a 8; tick com.puncak.a 8
chk "tidak ada catatan" "$([ -f "$AD_DIR/com.puncak.a.conf" ] && echo ada || echo tidak)" "tidak"
chk "beban tidak berubah" "$AD_OPEN" "0"
rm -f "$T/state/active_profile"

echo "== RAM sempit saja tidak menaikkan beban GPU"
T_FPS="60 60 16"; T_PSI=5; T_MEM=300000
rm -f "$AD_DIR/com.ram.conf"
AD_OPEN=0; T_NOW=100000
tick com.ram 8; tick com.ram 8; tick com.ram 8
chk "tetap tanpa bantuan" "$(conf com.ram beban)" ""
chk "kbase tidak berubah" "$(kb)" "0/8/88"

echo "== ad_release (layar mati/tutup app) memulihkan kbase"
T_FPS="6 60 900"; T_PSI=70; T_MEM=2000000
rm -f "$AD_DIR/com.lepas.conf"
AD_OPEN=0; T_NOW=110000
tick com.lepas 8; tick com.lepas 8; tick com.lepas 8
chk "beban naik dulu" "$(conf com.lepas beban)" "1"
ad_release
chk "kbase pulih" "$(kb)" "0/8/88"
chk "sesi ditutup" "$AD_OPEN" "0"

echo "== nilai 'asli' yang tersimpan ternyata tingkat boost kita: kembali ke bawaan"
printf '1\n' > "$P/gpu_boost_level2"; printf '2\n' > "$P/gpu_pollingtime"; printf '55\n' > "$P/gpu_upthreshold"
AD_KBASE_OWN=1; AD_KB_SAVE1=1; AD_KB_SAVE2=2; AD_KB_SAVE3=55
ad_kbase_own_restore
chk "tidak menyalin sisa boost" "$(kb)" "0/8/88"

echo "== sisa tingkat boost padahal beban 0 dibersihkan"
printf '1\n' > "$P/gpu_boost_level2"; printf '2\n' > "$P/gpu_pollingtime"; printf '55\n' > "$P/gpu_upthreshold"
AD_OPEN=0; AD_KBASE_OWN=0; T_NOW=120000
printf 'beban=0\n' > "$AD_DIR/com.sisa.conf"
tick com.sisa
chk "kbase kembali bawaan" "$(kb)" "0/8/88"
ad_end

echo "== sisa campuran (0/2/55) juga dibersihkan"
printf '0\n' > "$P/gpu_boost_level2"; printf '2\n' > "$P/gpu_pollingtime"; printf '55\n' > "$P/gpu_upthreshold"
AD_OPEN=0; AD_KBASE_OWN=0; T_NOW=125000
printf 'beban=0\n' > "$AD_DIR/com.sisa2.conf"
tick com.sisa2
chk "campuran kembali bawaan" "$(kb)" "0/8/88"
ad_end
AD_KBASE_OWN=0

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
