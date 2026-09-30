#!/system/bin/sh
# HSIN Scan Cache - topologi hardware scan SEKALI, simpan, baca lagi.
#
# Alasan (audit timing 2026-09-26, NOTES.md): setiap apply thermal men-scan
# thermal_zone* tiga kali (3 pass: CPU, GPU, battery) dan tiap apply manual
# memindai ulang node CPU/GPU/block/thermal. Yang mahal itu globby + cat,
# bukan logikanya. Cache ini memegang TOPOLOGI + daftar node valid - BUKAN
# suhu dan BUKAN frekuensi - jadi data yang berubah tiap detik tetap dibaca
# langsung dari sysfs saat apply.
#
# Format: flat KEY=VALUE di $HSIN_SCAN_CACHE_FILE (pola sama dengan
# core/protect.sh .integrity_cache dan action.sh .cache_refresh_hz).
# Nilai list dipisah spasi; field dalam satu item dipisah '|'. Isi:
#   SCAN_VERSION     versi format cache (naik -> cache lama dibuang)
#   SCAN_TS          epoch detik saat scan
#   BOOT_ID          /proc/sys/kernel/random/boot_id (reboot -> cache lama)
#   CPU_POLICIES     id policy cpufreq yang ada
#   CPU_POLICY_<id>  gov|min|max|cores|hwmax|writable|opp1,opp2,...
#   CPU_BIG          policy dengan cpuinfo_max_freq tertinggi
#   CPU_LITTLE       policy dengan cpuinfo_max_freq terendah
#   GPU_VENDOR       mali|adreno|powervr|unknown
#   GPU_DEVFREQ      nama devfreq node yang terdeteksi sebagai GPU
#   DEVFREQ_NODES    semua devfreq node (set yang diiterasi thermal policy)
#   DEVFREQ_OPP_<n>  available_frequencies node itu (kosong = tidak ada)
#   THERMAL_ZONES    "zoneN|type|writable" per zona (type: spasi -> '_')
#   THERMAL_MAXZONE  zona terpanas saat scan (penanda zona utama)
#   BLOCKS           block device riil (loop/ram/zram/dm dilewati)
#   VM_NODES         file sysctl yang ada di /proc/sys/vm
#
# Sysfs dibaca lewat $SYSFS_*_PREFIX (default = sysfs asli) supaya seluruh
# jalur baca bisa diuji tanpa menyentuh /sys. Engine thermal memakai
# HSIN_SYSFS_* (di-set di sini) sebagai gantinya.

[ -z "$HSIN_MODULE_PATH" ] && HSIN_MODULE_PATH="/data/adb/modules/hsin"
HSIN_DATA="${HSIN_DATA:-/data/adb/hsin}"

HSIN_SCAN_VERSION=1
HSIN_SCAN_CACHE_FILE="${HSIN_SCAN_CACHE_FILE:-$HSIN_DATA/scan_cache.env}"
# Cache dianggap basi setelah 6 jam. Topologi jarang berubah, tapi cache
# lama setelah reboot/recovery tidak boleh dipakai untuk keputusan apply.
HSIN_SCAN_TTL=21600

# STEP 8: guard [ -n ... ] || di semua prefix (dulu assignment polos
# menimpa prefix sandbox yang di-export harness — Known Issue 2026-09-27).
# Di device variabel ini unset -> default sama persis, perilaku identik.
[ -n "$HSIN_SYSFS_CPU" ] || HSIN_SYSFS_CPU="${SYSFS_CPU_PREFIX:-/sys/devices/system/cpu}"
[ -n "$HSIN_SYSFS_THERMAL" ] || HSIN_SYSFS_THERMAL="${SYSFS_THERMAL_PREFIX:-/sys/class/thermal}"
[ -n "$HSIN_SYSFS_DEVFREQ" ] || HSIN_SYSFS_DEVFREQ="${SYSFS_DEVFREQ_PREFIX:-/sys/class/devfreq}"
[ -n "$HSIN_SYSFS_GPU" ] || HSIN_SYSFS_GPU="${SYSFS_GPU_PREFIX:-/sys/class/kgsl}"
[ -n "$HSIN_SYSFS_BLOCK" ] || HSIN_SYSFS_BLOCK="${SYSFS_BLOCK_PREFIX:-/sys/block}"
[ -n "$HSIN_PROC" ] || HSIN_PROC="${SYSFS_PROC_PREFIX:-/proc}"

