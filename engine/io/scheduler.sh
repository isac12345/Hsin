#!/system/bin/sh
# HSIN IO Engine - Scheduler Management

[ -z "$HSIN_MODULE_PATH" ] && HSIN_MODULE_PATH="/data/adb/modules/hsin"
. "$HSIN_MODULE_PATH/core/sysfs.sh" 2>/dev/null
. "$HSIN_MODULE_PATH/core/logger.sh" 2>/dev/null
# Override knob user per block (pilihan user, bukan nilai profil).
. "$HSIN_MODULE_PATH/core/user_knobs.sh" 2>/dev/null
# shellcheck disable=SC1091
. "$HSIN_MODULE_PATH/core/scan_cache.sh" 2>/dev/null
# Path sysfs dari core/scan_cache.sh (satu-satunya definisi), default sama
# dengan path yang sebelumnya ditulis langsung di file ini.
[ -n "$HSIN_SYSFS_BLOCK" ] || HSIN_SYSFS_BLOCK="${SYSFS_BLOCK_PREFIX:-/sys/block}"
# Diisi _uk_sanitize() (core/user_knobs.sh) dan hsin_io_block_devs() (di
# bawah) - dideklarasikan di sini supaya jelas file ini memang memakainya.
_uk_sn=""
HSIN_IO_BLOCKS=""
HSIN_IO_BLOCK_SOURCE=""
HSIN_IO_BLOCKS_READY=""

# Daftar block device untuk scheduler + readahead (dipisah spasi, path penuh).
# Cache-first: field BLOCKS dari core/scan_cache.sh - topologi statis, sudah
# menyaring loop/ram/zram/dm-* saat scan, jadi apply tidak perlu glob
# /sys/block/* per file. Cache hilang/rusak/tua/boot beda -> scan live,
# persis loop yang lama. String BLOCKS kosong di cache berarti device memang
# tidak punya block riil, jadi tidak ada yang perlu ditulis (tetap tanpa
# glob). Di-resolve SEKALI per proses supaya scheduler + readahead + state
# cukup satu sumber data.
hsin_io_block_devs() {
    [ -n "$HSIN_IO_BLOCKS_READY" ] && return 0
    command -v hsin_scan_devfreq_get >/dev/null 2>&1 && hsin_scan_devfreq_get

    HSIN_IO_BLOCKS=""
    if [ "$HSIN_SCAN_OK" = "1" ]; then
        for _hib_n in $HSIN_SCAN_BLOCKS; do
            HSIN_IO_BLOCKS="${HSIN_IO_BLOCKS:+${HSIN_IO_BLOCKS} }$HSIN_SYSFS_BLOCK/$_hib_n"
        done
        HSIN_IO_BLOCK_SOURCE="cache"
    else
        for _hib_d in "$HSIN_SYSFS_BLOCK"/*; do
            [ -d "$_hib_d" ] || continue
            _hib_n="${_hib_d##*/}"
            case "$_hib_n" in loop*|ram*|zram*|dm-*) continue ;; esac
            HSIN_IO_BLOCKS="${HSIN_IO_BLOCKS:+${HSIN_IO_BLOCKS} }$_hib_d"
        done
        HSIN_IO_BLOCK_SOURCE="scan"
    fi
    HSIN_IO_BLOCKS_READY=1
    export HSIN_IO_BLOCK_SOURCE
    return 0
}

# Pick best IO scheduler for profile
hsin_io_pick_scheduler() {
    _profile="$1"
    _list="$2"

    case "$_profile" in
        battery)
            for _s in bfq none; do
                case " $_list " in
                    *" [$_s] "*|*" $_s "*|*"$_s"*) echo "$_s"; return 0 ;;
                esac
            done
            ;;
        balanced)
            for _s in mq-deadline kyber bfq; do
                case " $_list " in
                    *" [$_s] "*|*" $_s "*|*"$_s"*) echo "$_s"; return 0 ;;
                esac
            done
            ;;
        performance|extreme)
            for _s in mq-deadline none; do
                case " $_list " in
                    *" [$_s] "*|*" $_s "*|*"$_s"*) echo "$_s"; return 0 ;;
                esac
            done
            ;;
    esac
    echo ""
    return 1
}

