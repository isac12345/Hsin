#!/data/data/com.termux/files/usr/bin/sh
# HSIN - combo 9Router: "leader" (utama) + "agent" (2 subagent: modul & app).
#
# FAKTA DASAR (verified dari router, bukan asumsi):
# - 9Router TIDAK menyimpan data harga. Jadi "gratis" di sini berarti
#   tanpa biaya per-token: model openrouter ':free' (15 buah), provider
#   ber-oauth (antigravity/kiro/xai = kuota akun), dan ollama (lokal).
#   YANG BERBAYAR: nvidia & poolside (api key) -> TIDAK dipakai di sini.
# - Combo = JSON array id-model di kolom `combos.models`; URUTAN = prioritas
#   fallback. Nama combo harus unik.
# - Auth /api/* = session password. API key & cli-secret tidak berlaku (401).
#   Password dibaca interaktif, tidak disimpan, tidak masuk log.
#
# ATURAN FALLBACK (permintaan user): setelah model utama antigravity,
# SEMUA fallback wajib model GRATIS - yaitu openrouter ':free' dan ollama
# (lokal). Provider berbayar (nvidia, poolside apikey) tidak dipakai.
#
# CODEX (cx/*) sengaja TIDAK ada di rantai: kuota codex habis ~2 minggu
# dan bukan model gratis. Kalau kuota sudah pulih dan mau dipakai,
# tambahkan id-nya di ujung daftar (mis. "cx/gpt-5.5") -항 Urutan tetap
#utan: yang paling cepat/gründ paling dulu.
#
# Pemakaian:
#   sh tools/9router-combo.sh --dry-run     # cek semua model ada (tanpa auth)
#   sh tools/9router-combo.sh               # buat/pertahankan leader + agent
#   sh tools/9router-combo.sh --cleanup     # hapus combo bernama HSIN-* (lama)
#   sh tools/9router-combo.sh --base http://localhost:20128

BASE="${HSIN_9ROUTER_BASE:-http://localhost:20128}"
DRY=0
CLEAN=0
for _a in "$@"; do
    case "$_a" in
        --dry-run) DRY=1 ;;
        --cleanup) CLEAN=1 ;;
        --base) : ;;
    esac
done
# --base nilainya ada di argumen berikutnya
_prev=""
for _a in "$@"; do
    [ "$_prev" = "--base" ] && BASE="$_a"
    _prev="$_a"
done

# ---------------------------------------------------------------------------
# DATA - semua id di bawah WAJIB dicek ada di /v1/models sebelum combo dibuat
# (script otomatismemeriksa di langkah pre-flight).
# ---------------------------------------------------------------------------

# leader: model utama. Urutan = terbaik dulu.
LEADER_MODELS='[
  "ag/claude-sonnet-4-6",
  "ag/gemini-3.8-flash-high",
  "openrouter/deepseek/deepseek-v4-flash-0731:free",
  "openrouter/nvidia/nemotron-3-ultra-550b-a55b:free",
  "openrouter/thinkingmachines/inkling:free",
  "ollama/qwen3.5",
  "ollama/gpt-oss:120b"
]'

# agent: worker buat 2 subagent (modul + aplikasi). Prioritas ke yang cepat.
AGENT_MODELS='[
  "ag/gemini-3.8-flash-low",
  "openrouter/nvidia/nemotron-3.5-lightning:free",
  "openrouter/poolside/laguna-xs-2.1:free",
  "openrouter/nex-agi/nex-n2.5-mini:free",
  "openrouter/inclusionai/ling-3.0-flash-sante:free",
  "ollama/glm-4.7-flash"
]'

LEADER_NAME="leader"
AGENT_NAME="agent"

TMPDIR="${TMPDIR:-/data/data/com.termux/files/usr/tmp}"
mkdir -p "$TMPDIR" 2>/dev/null

command -v curl >/dev/null 2>&1 || { echo "ERROR: butuh curl" >&2; exit 1; }

# --- pre-flight: semua model harus benar-benar ada di router ---------------
_models_json() { curl -s -m 12 "$BASE/v1/models" 2>/dev/null; }

check_models() {
    _label="$1"; _models="$2"; _have="$3"; _bad=0
    echo "--- verifikasi model: $_label ---"
    for _m in $(printf '%s' "$_models" | tr -d '[]" ' | tr ',' ' '); do
        if printf '%s' "$_have" | grep -q "\"$_m\""; then
            printf '  OK      %s\n' "$_m"
        else
            printf '  HILANG  %s   <-- tidak ada di router\n' "$_m" >&2
            _bad=$((_bad + 1))
        fi
    done
    return $_bad
}

HAVE="$(_models_json)"
[ -n "$HAVE" ] || { echo "ERROR: tidak bisa membaca $BASE/v1/models" >&2; exit 1; }
echo "=== 9Router @ $BASE ==="
echo "model terdaftar: $(printf '%s' "$HAVE" | grep -o '"object":"model"' | wc -l | tr -d ' ')"
echo
check_models "$LEADER_NAME" "$LEADER_MODELS" "$HAVE" || {
    echo "ERROR: ada model leader yang tidak tersedia. Batal." >&2; exit 1; }