# Hasil scan (diisi oleh hsin_scan_*_live / hsin_scan_cache_load).
HSIN_SCAN_OK=0
HSIN_SCAN_TS=0
HSIN_SCAN_BOOT_ID=""
HSIN_SCAN_CPU_POLICIES=""
HSIN_SCAN_CPU_POLICY_LINES=""
HSIN_SCAN_CPU_BIG=""
HSIN_SCAN_CPU_LITTLE=""
HSIN_SCAN_GPU_VENDOR="unknown"
HSIN_SCAN_GPU_DEVFREQ=""
HSIN_SCAN_DEVFREQ_NODES=""
HSIN_SCAN_DEVFREQ_LINES=""
HSIN_SCAN_THERMAL_ZONES=""
HSIN_SCAN_THERMAL_MAXZONE=""
HSIN_SCAN_BLOCKS=""
HSIN_SCAN_VM_NODES=""
# cache = daftar diambil dari cache, scan = glob sysfs live
HSIN_SCAN_THERMAL_SOURCE=""
HSIN_SCAN_CPU_SOURCE=""
HSIN_SCAN_DEVFREQ_SOURCE=""
# Penanda "sudah di-resolve sekali per proses". Di-reset di sini karena
# apply.sh me-source monitor.sh di tengah alur: tanpa reset, zona yang
# sudah di-resolve dianggap masih ada padahal HSIN_SCAN_* sudah dikosongkan.
HSIN_SCAN_ZONES_READY=""
HSIN_SCAN_CPU_READY=""
HSIN_SCAN_DEVFREQ_READY=""

# Baca satu nilai sysfs tanpa fork; hasilnya di var _sc_r.
hsin_scan_read() {
    _sc_r=""
    [ -r "$1" ] || return 1
    IFS= read -r _sc_r < "$1" 2>/dev/null
    return 0
}

hsin_scan_log() {
    command -v hsin_log_info >/dev/null 2>&1 && hsin_log_info "scan" "$1"
    return 0
}

# Klasifikasi zona thermal -> var _sc_class (tanpa fork, dipanggil per
# zona di dalam loop baca). Pola ini sama dengan yang dipakai detect.sh /
# monitor.sh versi lama, jadi hasil cache = hasil scan lama.
hsin_scan_classify() {
    case "$1" in
        *cpu*|*CPU*|*tsens_tz_sensor*) _sc_class="cpu" ;;
        *gpu*|*GPU*|*kgsl*) _sc_class="gpu" ;;
        *battery*|*batt*|*Battery*) _sc_class="battery" ;;
        *) _sc_class="other" ;;
    esac
}

# Rapikan satu field supaya spasi/pemisah list tidak merusak format.
hsin_scan_clean() {
    printf '%s' "$1" | tr -s ' \t|' '_'
}

# Daftar token -> satu string, dipisah spasi (tanpa fork).
hsin_scan_join() {
    _sc_j=""
    for _sc_t in "$@"; do
        [ -z "$_sc_t" ] && continue
        if [ -z "$_sc_j" ]; then
            _sc_j="$_sc_t"
        else
            _sc_j="$_sc_j $_sc_t"
        fi
    done
    printf '%s' "$_sc_j"
}

# Cari satu field pada tabel in-memory "id|rec id|rec".
#   $1 tabel, $2 id, $3 nomor field di dalam rec (1..n) -> hasil di _sc_f
hsin_scan_lookup() {
    _sc_f=""
    for _sc_l in $1; do
        case "$_sc_l" in
            "$2|"*) ;;
            *) continue ;;
        esac
        _sc_rest="${_sc_l#*\|}"
        _sc_i=1
        while [ "$_sc_i" -lt "$3" ]; do
            case "$_sc_rest" in
                *'|'*) _sc_rest="${_sc_rest#*\|}" ;;
                *) _sc_rest=""; break ;;
            esac
            _sc_i=$((_sc_i + 1))
        done
        # _sc_i == $3 = field yang dicari masih ada; ambil satu field saja
        # (field terakhir tidak punya '|' jadi harus tetap diambil utuh).
        if [ "$_sc_i" -eq "$3" ]; then
            case "$_sc_rest" in
                *'|'*) _sc_f="${_sc_rest%%\|*}" ;;
                *) _sc_f="$_sc_rest" ;;
            esac
        fi
        return 0
    done
    return 1
}

