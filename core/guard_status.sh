#!/system/bin/sh
# HSIN Guard Status — READ-ONLY read of boot guard state.
# Tidak menulis apa pun. Tidak memanggil hsin_boot_guard_check.

HSIN_MODULE_PATH="${HSIN_MODULE_PATH:-/data/adb/modules/hsin}"
HSIN_DATA="${HSIN_DATA:-/data/adb/hsin}"
HSIN_GUARD_FILE="${HSIN_GUARD_FILE:-$HSIN_DATA/.boot_fail_count}"
HSIN_GUARD_THRESHOLD="${HSIN_GUARD_THRESHOLD:-2}"
HSIN_GUARD_COOLDOWN="${HSIN_GUARD_COOLDOWN:-86400}"

. "$HSIN_MODULE_PATH/core/boot_guard.sh" 2>/dev/null || {
    _hbg_read() {
        _HBG_TS=0; _HBG_COUNT=0
        [ -f "$HSIN_GUARD_FILE" ] || return 0
        _hbg_line=$(cat "$HSIN_GUARD_FILE" 2>/dev/null)
        _HBG_TS=$(printf '%s' "$_hbg_line" | cut -d: -f1 | tr -cd '0-9')
        _HBG_COUNT=$(printf '%s' "$_hbg_line" | cut -d: -f2 | tr -cd '0-9')
        if [ -z "$_HBG_COUNT" ] && [ -n "$_HBG_TS" ]; then
            _HBG_COUNT="$_HBG_TS"; _HBG_TS=0
        fi
        [ -z "$_HBG_TS" ] && _HBG_TS=0
        [ -z "$_HBG_COUNT" ] && _HBG_COUNT=0
        return 0
    }
    _hbg_threshold() {
        case "${HSIN_GUARD_THRESHOLD}" in ''|*[!0-9]*) printf '2\n'; return 0 ;; esac
        [ "$HSIN_GUARD_THRESHOLD" -ge 1 ] 2>/dev/null && printf '%s\n' "$HSIN_GUARD_THRESHOLD" || printf '2\n'
    }
    _hbg_now() { date +%s 2>/dev/null || printf '0\n'; }
}

hsin_guard_status() {
    # Baca state
    _hbg_read
    _thr=$(_hbg_threshold)
    _now=$(_hbg_now)

    # Sanitasi numerik
    _ts="$_HBG_TS"; case "$_ts" in ''|*[!0-9]*) _ts=0 ;; esac
    _count="$_HBG_COUNT"; case "$_count" in ''|*[!0-9]*) _count=0 ;; esac

    # Default: hilang / kosong / korup
    active=0
    fail_count=0
    threshold=$_thr
    cooldown_remaining_sec=0
    last_reason="tidak ada state"

    # Bila file tidak ada atau isi kosong semua karakter bukan angka
    [ -f "$HSIN_GUARD_FILE" ] || { active=0; fail_count=0; cooldown_remaining_sec=0; last_reason="tidak ada state"; }

    if [ -f "$HSIN_GUARD_FILE" ]; then
        _line=$(cat "$HSIN_GUARD_FILE" 2>/dev/null)
        _clean=$(printf '%s' "$_line" | tr -cd '0-9')
        if [ -n "$_clean" ]; then
            # Ada angka; periksa apakah format timestamp:count atau angka polos
            # Ekstrak ts dan count secara eksplisit
            _ts_raw=$(printf '%s' "$_line" | cut -d: -f1 | tr -cd '0-9')
            _count_raw=$(printf '%s' "$_line" | cut -d: -f2 | tr -cd '0-9')
            # Format lama angka polos (tidak ada colon) -> count = angka, ts = 0
            if echo "$_line" | grep -q ':' 2>/dev/null; then
                : # format timestamp:count
            else
                # Angka polos = format lama
                _count_raw="$_clean"
                _ts_raw=0
            fi
            # Sanitasi ulang setelah split
            case "$_ts_raw" in ''|*[!0-9]*) _ts_raw=0 ;; esac
            case "$_count_raw" in ''|*[!0-9]*) _count_raw=0 ;; esac
            _ts="$_ts_raw"
            _count="$_count_raw"
        else
            # Tidak ada angka sama sekali -> hilang / rusak
            _ts=0; _count=0
        fi
    else
        _ts=0; _count=0
    fi

    # Logika utama
    if [ "$_count" -gt 0 ]; then
        fail_count=$_count
        if [ "$_ts" -gt 0 ] && [ "$_now" -gt 0 ]; then
            _age=$((_now - _ts))
            if [ "$_age" -ge "$HSIN_GUARD_COOLDOWN" ]; then
                # Expired
                active=0
                fail_count=0
                cooldown_remaining_sec=0
                last_reason="tidak ada state"
            else
                # Belum expired
                if [ "$_count" -ge "$_thr" ]; then
                    active=1
                    _rem=$((HSIN_GUARD_COOLDOWN - _age))
                    [ "$_rem" -lt 0 ] 2>/dev/null && _rem=0
                    cooldown_remaining_sec=$_rem
                    last_reason="boot gagal ${_count} x berturut-turut"
                else
                    active=0
                    _rem=$((HSIN_GUARD_COOLDOWN - _age))
                    [ "$_rem" -lt 0 ] 2>/dev/null && _rem=0
                    cooldown_remaining_sec=$_rem
                    last_reason="boot gagal ${_count} x berturut-turut"
                fi
            fi
        else
            # ts tidak valid (0) -> belum bisa dinilai expired; perlakukan sebagai belum expired
            # tapi tetap pakai count
            if [ "$_count" -ge "$_thr" ]; then
                active=1
                fail_count=$_count
                cooldown_remaining_sec=0
                last_reason="boot gagal ${_count} x berturut-turut"
            else
                active=0
                fail_count=$_count
                cooldown_remaining_sec=0
                last_reason="boot gagal ${_count} x berturut-turut"
            fi
        fi
    else
        active=0
        fail_count=0
        cooldown_remaining_sec=0
        last_reason="tidak ada state"
    fi

    # Output key=value
    printf 'active=%s\n' "$active"
    printf 'fail_count=%s\n' "$fail_count"
    printf 'threshold=%s\n' "$threshold"
    printf 'cooldown_remaining_sec=%s\n' "$cooldown_remaining_sec"
    _reason_esc="$last_reason"
    _reason_esc=$(printf '%s' "$_reason_esc" | sed 's/\\/\\\\/g; s/"/\\"/g')
    printf 'last_reason="%s"\n' "$_reason_esc"

    printf '{"active":%s,"fail_count":%s,"threshold":%s,"cooldown_remaining_sec":%s,"last_reason":"%s"}\n' \
        "$active" "$fail_count" "$threshold" "$cooldown_remaining_sec" "$_reason_esc"
    return 0
}

return 0 2>/dev/null || true
