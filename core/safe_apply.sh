#!/system/bin/sh
# HSIN Safe Apply — gateway 5 kategori untuk SEMUA tulis sysfs/proc.
#
# Referensi pola apply_tweak() repo isac12345/Alpha (common/engine.sh):
#   cek node exist -> cek writable -> write -> read-back -> compare ->
#   kategorikan hasil.
# Adaptasi HSIN (bukan copy-paste):
#   - TANPA chmod paksa (Alpha chmod 0644 bila tak writable; HSIN:
#     read-only = SKIPPED beralasan, bukan dipaksa).
#   - 5 kategori (Alpha biner APPLIED/FAILED):
#       APPLIED     write ok + read-back cocok
#       SKIPPED     node tidak ada ATAU node read-only (alasan di log)
#       UNAVAILABLE node ada tapi requested value tidak didukung dan
#                   tidak ada alternatif valid
#       FALLBACK    requested tak tersedia, alternatif valid dipakai
#       FAILED      node writable tapi write/read-back gagal
#   - Write+verify inti REUSE hsin_node_write_verify() yang SUDAH ADA di
#     core/sysfs.sh (tanpa duplikasi). File ini menambah kategorisasi +
#     logging + counter sesi. Pemanggil wajib source sysfs.sh dulu
#     (pola semua engine: . $HSIN_MODULE_PATH/core/sysfs.sh).
#   - Return code: 0 APPLIED, 2 SKIPPED, 3 UNAVAILABLE, 4 FALLBACK,
#     1 FAILED. Bukan biner sukses/gagal.
#
# Counter sesi: HSIN_SAFE_APPLIED / _SKIPPED / _UNAVAIL / _FALLBACK /
# _FAILED. Baca ringkasan via hsin_safe_apply_summary().

[ -z "$HSIN_MODULE_PATH" ] && HSIN_MODULE_PATH="/data/adb/modules/hsin"
# shellcheck disable=SC1091
. "$HSIN_MODULE_PATH/core/sysfs.sh" 2>/dev/null

HSIN_SAFE_APPLIED=0
HSIN_SAFE_SKIPPED=0
HSIN_SAFE_UNAVAIL=0
HSIN_SAFE_FALLBACK=0
HSIN_SAFE_FAILED=0

# Log sejelas boot_guard.sh: node mana, value apa, hasil apa + alasan.
# Pakai logger HSIN bila ada, else stderr (pola core/boot_guard.sh).
_hsa_log() {
    _hsa_res="$1"
    _hsa_cat="$2"
    _hsa_detail="$3"
    if command -v hsin_log_info >/dev/null 2>&1; then
        hsin_log_info "safe_apply" "[$_hsa_cat] $_hsa_detail -> $_hsa_res"
    else
        echo "[safe_apply] [$_hsa_cat] $_hsa_detail -> $_hsa_res" >&2
    fi
    return 0
}

_hsa_count() {
    case "$1" in
        0) HSIN_SAFE_APPLIED=$((HSIN_SAFE_APPLIED + 1)) ;;
        2) HSIN_SAFE_SKIPPED=$((HSIN_SAFE_SKIPPED + 1)) ;;
        3) HSIN_SAFE_UNAVAIL=$((HSIN_SAFE_UNAVAIL + 1)) ;;
        4) HSIN_SAFE_FALLBACK=$((HSIN_SAFE_FALLBACK + 1)) ;;
        *) HSIN_SAFE_FAILED=$((HSIN_SAFE_FAILED + 1)) ;;
    esac
    return "$1"
}

# Token exact-match dalam daftar spasi ("schedutil" cocok, "sched" tidak).
_hsa_token_in() {
    _hsa_tok="$1"
    _hsa_list="$2"
    [ -n "$_hsa_tok" ] || return 1
    case " $_hsa_list " in
        *" $_hsa_tok "*) return 0 ;;
    esac
    return 1
}

