#!/system/bin/sh
# HSIN Memory Engine - zRAM Engine

[ -z "$HSIN_MODULE_PATH" ] && HSIN_MODULE_PATH="/data/adb/modules/hsin"
. "$HSIN_MODULE_PATH/core/logger.sh" 2>/dev/null
# Override knob user (zram_algo).
. "$HSIN_MODULE_PATH/core/user_knobs.sh" 2>/dev/null
# shellcheck disable=SC1091
. "$HSIN_MODULE_PATH/core/scan_cache.sh" 2>/dev/null
[ -n "$HSIN_SYSFS_BLOCK" ] || HSIN_SYSFS_BLOCK="${SYSFS_BLOCK_PREFIX:-/sys/block}"
# hsin_mem_zram_names() (daftar nama zram tanpa glob /sys/block/zram*)
# defined di detect.sh; file ini di-source setelahnya oleh apply.sh, tapi
# kalau di-source sendiri detect.sh tetap diambil.
command -v hsin_mem_zram_names >/dev/null 2>&1 || \
    . "$HSIN_MODULE_PATH/engine/memory/detect.sh" 2>/dev/null

# Detect zRAM devices
hsin_zram_detect() {
    HSIN_ZRAM_LIST=""
    HSIN_ZRAM_COUNT=0

    # Nama device dari module param kernel (hsin_mem_zram_names), bukan
    # glob /sys/block/zram*; nilai dibaca live dari sysfs tiap detect
    # (HSIN hanya menulis comp_algorithm, bukan disksize).
    hsin_mem_zram_names
    for _name in $HSIN_MEM_ZRAM_NAMES; do
        _dev="$HSIN_SYSFS_BLOCK/$_name"
        if [ ! -d "$_dev" ]; then
            hsin_log_warn "memory" "zRAM: $_name hilang sejak probe (skip)"
            continue
        fi

        _size=""
        [ -f "$_dev/disksize" ] && IFS= read -r _size < "$_dev/disksize" 2>/dev/null

        _algo=""
        [ -f "$_dev/comp_algorithm" ] && IFS= read -r _algo < "$_dev/comp_algorithm" 2>/dev/null

        _max_streams=""
        [ -f "$_dev/max_comp_streams" ] && IFS= read -r _max_streams < "$_dev/max_comp_streams" 2>/dev/null

        _writable="false"
        [ -w "$_dev/comp_algorithm" ] && _writable="true"

        HSIN_ZRAM_LIST="${HSIN_ZRAM_LIST}${_name}|${_size}|${_algo}|${_max_streams}|${_writable}
"
        HSIN_ZRAM_COUNT=$((HSIN_ZRAM_COUNT + 1))
    done
}

# Get recommended swappiness for profile
hsin_zram_swappiness() {
    _profile="$1"
    case "$_profile" in
        battery)     echo "120" ;;
        balanced)    echo "100" ;;
        performance) echo "60" ;;
        extreme)     echo "40" ;;
        *)           echo "100" ;;
    esac
}

# Get recommended compression algorithm for profile
hsin_zram_algo() {
    _profile="$1"
    case "$_profile" in
        battery)     echo "zstd" ;;
        balanced)
            # Try zstd first, fallback to lz4
            hsin_mem_zram_names
            for _name in $HSIN_MEM_ZRAM_NAMES; do
                _algo_file="$HSIN_SYSFS_BLOCK/$_name/comp_algorithm"
                [ -f "$_algo_file" ] || continue
                _avail=""
                IFS= read -r _avail < "$_algo_file" 2>/dev/null
                # Lepas [siku] aktif HANYA untuk cek dukungan (readback
                # tetap ketat di hsin_zram_algo_live).
                _avail_nosq=$(printf '%s' "$_avail" | tr -d '[]')
                case " $_avail_nosq " in
                    *" zstd "*) echo "zstd"; return 0 ;;
                    *" lz4 "*)  echo "lz4"; return 0 ;;
                esac
            done
            echo "lz4"
            ;;
        performance) echo "lz4" ;;
        extreme)     echo "lz4" ;;
        *)           echo "lz4" ;;
    esac
}

