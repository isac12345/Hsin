#!/bin/sh
# Uji beban adaptif (adapt.sh):  sh test_adapt.sh
# Aturan: sesi jelek -> beban naik; sesi bagus -> turun; batas 0..3; aplikasi
# sehat tidak dicatat; kbase ditulis lewat gameboost (satu penulis) dan
# dipulihkan; ganti paket menutup sesi lama; data FPS sampah diabaikan.
D="$(cd "$(dirname "$0")" && pwd)"
C="${COMMON_DIR:-$D/../../module/common}"
T=$(mktemp -d "${TMPDIR:-/tmp}/adapt.XXXXXX"); trap 'rm -rf "$T"' EXIT
PASS=0; FAIL=0
chk() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; else FAIL=$((FAIL+1)); printf '  FAIL %s (dapat=[%s] harap=[%s])\n' "$1" "$2" "$3"; fi; }

mkdir -p "$T/state" "$T/mod/mali_kbase/parameters" "$T/logdir"
printf '0\n' > "$T/mod/mali_kbase/parameters/gpu_boost_level2"
printf '8\n' > "$T/mod/mali_kbase/parameters/gpu_pollingtime"
printf '88\n' > "$T/mod/mali_kbase/parameters/gpu_upthreshold"

export HSIN_CONF_DIR="$T/state"
export HSIN_LOG_FILE="$T/log"
export AD_DIR="$T/state/adapt"
export SYSFS_MODULE_PREFIX="$T/mod"
. "$C/gameboost.sh" 2>/dev/null
. "$C/adapt.sh"

echo "== game baru di HP lemah: beban 3, kbase 1/1/30"
DEVICE_TIER=low
ad_begin com.uji.a
chk "beban" "$AD_BEBAN" "3"
chk "kbase tertulis" "$(cat "$T/mod/mali_kbase/parameters/gpu_boost_level2")/$(cat "$T/mod/mali_kbase/parameters/gpu_pollingtime")/$(cat "$T/mod/mali_kbase/parameters/gpu_upthreshold")" "1/1/30"

echo "== sesi jelek di batas atas: tetap 3"
FPS_LAST_P1=10; FPS_LAST_STALL=900
ad_tick com.uji.a; ad_tick com.uji.a; ad_tick com.uji.a
ad_end
chk "beban tetap" "$(sed -n 's/^beban=//p' "$AD_DIR/com.uji.a.conf")" "3"
chk "jank tercatat" "$(sed -n 's/^jank_pct=//p' "$AD_DIR/com.uji.a.conf")" "100"
chk "stall tercatat" "$(sed -n 's/^stall_max=//p' "$AD_DIR/com.uji.a.conf")" "900"
chk "kbase dipulihkan" "$(cat "$T/mod/mali_kbase/parameters/gpu_boost_level2")/$(cat "$T/mod/mali_kbase/parameters/gpu_pollingtime")/$(cat "$T/mod/mali_kbase/parameters/gpu_upthreshold")" "0/8/88"

echo "== sesi jelek dari beban 1: naik ke 2"
sed -i 's/^beban=.*/beban=1/' "$AD_DIR/com.uji.a.conf"
ad_begin com.uji.a
chk "beban dipakai" "$AD_BEBAN" "1"
chk "kbase beban 1" "$GB_KBASE_BOOST/$GB_KBASE_POLL/$GB_KBASE_UP" "0/4/75"
FPS_LAST_P1=8; ad_tick com.uji.a; ad_tick com.uji.a
ad_end
chk "beban naik" "$(sed -n 's/^beban=//p' "$AD_DIR/com.uji.a.conf")" "2"

echo "== sesi bagus: turun"
FPS_LAST_P1=55; FPS_LAST_STALL=40
ad_begin com.uji.a
ad_tick com.uji.a; ad_tick com.uji.a
ad_end
chk "beban turun" "$(sed -n 's/^beban=//p' "$AD_DIR/com.uji.a.conf")" "1"
chk "rata-rata" "$(sed -n 's/^p1_avg=//p' "$AD_DIR/com.uji.a.conf")" "55"

echo "== HP kuat: beban awal 1, kbase ringan"
DEVICE_TIER=high
ad_begin com.uji.b
chk "beban awal high" "$AD_BEBAN" "1"
chk "kbase high" "$GB_KBASE_BOOST/$GB_KBASE_POLL/$GB_KBASE_UP" "0/4/75"
FPS_LAST_P1=60
ad_tick com.uji.b; ad_tick com.uji.b
ad_end
chk "sesi bagus menurunkan ke 0" "$(sed -n 's/^beban=//p' "$AD_DIR/com.uji.b.conf")" "0"

echo "== beban 0: nilai paling adem"
DEVICE_TIER=mid
printf 'beban=0\n' >> "$AD_DIR/com.uji.b.conf"
ad_begin com.uji.b
chk "beban 0" "$AD_BEBAN" "0"
chk "kbase 0" "$GB_KBASE_BOOST/$GB_KBASE_POLL/$GB_KBASE_UP" "0/8/88"
FPS_LAST_P1=60
ad_end

# Semua paket uji dianggap game terdaftar; aplikasi biasa diuji terpisah
get_game_profile() { case "$1" in com.uji.*) printf 'performance' ;; *) : ;; esac; }

echo "== aplikasi biasa: tidak disentuh sama sekali"
FPS_LAST_P1=3
ad_tick com.app.biasa
chk "tidak ada sesi" "$AD_OPEN" "0"
chk "tidak ada berkas" "$([ -f "$AD_DIR/com.app.biasa.conf" ] && echo ada || echo tidak)" "tidak"

echo "== aplikasi sehat tanpa riwayat: tidak dicatat (daily tetap ringan)"
FPS_LAST_P1=58
ad_tick com.uji.sehat
ad_tick com.uji.sehat
chk "tidak ada sesi" "$AD_OPEN" "0"
chk "tidak ada berkas" "$([ -f "$AD_DIR/com.uji.sehat.conf" ] && echo ada || echo tidak)" "tidak"

echo "== aplikasi sehat tapi sudah punya riwayat: tetap dinilai"
FPS_LAST_P1=58
ad_tick com.uji.a
chk "sesi dibuka" "$AD_OPEN" "1"
ad_end

echo "== ganti paket: sesi lama ditutup dulu"
ad_begin com.uji.c
FPS_LAST_P1=5
ad_tick com.uji.c
ad_begin com.uji.d
chk "paket baru aktif" "$AD_PKG" "com.uji.d"
chk "sesi lama tercatat" "$(sed -n 's/^beban=//p' "$AD_DIR/com.uji.c.conf")" "3"

echo "== data FPS sampah diabaikan"
ad_begin com.uji.e
FPS_LAST_P1=""
ad_tick com.uji.e; ad_tick com.uji.e
chk "kosong diabaikan" "$AD_N" "0"
FPS_LAST_P1="abc"
ad_tick com.uji.e
chk "teks bukan angka diabaikan" "$AD_N" "0"
ad_end

echo
echo "HASIL: $PASS lolos, $FAIL gagal"
[ "$FAIL" -eq 0 ]
