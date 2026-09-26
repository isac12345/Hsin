#!/system/bin/sh
# HSIN GPU Engine - Universal Detector
[ -z "$HSIN_MODULE_PATH" ] && HSIN_MODULE_PATH="/data/adb/modules/hsin"
. "$HSIN_MODULE_PATH/core/sysfs.sh" 2>/dev/null
# shellcheck disable=SC1091
. "$HSIN_MODULE_PATH/core/scan_cache.sh" 2>/dev/null
# Path sysfs dari core/scan_cache.sh (satu-satunya definisi), default sama
# dengan path yang sebelumnya ditulis langsung di file ini. Mali platform /
# kbase / ged tidak punya var di scan_cache, jadi dicatat di sini dengan
# pola SYSFS_*_PREFIX yang sama supaya semua jalur baca bisa diuji dengan
# sysfs palsu.
[ -n "$HSIN_SYSFS_DEVFREQ" ] || HSIN_SYSFS_DEVFREQ="${SYSFS_DEVFREQ_PREFIX:-/sys/class/devfreq}"
[ -n "$HSIN_SYSFS_GPU" ] || HSIN_SYSFS_GPU="${SYSFS_GPU_PREFIX:-/sys/class/kgsl}"
HSIN_SYSFS_MALI="${SYSFS_MALI_PREFIX:-/sys/devices/platform}"
HSIN_SYSFS_KBASE="${SYSFS_KBASE_PREFIX:-/sys/module/mali_kbase/parameters}"
HSIN_SYSFS_GED="${SYSFS_GED_PREFIX:-/sys/kernel/ged}"
# Diisi hsin_scan_lookup() (core/scan_cache.sh).
_sc_f=""
# Diisi hsin_gpu_csv_to_words() di bawah.
_hgw_words=""
# Diisi hsin_gpu_opp_list() di bawah.
_hgo_avail=""

# Node devfreq yang lolos klasifikasi GPU (hsin_devfreq_gpu_candidate), dipisah
# spasi. Cache-first: hsin_scan_devfreq_get() memberi daftar ini dari cache
# scan-sekali-simpan (GPU_DEVFREQ) yang diklasifikasi dengan fungsi yang SAMA
# persis, jadi apply tidak perlu glob /sys/class/devfreq/* + 2 fork per node
# lagi. Cache hilang/rusak/versi naik/boot beda/tidak memuat daftar GPU ->
# scan live, persis loop yang lama. Di-resolve SEKALI per proses supaya
# backup + apply + restore dalam satu apply cuma satu kali.
HSIN_GPU_DEVFRES=""
HSIN_GPU_NODE_SOURCE=""
HSIN_GPU_NODES_READY=""

