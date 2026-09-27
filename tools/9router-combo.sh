#!/data/data/com.termux/files/usr/bin/sh
# HSIN - buat combo 9Router dari model GRATIS saja.
#
# Kenapa file ini perlu: 9Router tidak menyimpan data harga sama sekali, jadi
# "gratis" hanya bisa dibaca dari nama model id (suffix ":free"). Semua model
# di bawah diverifikasi ADA di /v1/models 9Router (15 model gratis, semua
# dari provider openrouter).
#
# Combo = satu nama yang berisi DAFTAR model-id; urutannya = prioritas
# fallback. Formatnya diambil dari skema SQLite 9Router sendiri:
#   combos(id, name UNIQUE, kind, models TEXT, createdAt, updatedAt)
# dengan `models` = JSON array dari id-model.
#
# AUTH: 9Router memakai session (password) untuk /api/*. API key tidak
# berlaku di sana (sudah diuji: 401). Jadi password dibaca interaktif
# (read -s), TIDAK disimpan di file, tidak masuk log, tidak di-commit.
#-stub 只有 dry-run yang jalan tanpa password.
#
# Pemakaian:
#   sh tools/9router-combo.sh --dry-run     # tampilkanrencana, tanpa network
#   sh tools/9router-combo.sh               # login + buat 2 combo + verifikasi
#   sh tools/9router-combo.sh --base http://localhost:20128
#
# Env: HSIN_9ROUTER_BASE (default http://localhost:20128)

BASE="${HSIN_9ROUTER_BASE:-http://localhost:20128}"
DRY=0
[ "$1" = "--dry-run" ] && DRY=1
case "$1" in --base) BASE="$2" ;; esac

# --- DATA: leader = kuat (ctx besar, reasoning+tools), subagent = cepat -----
# Semua id di bawah sudah dicek ada di /v1/models (JANGAN tambah id baru
# tanpa cek ulang, combo akan gagal saat dipakai).
LEADER_MODELS='[
  "openrouter/deepseek/deepseek-v4-flash-0731:free",
  "openrouter/nvidia/nemotron-3-ultra-550b-a55b:free",
  "openrouter/nvidia/nemotron-3-super-120b-a12b:free",
  "openrouter/thinkingmachines/inkling:free",
  "openrouter/nvidia/nemotron-3-nano-omni-30b-a3b-reasoning:free"
]'
SUBAGENT_MODELS='[
  "openrouter/nvidia/nemotron-3.5-lightning:free",
  "openrouter/poolside/laguna-xs-2.1:free",
  "openrouter/nex-agi/nex-n2.5-mini:free",
  "openrouter/inclusionai/ling-3.0-flash-sante:free",
  "openrouter/thinkingmachines/inkling-small:free"
]'
LEADER_NAME="HSIN-leader"
SUBAGENT_NAME="HSIN-subagent"

need() { command -v "$1" >/dev/null 2>&1 || { echo "ERROR: butuh '$1' (pkg install curl)" >&2; exit 1; }; }
need curl

# --- Verifikasi dulu: semua model benar-benar ada di router ----------------
verify_models() {
    _have=$(curl -s -m 10 "$BASE/v1/models" 2>/dev/null)
    [ -n "$_have" ] || { echo "ERROR: tidak bisa baca $BASE/v1/models" >&2; exit 1; }
    _missing=0
    for _m in $(printf '%s' "$1" | tr -d '[]" ' | tr ',' ' '); do
        if printf '%s' "$_have" | grep -q "\"$_m\""; then
            echo "  OK      $_m"
        else
            echo "  HILANG  $_m  <-- model ini tidak ada di router, jangan dipakai" >&2
            _missing=$((_missing + 1))
        fi
    done
    return $_missing
}

TMPDIR="${TMPDIR:-/data/data/com.termux/files/usr/tmp}"
mkdir -p "$TMPDIR" 2>/dev/null

