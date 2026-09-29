#!/system/bin/sh
# HSIN IO Engine - Readahead Management

[ -z "$HSIN_MODULE_PATH" ] && HSIN_MODULE_PATH="/data/adb/modules/hsin"
. "$HSIN_MODULE_PATH/core/sysfs.sh" 2>/dev/null
# shellcheck disable=SC1091
. "$HSIN_MODULE_PATH/core/safe_apply.sh" 2>/dev/null
. "$HSIN_MODULE_PATH/core/logger.sh" 2>/dev/null
# Override knob user (readahead per block) + hasil per knob.
. "$HSIN_MODULE_PATH/core/user_knobs.sh" 2>/dev/null
# shellcheck disable=SC1091
. "$HSIN_MODULE_PATH/core/scan_cache.sh" 2>/dev/null
# hsin_io_block_devs() (daftar block cache-first) ada di scheduler.sh, file
# pertama yang di-source io_manager.sh. Kalau file ini di-source sendiri,
# scheduler.sh tetap diambil.
command -v hsin_io_block_devs >/dev/null 2>&1 || \
    . "$HSIN_MODULE_PATH/engine/io/scheduler.sh" 2>/dev/null

# Apply read_ahead_kb for profile (K1: knob user per block device).
hsin_io_apply_readahead() {
    _profile="$1"
    _is_manual=0
    [ "$_profile" = "manual" ] && _is_manual=1

    case "$_profile" in
        battery)     _ra="128" ;;
        balanced)    _ra="512" ;;
        performance) _ra="2048" ;;
        extreme)     _ra="4096" ;;
        manual)      _ra="" ;;
    esac

    _ok=0
    _skip=0

    hsin_io_block_devs
    for _b in $HSIN_IO_BLOCKS; do
        _name="${_b##*/}"

        # Kunci knob = sanitasi nama (pola _uk_sanitize, sama dengan aplikasi).
        _uk_sanitize "$_name"
        _ra_key="io_block_${_uk_sn}_readahead"

        # Node hilang sejak scan - skip + log, bukan crash.
        if [ ! -d "$_b" ]; then
            hsin_report_skip "readahead: block $_name hilang sejak scan"
            _ra_req=$(hsin_uk_get "$_ra_key" 2>/dev/null)
            [ -n "$_ra_req" ] || { [ "$_is_manual" = "1" ] && _ra_req="(manual)" || _ra_req="(profil)"; }
            hsin_uk_result "$_ra_key" "$_ra_req" "-" "UNAVAILABLE" "block hilang sejak scan" 2>/dev/null || true
            _skip=$((_skip + 1))
            continue
        fi

        case "$_name" in
            loop*|ram*|zram*|dm-*) continue ;;
        esac

        # Override knob user. Engine CEK ULANG preset di sini (pola tfo):
        # file bisa diedit tangan di luar knob-set.
        _uk_ra=$(hsin_uk_get "$_ra_key" 2>/dev/null)
        _fb=0
        _fb_req=""
        if [ -n "$_uk_ra" ]; then
            case "$_uk_ra" in
                128|256|512|1024|2048|4096|8192) ;;
                *)
                    hsin_log_warn "io" "override $_ra_key=$_uk_ra ditolak: bukan preset 128/256/512/1024/2048/4096/8192"
                    if [ "$_is_manual" = "1" ]; then
                        hsin_uk_result "$_ra_key" "$_uk_ra" "-" "SKIPPED" "ditolak: bukan preset (mode manual, tidak ditulis)" 2>/dev/null || true
                        _skip=$((_skip + 1))
                        continue
                    fi
                    _fb_req="$_uk_ra"
                    _uk_ra=""
                    _fb=1
                    ;;
            esac
        fi

        if [ -n "$_uk_ra" ]; then
            _wval="$_uk_ra"
            _is_uk=1
        elif [ "$_is_manual" = "1" ]; then
            hsin_uk_result "$_ra_key" "(manual)" "-" "SKIPPED" "tidak diatur (mode manual)" 2>/dev/null || true
            continue
        else
            _wval="$_ra"
            _is_uk=0
        fi

        # File node hilang: UNAVAILABLE beralasan, tanpa crash.
        if [ ! -f "$_b/queue/read_ahead_kb" ]; then
            hsin_report_skip "readahead: $_name/read_ahead_kb hilang"
            hsin_uk_result "$_ra_key" "$_wval" "-" "UNAVAILABLE" "node read_ahead_kb hilang" 2>/dev/null || true
            _skip=$((_skip + 1))
            continue
        fi

        # Tulis via safe_apply gateway (Step 6): kategorisasi
        # APPLIED/SKIPPED/FAILED + log per node, bukan echo buta.
        # rc: 0 APPLIED, 2 SKIPPED (read-only/hilang), 1 FAILED.
        hsin_safe_apply "$_b/queue/read_ahead_kb" "$_wval" "IO_READAHEAD"
        _rc=$?
        case "$_rc" in
            0)
                _ok=$((_ok + 1))
                if [ "$_is_uk" = "1" ]; then
                    hsin_uk_used "io" "$_ra_key" "$_wval"
                elif [ "$_fb" = "1" ]; then
                    hsin_uk_result "$_ra_key" "$_fb_req" "$_wval" "FALLBACK" "ditolak: bukan preset, pakai profil" 2>/dev/null || true
                else
                    hsin_uk_result "$_ra_key" "(profil)" "$_wval" "APPLIED" "nilai profil (tanpa override)" 2>/dev/null || true
                fi
                ;;
            2)
                _skip=$((_skip + 1))
                if [ "$_is_uk" = "1" ]; then
                    hsin_log_warn "io" "override $_ra_key=$_wval tidak terpasang: node read-only atau hilang"
                    hsin_uk_result "$_ra_key" "$_wval" "-" "UNAVAILABLE" "node read-only atau hilang" 2>/dev/null || true
                fi
                ;;
            *)
                _skip=$((_skip + 1))
                hsin_log_warn "io" "readahead $_name tulis $_wval gagal (verify)"
                hsin_uk_result "$_ra_key" "$_wval" "-" "FAILED" "tulis/readback gagal" 2>/dev/null || true
                ;;
        esac
    done

    _ra_disp="${_ra:-$_is_manual}"
    echo "    Readahead [$_ra_disp KB]: ok=$_ok skip=$_skip"
    hsin_log_info "io" "readahead src=$HSIN_IO_BLOCK_SOURCE ra_kb=$_ra_disp ok=$_ok skip=$_skip"
    return 0
}

# Get current readahead state
hsin_io_readahead_state() {
    echo "  Readahead State:"
    hsin_io_block_devs
    for _b in $HSIN_IO_BLOCKS; do
        [ -d "$_b" ] || continue
        _name="${_b##*/}"
        case "$_name" in
            loop*|ram*|zram*|dm-*) continue ;;
        esac
        [ -f "$_b/queue/read_ahead_kb" ] || continue
        _ra=$(hsin_node_read "$_b/queue/read_ahead_kb")
        printf "    %-15s %s KB\n" "$_name" "$_ra"
    done
}

return 0 2>/dev/null || true
