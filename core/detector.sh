#!/system/bin/sh
# HSIN - Detector Module

HSIN_DATA="${HSIN_DATA:-/data/adb/hsin}"
HSIN_DATA_DEVICE="$HSIN_DATA/device.json"

[ -z "$HSIN_MODULE_PATH" ] && HSIN_MODULE_PATH="/data/adb/modules/hsin"
. "$HSIN_MODULE_PATH/core/logger.sh" 2>/dev/null
# /proc via $HSIN_PROC supaya bisa di-sandbox (prefix palsu), default /proc.
[ -n "$HSIN_PROC" ] || HSIN_PROC="${SYSFS_PROC_PREFIX:-/proc}"
[ -n "$HSIN_SYSFS_CPU" ] || HSIN_SYSFS_CPU="${SYSFS_CPU_PREFIX:-/sys/devices/system/cpu}"
[ -n "$HSIN_SYSFS_THERMAL" ] || HSIN_SYSFS_THERMAL="${SYSFS_THERMAL_PREFIX:-/sys/class/thermal}"
HSIN_DATA_DEVICE_TXT="$HSIN_DATA/device.txt"

# Helper: cek file exist + readable + writable
_node_ok() {
    [ -f "$1" ] && [ -r "$1" ] && [ -w "$1" ]
}

# Helper: cek file exist + readable (untuk read-only detection)
_node_ro() {
    [ -f "$1" ] && [ -r "$1" ]
}

# SoC detection via multi-source
detect_soc() {
    _soc=""
    # 1. $HSIN_PROC/device-tree/model (paling reliable untuk ARM64)
    if [ -f $HSIN_PROC/device-tree/model ]; then
        _soc=$(tr -d '\0' < $HSIN_PROC/device-tree/model 2>/dev/null)
    fi
    # 2. $HSIN_PROC/device-tree/compatible
    if [ -z "$_soc" ] && [ -f $HSIN_PROC/device-tree/compatible ]; then
        _soc=$(tr -d '\0' < $HSIN_PROC/device-tree/compatible 2>/dev/null | cut -d, -f1)
    fi
    # 3. getprop ro.soc.model
    if [ -z "$_soc" ]; then
        _soc=$(getprop ro.soc.model 2>/dev/null)
    fi
    # 4. /sys/devices/soc0/machine
    if [ -z "$_soc" ] && [ -f /sys/devices/soc0/machine ]; then
        _soc=$(cat /sys/devices/soc0/machine 2>/dev/null)
    fi
    # 5. ro.board.platform / ro.product.board
    if [ -z "$_soc" ]; then
        _soc=$(getprop ro.board.platform 2>/dev/null)
        [ -z "$_soc" ] && _soc=$(getprop ro.product.board 2>/dev/null)
    fi
    # 6. $HSIN_PROC/cpuinfo Hardware
    if [ -z "$_soc" ]; then
        _soc=$(grep -m1 '^Hardware' $HSIN_PROC/cpuinfo 2>/dev/null | cut -d: -f2 | sed 's/^[ \t]*//')
    fi
    [ -z "$_soc" ] && _soc="unknown"
    echo "$_soc"
}

# Klasifikasikan SoC vendor dari string
classify_soc_vendor() {
    _hw=$(echo "$1" | tr '[:upper:]' '[:lower:]')
    case "$_hw" in
        *mediatek*|*mt[0-9][0-9][0-9][0-9]*|*dimensity*|*helio*)
            echo "mediatek" ;;
        *qualcomm*|*qcom*|*sm[0-9][0-9][0-9][0-9]*|*sdm[0-9]*|*snapdragon*|*msm[0-9]*)
            echo "qualcomm" ;;
        *exynos*|*samsung*|*erd[0-9]*|*s5e[0-9]*|*universal[0-9]*)
            echo "exynos" ;;
        *unisoc*|*sprd*|*spreadtrum*|*ums[0-9]*|*sp[0-9][0-9][0-9][0-9]*|*t*6[0-9][0-9]*)
            echo "unisoc" ;;
        *kirin*|*hi[0-9][0-9][0-9]*|*hisilicon*)
            echo "kirin" ;;
        *tensor*|*gs[0-9][0-9]*)
            echo "tensor" ;;
        *)
            echo "unknown" ;;
    esac
}

