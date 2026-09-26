#!/system/bin/sh
# HSIN Memory Engine - Detection

[ -z "$HSIN_MODULE_PATH" ] && HSIN_MODULE_PATH="/data/adb/modules/hsin"

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

    # Read /proc/meminfo
    if [ -f /proc/meminfo ]; then
        HSIN_MEM_RAM_TOTAL=$(grep "^MemTotal:" /proc/meminfo 2>/dev/null | awk '{print $2}')
        HSIN_MEM_RAM_FREE=$(grep "^MemFree:" /proc/meminfo 2>/dev/null | awk '{print $2}')
        HSIN_MEM_RAM_AVAILABLE=$(grep "^MemAvailable:" /proc/meminfo 2>/dev/null | awk '{print $2}')
        HSIN_MEM_SWAP_TOTAL=$(grep "^SwapTotal:" /proc/meminfo 2>/dev/null | awk '{print $2}')
        HSIN_MEM_SWAP_FREE=$(grep "^SwapFree:" /proc/meminfo 2>/dev/null | awk '{print $2}')
    fi

    # Detect zRAM devices
    for _dev in /sys/block/zram*; do
        [ -d "$_dev" ] || continue
        _name=$(basename "$_dev")
        _size=""
        [ -f "$_dev/disksize" ] && _size=$(cat "$_dev/disksize" 2>/dev/null)
        _algo=""
        [ -f "$_dev/comp_algorithm" ] && _algo=$(cat "$_dev/comp_algorithm" 2>/dev/null)

        HSIN_MEM_ZRAM_DEVICES="${HSIN_MEM_ZRAM_DEVICES}${_name}|${_size}|${_algo}
"
        HSIN_MEM_ZRAM_COUNT=$((HSIN_MEM_ZRAM_COUNT + 1))
    done

    # Detect VM nodes
    for _node in swappiness vfs_cache_pressure dirty_ratio dirty_background_ratio page-cluster min_free_kbytes; do
        _path="/proc/sys/vm/$_node"
        if [ -f "$_path" ]; then
            _val=$(cat "$_path" 2>/dev/null)
            _writable="false"
            [ -w "$_path" ] && _writable="true"
            HSIN_MEM_VM_NODES="${HSIN_MEM_VM_NODES}${_node}|${_val}|${_writable}
"
        fi
    done

    # Check OOM availability
    [ -d /proc ] && HSIN_MEM_OOM_AVAILABLE="true"
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