# hsin_zram_algo_live() - cek apakah algo target benar-benar AKTIF di node
# comp_algorithm. Isi node bukan cuma daftar algo yang didukung: kernel
# menandai algo yang SEDANG DIPAKAI di dalam kurung siku ("lz4 deflate
# [zstd] lzo "), jadi target yang cuma muncul sebagai token biasa belum
# tentu aktif - itu bentuk paling umum dari kernel menolak tulis diam-diam
# (mis. zram sudah dipakai / EBUSY) yang shell tetap laporkan exit 0.
# Aturan: (1) target di dalam kurung siku = aktif, (2) isi node sama persis
# dengan target = aktif (node yang show hanya nilai saat ini). Selain itu
# belum terkonfirmasi. Nilai live disimpan di HSIN_ZRAM_LIVE supaya bisa
# dicantumkan di log saat tak terkonfirmasi.
hsin_zram_algo_live() {
    _zal_t="$1"
    _zal_mark="[$_zal_t]"
    HSIN_ZRAM_LIVE=""
    # 2>/dev/null ditulis sebelum redirect: kalau node hilang di antara tulis
    # dan readback, shell tidak sempat suppress pesan "cannot open".
    IFS= read -r HSIN_ZRAM_LIVE 2>/dev/null < "$2"
    case "$HSIN_ZRAM_LIVE" in
        *"$_zal_mark"*) return 0 ;;
        "$_zal_t")     return 0 ;;
    esac
    return 1
}

# Apply zRAM settings for profile
hsin_zram_apply() {
    _profile="$1"

    # HSIN_ZRAM_COUNT/LIST hanya diisi hsin_zram_detect, sementara jalur
    # apply (hsin_mem_apply) memanggil hsin_mem_detect yang mengisi
    # HSIN_MEM_ZRAM_COUNT/LIST. Akibatnya var zram kosong di tengah apply
    # dan comp_algorithm tak pernah ditulis. Kalau detect menemukan device,
    # probe ulang di sini supaya list + flag writable selalu live; kalau
    # zram memang absen, jatuh ke "not available" (aman, tanpa tulis).
    _zcount="${HSIN_ZRAM_COUNT:-0}"
    case "$_zcount" in ''|*[!0-9]*) _zcount=0 ;; esac
    if [ "$_zcount" -eq 0 ] && [ "${HSIN_MEM_ZRAM_COUNT:-0}" -gt 0 ] 2>/dev/null; then
        hsin_zram_detect
        _zcount="${HSIN_ZRAM_COUNT:-0}"
        case "$_zcount" in ''|*[!0-9]*) _zcount=0 ;; esac
    fi
    [ "$_zcount" -gt 0 ] || { echo "    zRAM: not available"; return 0; }

    # Mode manual: hanya terapkan override; tanpa override, lewati semua penulisan.
    if [ "$_profile" = "manual" ]; then
        _uk_algo=$(hsin_uk_get zram_algo 2>/dev/null)
        if [ -z "$_uk_algo" ]; then
            echo "    zRAM: dilewati (mode manual, tanpa override)"
            hsin_uk_result "zram_algo" "(manual)" "-" "SKIPPED" "tidak diatur (mode manual)" 2>/dev/null || true
            return 0
        fi
    fi

    _target_algo=$(hsin_zram_algo "$_profile")
    # Override knob user (zram_algo) hanya dipakai kalau algo itu ada di
    # daftar algo yang DIDUKUNG node - dicek sekali di sini supaya keputusan
    # dipakai/tidak dilaporkan sekali, bukan sekali per device. Cek per
    # node dan readback ketat hsin_zram_algo_live di loop bawah tetap
    # berlaku apa pun nilai _algo hasil detect, jadi override tidak
    # pernah melewati validasi yang sudah ada.
    _uk_algo=$(hsin_uk_get zram_algo 2>/dev/null)
    if [ -n "$_uk_algo" ]; then
        _uk_algo_ok=0
        hsin_mem_zram_names
        for _uk_zn in $HSIN_MEM_ZRAM_NAMES; do
            _uk_zf="$HSIN_SYSFS_BLOCK/$_uk_zn/comp_algorithm"
            [ -f "$_uk_zf" ] || continue
            _uk_za=""
            IFS= read -r _uk_za < "$_uk_zf" 2>/dev/null
            case " $(printf '%s' "$_uk_za" | tr -d '[]') " in
                *" $_uk_algo "*) _uk_algo_ok=1; break ;;
            esac
        done
        if [ "$_uk_algo_ok" = "1" ]; then
            _target_algo="$_uk_algo"
            hsin_uk_used "memory" "zram_algo" "$_uk_algo"
        else
            hsin_log_warn "memory" "override zram_algo=$_uk_algo ditolak: tidak ada di daftar algo comp_algorithm device mana pun (pakai profil)"
            hsin_uk_result "zram_algo" "$_uk_algo" "$_target_algo" "FALLBACK" "ditolak: tidak ada di daftar algo (pakai profil)" 2>/dev/null || true
        fi
    fi
    if [ -z "$_uk_algo" ]; then
        hsin_uk_result "zram_algo" "(profil)" "$_target_algo" "APPLIED" "nilai profil (tanpa override)" 2>/dev/null || true
    fi
    _ok=0
    _skip=0

    # BUG FIX: piping into `while` runs the loop in a subshell, so
    # _ok/_skip incremented inside it never made it back out - the
    # summary line below always printed "ok=0 skip=0" no matter what
    # actually happened. The comp_algorithm writes themselves were
    # unaffected (real file I/O, not shell state), only the reported
    # counters were wrong. Switched to a heredoc-fed loop (no pipe, no
    # subshell) so the counters are accurate.
    while IFS='|' read -r _name _size _algo _streams _w; do
        [ -z "$_name" ] && continue

        # Tulis hanya ke node yang writable, dicek ULANG saat tulis (bukan
        # hanya dari flag hasil probe) karena hak tulis bisa berubah.
        _afile="$HSIN_SYSFS_BLOCK/$_name/comp_algorithm"
        if [ "$_w" != "true" ] || [ ! -w "$_afile" ]; then
            _skip=$((_skip + 1))
            hsin_log_warn "memory" "zRAM $_name: comp_algorithm tidak writable (skip)"
            continue
        fi

        # Isi comp_algorithm = daftar algo yang DIDUKUNG device, bukan algo
        # yang sedang aktif. Target harus ada di daftar itu; kalau tidak,
        # kernel menolak tulis dan zram tetap jalan dengan algo lama.
        # Lepas [siku] aktif HANYA untuk cek dukungan ini (readback di
        # bawah tetap ketat: aktif = [siku]/persis).
        _algo_nosq=$(printf '%s' "$_algo" | tr -d '[]')
        case " $_algo_nosq " in
            *" $_target_algo "*)
                if echo "$_target_algo" > "$_afile" 2>/dev/null; then
                    # Exit 0 shell bukan bukti algo benar-benar berganti:
                    # comp_algorithm ditulis ulang di store(), isinya tetap
                    # SHOW dari kernel. Tanpa readback, zram yang tetap jalan
                    # dengan algo lama dilaporkan "ok".
                    if hsin_zram_algo_live "$_target_algo" "$_afile"; then
                        _ok=$((_ok + 1))
                    else
                        _skip=$((_skip + 1))
                        hsin_log_warn "memory" "zRAM $_name: algo $_target_algo tidak aktif setelah tulis, live='${HSIN_ZRAM_LIVE:-tak terbaca}' (skip)"
                    fi
                else
                    _skip=$((_skip + 1))
                    hsin_log_warn "memory" "zRAM $_name: tulis $_target_algo ditolak (skip)"
                fi
                ;;
            *)
                _skip=$((_skip + 1))
                hsin_log_warn "memory" "zRAM $_name: algo $_target_algo tidak didukung (skip)"
                ;;
        esac
    done <<EOF