# Gateway utama: tulis value ke node. rc 0/2/1 (APPLIED/SKIPPED/FAILED).
hsin_safe_apply() {
    _hsa_node="$1"
    _hsa_val="$2"
    _hsa_cat="${3:-MISC}"
    if [ ! -e "$_hsa_node" ]; then
        _hsa_log "SKIPPED" "$_hsa_cat" "node=$_hsa_node value=$_hsa_val (node missing)"
        _hsa_count 2
        return 2
    fi
    if [ ! -w "$_hsa_node" ]; then
        _hsa_log "SKIPPED" "$_hsa_cat" "node=$_hsa_node value=$_hsa_val (read-only)"
        _hsa_count 2
        return 2
    fi
    if ! command -v hsin_node_write_verify >/dev/null 2>&1; then
        _hsa_log "FAILED" "$_hsa_cat" "node=$_hsa_node value=$_hsa_val (verify helper missing — source core/sysfs.sh dulu)"
        _hsa_count 1
        return 1
    fi
    if hsin_node_write_verify "$_hsa_node" "$_hsa_val" 2>/dev/null; then
        _hsa_log "APPLIED" "$_hsa_cat" "node=$_hsa_node value=$_hsa_val"
        _hsa_count 0
        return 0
    fi
    _hsa_log "FAILED" "$_hsa_cat" "node=$_hsa_node value=$_hsa_val (write rejected / read-back mismatch)"
    _hsa_count 1
    return 1
}

# Gateway tervalidasi: requested harus ada di allowed (daftar spasi).
# Tak ada di allowed + allowed kosong -> UNAVAILABLE (rc 3).
# Tak ada di allowed + ada alternatif -> tulis alternatif pertama ->
#   ok = FALLBACK (rc 4), gagal tulis = rc aslinya (SKIPPED/FAILED).
hsin_safe_apply_validated() {
    _hsa_node="$1"
    _hsa_req="$2"
    _hsa_allowed="$3"
    _hsa_cat="${4:-MISC}"
    if [ ! -e "$_hsa_node" ]; then
        _hsa_log "SKIPPED" "$_hsa_cat" "node=$_hsa_node value=$_hsa_req (node missing)"
        _hsa_count 2
        return 2
    fi
    if _hsa_token_in "$_hsa_req" "$_hsa_allowed"; then
        hsin_safe_apply "$_hsa_node" "$_hsa_req" "$_hsa_cat"
        return $?
    fi
    if [ -z "$_hsa_allowed" ]; then
        _hsa_log "UNAVAILABLE" "$_hsa_cat" "node=$_hsa_node value=$_hsa_req (unsupported, no valid alternative)"
        _hsa_count 3
        return 3
    fi
    _hsa_alt="${_hsa_allowed%% *}"
    hsin_safe_apply "$_hsa_node" "$_hsa_alt" "$_hsa_cat"
    _hsa_rc=$?
    if [ "$_hsa_rc" -eq 0 ]; then
        _hsa_log "FALLBACK" "$_hsa_cat" "node=$_hsa_node requested=$_hsa_req used=$_hsa_alt"
        # Koreksi counter: hsin_safe_apply tadi hitung APPLIED, pindah ke FALLBACK.
        HSIN_SAFE_APPLIED=$((HSIN_SAFE_APPLIED - 1))
        _hsa_count 4
        return 4
    fi
    return "$_hsa_rc"
}

# Satu baris ringkasan sesi ke log (pola counter Alpha, 5 kategori HSIN).
hsin_safe_apply_summary() {
    _hsa_ctx="${1:-apply}"
    if command -v hsin_log_info >/dev/null 2>&1; then
        hsin_log_info "safe_apply" "summary($_hsa_ctx): APPLIED=$HSIN_SAFE_APPLIED SKIPPED=$HSIN_SAFE_SKIPPED UNAVAILABLE=$HSIN_SAFE_UNAVAIL FALLBACK=$HSIN_SAFE_FALLBACK FAILED=$HSIN_SAFE_FAILED"
    else
        echo "[safe_apply] summary($_hsa_ctx): APPLIED=$HSIN_SAFE_APPLIED SKIPPED=$HSIN_SAFE_SKIPPED UNAVAILABLE=$HSIN_SAFE_UNAVAIL FALLBACK=$HSIN_SAFE_FALLBACK FAILED=$HSIN_SAFE_FAILED" >&2
    fi
    return 0
}

return 0 2>/dev/null || true