check_models "$AGENT_NAME" "$AGENT_MODELS" "$HAVE" || {
    echo "ERROR: ada model agent yang tidak tersedia. Batal." >&2; exit 1; }
echo

if [ "$DRY" = "1" ]; then
    echo "=== DRY RUN: tidak ada yang dikirim ==="
    echo "1) POST $BASE/api/auth/login  (password interaktif, tidak disimpan)"
    echo "2) POST $BASE/api/combos  name=$LEADER_NAME"
    printf '%s\n' "$LEADER_MODELS" | sed 's/^/     /'
    echo "3) POST $BASE/api/combos  name=$AGENT_NAME"
    printf '%s\n' "$AGENT_MODELS" | sed 's/^/     /'
    [ "$CLEAN" = "1" ] && echo "4) DELETE combo lama berawalan 'HSIN-' (kalau ada)"
    echo "5) GET  $BASE/api/combos  (verifikasi)"
    exit 0
fi

# --- login -----------------------------------------------------------------
printf 'Password 9Router (tidak disimpan): '
stty -echo 2>/dev/null
read -r PW
stty echo 2>/dev/null
printf '\n'
[ -n "$PW" ] || { echo "ERROR: password kosong" >&2; exit 1; }

JAR="$TMPDIR/hsin-9r-cookie.$$"
chmod 600 "$JAR" 2>/dev/null
trap 'rm -f "$JAR" "$TMPDIR/hsin-9r-*.out"' EXIT INT TERM

CODE=$(curl -s -m 15 -o "$TMPDIR/hsin-9r-login.out" -w '%{http_code}' \
    -c "$JAR" -H 'Content-Type: application/json' \
    -d "{\"password\":\"$PW\"}" "$BASE/api/auth/login")
PW=''
echo "login -> HTTP $CODE"
if [ "$CODE" != "200" ]; then
    echo "ERROR: login gagal. Body server:" >&2
    head -c 300 "$TMPDIR/hsin-9r-login.out" >&2; echo >&2
    echo "Kalau belum pernah set password, buka $BASE lalu atur password di halaman login." >&2
    exit 1
fi

api() { curl -s -m 15 -b "$JAR" -H 'Content-Type: application/json' "$@"; }

# --- cleanup combo lama (opsional, hanya yang berawalan HSIN-) -------------
if [ "$CLEAN" = "1" ]; then
    echo "--- combo yang ada sekarang ---"
    CUR=$(api "$BASE/api/combos")
    printf '%s' "$CUR" | grep -o '"name":"[^"]*"' | sed 's/"name":"/  - /;s/"$//'
    for _old in $(printf '%s' "$CUR" | grep -o '"name":"HSIN-[^"]*"' | sed 's/"name":"//;s/"$//'); do
        # id muncul SEBELUM name di JSON, jadi jangan pakai grep -A (itu
        # mencari ke bawah). Pecah per objek dulu, baru ambil id-nya.
        _oid=$(printf '%s' "$CUR" | tr '{' '\n' | grep "\"name\":\"$_old\"" | grep -o '"id":"[^"]*"' | head -1 | sed 's/"id":"//;s/"$//')
        if [ -n "$_oid" ]; then
            _dc=$(curl -s -m 10 -o /dev/null -w '%{http_code}' -b "$JAR" -X DELETE "$BASE/api/combos/$_oid")
            echo "  hapus '$_old' (id=$_oid) -> HTTP $_dc"
        else
            echo "  '$_old': id tidak terbaca, hapus manual di dashboard"
        fi
    done
    echo
fi

# --- buat / pertahankan combo ----------------------------------------------
put_combo() {
    _name="$1"; _models="$2"
    _body="{\"name\":\"$_name\",\"models\":$_models}"
    CODE=$(curl -s -m 15 -o "$TMPDIR/hsin-9r-create.out" -w '%{http_code}' \
        -b "$JAR" -H 'Content-Type: application/json' \
        -d "$_body" "$BASE/api/combos")
    case "$CODE" in
        200|201) echo "  '$_name' tersimpan (HTTP $CODE)" ;;
        409) echo "  '$_name' sudah ada & tidak bisa di-update lewat API" >&2
              echo "     hapus dulu di dashboard, lalu jalankan ulang" >&2; return 1 ;;
        *)   echo "  '$_name' GAGAL (HTTP $CODE): $(head -c 250 "$TMPDIR/hsin-9r-create.out")" >&2
             return 1 ;;
    esac
}

echo "--- combo ---"
put_combo "$LEADER_NAME" "$LEADER_MODELS" || exit 1
put_combo "$AGENT_NAME"  "$AGENT_MODELS"  || exit 1

echo "--- verifikasi ---"
FINAL=$(api "$BASE/api/combos")
for _n in "$LEADER_NAME" "$AGENT_NAME"; do
    if printf '%s' "$FINAL" | grep -q "\"name\":\"$_n\"\|\"id\":\"$_n\""; then
        echo "  OK  $_n"
    else
        echo "  PERIKSA  $_n tidak terlihat di /api/combos" >&2
    fi
done
echo
echo "Cek di dashboard: $BASE"
