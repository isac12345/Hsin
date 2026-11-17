#!/bin/sh
# Uji get_game_profile: game yang ditambahkan app dengan profil adapt|puncak harus
# tetap dikenali sebagai game. sh test_map.sh
D="$(cd "$(dirname "$0")" && pwd)"
C="${COMMON_DIR:-$D/../../module/common}"
T=$(mktemp -d "${TMPDIR:-/tmp}/map.XXXXXX"); trap 'rm -rf "$T"' EXIT
PASS=0; FAIL=0
chk() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; else FAIL=$((FAIL+1)); printf '  FAIL %s (dapat=[%s] harap=[%s])\n' "$1" "$2" "$3"; fi; }
sed -n '/^get_game_profile() {/,/^}/p' "$C/monitor.sh" > "$T/fn.sh"
. "$T/fn.sh"
cat > "$T/map" <<'M'
com.game.perf:performance
com.game.bal:balanced
com.game.bat:battery
com.game.adapt:adapt
com.game.puncak:puncak
com.game.ngawur:xyz
M
MAP_FILE="$T/map"
chk "performance" "$(get_game_profile com.game.perf)"  "performance"
chk "balanced"    "$(get_game_profile com.game.bal)"   "balanced"
chk "battery"     "$(get_game_profile com.game.bat)"   "battery"
chk "adapt jadi balanced" "$(get_game_profile com.game.adapt)" "balanced"
chk "puncak jadi performance" "$(get_game_profile com.game.puncak)" "performance"
chk "profil ngawur ditolak" "$(get_game_profile com.game.ngawur)" ""
chk "bukan game" "$(get_game_profile com.lain.app)" ""
echo "HASIL: $PASS lolos, $FAIL gagal"
[ "$FAIL" -eq 0 ]
