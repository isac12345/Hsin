#!/system/bin/sh
# HSIN Memory Engine - Detection

[ -z "$HSIN_MODULE_PATH" ] && HSIN_MODULE_PATH="/data/adb/modules/hsin"
. "$HSIN_MODULE_PATH/core/logger.sh" 2>/dev/null
. "$HSIN_MODULE_PATH/core/sysfs.sh" 2>/dev/null
# shellcheck disable=SC1091
. "$HSIN_MODULE_PATH/core/scan_cache.sh" 2>/dev/null
# Path sysfs dari core/scan_cache.sh (satu-satunya definisi), default sama
# dengan path yang sebelumnya ditulis langsung di file ini.
[ -n "$HSIN_SYSFS_BLOCK" ] || HSIN_SYSFS_BLOCK="${SYSFS_BLOCK_PREFIX:-/sys/block}"
[ -n "$HSIN_PROC" ] || HSIN_PROC="${SYSFS_PROC_PREFIX:-/proc}"
HSIN_SYSFS_MODULE="${SYSFS_MODULE_PREFIX:-/sys/module}"
# Diisi hsin_mem_zram_names() (di bawah).
HSIN_MEM_ZRAM_NAMES=""
HSIN_MEM_ZRAM_SOURCE=""
# Batas iterasi probe zram (bukan angka tuning): num_devices yang dibaca
# dari module param bisa absurd, jadi dijepit supaya loop tidak monster.
HSIN_MEM_ZRAM_PROBE_MAX=32

# Nama device zram aktif, dipisah spasi, TANPA glob /sys/block/zram*.
# Cache scan tidak menyimpan zram (field BLOCKS memang menyaring zram-*),
# jadi sumbernya module param kernel /sys/module/zram/parameters/
# num_devices = jumlah device zram yang dibuat, dan kernel memberi nama
# berurutan zram0..zramN-1. Module param tak terbaca = zram dianggap
# absen (dilogar), bukan glob directory.
hsin_mem_zram_names() {
    _hzn_n=0
    IFS= read -r _hzn_n < "$HSIN_SYSFS_MODULE/zram/parameters/num_devices" 2>/dev/null
    case "$_hzn_n" in ''|*[!0-9]*) _hzn_n=0 ;; esac
    if [ "$_hzn_n" -gt "$HSIN_MEM_ZRAM_PROBE_MAX" ] 2>/dev/null; then
        hsin_log_warn "memory" "zram num_devices=$_hzn_n > batas probe $HSIN_MEM_ZRAM_PROBE_MAX"
        _hzn_n=$HSIN_MEM_ZRAM_PROBE_MAX
    fi
    HSIN_MEM_ZRAM_NAMES=""
    _hzn_i=0
    while [ "$_hzn_i" -lt "$_hzn_n" ]; do
        [ -d "$HSIN_SYSFS_BLOCK/zram$_hzn_i" ] && \
            HSIN_MEM_ZRAM_NAMES="${HSIN_MEM_ZRAM_NAMES:+$HSIN_MEM_ZRAM_NAMES }zram$_hzn_i"
        _hzn_i=$((_hzn_i + 1))
    done
    if [ "$_hzn_n" -gt 0 ]; then
        HSIN_MEM_ZRAM_SOURCE="param"
    else
        HSIN_MEM_ZRAM_SOURCE="none"
        hsin_log_info "memory" "zram tidak ada (num_devices tak terbaca / 0)"
    fi
    return 0
}