# Apply scheduler to all block devices
hsin_io_apply_scheduler() {
    _profile="$1"
    _ok=0
    _skip=0

    hsin_io_block_devs
    for _b in $HSIN_IO_BLOCKS; do
        _name="${_b##*/}"

        # Node hilang sejak scan - skip + log, bukan crash.
        if [ ! -d "$_b" ]; then
            hsin_report_skip "scheduler: block $_name hilang sejak scan"
            _skip=$((_skip + 1))
            continue
        fi

        # Skip non-block devices (cache lama / ditulis manual tetap aman)
        case "$_name" in
            loop*|ram*|zram*|dm-*) continue ;;
        esac

        # Check scheduler exists
        [ -f "$_b/queue/scheduler" ] || { _skip=$((_skip + 1)); continue; }

        # Check writable
        [ -w "$_b/queue/scheduler" ] || { _skip=$((_skip + 1)); continue; }

        _list=$(hsin_node_read "$_b/queue/scheduler")

        # Special case for rotational devices (HDD)
        _rot=$(hsin_node_read "$_b/queue/rotational")
        if [ "$_rot" = "1" ]; then
            _target="bfq"
        else
            _target=$(hsin_io_pick_scheduler "$_profile" "$_list")
        fi

        # Override knob user menang atas pilihan profil (dan atas default
        # bfq untuk disk rotasional), TAPI hanya kalau scheduler itu ada
        # di daftar node ini - kernel menolak scheduler tak dikenal dengan
        # write error, jadi lebih baik SKIP + bilang ke user.
        # Sama seperti GPU: kunci yang ditulis ke log harus persis sama
        # dengan yang disimpan di user_knobs.env (nama block bisa mengandung
        # karakter yang jadi '_').
        _uk_sanitize "$_name"
        _uk_ksched="io_block_${_uk_sn}_sched"
        _uk_sched=$(hsin_uk_io_field "$_name" sched 2>/dev/null)
        if [ -n "$_uk_sched" ]; then
            # Node queue/scheduler memakai penanda kurung siku untuk yang
            # aktif, sama seperti comp_algorithm; kurung hanya dibuang
            # untuk cek anggota daftar.
            _uk_slist=$(printf '%s' "$_list" | tr -d '[]')
            case " $_uk_slist " in
                *" $_uk_sched "*)
                    _target="$_uk_sched"
                    hsin_uk_used "io" "$_uk_ksched" "$_uk_sched"
                    ;;
                *)
                    hsin_log_warn "io" "override ${_uk_ksched}=$_uk_sched ditolak: tidak ada di daftar queue/scheduler node ini (pakai profil)"
                    hsin_uk_result "$_uk_ksched" "$_uk_sched" "$_target" "FALLBACK" "ditolak: tidak ada di daftar scheduler (pakai profil)" 2>/dev/null || true
                    ;;
            esac
        fi
        # Mode manual: tanpa override, lewati penulisan.
        if [ "$_profile" = "manual" ] && [ -z "$_uk_sched" ]; then
            hsin_uk_result "$_uk_ksched" "(manual)" "-" "SKIPPED" "tidak diatur (mode manual)" 2>/dev/null || true
            _skip=$((_skip + 1))
            continue
        fi

        if [ -z "$_uk_sched" ]; then
            hsin_uk_result "$_uk_ksched" "(profil)" "$_target" "APPLIED" "nilai profil (tanpa override)" 2>/dev/null || true
        fi

        [ -z "$_target" ] && { _skip=$((_skip + 1)); continue; }

        echo "$_target" > "$_b/queue/scheduler" 2>/dev/null && _ok=$((_ok + 1)) || _skip=$((_skip + 1))
    done

    echo "    Scheduler [$_profile]: ok=$_ok skip=$_skip"
    hsin_log_info "io" "scheduler src=$HSIN_IO_BLOCK_SOURCE profile=$_profile ok=$_ok skip=$_skip"
    return 0
}

# Get current scheduler state
hsin_io_scheduler_state() {
    echo "  IO Scheduler State:"
    hsin_io_block_devs
    for _b in $HSIN_IO_BLOCKS; do
        [ -d "$_b" ] || continue
        _name="${_b##*/}"
        case "$_name" in
            loop*|ram*|zram*|dm-*) continue ;;
        esac
        [ -f "$_b/queue/scheduler" ] || continue
        _cur=$(hsin_node_read "$_b/queue/scheduler")
        printf "    %-15s %s\n" "$_name" "$_cur"
    done
}

return 0 2>/dev/null || true