echo "=== 9Router @ $BASE ==="
echo
echo "--- verifikasi model leader ---"
verify_models "$LEADER_MODELS" || { echo "ERROR: ada model leader yang tidak tersedia. Batal." >&2; exit 1; }
echo "--- verifikasi model subagent ---"
verify_models "$SUBAGENT_MODELS" || { echo "ERROR: ada model subagent yang tidak tersedia. Batal." >&2; exit 1; }
echo

if [ "$DRY" = "1" ]; then
    echo "=== DRY RUN: tidak ada yang dikirim ==="
    echo "1) POST $BASE/api/auth/login   (password dibaca interaktif, tidak disimpan)"
    echo "2) POST $BASE/api/combos  name=$LEADER_NAME"
    printf '%s\n' "$LEADER_MODELS" | sed 's/^/     /'
    echo "3) POST $BASE/api/combos  name=$SUBAGENT_NAME"
    printf '%s\n' "$SUBAGENT_MODELS" | sed 's/^/     /'
    echo "4) GET  $BASE/api/combos  (verifikasi hasil)"
    exit 0
fi

# --- Password (interaktif, tidak disimpan) ---------------------------------
printf 'Password 9Router (tidak disimpan, disembunyikan): '
stty -echo 2>/dev/null
read -r PW
stty echo 2>/dev/null
printf '\n'
[ -n "$PW" ] || { echo "ERROR: password kosong." >&2; exit 1; }

JAR="$TMPDIR/hsin-9r-cookie.$$.txt"
chmod 600 "$JAR" 2>/dev/null
cleanup() { rm -f "$JAR"; }
trap cleanup EXIT INT TERM

echo "--- login ---"
LOGIN_CODE=$(curl -s -m 15 -o "$TMPDIR/hsin-9r-login.out" -w '%{http_code}' \
    -c "$JAR" -H 'Content-Type: application/json' \
    -d "{\"password\":\"$PW\"}" "$BASE/api/auth/login")
PW=''
echo "  HTTP $LOGIN_CODE"
if [ "$LOGIN_CODE" != "200" ]; then
    echo "ERROR: login gagal. Body dari server:" >&2
    head -c 300 "$TMPDIR/hsin-9r-login.out" >&2
    echo >&2
    echo "Kalau 9Router belum punya password, set dulu di dashboard:" >&2
    echo "  $BASE  (login page) lalu ulangi perintah ini." >&2
    exit 1
fi

create_combo() {
    _name="$1"; _models="$2"
    _existing=$(curl -s -m 10 -b "$JAR" "$BASE/api/combos" 2>/dev/null)
    if printf '%s' "$_existing" | grep -q "\"$_name\""; then
        echo "  COMBO '$_name' sudah ada - dilewati (hapus dulu di dashboard bila ingin diganti)"
        return 0
    fi
    _body="{\"name\":\"$_name\",\"models\":$_models}"
    _code=$(curl -s -m 15 -o "$TMPDIR/hsin-9r-create.out" -w '%{http_code}' \
        -b "$JAR" -H 'Content-Type: application/json' -d "$_body" "$BASE/api/combos")
    echo "  create '$_name' -> HTTP $_code"
    [ "$_code" = "200" ] || [ "$_code" = "201" ] || {
        echo "  body: $(head -c 300 "$TMPDIR/hsin-9r-create.out")" >&2
        return 1
    }
    return 0
}

echo "--- buat combo ---"
create_combo "$LEADER_NAME" "$LEADER_MODELS"   || exit 1
create_combo "$SUBAGENT_NAME" "$SUBAGENT_MODELS" || exit 1

echo "--- verifikasi ---"
FINAL=$(curl -s -m 10 -b "$JAR" "$BASE/api/combos" 2>/dev/null)
for _n in "$LEADER_NAME" "$SUBAGENT_NAME"; do
    if printf '%s' "$FINAL" | grep -q "\"$_n\""; then
        echo "  OK  $_n ada di 9Router"
    else
        echo "  GAGAL  $_n tidak terlihat setelah dibuat" >&2
        exit 1
    fi
done
echo
echo "Selesai. Cek di dashboard: $BASE/combos"