hsin_scan_boot_id() {
    hsin_scan_read "$HSIN_PROC/sys/kernel/random/boot_id" || return 0
    printf '%s' "$_sc_r"
}

# --- scan live (sekali saat boot / rescan) --------------------------------

hsin_scan_cpu_live() {
    HSIN_SCAN_CPU_POLICIES=""
    HSIN_SCAN_CPU_POLICY_LINES=""
    HSIN_SCAN_CPU_BIG=""
    HSIN_SCAN_CPU_LITTLE=""
    _sc_big_hw=0
    _sc_low_hw=0

    for _sc_p in "$HSIN_SYSFS_CPU"/cpufreq/policy*; do
        [ -d "$_sc_p" ] || continue
        _sc_id="${_sc_p##*/policy}"
        case "$_sc_id" in ''|*[!0-9]*) continue ;; esac

        hsin_scan_read "$_sc_p/scaling_governor"; _sc_gov="$_sc_r"
        hsin_scan_read "$_sc_p/scaling_min_freq"; _sc_min="$_sc_r"
        hsin_scan_read "$_sc_p/scaling_max_freq"; _sc_max="$_sc_r"
        hsin_scan_read "$_sc_p/related_cpus"; _sc_cores="$_sc_r"
        [ -z "$_sc_cores" ] && { hsin_scan_read "$_sc_p/cpus"; _sc_cores="$_sc_r"; }
        [ -z "$_sc_cores" ] && _sc_cores="$_sc_id"
        hsin_scan_read "$_sc_p/cpuinfo_max_freq"; _sc_hw="$_sc_r"
        hsin_scan_read "$_sc_p/scaling_available_frequencies"; _sc_opp="$_sc_r"

        _sc_w=0
        [ -w "$_sc_p/scaling_max_freq" ] && _sc_w=1
        # OPP jadi daftar koma: satu item per policy, tidak ada spasi di
        # dalam item, jadi tabel cache tetap bisa dipisah spasi.
        _sc_opp_csv=$(printf '%s' "$_sc_opp" | tr -s ' \t' '\n' | tr '\n' ',' | sed 's/,$//')

        HSIN_SCAN_CPU_POLICIES="$(hsin_scan_join "$HSIN_SCAN_CPU_POLICIES" "$_sc_id")"
        HSIN_SCAN_CPU_POLICY_LINES="$HSIN_SCAN_CPU_POLICY_LINES$_sc_id|$(hsin_scan_clean "$_sc_gov")|${_sc_min}|${_sc_max}|$(hsin_scan_clean "$_sc_cores")|${_sc_hw}|${_sc_w}|${_sc_opp_csv} "

        # Klaster besar/kecil = cpuinfo_max_freq tertinggi/terendah. Dipakai
        # engine cpu nanti; thermal cuma butuh daftar policy-nya.
        case "$_sc_hw" in
            ''|*[!0-9]*) ;;
            *)
                if [ "$_sc_hw" -gt "$_sc_big_hw" ] 2>/dev/null; then
                    _sc_big_hw="$_sc_hw"
                    HSIN_SCAN_CPU_BIG="$_sc_id"
                fi
                if [ "$_sc_low_hw" -eq 0 ] 2>/dev/null || [ "$_sc_hw" -lt "$_sc_low_hw" ] 2>/dev/null; then
                    _sc_low_hw="$_sc_hw"
                    HSIN_SCAN_CPU_LITTLE="$_sc_id"
                fi
                ;;
        esac
    done
    return 0
}

