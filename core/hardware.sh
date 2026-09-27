#!/system/bin/sh
# HSIN - Hardware Information (No Root Required)

HSIN_DATA="${HSIN_DATA:-/data/adb/hsin}"
# /proc via $HSIN_PROC supaya bisa di-sandbox (prefix palsu), default /proc.
[ -n "$HSIN_PROC" ] || HSIN_PROC="${SYSFS_PROC_PREFIX:-/proc}"

# Read a property with fallback
_prop() {
    getprop "$1" 2>/dev/null || echo ""
}

# Detect SoC name
_detect_soc() {
    # Try from device-tree
    _soc=""
    for f in $HSIN_PROC/device-tree/compatible /sys/firmware/devicetree/base/compatible; do
        [ -f "$f" ] && _soc=$(cat "$f" 2>/dev/null | tr '\0' '\n' | head -1)
        [ -n "$_soc" ] && break
    done
    # Fallback to props
    [ -z "$_soc" ] && _soc=$(_prop "ro.soc.model")
    [ -z "$_soc" ] && _soc=$(_prop "ro.hardware.chipname")
    [ -z "$_soc" ] && _soc=$(_prop "ro.board.platform")
    echo "${_soc:-unknown}"
}

# Detect SoC vendor
_detect_vendor() {
    _vendor=""
    _vendor=$(_prop "ro.soc.manufacturer")
    [ -z "$_vendor" ] && _vendor=$(_prop "ro.hardware")
    # Infer from SoC name
    [ -z "$_vendor" ] && {
        _soc=$(_detect_soc)
        _socl=$(printf '%s' "$_soc" | tr '[:upper:]' '[:lower:]')
        case "$_socl" in
            *mediatek*|mt[0-9]*|*dimensity*|*helio*) _vendor="mediatek" ;;
            *qualcomm*|*qcom*|sm[0-9]*|sdm[0-9]*|*snapdragon*|msm[0-9]*) _vendor="qualcomm" ;;
            *exynos*|*samsung*|s5e[0-9]*|universal[0-9]*) _vendor="samsung" ;;
            *unisoc*|*sprd*|*spreadtrum*|ums[0-9]*|sp[0-9]*|t[0-9][0-9][0-9][0-9]*) _vendor="unisoc" ;;
            *kirin*|hi[0-9]*|*hisilicon*) _vendor="huawei" ;;
            *tensor*|*google*gs[0-9]*) _vendor="google" ;;
            *) _vendor="unknown" ;;
        esac
    }
    echo "${_vendor:-unknown}"
}

# Detect CPU info
_detect_cpu() {
    _cores=$(nproc 2>/dev/null || grep -c "^processor" "$HSIN_PROC/cpuinfo" 2>/dev/null)
    _arch=$(uname -m 2>/dev/null)
    # Try to get CPU model
    _model=$(grep -m1 "model name" "$HSIN_PROC/cpuinfo" 2>/dev/null | cut -d: -f2 | tr -d ' ')
    [ -z "$_model" ] && _model=$(_prop "ro.soc.model")
    echo "${_model:-unknown}|${_cores:-?}|${_arch:-?}"
}