# Detect memory info
hsin_mem_detect() {
    # Reset
    HSIN_MEM_RAM_TOTAL=""
    HSIN_MEM_RAM_FREE=""
    HSIN_MEM_RAM_AVAILABLE=""
    HSIN_MEM_SWAP_TOTAL=""
    HSIN_MEM_SWAP_FREE=""
    HSIN_MEM_ZRAM_DEVICES=""
    HSIN_MEM_ZRAM_COUNT=0
    HSIN_MEM_VM_NODES=""
    HSIN_MEM_OOM_AVAILABLE="false"

    # Read meminfo
    if [ -f "$HSIN_PROC/meminfo" ]; then
        HSIN_MEM_RAM_TOTAL=$(grep "^MemTotal:" "$HSIN_PROC/meminfo" 2>/dev/null | awk '{print $2}')
        HSIN_MEM_RAM_FREE=$(grep "^MemFree:" "$HSIN_PROC/meminfo" 2>/dev/null | awk '{print $2}')
        HSIN_MEM_RAM_AVAILABLE=$(grep "^MemAvailable:" "$HSIN_PROC/meminfo" 2>/dev/null | awk '{print $2}')
        HSIN_MEM_SWAP_TOTAL=$(grep "^SwapTotal:" "$HSIN_PROC/meminfo" 2>/dev/null | awk '{print $2}')
        HSIN_MEM_SWAP_FREE=$(grep "^SwapFree:" "$HSIN_PROC/meminfo" 2>/dev/null | awk '{print $2}')
    fi

    # Detect zRAM devices. Nama dari module param (tanpa glob); disksize /
    # comp_algorithm / max_comp_streams SELALU live karena nilainya berubah
    # (HSIN sendiri yang menulis comp_algorithm).
    hsin_mem_zram_names
    for _name in $HSIN_MEM_ZRAM_NAMES; do
        _dev="$HSIN_SYSFS_BLOCK/$_name"
        if [ ! -d "$_dev" ]; then
            hsin_report_skip "zRAM: $_name hilang sejak probe (skip)"
            continue
        fi
        _size=""
        [ -f "$_dev/disksize" ] && IFS= read -r _size < "$_dev/disksize" 2>/dev/null

        _algo=""
        [ -f "$_dev/comp_algorithm" ] && IFS= read -r _algo < "$_dev/comp_algorithm" 2>/dev/null

        HSIN_MEM_ZRAM_DEVICES="${HSIN_MEM_ZRAM_DEVICES}${_name}|${_size}|${_algo}
"
        HSIN_MEM_ZRAM_COUNT=$((HSIN_MEM_ZRAM_COUNT + 1))
    done

    # Detect VM nodes. Cache-first: VM_NODES di core/scan_cache.sh = daftar
    # file /proc/sys/vm yang ADA saat scan, jadi 4 node yang tidak ada di
    # device ini tidak perlu dicek ulang tiap apply. Cache absen/rusak ->
    # cek [ -r ] seperti sebelumnya. Nilai SELALU live (HSIN yang menulis
    # swappiness/vfs_cache_pressure/dirty_*), dan [ -r ] tetap dipakai
    # supaya node yang hilang sejak scan di-skip, bukan dilaporkan kosong.
    command -v hsin_scan_devfreq_get >/dev/null 2>&1 && hsin_scan_devfreq_get
    _vm_src="scan"
    [ "$HSIN_SCAN_OK" = "1" ] && _vm_src="cache"
    for _node in swappiness vfs_cache_pressure dirty_ratio dirty_background_ratio page-cluster min_free_kbytes; do
        if [ "$_vm_src" = "cache" ]; then
            case " $HSIN_SCAN_VM_NODES " in
                *" $_node "*) ;;
                *) continue ;;
            esac
        fi
        _path="$HSIN_PROC/sys/vm/$_node"
        [ -r "$_path" ] || continue
        _val=""
        IFS= read -r _val < "$_path" 2>/dev/null
        _writable="false"
        [ -w "$_path" ] && _writable="true"
        HSIN_MEM_VM_NODES="${HSIN_MEM_VM_NODES}${_node}|${_val}|${_writable}
"
    done

    # Check OOM availability
    [ -d "$HSIN_PROC" ] && HSIN_MEM_OOM_AVAILABLE="true"

    hsin_scan_log "mem detect vm_src=$_vm_src zram_src=$HSIN_MEM_ZRAM_SOURCE zram=$HSIN_MEM_ZRAM_COUNT"
    return 0
}

# Print detection report
hsin_mem_print() {
    [ -z "$HSIN_MEM_RAM_TOTAL" ] && hsin_mem_detect

    echo ""
    echo "╔══════════════════════════════════════╗"
    echo "║   HSIN Memory Detection              ║"
    echo "╚══════════════════════════════════════╝"
    echo ""

    # RAM
    if [ -n "$HSIN_MEM_RAM_TOTAL" ]; then
        _ram_mb=$((HSIN_MEM_RAM_TOTAL / 1024))
        printf "  RAM:       %s MB\n" "$_ram_mb"
    else
        printf "  RAM:       unknown\n"
    fi

    # zRAM
    if [ "$HSIN_MEM_ZRAM_COUNT" -gt 0 ] 2>/dev/null; then
        echo "$HSIN_MEM_ZRAM_DEVICES" | while IFS='|' read -r _name _size _algo; do
            [ -z "$_name" ] && continue
            # Guard against empty size - arithmetic on unset/empty
            # string would silently produce 0 on some shells and error
            # on others. Default to 0 for display.
            _size_mb=0
            if [ -n "$_size" ] && [ "$_size" -gt 0 ] 2>/dev/null; then
                _size_mb=$((_size / 1024 / 1024))
            fi
            printf "  zRAM:      %s MB (%s)\n" "$_size_mb" "${_algo:-?}"
        done
    else
        printf "  zRAM:      not available\n"
    fi

    # Swap
    if [ -n "$HSIN_MEM_SWAP_TOTAL" ] && [ "$HSIN_MEM_SWAP_TOTAL" -gt 0 ] 2>/dev/null; then
        printf "  Swap:      enabled (%s MB)\n" "$((HSIN_MEM_SWAP_TOTAL / 1024))"
    else
        printf "  Swap:      disabled\n"
    fi

    # VM nodes
    echo ""
    echo "  VM Nodes:"
    echo "$HSIN_MEM_VM_NODES" | while IFS='|' read -r _name _val _w; do
        [ -z "$_name" ] && continue
        printf "    ✓ %-30s = %s (writable=%s)\n" "$_name" "$_val" "$_w"
    done

    # OOM
    echo ""
    printf "  OOM:       %s\n" "$HSIN_MEM_OOM_AVAILABLE"
    echo ""
}

return 0 2>/dev/null || true