hsin_gpu_devfreq_candidates() {
    [ -n "$HSIN_GPU_NODES_READY" ] && return 0
    command -v hsin_scan_devfreq_get >/dev/null 2>&1 && hsin_scan_devfreq_get
    HSIN_GPU_DEVFRES=""
    if [ -n "$HSIN_SCAN_GPU_DEVFREQ" ]; then
        # Dari cache ATAU dari scan live barusan: hsin_scan_gpu_live() sudah
        # mengklasifikasi tiap node dengan hsin_devfreq_gpu_candidate() yang
        # sama persis, jadi daftar ini tidak perlu glob kedua.
        for _hgd_n in $HSIN_SCAN_GPU_DEVFREQ; do
            HSIN_GPU_DEVFRES="${HSIN_GPU_DEVFRES:+$HSIN_GPU_DEVFRES }$HSIN_SYSFS_DEVFREQ/$_hgd_n"
        done
        HSIN_GPU_NODE_SOURCE="${HSIN_SCAN_DEVFREQ_SOURCE:-scan}"
    else
        # Tidak ada node GPU di cache/scan - atau core/scan_cache.sh tak
        # termuat sama sekali. Glob sysfs langsung, seperti implementasi lama.
        for _hgd_d in "$HSIN_SYSFS_DEVFREQ"/*; do
            [ -d "$_hgd_d" ] || continue
            hsin_devfreq_gpu_candidate "$_hgd_d" || continue
            HSIN_GPU_DEVFRES="${HSIN_GPU_DEVFRES:+$HSIN_GPU_DEVFRES }$_hgd_d"
        done
        HSIN_GPU_NODE_SOURCE="scan"
    fi
    HSIN_GPU_NODES_READY=1
    export HSIN_GPU_NODE_SOURCE
    return 0
}

# Field OPP di cache disimpan sebagai koma (satu item per node, supaya tabel
# cache tetap bisa dipisah spasi). Ubah ke spasi tanpa fork dan tanpa menyentuh
# IFS global - hasil di _hgw_words.
hsin_gpu_csv_to_words() {
    _hgw_words=""
    _hgw_rest="$1"
    while [ -n "$_hgw_rest" ]; do
        _hgw_tok="${_hgw_rest%%,*}"
        if [ "$_hgw_tok" = "$_hgw_rest" ]; then
            _hgw_rest=""
        else
            _hgw_rest="${_hgw_rest#*,}"
        fi
        [ -z "$_hgw_tok" ] && continue
        if [ -z "$_hgw_words" ]; then
            _hgw_words="$_hgw_tok"
        else
            _hgw_words="$_hgw_words $_hgw_tok"
        fi
    done
    return 0
}

# available_frequencies satu node devfreq: dari cache (DEVFREQ_OPP_<n>, field
# 1) kalau ada; kalau tidak (cache tak termuat, node tidak ada di cache, atau
# cache tidak menyimpan OPP) baca file live seperti sebelumnya. Hasil di
# _hgo_avail dengan pemisah spasi, sama seperti isi file aslinya. Daftar OPP
# itu topologi statis, jadi aman dari cache - yang HSIN tulis sendiri
# (governor/max_freq/min_freq) tetap dibaca live di tempatnya.
hsin_gpu_opp_list() {
    _hgo_avail=""
    _hgo_n="${1##*/}"
    command -v hsin_scan_devfreq_get >/dev/null 2>&1 && hsin_scan_devfreq_get
    if command -v hsin_scan_lookup >/dev/null 2>&1; then
        hsin_scan_lookup "$HSIN_SCAN_DEVFREQ_LINES" "$_hgo_n" 1
        hsin_gpu_csv_to_words "$_sc_f"
        _hgo_avail="$_hgw_words"
    fi
    if [ -z "$_hgo_avail" ] && [ -f "$1/available_frequencies" ]; then
        _hgo_avail=$(cat "$1/available_frequencies" 2>/dev/null)
    fi
    return 0
}

