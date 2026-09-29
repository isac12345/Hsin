#!/system/bin/sh
# HSIN IO Engine - Block Queue Tuning (K2)
#
# MENGAPA file ini terpisah dari scheduler.sh / readahead.sh: ketiga node
# ini (add_random, iostats, nomerges) adalah atribut queue per block
# device yang TIDAK punya nilai profil di profiles/*.conf, jadi tidak ada
# jalur tulis yang bisa "dipinjam" dari file lain. Semuanya read-only
# sampai user benar-benar set override.
#
# Kontrak:
#   - Value user hanya 0 atau 1 (keputusan K2; kedua nilai diterima
#     kernel pada semua driver block modern). File override dicek ULANG di
#     sini, bukan hanya di hsin_uk_val_ok, supaya file yang diisi manual
#     di luar modul tidak bisa menulis angka lain.
#   - Node hilang / read-only = UNAVAILABLE + alasan, bukan crash, dan
#     node lain tidak boleh ikut ditulis.
#   - Mode manual tanpa override = nol penulisan untuk ketiga knob ini.
#   - Blok yang tidak boleh disentuh: loop/ram/zram/dm-* (sudah disaring
#     hsin_io_block_devs) plus blok removable/boot yang ditandai
#     HSIN_IO_SKIP_BLOCKS (dipakai modul untuk mengecualikan volume
#     eksternal; kosong = semua block riil ikut).
#
# Sumber nilai: user_knobs.sh (kunci io_block_<n>_add_random|iostats|
# nomerges), penulisan lewat hsin_safe_apply supaya kategorisasi tetap
# satu sumber (pola readahead.sh).

[ -z "$HSIN_MODULE_PATH" ] && HSIN_MODULE_PATH="/data/adb/modules/hsin"
# shellcheck disable=SC1091
. "$HSIN_MODULE_PATH/core/sysfs.sh" 2>/dev/null
# shellcheck disable=SC1091
. "$HSIN_MODULE_PATH/core/safe_apply.sh" 2>/dev/null
. "$HSIN_MODULE_PATH/core/logger.sh" 2>/dev/null
. "$HSIN_MODULE_PATH/core/user_knobs.sh" 2>/dev/null
# hsin_io_block_devs() ada di scheduler.sh (file pertama yang di-source
# io_manager.sh). Kalau file ini di-source sendiri, scheduler.sh tetap diambil.
command -v hsin_io_block_devs >/dev/null 2>&1 || \
    . "$HSIN_MODULE_PATH/engine/io/scheduler.sh" 2>/dev/null

# Volume yang tidak boleh disentuh (nama basename, dipisah spasi). Kosong =
# tidak ada pengecualian. Diisi modul, bukan hardcode per device.
HSIN_IO_SKIP_BLOCKS="${HSIN_IO_SKIP_BLOCKS:-}"

# Daftar field yang ditangani file ini, urut = urutan apply.
_HSIN_QT_FIELDS="add_random iostats nomerges"

