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
echo
echo "HASIL: $PASS lolos, $FAIL gagal"
[ "$FAIL" -eq 0 ]