# GPU vendor detection
detect_gpu_vendor() {
    _gpu=""
    # 1. $HSIN_PROC/gpuinfo (kebanyakan ARM)
    if [ -f $HSIN_PROC/gpuinfo ]; then
        _gpu=$(grep -m1 -i 'model\|vendor' $HSIN_PROC/gpuinfo 2>/dev/null | cut -d: -f2 | sed 's/^[ \t]*//')
    fi
    # 2. $HSIN_PROC/driver/gpu
    if [ -z "$_gpu" ] && [ -d $HSIN_PROC/driver/gpu ]; then
        _gpu=$(find $HSIN_PROC/driver/gpu -maxdepth 2 -name 'model' 2>/dev/null | head -1 | xargs cat 2>/dev/null)
    fi
    # 3. Mali via /sys/devices/platform/*.mali (silent kalau tidak ada)
    if [ -z "$_gpu" ]; then
        for m in /sys/devices/platform/*.mali; do
            [ -d "$m" ] || continue
            _gpu=$(cat "$m/gpu_model" 2>/dev/null)
            [ -n "$_gpu" ] && break
        done
    fi
    # 4. KGSL (Qualcomm Adreno)
    if [ -z "$_gpu" ] && [ -d /sys/class/kgsl/kgsl-3d0 ]; then
        _gpu="adreno"
    fi
    # 5. PowerVR
    if [ -z "$_gpu" ] && [ -d /sys/devices/pvrsrvkm ]; then
        _gpu="powervr"
    fi
    # 6. devfreq scan untuk node GPU
    if [ -z "$_gpu" ]; then
        for d in /sys/class/devfreq/*; do
            [ -d "$d" ] || continue
            _name=$(basename "$d" | tr '[:upper:]' '[:lower:]')
            case "$_name" in
                *gpu*|*gfx*|*mali*)
                    _gpu=$(echo "$_name" | sed 's/[0-9]\+//g')
                    break ;;
            esac
        done 2>/dev/null
    fi
    # 7. Xclipse via device-tree compatible (STEP4)
    if [ -z "$_gpu" ]; then
        if [ -f "$HSIN_PROC/device-tree/compatible" ]; then
            _compat=$(tr -d '\0' < "$HSIN_PROC/device-tree/compatible" 2>/dev/null | tr '[:upper:]' '[:lower:]')
            case "$_compat" in
                *xclipse*) _gpu="xclipse" ;;
            esac
        fi
    fi
    [ -z "$_gpu" ] && _gpu="unknown"
    # Normalize vendor
    case "$(echo "$_gpu" | tr '[:upper:]' '[:lower:]')" in
        *mali*) echo "mali" ;;
        *adreno*) echo "adreno" ;;
        *powervr*) echo "powervr" ;;
        *xclipse*) echo "xclipse" ;;
        *tegra*) echo "tegra" ;;
        *) echo "$_gpu" ;;
    esac
}

# CPU cluster scanning (DARI policy*, BUKAN cpu0-7)
detect_cpu_clusters() {
    # Output: baris "policy<N>:governor:min:max:cores"
    _count=0
    for p in /sys/devices/system/cpu/cpufreq/policy*; do
        [ -d "$p" ] || continue
        _name=$(basename "$p")
        _gov=$(cat "$p/scaling_governor" 2>/dev/null)
        _min=$(cat "$p/scaling_min_freq" 2>/dev/null)
        _max=$(cat "$p/scaling_max_freq" 2>/dev/null)
        # Cores yang termasuk policy ini
        _cores=$(cat "$p/related_cpus" 2>/dev/null | tr '\n' ',' | sed 's/,$//')
        [ -z "$_cores" ] && _cores=$(cat "$p/cpus" 2>/dev/null | tr '\n' ',' | sed 's/,$//')
        [ -z "$_cores" ] && _cores=$(echo "$_name" | sed 's/policy//')
        echo "$_name|$_gov|$_min|$_max|$_cores"
        _count=$((_count + 1)) 2>/dev/null
    done
    return 0
}

# Total core online
detect_core_online() {
    _on=0
    _total=0
    for c in /sys/devices/system/cpu/cpu[0-9]*; do
        [ -d "$c" ] || continue
        _total=$((_total + 1))
        _v=$(cat "$c/online" 2>/dev/null)
        [ "$_v" = "1" ] && _on=$((_on + 1))
    done 2>/dev/null
    echo "$_on|$_total"
}

# Governor list detection
detect_governor_list() {
    # Aggregate semua governor yang tersedia dari semua policy
    _all_gov=""
    for p in /sys/devices/system/cpu/cpufreq/policy*; do
        [ -f "$p/scaling_available_governors" ] || continue
        for g in $(cat "$p/scaling_available_governors" 2>/dev/null); do
            case " $_all_gov " in
                *" $g "*) ;;
                *) _all_gov="$_all_gov $g" ;;
            esac
        done
    done
    echo "$_all_gov" | sed 's/^ //'
}

# RAM detection
detect_ram() {
    _total=$(grep '^MemTotal' $HSIN_PROC/meminfo 2>/dev/null | awk '{print $2}')
    _avail=$(grep '^MemAvailable' $HSIN_PROC/meminfo 2>/dev/null | awk '{print $2}')
    echo "$_total|$_avail"
}

# zRAM detection
detect_zram() {
    if [ -d /sys/block/zram0 ]; then
        _size=$(cat /sys/block/zram0/disksize 2>/dev/null)
        echo "available|$_size"
    else
        echo "unavailable|0"
    fi
}

# Thermal zones
# STEP4: set global THERMAL_PATH (sandboxable via HSIN_SYSFS_THERMAL)
detect_thermal_zones() {
    _count=0
    _writable=0
    THERMAL_PATH=""
    _thermal_base="${HSIN_SYSFS_THERMAL:-/sys/class/thermal}"
    _first_zone_path=""
    for z in $_thermal_base/thermal_zone*; do
        [ -d "$z" ] || continue
        [ -n "$_first_zone_path" ] || _first_zone_path="$z/temp"
        _count=$((_count + 1)) 2>/dev/null
        _m=$(cat "$z/mode" 2>/dev/null)
        # enabled mode = writable override
        if [ "$_m" = "enabled" ]; then
            _writable=$((_writable + 1)) 2>/dev/null
        fi
        # Cari zone pertama yang tipenya cocok
        if [ -z "$THERMAL_PATH" ]; then
            _type_str=""
            [ -f "$z/type" ] && _type_str=$(cat "$z/type" 2>/dev/null | tr '[:upper:]' '[:lower:]')
            case "$_type_str" in
                *gpu*|*soc*|*tsens*|*cpu*)
                    THERMAL_PATH="$z/temp"
                    ;;
            esac
        fi
    done 2>/dev/null
    # Fallback: zone pertama yang ada
    if [ -z "$THERMAL_PATH" ] && [ -n "$_first_zone_path" ]; then
        THERMAL_PATH="$_first_zone_path"
    fi
    echo "$_count|$_writable"
    # Global tetap tersedia di luar fungsi (shell non-local)
}

# STEP4: Vendor-specific SoC detection (sandboxable getprop)
# Helper getprop aman (hasil kosong, rc 0 bila perintah hilang)
_getprop_safe() {
    getprop "$1" 2>/dev/null || echo ""
}

# 1. Qualcomm
detect_qualcomm() {
    _model=$(getprop ro.soc.model 2>/dev/null || echo "")
    case "$_model" in
        *[Ss][Mm]*|*[Ss][Dd]*|*[Mm][Ss][Mm]*)
            [ -n "$_model" ] || _model=$(getprop ro.board.platform 2>/dev/null || echo "")
            ;;
    esac
    if [ -z "$_model" ]; then
        _model=$(getprop ro.board.platform 2>/dev/null || echo "")
    fi
    case "$_model" in
        *[Ss][Mm][0-9]*|*[Ss][Dd][0-9]*|*[Mm][Ss][Mm]*|*[Qq][Cc][Oo][Mm]*|*snapdragon*)
            SOC_VENDOR="QUALCOMM"
            SOC_MODEL="$_model"
            GPU_VENDOR="ADRENO"
            return 0
            ;;
    esac
    _bp=$(getprop ro.board.platform 2>/dev/null || echo "")
    case "$_bp" in
        *[Qq][Cc][Oo][Mm]*|*msm*|*snapdragon*)
            SOC_VENDOR="QUALCOMM"
            SOC_MODEL="$_bp"
            GPU_VENDOR="ADRENO"
            return 0
            ;;
    esac
    return 1
}

# 2. MediaTek
detect_mediatek() {
    _model=$(getprop ro.soc.model 2>/dev/null || echo "")
    _platform=$(getprop ro.vendor.mediatek.platform 2>/dev/null || echo "")
    _lib=$(getprop ro.vendor.extension_library 2>/dev/null || echo "")
    # Urutan model: ro.soc.model → ro.vendor.mediatek.platform → lib (terakhir)
    SOC_MODEL="$_model"
    [ -n "$SOC_MODEL" ] || SOC_MODEL="$_platform"
    [ -n "$SOC_MODEL" ] || SOC_MODEL="$_lib"
    case "$_model$_platform$_lib" in
        *[Mm][Tt][Kk]*|*[Ll][Ii][Bb][Mm][Tt]*|*mediatek*|*mt[0-9]*)
            SOC_VENDOR="MEDIATEK"
            [ -n "$SOC_MODEL" ] || SOC_MODEL="$_lib"
            GPU_VENDOR="MALI"
            return 0
            ;;
    esac
    return 1
}

# 3. Exynos
detect_exynos() {
    _fp=$(getprop ro.vendor.fingerprint 2>/dev/null || echo "")
    _model=$(getprop ro.soc.model 2>/dev/null || echo "")
    _bp=$(getprop ro.board.platform 2>/dev/null || echo "")
    case "$_fp$_model$_bp" in
        *[Ss][Aa][Mm][Ss][Uu][Nn][Gg]*|*[Ee][Xx][Yy][Nn][Oo][Ss]*|*[Ee][Rr][Dd]*|*[Ss]5[Ee]*|*[Uu][Nn][Ii][Vv][Ee][Rr][Ss][Aa][Ll]*|*samsung*)
            SOC_VENDOR="EXYNOS"
            SOC_MODEL="$_model"
            [ -n "$SOC_MODEL" ] || SOC_MODEL="$_bp"
            [ -n "$SOC_MODEL" ] || SOC_MODEL="$_fp"
            # Cek Xclipse via compatible
            if [ -f "$HSIN_PROC/device-tree/compatible" ]; then
                _compat=$(tr -d '\0' < "$HSIN_PROC/device-tree/compatible" 2>/dev/null | tr '[:upper:]' '[:lower:]')
                case "$_compat" in
                    *xclipse*) GPU_VENDOR="XCLIPSE" ;;
                    *) GPU_VENDOR="MALI" ;;
                esac
            else
                GPU_VENDOR="MALI"
            fi
            return 0
            ;;
    esac
    return 1
}

# 4. Unisoc
detect_unisoc() {
    _bp=$(getprop ro.board.platform 2>/dev/null || echo "")
    case "$_bp" in
        *[Uu][Mm][Ss]*|*[Uu][Nn][Ii][Ss][Oo][Cc]*|*[Ss][Pp][Rr][Dd]*|*spreadtrum*)
            SOC_VENDOR="UNISOC"
            SOC_MODEL="$_bp"
            GPU_VENDOR="MALI"
            return 0
            ;;
    esac
    _model=$(getprop ro.soc.model 2>/dev/null || echo "")
    case "$_model" in
        *[Uu][Mm][Ss]*|*[Tt]6*|*[Tt]7*|*[Tt]8*|*unisoc*|*sprd*)
            SOC_VENDOR="UNISOC"
            SOC_MODEL="$_model"
            GPU_VENDOR="MALI"
            return 0
            ;;
    esac
    return 1
}

# 5. Apple
detect_apple() {
    if [ -f "$HSIN_PROC/device-tree/compatible" ]; then
        _compat=$(tr -d '\0' < "$HSIN_PROC/device-tree/compatible" 2>/dev/null | tr '[:upper:]' '[:lower:]')
        case "$_compat" in
            *apple*)
                SOC_VENDOR="APPLE"
                SOC_MODEL="apple"
                GPU_VENDOR="APPLE"
                return 0
                ;;
        esac
    fi
    return 1
}

# 6. CPU policies
detect_cpu_policies() {
    CPU_POLICIES=""
    _cpu_base="${HSIN_SYSFS_CPU:-/sys/devices/system/cpu}"
    _policies=""
    for p in $_cpu_base/cpufreq/policy*; do
        [ -d "$p" ] || continue
        _name=$(basename "$p")
        case " $_policies " in
            *" $_name "*) ;;
            *) _policies="$_policies $_name" ;;
        esac
    done
    # Trim leading space
    CPU_POLICIES=$(echo "$_policies" | sed 's/^ *//')
    if [ -z "$CPU_POLICIES" ]; then
        CPU_POLICIES="policy0"
    fi
    echo "$CPU_POLICIES"
}