$HSIN_ZRAM_LIST
EOF

    echo "    zRAM [$_profile]: algo=$_target_algo ok=$_ok skip=$_skip"
    return 0
}

# Trigger zRAM compaction (optional, safe)
hsin_zram_compact() {
    hsin_mem_zram_names
    for _name in $HSIN_MEM_ZRAM_NAMES; do
        _dev="$HSIN_SYSFS_BLOCK/$_name"
        [ -d "$_dev" ] || { hsin_log_warn "memory" "zRAM compact: $_name hilang sejak probe (skip)"; continue; }
        [ -w "$_dev/compact" ] && echo 1 > "$_dev/compact" 2>/dev/null
    done
}

# Get zRAM state
hsin_zram_state() {
    [ "$HSIN_ZRAM_COUNT" -gt 0 ] 2>/dev/null || { echo "  zRAM: not available"; return 0; }

    echo "  zRAM State:"
    echo "$HSIN_ZRAM_LIST" | while IFS='|' read -r _name _size _algo _streams _w; do
        [ -z "$_name" ] && continue
        _size_mb=$((_size / 1024 / 1024))
        printf "    %-10s %s MB  algo=%s  streams=%s  writable=%s\n" "$_name" "$_size_mb" "${_algo:-?}" "${_streams:-?}" "$_w"
    done
}

return 0 2>/dev/null || true