hsin_scan_gpu_live() {
    HSIN_SCAN_GPU_DEVFREQ=""
    HSIN_SCAN_DEVFREQ_NODES=""
    HSIN_SCAN_DEVFREQ_LINES=""
    _sc_vendor="unknown"

    for _sc_d in "$HSIN_SYSFS_DEVFREQ"/*; do
        [ -d "$_sc_d" ] || continue
        _sc_dn="${_sc_d##*/}"
        hsin_scan_read "$_sc_d/available_frequencies"; _sc_opp="$_sc_r"
        _sc_opp_csv=$(printf '%s' "$_sc_opp" | tr -s ' \t' '\n' | tr '\n' ',' | sed 's/,$//')

        HSIN_SCAN_DEVFREQ_NODES="$(hsin_scan_join "$HSIN_SCAN_DEVFREQ_NODES" "$_sc_dn")"
        HSIN_SCAN_DEVFREQ_LINES="$HSIN_SCAN_DEVFREQ_LINES$_sc_dn|${_sc_opp_csv} "

        if command -v hsin_devfreq_gpu_candidate >/dev/null 2>&1; then
            hsin_devfreq_gpu_candidate "$_sc_d" || continue
        else
            case "$_sc_dn" in *gpu*|*gfx*|*mali*|*kgsl*) ;; *) continue ;; esac
        fi
        HSIN_SCAN_GPU_DEVFREQ="$(hsin_scan_join "$HSIN_SCAN_GPU_DEVFREQ" "$_sc_dn")"
        case "$_sc_dn" in
            *mali*) _sc_vendor="mali" ;;
            *kgsl*|*adreno*) _sc_vendor="adreno" ;;
            *pvr*|*img*|*powervr*) _sc_vendor="powervr" ;;
        esac
    done

    [ -d "$HSIN_SYSFS_GPU/kgsl-3d0" ] && [ "$_sc_vendor" = "unknown" ] && _sc_vendor="adreno"
    HSIN_SCAN_GPU_VENDOR="$_sc_vendor"
    return 0
}

# Daftar zona thermal sebagai "zoneN|type|writable" (spasi antar item).
# Dipakai juga sebagai fallback saat cache tidak ada/rusak, jadi hanya ada
# SATU implementasi scan zona di repo ini.
hsin_scan_thermal_live() {
    _sc_tz=""
    _sc_tmax=""
    _sc_tmax_v=0

    for _sc_z in "$HSIN_SYSFS_THERMAL"/thermal_zone*; do
        [ -d "$_sc_z" ] || continue
        hsin_scan_read "$_sc_z/type" || continue
        _sc_type="$(hsin_scan_clean "$_sc_r")"
        [ -n "$_sc_type" ] || continue
        _sc_zn="${_sc_z##*/}"
        _sc_w=0
        [ -w "$_sc_z/temp" ] && _sc_w=1
        _sc_tz="$_sc_tz $_sc_zn|$_sc_type|$_sc_w"

        hsin_scan_read "$_sc_z/temp" || continue
        case "$_sc_r" in ''|*[!0-9]*) continue ;; esac
        if [ "$_sc_r" -gt "$_sc_tmax_v" ] 2>/dev/null; then
            _sc_tmax_v="$_sc_r"
            _sc_tmax="$_sc_zn"
        fi
    done

    HSIN_SCAN_THERMAL_ZONES="${_sc_tz# }"
    HSIN_SCAN_THERMAL_MAXZONE="$_sc_tmax"
    return 0
}

hsin_scan_blocks_live() {
    HSIN_SCAN_BLOCKS=""
    for _sc_b in "$HSIN_SYSFS_BLOCK"/*; do
        [ -d "$_sc_b" ] || continue
        _sc_bn="${_sc_b##*/}"
        case "$_sc_bn" in loop*|ram*|zram*|dm-*) continue ;; esac
        HSIN_SCAN_BLOCKS="$(hsin_scan_join "$HSIN_SCAN_BLOCKS" "$_sc_bn")"
    done
    return 0
}

hsin_scan_vm_live() {
    HSIN_SCAN_VM_NODES=""
    for _sc_v in "$HSIN_PROC"/sys/vm/*; do
        [ -f "$_sc_v" ] || continue
        HSIN_SCAN_VM_NODES="$(hsin_scan_join "$HSIN_SCAN_VM_NODES" "${_sc_v##*/}")"
    done
    return 0
}

