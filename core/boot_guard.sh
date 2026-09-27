#!/system/bin/sh
# HSIN Boot Guard — skip tuning bila boot gagal berturut-turut.
#
# Adaptasi pola fail-count + auto-disable + reset-on-success dari
# service.sh repo isac12345/Alpha (BOOT_FAIL_FILE/.boot_fail_count,
# threshold >= 2, skip + exit bersih, reset saat boot_completed=1),
# disesuaikan struktur HSIN: state format timestamp:count (bisa
# kedaluwarsa via cooldown), threshold/cooldown/file bisa di-override
# via env (untuk sandbox test), log via hsin_log_* bila tersedia
# (fallback stderr bila logger belum di-source).
#
# Kontrak return (konsisten di semua fungsi):
#   0 = aman, lanjut tuning | 1 = guard AKTIF, skip SEMUA tuning
#
# Dipakai service.sh (Step 6): check di awal boot, on_boot_failed bila
# boot_completed tak kunjung 1, on_boot_ok setelah modul jalan normal.

HSIN_DATA="${HSIN_DATA:-/data/adb/hsin}"
HSIN_GUARD_FILE="${HSIN_GUARD_FILE:-$HSIN_DATA/.boot_fail_count}"
HSIN_GUARD_THRESHOLD="${HSIN_GUARD_THRESHOLD:-2}"
HSIN_GUARD_COOLDOWN="${HSIN_GUARD_COOLDOWN:-86400}"

# Log internal: pakai logger HSIN bila sudah di-source, else stderr.
# (service.sh me-source logger.sh sebelum guard — Step 6; sandbox tanpa
# logger tetap jalan via fallback.)
_hbg_log() {
    _hbg_lvl="$1"
    _hbg_msg="$2"
    if command -v hsin_log_warn >/dev/null 2>&1 && command -v hsin_log_boot >/dev/null 2>&1; then
        case "$_hbg_lvl" in
            WARN) hsin_log_warn "boot_guard" "$_hbg_msg" ;;
            OK) hsin_log_ok "boot_guard" "$_hbg_msg" 2>/dev/null || hsin_log_boot "$_hbg_msg" ;;
            *) hsin_log_boot "$_hbg_msg" ;;
        esac
    else
        echo "[boot_guard] [$_hbg_lvl] $_hbg_msg" >&2
    fi
    return 0
}

# Normalisasi threshold: wajib angka >= 1, default 2 (perintah user).
_hbg_threshold() {
    case "$HSIN_GUARD_THRESHOLD" in
        ''|*[!0-9]*) printf '2\n'; return 0 ;;
    esac
    if [ "$HSIN_GUARD_THRESHOLD" -ge 1 ] 2>/dev/null; then
        printf '%s\n' "$HSIN_GUARD_THRESHOLD"
    else
        printf '2\n'
    fi
    return 0
}

_hbg_now() {
    date +%s 2>/dev/null || printf '0\n'
    return 0
}

# Baca state file -> _HBG_TS (timestamp) + _HBG_COUNT (angka aman).
# File korup/kosong = 0:0 (sanitize, bukan crash). Format lama Alpha
# (angka polos tanpa colon) tetap dibaca sebagai count.
_hbg_read() {
    _HBG_TS=0
    _HBG_COUNT=0
    [ -f "$HSIN_GUARD_FILE" ] || return 0
    _hbg_line=$(cat "$HSIN_GUARD_FILE" 2>/dev/null)
    _HBG_TS=$(printf '%s' "$_hbg_line" | cut -d: -f1 | tr -cd '0-9')
    _HBG_COUNT=$(printf '%s' "$_hbg_line" | cut -d: -f2 | tr -cd '0-9')
    if [ -z "$_HBG_COUNT" ] && [ -n "$_HBG_TS" ]; then
        _HBG_COUNT="$_HBG_TS"
        _HBG_TS=0
    fi
    [ -z "$_HBG_TS" ] && _HBG_TS=0
    [ -z "$_HBG_COUNT" ] && _HBG_COUNT=0
    return 0
}

# Tulis state atomik (tmp + mv) supaya reboot di tengah tulis tak korup.
_hbg_write() {
    _hbg_wts="$1"
    _hbg_wc="$2"
    mkdir -p "$HSIN_DATA" 2>/dev/null
    printf '%s:%s\n' "$_hbg_wts" "$_hbg_wc" > "$HSIN_GUARD_FILE.tmp.$$" 2>/dev/null \
        && mv -f "$HSIN_GUARD_FILE.tmp.$$" "$HSIN_GUARD_FILE" 2>/dev/null
    return $?
}

hsin_boot_guard_init() {
    mkdir -p "$HSIN_DATA" 2>/dev/null
    return 0
}

# Cek guard: 0 = lanjut tuning, 1 = AKTIF (skip semua tuning).
hsin_boot_guard_check() {
    _hbg_read
    _hbg_thr=$(_hbg_threshold)
    # State basi (lebih tua dari cooldown) = kedaluwarsa, reset otomatis.
    _hbg_now=$(_hbg_now)
    if [ "$_HBG_TS" -gt 0 ] && [ "$_hbg_now" -gt 0 ] \
        && [ $((_hbg_now - _HBG_TS)) -ge "$HSIN_GUARD_COOLDOWN" ]; then
        rm -f "$HSIN_GUARD_FILE" 2>/dev/null
        _hbg_log "OK" "stale guard state expired — counter reset ke 0"
        return 0
    fi
    if [ "$_HBG_COUNT" -ge "$_hbg_thr" ]; then
        _hbg_log "WARN" "BOOT-GUARD AKTIF: boot gagal $_HBG_COUNT x berturut-turut (threshold $_hbg_thr) — semua tuning DILEWATI, modul tidak melakukan apapun"
        return 1
    fi
    return 0
}

# Dipanggil saat boot DINYATAKAN gagal (service.sh: boot_completed tak
# kunjung 1). Return 1 = guard baru saja/jadi aktif (caller harus skip).
hsin_boot_guard_on_boot_failed() {
    _hbg_reason="${1:-boot_completed timeout}"
    _hbg_read
    _hbg_thr=$(_hbg_threshold)
    _hbg_new=$((_HBG_COUNT + 1))
    if _hbg_write "$(_hbg_now)" "$_hbg_new"; then
        :
    else
        _hbg_log "WARN" "gagal menulis guard state ($_hbg_reason) — counter tidak persisten"
        return 0
    fi
    if [ "$_hbg_new" -ge "$_hbg_thr" ]; then
        _hbg_log "WARN" "boot gagal $_hbg_new x berturut-turut ($_hbg_reason) — BOOT-GUARD AKTIF, tuning DILEWATI. Coba reboot, atau tunggu cooldown $HSIN_GUARD_COOLDOWN detik."
        return 1
    fi
    _hbg_log "INFO" "boot gagal $_hbg_new x ($_hbg_reason) — guard belum aktif (butuh $_hbg_thr x berturut-turut)"
    return 0
}

# Dipanggil setelah boot sukses DAN modul jalan normal (service.sh Step 6).
# Selalu return 0 — reset bukan kegagalan.
hsin_boot_guard_on_boot_ok() {
    if [ -f "$HSIN_GUARD_FILE" ]; then
        rm -f "$HSIN_GUARD_FILE" 2>/dev/null
        _hbg_log "OK" "boot sukses, modul jalan normal — fail counter reset ke 0"
    fi
    return 0
}