# 7. Cache detection
cache_detection() {
    mkdir -p "$HSIN_DATA" 2>/dev/null
    {
        echo "SOC_VENDOR=${SOC_VENDOR:-}"
        echo "SOC_MODEL=${SOC_MODEL:-}"
        echo "GPU_VENDOR=${GPU_VENDOR:-}"
        echo "CPU_POLICIES=${CPU_POLICIES:-}"
        echo "THERMAL_PATH=${THERMAL_PATH:-}"
    } > "$HSIN_DATA/detected.conf"
}

# Block devices (storage) detection
detect_storage() {
    _devs=""
    for b in /sys/block/*; do
        [ -d "$b" ] || continue
        _name=$(basename "$b")
        case "$_name" in
            loop*|ram*|zram*|dm-*) continue ;;
        esac
        # Scheduler available
        _sched=$(cat "$b/queue/scheduler" 2>/dev/null | tr -d '[]' | awk '{print $1}')
        # Guard: read_ahead_kb may not exist on all block devices (eMMC
        # partitions, virtio, etc). The previous `||` default to "" is
        # already defensive but `cat` of a non-existent file would emit
        # to stderr - that's harmless but noisy. The `||` suppresses it.
        _ra=$(cat "$b/queue/read_ahead_kb" 2>/dev/null || echo "")
        _ro=$(cat "$b/queue/rotational" 2>/dev/null || echo "")
        _devs="$_devs$_name:s=$_sched:ra=$_ra:rot=$_ro;"
    done 2>/dev/null
    echo "$_devs"
}

# Network capabilities
detect_network() {
    _tcp_avail=$(cat $HSIN_PROC/sys/net/ipv4/tcp_available_congestion_control 2>/dev/null | tr ' ' '\n' | sort -u | tr '\n' ' ')
    _tcp_curr=$(cat $HSIN_PROC/sys/net/ipv4/tcp_congestion_control 2>/dev/null)
    echo "${_tcp_curr}|${_tcp_avail}"
}

# GPU device nodes (scan /sys/class/devfreq)
detect_gpu_nodes() {
    _nodes=""
    for d in /sys/class/devfreq/*; do
        [ -d "$d" ] || continue
        _name=$(basename "$d")
        case "$(echo "$_name" | tr '[:upper:]' '[:lower:]')" in
            *gpu*|*gfx*|*mali*|*kgsl*)
                _gov=$(cat "$d/governor" 2>/dev/null || echo "")
                _min=$(cat "$d/min_freq" 2>/dev/null || echo "")
                _max=$(cat "$d/max_freq" 2>/dev/null || echo "")
                _nodes="$_nodes$_name:gov=$_gov:min=$_min:max=$_max;"
                ;;
        esac
    done 2>/dev/null
    echo "$_nodes"
}

# Main: jalankan semua detector dan tulis ke JSON sederhana
hsin_detect_all() {
    mkdir -p "$HSIN_DATA"

    hsin_log_section "HSIN Hardware Detection"

    _soc=$(detect_soc)
    _vendor=$(classify_soc_vendor "$_soc")
    hsin_log_info "detect" "SoC: $_soc"
    hsin_log_info "detect" "Vendor: $_vendor"

    _gpu=$(detect_gpu_vendor)
    hsin_log_info "detect" "GPU vendor: $_gpu"

    _kernel=$(uname -r)
    _android=$(getprop ro.build.version.release)
    _sdk=$(getprop ro.build.version.sdk)
    _arch=$(uname -m)
    hsin_log_info "detect" "Kernel: $_kernel"
    hsin_log_info "detect" "Android: $_android (SDK $_sdk)"
    hsin_log_info "detect" "Arch: $_arch"

    _clusters=$(detect_cpu_clusters)
    _online=$(detect_core_online)
    _govs=$(detect_governor_list)
    hsin_log_info "detect" "CPU clusters: $(echo "$_clusters" | wc -l)"
    hsin_log_info "detect" "Cores online: $_online"
    hsin_log_info "detect" "Available governors: $_govs"

    _ram=$(detect_ram)
    _zram=$(detect_zram)
    # Panggil thermal tanpa $(...) agar THERMAL_PATH global tetap
    _thermal_tmp="${HSIN_DATA}/.thermal_tmp"
    detect_thermal_zones > "$_thermal_tmp"
    _thermal=$(cat "$_thermal_tmp" 2>/dev/null)
    rm -f "$_thermal_tmp"
    _storage=$(detect_storage)
    _net=$(detect_network)
    _gpu_nodes=$(detect_gpu_nodes)

    # STEP4: Deteksi vendor komprehensif (berhenti saat cocok)
    # Tidak reset SOC_VENDOR/SOC_MODEL/GPU_VENDOR agar hasil vendor baru tetap
    if detect_qualcomm; then
        : # SOC_VENDOR/SOC_MODEL/GPU_VENDOR sudah ter-set
    elif detect_mediatek; then
        : # sudah ter-set
    elif detect_exynos; then
        : # sudah ter-set
    elif detect_unisoc; then
        : # sudah ter-set
    elif detect_apple; then
        : # sudah ter-set
    fi
    if [ -n "$SOC_VENDOR" ]; then
        # Gunakan hasil vendor baru
        case "$SOC_VENDOR" in
            QUALCOMM) _vendor="qualcomm" ;;
            MEDIATEK) _vendor="mediatek" ;;
            EXYNOS) _vendor="exynos" ;;
            UNISOC) _vendor="unisoc" ;;
            APPLE) _vendor="apple" ;;
            *) _vendor="unknown" ;;
        esac
        if [ -n "$SOC_MODEL" ]; then
            _soc="$SOC_MODEL"
        fi
        if [ -n "$GPU_VENDOR" ]; then
            _gpu="$GPU_VENDOR"
        fi
        hsin_log_info "detect" "STEP4 vendor: $SOC_VENDOR model=$SOC_MODEL gpu=$GPU_VENDOR"
    else
        # Fallback ke existing (tidak ubah baris existing)
        # _soc, _vendor, _gpu sudah ada dari detect_soc/classify/gpu
        SOC_MODEL="$_soc"
        hsin_log_info "detect" "STEP4 fallback existing: vendor=$_vendor soc=$_soc"
    fi

    # STEP4: CPU policies + thermal path global
    CPU_POLICIES=$(detect_cpu_policies)
    # THERMAL_PATH sudah di-set oleh detect_thermal_zones() (dipanggil sebelumnya)
    # Tapi kita pastikan ada fallback jika belum
    [ -z "$THERMAL_PATH" ] && THERMAL_PATH=""

    # STEP4: Cache detection
    cache_detection
    hsin_log_info "detect" "STEP4 detected.conf cached"

    # Tulis JSON sederhana (no escapes, semua string adalah identifier-safe)
    {
        echo "{"
        echo "  \"soc\": \"$_soc\","
        echo "  \"vendor\": \"$_vendor\","
        echo "  \"gpu_vendor\": \"$_gpu\","
        echo "  \"kernel\": \"$_kernel\","
        echo "  \"android\": \"$_android\","
        echo "  \"sdk\": \"$_sdk\","
        echo "  \"arch\": \"$_arch\","
        echo "  \"ram_total_kb\": \"$(echo "$_ram" | cut -d'|' -f1)\","
        echo "  \"ram_avail_kb\": \"$(echo "$_ram" | cut -d'|' -f2)\","
        echo "  \"zram\": \"$(echo "$_zram" | cut -d'|' -f1)\","
        echo "  \"thermal_zones\": \"$(echo "$_thermal" | cut -d'|' -f1)\","
        echo "  \"thermal_writable\": \"$(echo "$_thermal" | cut -d'|' -f2)\","
        echo "  \"cores_online\": \"$(echo "$_online" | cut -d'|' -f1)\","
        echo "  \"cores_total\": \"$(echo "$_online" | cut -d'|' -f2)\","
        echo "  \"governors\": \"$_govs\","
        echo "  \"tcp_current\": \"$(echo "$_net" | cut -d'|' -f1)\","
        echo "  \"tcp_available\": \"$(echo "$_net" | cut -d'|' -f2)\","
        echo "  \"storage_raw\": \"$_storage\","
        echo "  \"gpu_nodes_raw\": \"$_gpu_nodes\","
        echo "  \"cpu_clusters_raw\": \"$(echo "$_clusters" | tr '\n' ';')\""
        echo "}"
    } > "$HSIN_DATA_DEVICE" 2>/dev/null

    # Plain text untuk grep/awk
    {
        echo "SOC=$_soc"
        echo "VENDOR=$_vendor"
        echo "GPU=$_gpu"
        echo "KERNEL=$_kernel"
        echo "ANDROID=$_android"
        echo "SDK=$_sdk"
        echo "ARCH=$_arch"
        echo "RAM_KB=$(echo "$_ram" | cut -d'|' -f1)"
        echo "ZRAM=$(echo "$_zram" | cut -d'|' -f1)"
        echo "THERMAL=$(echo "$_thermal" | cut -d'|' -f1)"
        echo "THERMAL_W=$(echo "$_thermal" | cut -d'|' -f2)"
        echo "CORES_ON=$(echo "$_online" | cut -d'|' -f1)"
        echo "CORES_TOTAL=$(echo "$_online" | cut -d'|' -f2)"
        echo "GOVS=$_govs"
        echo "TCP_CUR=$(echo "$_net" | cut -d'|' -f1)"
        echo "STORAGE=$_storage"
        echo "GPU_NODES=$_gpu_nodes"
        echo "CPU_CLUSTERS=$(echo "$_clusters" | tr '\n' '|')"
    } > "$HSIN_DATA_DEVICE_TXT" 2>/dev/null

    hsin_log_ok "detect" "device.json written: $HSIN_DATA_DEVICE"
}

# Entry point ketika di-source: definisikan semua function tapi JANGAN jalankan otomatis.
return 0 2>/dev/null || true