# Scan penuh lalu tulis cache (atomic lewat file tmp + mv).
hsin_scan_write() {
    mkdir -p "$HSIN_DATA" 2>/dev/null

    hsin_scan_cpu_live
    hsin_scan_gpu_live
    hsin_scan_thermal_live
    hsin_scan_blocks_live
    hsin_scan_vm_live

    HSIN_SCAN_BOOT_ID="$(hsin_scan_boot_id)"
    HSIN_SCAN_TS=$(date +%s 2>/dev/null)
    case "$HSIN_SCAN_TS" in ''|*[!0-9]*) HSIN_SCAN_TS=0 ;; esac
    HSIN_SCAN_OK=1

    # Cache yang benar-benar kosong TIDAK boleh dikommit. Begitu ditulis,
    # file itu dianggap sah sampai TTL habis atau reboot, dan pembaca
    # (termasuk apply) lalu memakai 0 policy + 0 zona sebagai fakta -
    # artinya hsin_thermal_read() dan hsin_cpu_safety_temp() membaca nol
    # lalu menganggap device "cool", bukan jatuh ke scan live. Scan kosong
    # terjadi di dunia nyata (sysfs belum naik saat boot, permission,
    # mount telat), jadi lebih aman membiarkan cache kosong tidak
    # tertulis sama sekali. Device yang memang tidak punya zona termal
    # tetap aman: yang dilarang hanya cache kosong, bukan device tanpa zona.
    if [ -z "$HSIN_SCAN_CPU_POLICIES$HSIN_SCAN_THERMAL_ZONES$HSIN_SCAN_DEVFREQ_NODES" ]; then
        hsin_scan_log "scan kosong (tanpa policy/zona/devfreq) - cache TIDAK ditulis, pembaca tetap scan live"
        return 1
    fi

    _sw_tmp="$HSIN_SCAN_CACHE_FILE.tmp.$$"
    {
        echo "SCAN_VERSION=$HSIN_SCAN_VERSION"
        echo "SCAN_TS=$HSIN_SCAN_TS"
        echo "BOOT_ID=$HSIN_SCAN_BOOT_ID"
        echo "CPU_POLICIES=$HSIN_SCAN_CPU_POLICIES"
        for _sw_p in $HSIN_SCAN_CPU_POLICY_LINES; do
            echo "CPU_POLICY_${_sw_p%%\|*}=${_sw_p#*\|}"
        done
        echo "CPU_BIG=$HSIN_SCAN_CPU_BIG"
        echo "CPU_LITTLE=$HSIN_SCAN_CPU_LITTLE"
        echo "GPU_VENDOR=$HSIN_SCAN_GPU_VENDOR"
        echo "GPU_DEVFREQ=$HSIN_SCAN_GPU_DEVFREQ"
        echo "DEVFREQ_NODES=$HSIN_SCAN_DEVFREQ_NODES"
        for _sw_d in $HSIN_SCAN_DEVFREQ_LINES; do
            echo "DEVFREQ_OPP_${_sw_d%%\|*}=${_sw_d#*\|}"
        done
        echo "THERMAL_ZONES=$HSIN_SCAN_THERMAL_ZONES"
        echo "THERMAL_MAXZONE=$HSIN_SCAN_THERMAL_MAXZONE"
        echo "BLOCKS=$HSIN_SCAN_BLOCKS"
        echo "VM_NODES=$HSIN_SCAN_VM_NODES"
    } > "$_sw_tmp" 2>/dev/null || { rm -f "$_sw_tmp" 2>/dev/null; return 1; }

    mv -f "$_sw_tmp" "$HSIN_SCAN_CACHE_FILE" 2>/dev/null || {
        rm -f "$_sw_tmp" 2>/dev/null
        return 1
    }
    chmod 600 "$HSIN_SCAN_CACHE_FILE" 2>/dev/null
    hsin_scan_log "cache written: zones=$(printf '%s' "$HSIN_SCAN_THERMAL_ZONES" | wc -w | tr -d ' ') policies=$HSIN_SCAN_CPU_POLICIES devfreq=$HSIN_SCAN_DEVFREQ_NODES gpu=$HSIN_SCAN_GPU_VENDOR"
    return 0
}

# --- baca cache -----------------------------------------------------------

