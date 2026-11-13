#!/bin/sh
# Uji mode baru (2 mode: adapt & puncak) + harian tanpa patok buatan.
#   sh test_profil.sh
D="$(cd "$(dirname "$0")" && pwd)"
C="${COMMON_DIR:-$D/../../module/common}"
PASS=0; FAIL=0
chk() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; else FAIL=$((FAIL+1)); printf '  FAIL %s (dapat=[%s] harap=[%s])\n' "$1" "$2" "$3"; fi; }

. "$C/profiles.sh" 2>/dev/null
# autoctl.sh itu daemon (sourcing = jalan lalu exit), jadi hanya definisi
# valid_profile yang diambil supaya yang diuji tetap baris aslinya.
eval "$(grep '^valid_profile()' "$C/autoctl.sh")"

echo "== adapt = harian tanpa patok"
load_profile adapt
chk "internal" "$ACTIVE_PROFILE" "battery"
chk "gpu max" "$GPU_FREQ_MAX_PERCENT" "100"
chk "devfreq max" "$DEVFREQ_MAX_PERCENT" "100"
chk "cpu max" "$CPU_FREQ_MAX_PERCENT" "100"

echo "== puncak = performa penuh"
load_profile puncak
chk "internal" "$ACTIVE_PROFILE" "performance"
chk "gpu max" "$GPU_FREQ_MAX_PERCENT" "100"

echo "== nama lama tetap jalan (APK versi sekarang tidak rusak)"
for _m in battery balanced performance; do
    load_profile "$_m"
    chk "lama $_m" "$ACTIVE_PROFILE" "$_m"
done

echo "== nama ngawur tetap jatuh ke balanced"
load_profile ngawur 2>/dev/null
chk "fallback" "$ACTIVE_PROFILE" "balanced"

echo "== validasi profil menerima dua mode"
valid_profile adapt && valid_profile puncak && chk "valid" "ya" "ya" || chk "valid" "tidak" "ya"
valid_profile hemat 2>/dev/null && chk "tolak ngawur" "terima" "tolak" || chk "tolak ngawur" "tolak" "tolak"

echo
echo "HASIL: $PASS lolos, $FAIL gagal"
[ "$FAIL" -eq 0 ]