hsin_gpu_detect() {
    HSIN_GPU_VENDOR="none"; HSIN_GPU_NODES=""; HSIN_GPU_DEVFREQ=""; HSIN_GPU_DEVFREQS=""; HSIN_GPU_PLATFORM=""; HSIN_GPU_KGSL=""; HSIN_GPU_MALI=""; HSIN_GPU_KBASE=""; HSIN_GPU_GED=""
    HSIN_GPU_GOV_WRITABLE="false"; HSIN_GPU_FREQ_WRITABLE="false"

    # Prefer KGSL when present: this is the native Adreno path.
    if [ -d "$HSIN_SYSFS_GPU/kgsl-3d0" ]; then
        HSIN_GPU_VENDOR="adreno"
        HSIN_GPU_KGSL="$HSIN_SYSFS_GPU/kgsl-3d0"
        HSIN_GPU_NODES="$HSIN_GPU_KGSL"
    fi

    # Universal devfreq scan. Vendor-specific names are only a hint; an OF
    # compatible/device modalias is also inspected so nodes such as 23100000.gpu
    # on Unisoc are correctly classified as GPU. Klasifikasi itself (OF
    # compatible) TETAP live per node - hanya daftarnya yang dari cache,
    # supaya device yang nama node-nya tidak mengandung "mali/gpu" tetap
    # dikenali sama seperti sebelumnya.
    hsin_gpu_devfreq_candidates
    for _d in $HSIN_GPU_DEVFRES; do
        [ -d "$_d" ] || { hsin_report_skip "GPU node ${_d##*/} hilang sejak scan (skip)"; continue; }
        [ -z "$HSIN_GPU_DEVFREQ" ] && HSIN_GPU_DEVFREQ="$_d"
        HSIN_GPU_DEVFREQS="$HSIN_GPU_DEVFREQS $_d"
        case "$HSIN_GPU_VENDOR" in
            none)
                _meta=$(cat "$_d/device/of_node/compatible" 2>/dev/null | tr '\0' ' ' | tr '[:upper:]' '[:lower:]')
                _name=$(basename "$_d" | tr '[:upper:]' '[:lower:]')
                case "$_meta $_name" in
                    *adreno*|*kgsl*) HSIN_GPU_VENDOR="adreno" ;;
                    *mali*) HSIN_GPU_VENDOR="mali" ;;
                    *powervr*|*pvr*|*imgtec*|*img*) HSIN_GPU_VENDOR="powervr" ;;
                    *) HSIN_GPU_VENDOR="generic" ;;
                esac
                ;;
        esac
    done

    # Fallback metadata for Mali KBase / classic platform paths.
    if [ "$HSIN_GPU_VENDOR" = "none" ]; then
        for _m in "$HSIN_SYSFS_MALI"/*.mali "$HSIN_SYSFS_MALI"/*mali*; do
            [ -d "$_m" ] || continue
            HSIN_GPU_VENDOR="mali"; HSIN_GPU_MALI="$_m"; HSIN_GPU_NODES="$_m"; break
        done
    fi
    [ -d "$HSIN_SYSFS_KBASE" ] && HSIN_GPU_KBASE="$HSIN_SYSFS_KBASE"
    [ -d "$HSIN_SYSFS_GED" ] && HSIN_GPU_GED="$HSIN_SYSFS_GED"
    [ -d "$HSIN_SYSFS_GPU/kgsl-3d0" ] && HSIN_GPU_VENDOR="adreno"

    [ -n "$HSIN_GPU_DEVFREQ" ] && HSIN_GPU_NODES="$HSIN_GPU_DEVFREQ"
    if [ -n "$HSIN_GPU_DEVFREQ" ]; then
        [ -w "$HSIN_GPU_DEVFREQ/governor" ] && HSIN_GPU_GOV_WRITABLE="true"
        [ -w "$HSIN_GPU_DEVFREQ/max_freq" ] && HSIN_GPU_FREQ_WRITABLE="true"
    fi
    [ -n "$HSIN_GPU_KGSL" ] && [ -w "$HSIN_GPU_KGSL/default_pwrlevel" ] && HSIN_GPU_FREQ_WRITABLE="true"
    command -v hsin_scan_log >/dev/null 2>&1 && hsin_scan_log "gpu detect source=$HSIN_GPU_NODE_SOURCE nodes=$HSIN_GPU_DEVFRES vendor=$HSIN_GPU_VENDOR"
    return 0
}

hsin_gpu_print() {
    hsin_gpu_detect
    echo ""
    echo "HSIN GPU Detection"
    printf "  Vendor: %s\n" "$HSIN_GPU_VENDOR"
    printf "  Devfreq: %s\n" "${HSIN_GPU_DEVFREQ:-none}"
    printf "  KGSL: %s\n" "${HSIN_GPU_KGSL:-none}"
    printf "  Writable governor: %s\n" "$HSIN_GPU_GOV_WRITABLE"
    printf "  Writable max_freq: %s\n" "$HSIN_GPU_FREQ_WRITABLE"
    if [ -n "$HSIN_GPU_DEVFREQ" ]; then
        [ -f "$HSIN_GPU_DEVFREQ/available_governors" ] && printf "  Governors: %s\n" "$(cat "$HSIN_GPU_DEVFREQ/available_governors" 2>/dev/null)"
        [ -f "$HSIN_GPU_DEVFREQ/available_frequencies" ] && printf "  Frequencies: %s\n" "$(cat "$HSIN_GPU_DEVFREQ/available_frequencies" 2>/dev/null)"
    fi
}

return 0 2>/dev/null || true