# Parse cache ke HSIN_SCAN_*. Hanya key yang dikenal yang dipakai, dan
# baru ditulis ke HSIN_SCAN_* SETELAH semua validasi lolos - jadi file
# rusak / versi lama / boot_id beda tidak pernah meninggalkan setengah
# data di var global. Engine tinggal pakai scan live.
hsin_scan_cache_load() {
    HSIN_SCAN_OK=0
    [ -f "$HSIN_SCAN_CACHE_FILE" ] || return 1

    _sl_ver=""
    _sl_ts=""
    _sl_boot=""
    _sl_have_zones=0
    _sl_have_policies=0
    _sl_have_devfreq=0
    _sl_cpu_policies=""
    _sl_cpu_lines=""
    _sl_big=""
    _sl_little=""
    _sl_gpu_vendor=""
    _sl_gpu_devfreq=""
    _sl_devfreq_nodes=""
    _sl_devfreq_lines=""
    _sl_zones=""
    _sl_maxzone=""
    _sl_blocks=""
    _sl_vm=""
    _sl_cr=$(printf '\r')

    while IFS= read -r _sl_l || [ -n "$_sl_l" ]; do
        _sl_l="${_sl_l%"$_sl_cr"}"
        _sl_l="${_sl_l#"${_sl_l%%[! ]*}"}"
        _sl_l="${_sl_l%"${_sl_l##*[! ]}"}"
        case "$_sl_l" in
            ''|'#'*) continue ;;
            SCAN_VERSION=*) _sl_ver="${_sl_l#*=}" ;;
            SCAN_TS=*) _sl_ts="${_sl_l#*=}" ;;
            BOOT_ID=*) _sl_boot="${_sl_l#*=}" ;;
            CPU_POLICIES=*) _sl_cpu_policies="${_sl_l#*=}"; _sl_have_policies=1 ;;
            CPU_POLICY_*=*)
                _sl_cid="${_sl_l%%=*}"
                _sl_cid="${_sl_cid#CPU_POLICY_}"
                _sl_cpu_lines="$_sl_cpu_lines ${_sl_cid}|${_sl_l#*=}"
                ;;
            CPU_BIG=*) _sl_big="${_sl_l#*=}" ;;
            CPU_LITTLE=*) _sl_little="${_sl_l#*=}" ;;
            GPU_VENDOR=*) _sl_gpu_vendor="${_sl_l#*=}" ;;
            GPU_DEVFREQ=*) _sl_gpu_devfreq="${_sl_l#*=}" ;;
            DEVFREQ_NODES=*) _sl_devfreq_nodes="${_sl_l#*=}"; _sl_have_devfreq=1 ;;
            DEVFREQ_OPP_*=*)
                _sl_did="${_sl_l%%=*}"
                _sl_did="${_sl_did#DEVFREQ_OPP_}"
                _sl_devfreq_lines="$_sl_devfreq_lines ${_sl_did}|${_sl_l#*=}"
                ;;
            THERMAL_ZONES=*) _sl_zones="${_sl_l#*=}"; _sl_have_zones=1 ;;
            THERMAL_MAXZONE=*) _sl_maxzone="${_sl_l#*=}" ;;
            BLOCKS=*) _sl_blocks="${_sl_l#*=}" ;;
            VM_NODES=*) _sl_vm="${_sl_l#*=}" ;;
        esac
    done < "$HSIN_SCAN_CACHE_FILE"

    [ "$_sl_ver" = "$HSIN_SCAN_VERSION" ] || return 1
    case "$_sl_ts" in ''|*[!0-9]*) return 1 ;; esac
    [ "$_sl_have_zones" = "1" ] || return 1
    [ "$_sl_have_policies" = "1" ] || return 1
    [ "$_sl_have_devfreq" = "1" ] || return 1
    # Key boleh ada tapi nilainya kosong - itu cache dari scan yang gagal,
    # dan menerimanya membuat thermal/CPU safety buta (lihat gate tulis di
    # hsin_scan_write). Fallback ke scan live selalu lebih aman.
    [ -n "$_sl_cpu_policies$_sl_zones$_sl_devfreq_nodes" ] || return 1

    # boot_id beda = cache dari boot sebelumnya (atau device lain).
    if [ -n "$_sl_boot" ]; then
        [ "$_sl_boot" = "$(hsin_scan_boot_id)" ] || return 1
    fi

    _sl_now=$(date +%s 2>/dev/null)
    case "$_sl_now" in ''|*[!0-9]*) _sl_now=0 ;; esac
    _sl_age=$((_sl_now - _sl_ts))
    [ "$_sl_age" -ge 0 ] 2>/dev/null || return 1
    [ "$_sl_age" -lt "$HSIN_SCAN_TTL" ] 2>/dev/null || return 1

    HSIN_SCAN_TS="$_sl_ts"
    HSIN_SCAN_BOOT_ID="$_sl_boot"
    HSIN_SCAN_CPU_POLICIES="$_sl_cpu_policies"
    HSIN_SCAN_CPU_POLICY_LINES="${_sl_cpu_lines# }"
    HSIN_SCAN_CPU_BIG="$_sl_big"
    HSIN_SCAN_CPU_LITTLE="$_sl_little"
    HSIN_SCAN_GPU_VENDOR="$_sl_gpu_vendor"
    HSIN_SCAN_GPU_DEVFREQ="$_sl_gpu_devfreq"
    HSIN_SCAN_DEVFREQ_NODES="$_sl_devfreq_nodes"
    HSIN_SCAN_DEVFREQ_LINES="${_sl_devfreq_lines# }"
    HSIN_SCAN_THERMAL_ZONES="$_sl_zones"
    HSIN_SCAN_THERMAL_MAXZONE="$_sl_maxzone"
    HSIN_SCAN_BLOCKS="$_sl_blocks"
    HSIN_SCAN_VM_NODES="$_sl_vm"
    HSIN_SCAN_OK=1
    return 0
}