# Terapkan ketiga knob queue untuk satu block device.
# $1 = path block, $2 = basename, $3 = profile, $4 = mode manual (0/1)
_hsin_io_queue_one() {
    _qt_b="$1"
    _qt_name="$2"
    _qt_profile="$3"
    _qt_manual="$4"
    # Dikembalikan lewat global (bukan echo) supaya pemanggil bisa
    # menjumlahkan tanpa menangkap stdout fungsi ini.
    _HSIN_QT_ONE_OK=0
    _HSIN_QT_ONE_SKIP=0

    # Sanitasi nama = pola _uk_sanitize (sama dengan aplikasi).
    _uk_sanitize "$_qt_name"

    for _qt_f in $_HSIN_QT_FIELDS; do
        _qt_key="io_block_${_uk_sn}_${_qt_f}"
        _qt_node="$_qt_b/queue/$_qt_f"
        _qt_uk=$(hsin_uk_get "$_qt_key" 2>/dev/null)
        _qt_req="(manual)"
        [ "$_qt_manual" = "1" ] || _qt_req="(profil)"

        # Validasi ulang di engine (pola tfo): file bisa diisi manual.
        # nomerges punya 3 nilai sah (0/1/2), dua knob lain boolean.
        if [ -n "$_qt_uk" ]; then
            _qt_bad=1
            case "$_qt_uk" in
                0|1) _qt_bad=0 ;;
                2)
                    [ "$_qt_f" = "nomerges" ] && _qt_bad=0
                    ;;
            esac
            if [ "$_qt_bad" = "1" ]; then
                if [ "$_qt_f" = "nomerges" ]; then
                    hsin_log_warn "io" "override $_qt_key=$_qt_uk ditolak: harus 0, 1, atau 2"
                    _qt_why="ditolak: harus 0/1/2"
                else
                    hsin_log_warn "io" "override $_qt_key=$_qt_uk ditolak: harus 0 atau 1"
                    _qt_why="ditolak: bukan 0/1"
                fi
                if [ "$_qt_manual" = "1" ]; then
                    hsin_uk_result "$_qt_key" "$_qt_uk" "-" "SKIPPED" "$_qt_why (mode manual, tidak ditulis)" 2>/dev/null || true
                else
                    hsin_uk_result "$_qt_key" "$_qt_uk" "-" "FALLBACK" "$_qt_why, tidak ada nilai profil" 2>/dev/null || true
                fi
                _qt_uk=""
            fi
        fi

        if [ -z "$_qt_uk" ]; then
            # Tanpa override: di manual dilewati; di profil tidak ada nilai
            # profil untuk ketiga knob ini, jadi tidak ada yang ditulis.
            if [ "$_qt_manual" = "1" ]; then
                hsin_uk_result "$_qt_key" "$_qt_req" "-" "SKIPPED" "tidak diatur (mode manual)" 2>/dev/null || true
            fi
            continue
        fi

        if [ ! -f "$_qt_node" ]; then
            hsin_report_skip "queue_tuning: $_qt_name/queue/$_qt_f hilang"
            hsin_uk_result "$_qt_key" "$_qt_uk" "-" "UNAVAILABLE" "node queue/$_qt_f hilang" 2>/dev/null || true
            _HSIN_QT_ONE_SKIP=$((_HSIN_QT_ONE_SKIP + 1))
            continue
        fi

        # rc: 0 APPLIED, 2 SKIPPED (read-only/hilang), 1 FAILED.
        hsin_safe_apply "$_qt_node" "$_qt_uk" "IO_QUEUE"
        _qt_rc=$?
        case "$_qt_rc" in
            0)
                _HSIN_QT_ONE_OK=$((_HSIN_QT_ONE_OK + 1))
                hsin_uk_used "io" "$_qt_key" "$_qt_uk"
                ;;
            2)
                _HSIN_QT_ONE_SKIP=$((_HSIN_QT_ONE_SKIP + 1))
                hsin_log_warn "io" "override $_qt_key=$_qt_uk tidak terpasang: node read-only"
                hsin_uk_result "$_qt_key" "$_qt_uk" "-" "UNAVAILABLE" "node read-only" 2>/dev/null || true
                ;;
            *)
                _HSIN_QT_ONE_SKIP=$((_HSIN_QT_ONE_SKIP + 1))
                hsin_log_warn "io" "queue_tuning $_qt_name $_qt_f=$_qt_uk gagal (verify)"
                hsin_uk_result "$_qt_key" "$_qt_uk" "-" "FAILED" "tulis/readback gagal" 2>/dev/null || true
                ;;
        esac
    done
    return 0
}

# Entry point: $1 = profile.
hsin_io_apply_queue_tuning() {
    _qt_profile="$1"
    _qt_manual=0
    [ "$_qt_profile" = "manual" ] && _qt_manual=1

    _qt_ok=0
    _qt_skip=0
    hsin_io_block_devs
    for _qt_b in $HSIN_IO_BLOCKS; do
        [ -d "$_qt_b" ] || continue
        _qt_name="${_qt_b##*/}"
        case "$_qt_name" in loop*|ram*|zram*|dm-*) continue ;; esac
        # Pengecualian volume (mis. eksternal) bila diisi modul.
        case " $HSIN_IO_SKIP_BLOCKS " in
            *" $_qt_name "*) continue ;;
        esac
        _hsin_io_queue_one "$_qt_b" "$_qt_name" "$_qt_profile" "$_qt_manual"
        _qt_ok=$((_qt_ok + _HSIN_QT_ONE_OK))
        _qt_skip=$((_qt_skip + _HSIN_QT_ONE_SKIP))
    done

    echo "    Queue tuning [add_random/iostats/nomerges]: applied=$_qt_ok skip=$_qt_skip"
    return 0
}

# State: nilai live ketiga node per block (untuk knobs JSON + status).
# Cetak satu baris per field: "<name> <field> <cur> <writable> <supported>"
hsin_io_queue_state() {
    hsin_io_block_devs
    for _qt_b in $HSIN_IO_BLOCKS; do
        [ -d "$_qt_b" ] || continue
        _qt_name="${_qt_b##*/}"
        case "$_qt_name" in loop*|ram*|zram*|dm-*) continue ;; esac
        for _qt_f in $_HSIN_QT_FIELDS; do
            _qt_node="$_qt_b/queue/$_qt_f"
            if [ -r "$_qt_node" ]; then
                _qt_cur=$(hsin_node_read "$_qt_node")
                [ -w "$_qt_node" ] && _qt_w=true || _qt_w=false
                printf '%s %s %s %s true\n' "$_qt_name" "$_qt_f" "${_qt_cur:-0}" "$_qt_w"
            else
                printf '%s %s 0 false false\n' "$_qt_name" "$_qt_f"
            fi
        done
    done
    return 0
}

return 0 2>/dev/null || true