# Detect GPU info (from sysfs if available, no root needed for reading)
_detect_gpu() {
    _gpu=""
    # Mali
    for f in /sys/devices/platform/*.mali/gpu/gpu_model \
             /sys/devices/platform/*.mali/gpu/gpu_id; do
        [ -f "$f" ] && _gpu="Mali $(cat "$f" 2>/dev/null)" && break
    done
    # KGSL (Adreno)
    [ -d /sys/class/kgsl/kgsl-3d0 ] && _gpu="Adreno (KGSL detected)"
    # Fallback to props
    [ -z "$_gpu" ] && _gpu=$(_prop "ro.hardware.vulkan")
    [ -z "$_gpu" ] && _gpu=$(_prop "ro.board.platform")
    echo "${_gpu:-unknown}"
}

# Detect RAM
_detect_ram() {
    _ram_kb=$(grep "MemTotal" "$HSIN_PROC/meminfo" 2>/dev/null | awk '{print $2}')
    [ -z "$_ram_kb" ] && echo "unknown" && return
    _ram_mb=$((_ram_kb / 1024))
    if [ "$_ram_mb" -ge 1024 ]; then
        _ram_gb=$((_ram_mb / 1024))
        echo "${_ram_gb}GB"
    else
        echo "${_ram_mb}MB"
    fi
}

# Detect ZRAM
_detect_zram() {
    [ -d /sys/block/zram0 ] && echo "available" || echo "none"
}

# Detect Android version
_detect_android() {
    _ver=$(_prop "ro.build.version.release")
    _sdk=$(_prop "ro.build.version.sdk")
    echo "${_ver:-?}|SDK${_sdk:-?}"
}

# Detect kernel version
_detect_kernel() {
    uname -r 2>/dev/null || echo "unknown"
}

# Detect storage type (best guess from /proc/diskstats)
_detect_storage() {
    _has_emmc=0; _has_ufs=0
    for d in /sys/block/*; do
        [ -d "$d" ] || continue
        _name=$(basename "$d")
        case "$_name" in
            *mmcblk*) _has_emmc=1 ;;
            *sda*|*sdb*) _has_ufs=1 ;;
        esac
    done
    if [ "$_has_ufs" -eq 1 ]; then
        echo "UFS"
    elif [ "$_has_emmc" -eq 1 ]; then
        echo "eMMC"
    else
        echo "unknown"
    fi
}

# Generate full hardware info (no root needed)
hsin_hardware_info() {
    echo ""  # Placeholder for log section

    _soc=$(_detect_soc)
    _vendor=$(_detect_vendor)
    _cpu_info=$(_detect_cpu)
    _cpu_model=$(echo "$_cpu_info" | cut -d'|' -f1)
    _cores=$(echo "$_cpu_info" | cut -d'|' -f2)
    _arch=$(echo "$_cpu_info" | cut -d'|' -f3)
    _gpu=$(_detect_gpu)
    _ram=$(_detect_ram)
    _zram=$(_detect_zram)
    _android=$(_detect_android)
    _kernel=$(_detect_kernel)
    _storage=$(_detect_storage)

    # Print human-readable report
    echo ""
    echo "╔══════════════════════════════════════╗"
    echo "║   HSIN Hardware Information          ║"
    echo "╚══════════════════════════════════════╝"
    echo ""
    printf "  SoC:        %s\n" "$_soc"
    printf "  Vendor:     %s\n" "$_vendor"
    printf "  CPU:        %s (%s cores, %s)\n" "$_cpu_model" "$_cores" "$_arch"
    printf "  GPU:        %s\n" "$_gpu"
    printf "  RAM:        %s\n" "$_ram"
    printf "  ZRAM:       %s\n" "$_zram"
    printf "  Storage:    %s\n" "$_storage"
    printf "  Android:    %s\n" "$_android"
    printf "  Kernel:     %s\n" "$_kernel"
    echo ""
    echo "──────────────────────────────────────"
    echo ""
}

# Write hardware info to files
hsin_hardware_write() {
    _out_dir="$HSIN_DATA"
    [ -d "$_out_dir" ] || mkdir -p "$_out_dir" 2>/dev/null

    _soc=$(_detect_soc)
    _vendor=$(_detect_vendor)
    _cpu_info=$(_detect_cpu)
    _cpu_model=$(echo "$_cpu_info" | cut -d'|' -f1)
    _cores=$(echo "$_cpu_info" | cut -d'|' -f2)
    _arch=$(echo "$_cpu_info" | cut -d'|' -f3)
    _gpu=$(_detect_gpu)
    _ram=$(_detect_ram)
    _zram=$(_detect_zram)
    _android=$(_detect_android)
    _kernel=$(_detect_kernel)
    _storage=$(_detect_storage)

    # Write human-readable txt
    {
        echo "HSIN Hardware Information"
        echo "========================"
        echo "SoC: $_soc"
        echo "Vendor: $_vendor"
        echo "CPU: $_cpu_model ($_cores cores, $_arch)"
        echo "GPU: $_gpu"
        echo "RAM: $_ram"
        echo "ZRAM: $_zram"
        echo "Storage: $_storage"
        echo "Android: $_android"
        echo "Kernel: $_kernel"
        echo ""
        echo "Root: NOT REQUIRED for this scan"
        echo "Engine capability: Run 'su -c hsin scan' for full capability check"
    } > "$_out_dir/hardware_info.txt"

    # Write JSON
    {
        echo "{"
        echo "  \"soc\": \"$_soc\","
        echo "  \"vendor\": \"$_vendor\","
        echo "  \"cpu_model\": \"$_cpu_model\","
        echo "  \"cpu_cores\": $_cores,"
        echo "  \"cpu_arch\": \"$_arch\","
        echo "  \"gpu\": \"$_gpu\","
        echo "  \"ram\": \"$_ram\","
        echo "  \"zram\": \"$_zram\","
        echo "  \"storage\": \"$_storage\","
        echo "  \"android\": \"$_android\","
        echo "  \"kernel\": \"$_kernel\""
        echo "}"
    } > "$_out_dir/hardware_info.json"
}

return 0 2>/dev/null || true