# --- accessor: cache kalau bisa, kalau tidak scan live --------------------
# Dipanggil sekali per proses; HSIN_SCAN_*_SOURCE mencatat jalur mana
# yang dipakai supaya log/CLI bisa lihat.

hsin_scan_thermal_zones_get() {
    [ -n "$HSIN_SCAN_ZONES_READY" ] && return 0
    if hsin_scan_cache_load; then
        HSIN_SCAN_THERMAL_SOURCE="cache"
    else
        hsin_scan_thermal_live
        HSIN_SCAN_THERMAL_SOURCE="scan"
    fi
    HSIN_SCAN_ZONES_READY=1
    export HSIN_SCAN_THERMAL_SOURCE
    return 0
}

hsin_scan_cpu_get() {
    [ -n "$HSIN_SCAN_CPU_READY" ] && return 0
    if hsin_scan_cache_load; then
        HSIN_SCAN_CPU_SOURCE="cache"
    else
        hsin_scan_cpu_live
        HSIN_SCAN_CPU_SOURCE="scan"
    fi
    HSIN_SCAN_CPU_READY=1
    export HSIN_SCAN_CPU_SOURCE
    return 0
}

hsin_scan_devfreq_get() {
    [ -n "$HSIN_SCAN_DEVFREQ_READY" ] && return 0
    if hsin_scan_cache_load; then
        HSIN_SCAN_DEVFREQ_SOURCE="cache"
    else
        hsin_scan_gpu_live
        HSIN_SCAN_DEVFREQ_SOURCE="scan"
    fi
    HSIN_SCAN_DEVFREQ_READY=1
    export HSIN_SCAN_DEVFREQ_SOURCE
    return 0
}

# Cache siap pakai; kalau tidak, scan ulang lalu tulis (self-heal).
hsin_scan_cache_ensure() {
    if hsin_scan_cache_load; then
        return 0
    fi
    hsin_scan_log "cache tidak valid/tak ada -> rescan (versi=$HSIN_SCAN_VERSION)"
    hsin_scan_write
}

# Ringkasan satu baris untuk CLI/log.
hsin_scan_cache_status() {
    if hsin_scan_cache_load; then
        _ss_mode="ready"
    else
        _ss_mode="stale"
    fi
    printf 'Scan cache: %s file=%s ts=%s boot=%s zones=%s policies=%s devfreq=%s gpu=%s\n' \
        "$_ss_mode" "$HSIN_SCAN_CACHE_FILE" "$HSIN_SCAN_TS" "${HSIN_SCAN_BOOT_ID:-unknown}" \
        "$(printf '%s' "$HSIN_SCAN_THERMAL_ZONES" | wc -w | tr -d ' ')" \
        "$HSIN_SCAN_CPU_POLICIES" "$HSIN_SCAN_DEVFREQ_NODES" "$HSIN_SCAN_GPU_VENDOR"
}

return 0 2>/dev/null || true
