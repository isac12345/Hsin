#!/system/bin/sh
# HSIN + Uperf + fas-rs Fusion
# Sinkronkan [game_list] di fas-rs games.toml -> exclusion rule "Alpha-FasrsManaged"
# di uperf.json, supaya package yang sudah didaftarkan ke fas-rs otomatis TIDAK
# lagi disentuh cpuset-nya oleh uperf (menghindari rebutan thread classification).
#
# Aturan pilih-engine: cukup edit [game_list] di fas-rs/games.toml.
#   - Package ADA di [game_list]      -> dipegang fas-rs, uperf otomatis skip.
#   - Package TIDAK ADA di [game_list] -> tetap dipegang uperf seperti biasa.
# Tidak perlu file konfigurasi terpisah; games.toml adalah satu-satunya sumber.
#
# Dipanggil dengan 2 argumen: $1 = path games.toml, $2 = path uperf.json (live)

FASRS_TOML="$1"
UPERF_JSON="$2"
PLACEHOLDER="ALPHA_NO_GAMES_YET_PLACEHOLDER"

[ -f "$FASRS_TOML" ] || exit 0
[ -f "$UPERF_JSON" ] || exit 0

# Ambil baris di dalam section [game_list] sampai section berikutnya (atau EOF),
# lalu ambil nama package (teks di antara tanda kutip pertama tiap baris).
# Hanya pakai sed (tanpa awk/jq) supaya aman di busybox minimal.
pkg_list=$(sed -n '/^\[game_list\]/,/^\[/p' "$FASRS_TOML" | sed -n 's/^"\([^"]*\)".*/\1/p')

if [ -z "$pkg_list" ]; then
    regex_val="$PLACEHOLDER"
else
    regex_val=""
    for pkg in $pkg_list; do
        # Titik dibiarkan: sed sudah tidak bisa menulis backslash lewat
        # replacement, dan pola "com.a.b" tetap cocok dengan nama paket asli.
        if [ -z "$regex_val" ]; then
            regex_val="$pkg"
        else
            regex_val="$regex_val|$pkg"
        fi
    done
fi

LOG="${HSIN_LOG_FILE:-/data/adb/hsin/hsin.log}"

# Tulis lalu BACA BALIK. Tanpa ini, sed yang gagal senyap membuat uperf dan
# fas-rs sama-sama menangani game yang sama (temuan T22).
set_regex() {
    sed -i '/"name": "Alpha-FasrsManaged"/{n;s#"regex": *".*"#"regex": "'"$regex_val"'"#
}' "$UPERF_JSON"
}

read_regex() {
    sed -n '/"name": "Alpha-FasrsManaged"/{n;s/.*"regex": *"\([^"]*\)".*/\1/p;}' "$UPERF_JSON" 2>/dev/null | head -n 1
}

set_regex
_ur=$(read_regex)
[ "$_ur" = "$regex_val" ] || set_regex
_ur=$(read_regex)
if [ "$_ur" != "$regex_val" ]; then
    printf '[%s] [UPERF] [FAILED] regex exclusion uperf tidak sesuai (dapat=%s harap=%s)\n' \
        "$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date)" "${_ur:-kosong}" "${regex_val:-kosong}" >> "$LOG" 2>/dev/null
    exit 1
fi
printf '[%s] [UPERF] [APPLIED] regex exclusion=%s\n' \
    "$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date)" "${regex_val:-kosong}" >> "$LOG" 2>/dev/null
exit 0
