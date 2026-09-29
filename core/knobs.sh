#!/system/bin/sh
# HSIN Knobs API - inventaris knob yang bisa diubah user BESERTA nilai yang
# benar-benar tersedia di device ini, sebagai SATU BARIS JSON.
#
# Ini kontrak data untuk aplikasi Android (HSIN): daftar pilihan di-render
# dari sini, bukan dari daftar yang diketik ulang di aplikasi. Karena itu
# aturannya ketat:
#   - READ-ONLY. Tidak ada satu pun tulis ke sysfs/proc di file ini.
#   - Tidak mengarang. Setiap angka/string berasal dari node nyata. Node
#     absen atau tidak terbaca -> [] / 0 / "" plus "supported":false di
#     bagiannya, bukan tebakan.
#   - Semua jalur sysfs/proc lewat $HSIN_SYSFS_* / $HSIN_PROC (dari
#     core/scan_cache.sh), jadi seluruhnya bisa diuji dengan sysfs/proc
#     palsu. Variabel yang kosong = jangan sentuh path apa pun, bagiannya
#     dilaporkan tidak tersedia.
#   - Struktur JSON dirakit di dalam string lalu dicetak SEKALI, supaya
#     tidak ada output lain yang bisa ikut tercampur ke baris JSON.
#   - Topologi (daftar policy, governor, OPP, node devfreq, block device)
#     diambil lewat helper cache-first yang sudah dipakai jalur apply, jadi
#     tidak ada glob sysfs tambahan per panggilan.
#
# Output: {"v":1,"profiles":[...],"cpu":{...},"gpu":{...},"memory":{...},
#          "io":{...},"network":{...},"display":{...},"features":{...},
#          "capabilities":{...}}

[ -z "$HSIN_MODULE_PATH" ] && HSIN_MODULE_PATH="/data/adb/modules/hsin"
HSIN_DATA="${HSIN_DATA:-/data/adb/hsin}"
# shellcheck disable=SC1091
. "$HSIN_MODULE_PATH/core/sysfs.sh" 2>/dev/null
# shellcheck disable=SC1091
. "$HSIN_MODULE_PATH/core/scan_cache.sh" 2>/dev/null

# --- primitif JSON (tanpa fork) --------------------------------------------

# Dibuang _kn_esc() dari tiap karakter: beberapa file node dibaca sebagai
# CRLF, dan CR di dalam string JSON menggagalkan parse.
HSIN_KN_CR=""
# Satu array string JSON, dibangun token per token (isi node dipisah spasi).
_kn_arr=""
_kn_first=1
# Diturunkan di _kn_cpu_json, dipakai _kn_feat_json untuk menguji apakah
# limiter DVFS punya node yang benar-benar bisa ditulis.
_kn_any_wmax=false
# Diisi helper yang dipakai ulang, di-defaultkan di sini supaya jelas
# bahwa var itu bukan milik file ini (pola yang sama dipakai
# engine/gpu/detector.sh dan engine/cpu/detect.sh).
_hgo_avail=""
_sc_r=""
# Direktori sysctl di bawah $HSIN_PROC, disimpan sebagai var supaya jalur
# sysctl di file ini tetap $HSIN_PROC/<var>/... : tidak ada satu pun path
# absolut di file ini, semuanya bisa diarahkan ke prefix palsu saat diuji
# (pola join yang sama dipakai core/backup.sh).
_kn_sysdir="sys"

# Escape satu string dari device jadi badan string JSON (tanpa tanda kutip).
# Dari isi node, hanya dua karakter yang bisa merusak JSON: tanda kutip dan
# backslash; spasi sah apa adanya, jadi string multi kata tetap utuh.
_kn_esc() {
    _kn_e=""
    _kn_s="$1"
    while [ -n "$_kn_s" ]; do
        _kn_c="${_kn_s%"${_kn_s#?}"}"
        _kn_s="${_kn_s#?}"
        if [ "$_kn_c" = "$HSIN_KN_CR" ]; then
            continue
        fi
        case "$_kn_c" in
            '"') _kn_e="${_kn_e}\\\"" ;;
            \\) _kn_e="${_kn_e}\\\\" ;;
            *) _kn_e="${_kn_e}${_kn_c}" ;;
        esac
    done
    return 0
}

# Node sysfs kadang berisi "N/A" atau baris kosong; JSON tidak boleh
# menerima itu sebagai angka, jadi yang tidak bisa dipakai dilaporkan 0.
_kn_num() {
    case "$1" in
        ''|*[!0-9]*) _kn_n=0 ;;
        *) _kn_n="$1" ;;
    esac
    return 0
}

# Flag di repo sudah berupa "true"/"false" (dipakai engine); di sini
# dikembalikan sebagai boolean JSON, bukan string.
_kn_bool() {
    if [ "$1" = "true" ]; then
        _kn_b=true
    else
        _kn_b=false
    fi
    return 0
}

_kn_arr_reset() {
    _kn_arr=""
    _kn_first=1
    return 0
}

# $1 = satu token bebas spasi
_kn_arr_add() {
    [ -n "$1" ] || return 0
    _kn_esc "$1"
    if [ "$_kn_first" = "1" ]; then
        _kn_arr="\"${_kn_e}\""
        _kn_first=0
    else
        _kn_arr="${_kn_arr},\"${_kn_e}\""
    fi
    return 0
}

# $1 = daftar token dipisah spasi (isi file node) -> array di _kn_arr
_kn_arr_list() {
    _kn_arr_reset
    for _kn_tok in $1; do
        _kn_arr_add "$_kn_tok"
    done
    return 0
}

# Versi angka untuk yang HARUS berupa frekuensi/Hz (opp_khz, modes_hz).
# Token non-numeric dibuang, bukan dipaksa jadi 0, supaya daftar tetap
# berarti "nilai yang benar-benar ada di device ini".
_kn_arr_num_list() {
    _kn_arr_reset
    for _kn_tok in $1; do
        _kn_num "$_kn_tok"
        [ "$_kn_n" = "0" ] && continue
        if [ "$_kn_first" = "1" ]; then
            _kn_arr="$_kn_n"
            _kn_first=0
        else
            _kn_arr="${_kn_arr},${_kn_n}"
        fi
    done
    return 0
}

# Daftar OPP hanya dipublikasikan kalau benar-benar bisa diurai jadi
# frekuensi: hsin_opp_min/max harus menemukan angka bawah dan atas. Node
# devfreq beberapa vendor memang berisi "-" atau "N/A" dan itu tidak boleh
# muncul sebagai angka di JSON. Angka atas disimpan di _kn_hi karena dipakai
# sebagai plafon hardware saat cpuinfo_max_freq tidak diekspos kernel.
_kn_opp_ok() {
    _kn_opp_ok=false
    _kn_hi=""
    [ -n "$1" ] || return 0
    _kn_lo=$(hsin_opp_min "$1")
    _kn_hi=$(hsin_opp_max "$1")
    [ -n "$_kn_lo" ] && [ -n "$_kn_hi" ] && _kn_opp_ok=true
    return 0
}

# Kernel menandai nilai yang SEDANG aktif dengan kurung siku, misalnya
# comp_algorithm "lz4 deflate [zstd] lzo" atau queue/scheduler
# "none [mq-deadline] kyber". Hasil ke _kn_bk TANPA kurung supaya aplikasi
# langsung bisa memakainya; daftar lengkap (kurung ikut) tetap ada di field
# algos/schedulers. Tanpa kurung siku: daftar satu token = satu-satunya
# pilihan, lebih dari satu tidak ditebak.
_kn_active_token() {
    _kn_bk=""
    _kn_t=0
    for _kn_tok in $1; do
        _kn_t=$((_kn_t + 1))
        case "$_kn_tok" in
            \[*\]) _kn_bk="${_kn_tok#\[}"; _kn_bk="${_kn_bk%\]}"; return 0 ;;
        esac
    done
    [ "$_kn_t" = "1" ] && _kn_bk="$1"
    return 0
}

# --- config ----------------------------------------------------------------

# Key hsin.conf yang dibutuhkan bagian features + downscale, satu pass.
# Sumber = conf aktif yang sama dengan action.sh (HSIN_CONF, yaitu
# /sdcard/Android/hsin/hsin.conf hasil customize.sh), dengan fallback ke
# config bawaan modul kalau salinan user belum ada - pola yang sama dipakai
# service.sh dan engine/*_from_conf.
_kn_conf_load() {
    _kn_c_dvfs="false"
    _kn_c_rr="false"
    _kn_c_frl="false"
    _kn_c_sf="false"
    _kn_c_gam="false"
    _kn_c_ext="false"
    _kn_c_ds="30"
    _kn_conf="$HSIN_CONF"
    [ -r "$_kn_conf" ] || _kn_conf="$HSIN_MODULE_PATH/config/hsin.conf"
    [ -r "$_kn_conf" ] || return 1
    while IFS='=' read -r _kn_ck _kn_cv || [ -n "$_kn_ck" ]; do
        case "$_kn_ck" in
            ADVANCED_DVFS_ENABLED) _kn_c_dvfs="$_kn_cv" ;;
            GLOBAL_RR_ENABLED) _kn_c_rr="$_kn_cv" ;;
            FRAME_RATE_LIMIT_DISABLED) _kn_c_frl="$_kn_cv" ;;
            SURFACEFLINGER_TWEAK_ENABLED) _kn_c_sf="$_kn_cv" ;;
            GAM_BOOST_ENABLED) _kn_c_gam="$_kn_cv" ;;
            ALLOW_EXTREME) _kn_c_ext="$_kn_cv" ;;
            DOWNSCALE_PERCENT) [ -n "$_kn_cv" ] && _kn_c_ds="$_kn_cv" ;;
        esac
    done < "$_kn_conf"
    return 0
}

# --- bagian JSON -----------------------------------------------------------

# profiles: daftar file di profiles/ lewat helper yang sama dengan WebUI/CLI,
# jadi tidak ada daftar kedua yang bisa berbeda.
_kn_profiles_json() {
    _kn_arr_reset
    for _kn_p in $(hsin_profile_list 2>/dev/null); do
        _kn_arr_add "$_kn_p"
    done
    _kn_out_profiles="[${_kn_arr}]"
    return 0
}

# cpu: hsin_cpu_detect() sudah mengumpulkan persis apa yang dibutuhkan -
# daftar policy (cache-first), governor saat ini, daftar governor live,
# OPP dari cache/live, dan flag writable per policy - jadi tidak ada glob
# sysfs tambahan di sini. hw_max_khz = helper hsin_cpu_policy_hwmax() yang
# dipakai engine cpu.
_kn_cpu_json() {
    _kn_out_cpu='{"supported":false,"policies":[]}'
    _kn_any_wmax=false
    [ -n "$HSIN_SYSFS_CPU" ] || return 0
    # stdout di-buang supaya tidak ada output lain yang bisa tercampur ke
    # baris JSON; log tetap ditulis ke file oleh hsin_scan_log di helper.
    hsin_cpu_detect >/dev/null 2>&1 || return 0

    _kn_items=""
    _kn_cnt=0
    # Format satu baris HSIN_CPU_CLUSTERS:
    # name|type|cpus|info_min|info_max|cur_min|cur_max|cur_gov|govs|opps|wmin|wmax|wgov
    while IFS='|' read -r _kn_nm _kn_ty _kn_cp _kn_imin _kn_imax _kn_smin _kn_smax \
        _kn_cg _kn_ag _kn_af _kn_wmin _kn_wmax _kn_wgov; do
        [ -n "$_kn_nm" ] || continue
        # Path policy untuk cek node schedutil (bukan dari cache, tapi
        # dari id policy yang sudah dibaca di baris HSIN_CPU_CLUSTERS).
        _kn_path="$HSIN_SYSFS_CPU/cpufreq/$_kn_nm"

        _kn_num "$_kn_imax"
        _kn_hw="$_kn_n"
        # cpuinfo_max_freq tidak diekspos semua kernel; kalau kosong, plafon
        # diambil dari frekuensi tertinggi yang tersedia (lihat _kn_opp_ok).
        _kn_opp_ok "$_kn_af"
        if [ "$_kn_opp_ok" = "true" ]; then
            _kn_arr_num_list "$_kn_af"
            _kn_opps="[${_kn_arr}]"
            [ "$_kn_hw" = "0" ] && _kn_hw="$_kn_hi"
        else
            _kn_opps="[]"
        fi

        _kn_arr_list "$_kn_ag"
        _kn_govs="[${_kn_arr}]"
        _kn_esc "$_kn_cg"
        _kn_cgov="$_kn_e"
        _kn_esc "${_kn_nm#policy}"
        _kn_id="$_kn_e"
        _kn_bool "$_kn_wmin"
        _kn_wm="$_kn_b"
        _kn_bool "$_kn_wmax"
        _kn_wx="$_kn_b"
        [ "$_kn_wx" = "true" ] && _kn_any_wmax=true

        # K2: schedutil rate_limit_us per policy. Node milik governor
        # schedutil, jadi hanya "supported" kalau governor aktif itu
        # schedutil DAN node ada (dicek live, bukan asumsi).
        _kn_rl_sup=false
        _kn_rl_w=false
        _kn_rl_cur=0
        _kn_rl_node="$_kn_path/schedutil/rate_limit_us"
        if [ -r "$_kn_rl_node" ]; then
            _kn_rl_raw=$(hsin_node_read "$_kn_rl_node" 2>/dev/null)
            _kn_num "$_kn_rl_raw"
            _kn_rl_cur="$_kn_n"
            [ -w "$_kn_rl_node" ] && _kn_rl_w=true
            _kn_rl_sup=true
        fi

        [ "$_kn_cnt" = "0" ] || _kn_items="${_kn_items},"
        _kn_items="${_kn_items}{\"id\":\"${_kn_id}\",\"hw_max_khz\":${_kn_hw},\"govs\":${_kn_govs},\"cur_gov\":\"${_kn_cgov}\",\"opp_khz\":${_kn_opps},\"writable_min\":${_kn_wm},\"writable_max\":${_kn_wx},\"rate_limit_us\":{\"min\":0,\"max\":100000,\"cur\":${_kn_rl_cur},\"writable\":${_kn_rl_w},\"supported\":${_kn_rl_sup}}}"
        _kn_cnt=$((_kn_cnt + 1))
    done <<EOF
$HSIN_CPU_CLUSTERS
EOF

    _kn_sup=false
    [ "$_kn_cnt" -gt 0 ] 2>/dev/null && _kn_sup=true
    _kn_out_cpu="{\"supported\":${_kn_sup},\"policies\":[${_kn_items}]}"
    return 0
}

# gpu: HSIN_GPU_DEVFRES = node devfreq yang lolos klasifikasi GPU,
# cache-first, sama seperti yang dipakai jalur apply. hsin_gpu_detect()
# sengaja tidak dipanggil: hsin_report_skip di dalamnya mencetak ke stdout
# dan itu akan merusak baris JSON ini.
_kn_gpu_json() {
    _kn_out_gpu='{"supported":false,"nodes":[]}'
    [ -n "$HSIN_SYSFS_DEVFREQ" ] || return 0
    hsin_gpu_devfreq_candidates >/dev/null 2>&1 || return 0

    _kn_items=""
    _kn_cnt=0
    for _kn_g in $HSIN_GPU_DEVFRES; do
        [ -d "$_kn_g" ] || continue
        # hsin_gpu_opp_list() = available_frequencies dari cache, dengan
        # fallback ke file live.
        hsin_gpu_opp_list "$_kn_g" >/dev/null 2>&1
        if _kn_opp_ok "$_hgo_avail"; then
            _kn_arr_num_list "$_hgo_avail"
            _kn_opps="[${_kn_arr}]"
        else
            _kn_opps="[]"
        fi
        hsin_scan_read "$_kn_g/available_governors"
        _kn_govs_raw="$_sc_r"
        hsin_scan_read "$_kn_g/governor"
        _kn_cg="$_sc_r"

        # Writable kalau salah satu knob-nya bisa ditulis: clamp max_freq
        # ATAU ganti governor. Node yang keduanya read-only tidak berguna
        # untuk user, jadi dilaporkan false.
        _kn_wr=false
        if [ -w "$_kn_g/max_freq" ] || [ -w "$_kn_g/governor" ]; then
            _kn_wr=true
        fi

        _kn_arr_list "$_kn_govs_raw"
        _kn_govs="[${_kn_arr}]"
        _kn_esc "$_kn_cg"
        _kn_cgov="$_kn_e"
        _kn_esc "${_kn_g##*/}"
        _kn_nm="$_kn_e"

        [ "$_kn_cnt" = "0" ] || _kn_items="${_kn_items},"
        _kn_items="${_kn_items}{\"name\":\"${_kn_nm}\",\"govs\":${_kn_govs},\"opp_khz\":${_kn_opps},\"cur_gov\":\"${_kn_cgov}\",\"writable\":${_kn_wr}}"
        _kn_cnt=$((_kn_cnt + 1))
    done

    _kn_sup=false
    [ "$_kn_cnt" -gt 0 ] 2>/dev/null && _kn_sup=true
    _kn_out_gpu="{\"supported\":${_kn_sup},\"nodes\":[${_kn_items}]}"
    return 0
}

# memory: swappiness (node vm, nilai live) + zram. comp_algorithm DIBAWA apa
# adanya - kernel menandai algo aktif dengan kurung siku dan aplikasi butuh
# tahu yang mana, jadi tidak dirapikan; field cur sudah bersih dari kurung.
# zram yang dilaporkan = device pertama yang ada (daftar dari module param
# lewat hsin_mem_zram_names(), tanpa glob directory), sesuai skema zram
# tunggal di kontrak JSON.
_kn_mem_json() {
    _kn_sw_cur=0
    _kn_sw_w=false
    _kn_sw_sup=false
    if [ -n "$HSIN_PROC" ]; then
        _kn_sw_node="$HSIN_PROC/$_kn_sysdir/vm/swappiness"
        if [ -r "$_kn_sw_node" ]; then
            _kn_sw_raw=$(hsin_node_read "$_kn_sw_node" 2>/dev/null)
            _kn_num "$_kn_sw_raw"
            _kn_sw_cur="$_kn_n"
            [ -w "$_kn_sw_node" ] && _kn_sw_w=true
            _kn_sw_sup=true
        fi
    fi

    _kn_z_algos="[]"
    _kn_z_cur=""
    _kn_z_w=false
    _kn_z_sup=false
    _kn_z_raw=""
    if [ -n "$HSIN_SYSFS_BLOCK" ]; then
        hsin_mem_zram_names >/dev/null 2>&1
        for _kn_z in $HSIN_MEM_ZRAM_NAMES; do
            _kn_zdir="$HSIN_SYSFS_BLOCK/$_kn_z"
            [ -r "$_kn_zdir/comp_algorithm" ] || continue
            hsin_scan_read "$_kn_zdir/comp_algorithm" || continue
            _kn_z_raw="$_sc_r"
            break
        done
    fi
    if [ -n "$_kn_z_raw" ]; then
        _kn_arr_list "$_kn_z_raw"
        _kn_z_algos="[${_kn_arr}]"
        _kn_active_token "$_kn_z_raw"
        _kn_esc "$_kn_bk"
        _kn_z_cur="$_kn_e"
        [ -w "$_kn_zdir/comp_algorithm" ] && _kn_z_w=true
        _kn_z_sup=true
    fi

    # 0..100 = rentang vm.swappiness menurut kernel. (HSIN_VM_SAFE di
    # engine/memory/vm.sh menerima tulis sampai 200, tetapi kernel
    # meng-clamp di 100, jadi 100 yang jujur untuk batas atas di UI.)
    _kn_out_mem="{\"supported\":${_kn_sw_sup},\"swappiness\":{\"min\":0,\"max\":100,\"cur\":${_kn_sw_cur},\"writable\":${_kn_sw_w},\"supported\":${_kn_sw_sup}},\"zram\":{\"algos\":${_kn_z_algos},\"cur\":\"${_kn_z_cur}\",\"writable\":${_kn_z_w},\"supported\":${_kn_z_sup}}}"
    return 0
}

# K1: 3 knob VM (vfs_cache_pressure, dirty_ratio, dirty_background_ratio).
# Bentuk sama dengan swappiness: {min,max,cur,writable,supported} per node,
# nilai live dari node. Batas = tabel HSIN_VM_SAFE (engine/memory/vm.sh),
# yaitu rentang yang benar-benar dipakai engine untuk menulis. Dipisah dari
# _kn_mem_json supaya tiap node punya blok JSON sendiri dan tidak ada daftar
# batas kedua yang bisa berbeda dari engine.
_kn_vm_knob() {
    _kn_vk_name="$1"
    _kn_vk_min="$2"
    _kn_vk_max="$3"
    _kn_vk_sup=false
    _kn_vk_w=false
    _kn_vk_cur=0
    if [ -n "$HSIN_PROC" ]; then
        _kn_vk_node="$HSIN_PROC/$_kn_sysdir/vm/$_kn_vk_name"
        if [ -r "$_kn_vk_node" ]; then
            _kn_vk_raw=$(hsin_node_read "$_kn_vk_node" 2>/dev/null)
            _kn_num "$_kn_vk_raw"
            _kn_vk_cur="$_kn_n"
            [ -w "$_kn_vk_node" ] && _kn_vk_w=true
            _kn_vk_sup=true
        fi
    fi
    _kn_out_vk="{\"min\":${_kn_vk_min},\"max\":${_kn_vk_max},\"cur\":${_kn_vk_cur},\"writable\":${_kn_vk_w},\"supported\":${_kn_vk_sup}}"
    return 0
}

# vfs_cache_pressure 0-1000, dirty_ratio 1-90, dirty_background_ratio 1-50
# (keputusan user K1; batas atas = max HSIN_VM_SAFE).
_kn_vm_knobs_json() {
    _kn_vm_knob vfs_cache_pressure 0 1000
    _kn_vfs="$_kn_out_vk"
    _kn_vm_knob dirty_ratio 1 90
    _kn_dr="$_kn_out_vk"
    _kn_vm_knob dirty_background_ratio 1 50
    _kn_dbr="$_kn_out_vk"
    # K2: stat_interval (detik) + page_cluster. Batas = HSIN_VM_SAFE.
    _kn_vm_knob stat_interval 1 60
    _kn_si="$_kn_out_vk"
    _kn_vm_knob page-cluster 0 9
    _kn_pc="$_kn_out_vk"
    _kn_out_vm="{\"vfs_cache_pressure\":${_kn_vfs},\"dirty_ratio\":${_kn_dr},\"dirty_background_ratio\":${_kn_dbr},\"stat_interval\":${_kn_si},\"page_cluster\":${_kn_pc}}"
    return 0
}

# io: hsin_io_block_devs() sudah menyaring loop/ram/zram/dm-* saat scan, jadi
# hanya device riil yang bisa ditulis user. queue/scheduler memakai penanda
# kurung siku yang sama dengan comp_algorithm.
_kn_io_json() {
    _kn_out_io='{"supported":false,"blocks":[]}'
    [ -n "$HSIN_SYSFS_BLOCK" ] || return 0
    hsin_io_block_devs >/dev/null 2>&1 || return 0

    _kn_items=""
    _kn_cnt=0
    for _kn_b in $HSIN_IO_BLOCKS; do
        [ -r "$_kn_b/queue/scheduler" ] || continue
        hsin_scan_read "$_kn_b/queue/scheduler" || continue
        _kn_s_raw="$_sc_r"
        _kn_wr=false
        [ -w "$_kn_b/queue/scheduler" ] && _kn_wr=true

        _kn_arr_list "$_kn_s_raw"
        _kn_sch="[${_kn_arr}]"
        _kn_active_token "$_kn_s_raw"
        _kn_esc "$_kn_bk"
        _kn_cur="$_kn_e"
        # K1: readahead per block = PRESET (keputusan user), bukan rentang.
        # Preset di sini WAJIB sama dengan daftar yang diterima
        # hsin_uk_val_ok (core/user_knobs.sh) dan yang dicek ulang engine
        # io/readahead.sh. Node hilang/tak-baca = supported:false + cur 0.
        _kn_ra_sup=false
        _kn_ra_w=false
        _kn_ra_cur=0
        if [ -f "$_kn_b/queue/read_ahead_kb" ]; then
            _kn_ra_raw=$(hsin_node_read "$_kn_b/queue/read_ahead_kb" 2>/dev/null)
            _kn_num "$_kn_ra_raw"
            _kn_ra_cur="$_kn_n"
            [ -w "$_kn_b/queue/read_ahead_kb" ] && _kn_ra_w=true
            _kn_ra_sup=true
        fi
        _kn_ra_opts="[128,256,512,1024,2048,4096,8192]"
        # K2: tiga knob queue boolean. Bentuk {options,cur,writable,
        # supported}; node hilang = supported:false + cur 0.
        _kn_qt=""
        for _kn_qf in add_random iostats nomerges; do
            _kn_qn="$_kn_b/queue/$_kn_qf"
            if [ -r "$_kn_qn" ]; then
                _kn_qr=$(hsin_node_read "$_kn_qn" 2>/dev/null)
                _kn_num "$_kn_qr"
                _kn_qcur="$_kn_n"
                [ -w "$_kn_qn" ] && _kn_qw=true || _kn_qw=false
                _kn_qsup=true
            else
                _kn_qcur=0
                _kn_qw=false
                _kn_qsup=false
            fi
            # nomerges punya 3 nilai sah (dokumentasi kernel block layer);
            # add_random/iostats boolean 0/1. Daftar WAJIB sama dengan
            # hsin_uk_val_ok (core/user_knobs.sh) dan cek ulang engine
            # io/queue_tuning.sh.
            case "$_kn_qf" in
                nomerges) _kn_qopts="[0,1,2]" ;;
                *)        _kn_qopts="[0,1]" ;;
            esac
            [ -n "$_kn_qt" ] && _kn_qt="${_kn_qt},"
            _kn_qt="${_kn_qt}\"${_kn_qf}\":{\"options\":${_kn_qopts},\"cur\":${_kn_qcur},\"writable\":${_kn_qw},\"supported\":${_kn_qsup}}"
        done
        _kn_esc "${_kn_b##*/}"
        _kn_nm="$_kn_e"

        [ "$_kn_cnt" = "0" ] || _kn_items="${_kn_items},"
        _kn_items="${_kn_items}{\"name\":\"${_kn_nm}\",\"schedulers\":${_kn_sch},\"cur\":\"${_kn_cur}\",\"writable\":${_kn_wr},\"readahead\":{\"options\":${_kn_ra_opts},\"cur\":${_kn_ra_cur},\"writable\":${_kn_ra_w},\"supported\":${_kn_ra_sup}},\"queue_tuning\":{${_kn_qt}}}"
        _kn_cnt=$((_kn_cnt + 1))
    done

    _kn_sup=false
    [ "$_kn_cnt" -gt 0 ] 2>/dev/null && _kn_sup=true
    _kn_out_io="{\"supported\":${_kn_sup},\"blocks\":[${_kn_items}]}"
    return 0
}

# network: TCP congestion control + TCP Fast Open. Batas TFO 0..3 = bitmask
# kernel (1 client, 2 server, 3 keduanya) - nilai yang sama dengan yang
# ditulis engine/network/tcp.sh.
# K3: tiga tunable devfreq per node. Batas = devfreq ABI + batas UI
# (lihat NOTES K3). Node hilang = supported:false, cur 0 (bukan crash).
_kn_gpu_tunables_json() {
    _kn_gt=""
    for _kn_g in $HSIN_GPU_DEVFRES; do
        [ -d "$_kn_g" ] || continue
        _kn_esc "${_kn_g##*/}"
        _kn_gtn="$_kn_e"
        for _kn_gt_spec in "polling_interval|1|1000" "up_threshold|1|100" "down_differential|0|100"; do
            _kn_gt_f="${_kn_gt_spec%%|*}"
            _kn_gt_rest="${_kn_gt_spec#*|}"
            _kn_gt_min="${_kn_gt_rest%%|*}"
            _kn_gt_max="${_kn_gt_rest#*|}"
            _kn_gt_node="$_kn_g/$_kn_gt_f"
            if [ -r "$_kn_gt_node" ]; then
                _kn_gt_raw=$(hsin_node_read "$_kn_gt_node" 2>/dev/null)
                _kn_num "$_kn_gt_raw"
                _kn_gt_cur="$_kn_n"
                [ -w "$_kn_gt_node" ] && _kn_gt_w=true || _kn_gt_w=false
                _kn_gt_sup=true
            else
                _kn_gt_cur=0
                _kn_gt_w=false
                _kn_gt_sup=false
            fi
            _kn_arr_reset
            _kn_num "$_kn_gt_min"; _kn_arr_add "$_kn_n"
            _kn_num "$_kn_gt_max"; _kn_arr_add "$_kn_n"
            _kn_gt_obj="\"min\":${_kn_gt_min},\"max\":${_kn_gt_max},\"cur\":${_kn_gt_cur},\"writable\":${_kn_gt_w},\"supported\":${_kn_gt_sup}"
            _kn_gt_all="${_kn_gt_all:+${_kn_gt_all},}"
            _kn_gt_all="${_kn_gt_all}\"${_kn_gt_f}\":{${_kn_gt_obj}}"
        done
        _kn_gt_all2="${_kn_gt_all2:+${_kn_gt_all2},}"
        _kn_gt_all2="${_kn_gt_all2}{\"node\":\"${_kn_gtn}\",\"tunables\":{${_kn_gt_all}}}"
        _kn_gt_all=""
    done
    _kn_out_gt="[${_kn_gt_all2}]"
    return 0
}

# K3: node scheduler (sched_child_runs_first + 3 sysctl sched) + uclamp
# foreground + parameter Mali KBase. Semua live dari node; yang hilang =
# supported:false, cur 0.
_kn_sched_json() {
    _kn_sc_crf_sup=false
    _kn_sc_crf_cur=0
    if [ -f "$HSIN_PROC/sys/kernel/sched_child_runs_first" ]; then
        _kn_sc_crf_raw=$(hsin_node_read "$HSIN_PROC/sys/kernel/sched_child_runs_first" 2>/dev/null)
        _kn_num "$_kn_sc_crf_raw"
        _kn_sc_crf_cur="$_kn_n"
        [ -w "$HSIN_PROC/sys/kernel/sched_child_runs_first" ] && _kn_sc_crf_w=true || _kn_sc_crf_w=false
        _kn_sc_crf_sup=true
    else
        _kn_sc_crf_w=false
    fi
    _kn_sc_lat='{"min":10,"max":200,"cur":0,"writable":false,"supported":false}'
    for _kn_sc_spec in "sched_latency_ns|10|200" "sched_min_granularity_ns|10|200" "sched_wakeup_granularity_ns|10|200"; do
        _kn_sc_f="${_kn_sc_spec%%|*}"
        _kn_sc_rest="${_kn_sc_spec#*|}"
        _kn_sc_min="${_kn_sc_rest%%|*}"
        _kn_sc_max="${_kn_sc_rest#*|}"
        _kn_sc_node="$HSIN_PROC/sys/kernel/$_kn_sc_f"
        if [ -r "$_kn_sc_node" ]; then
            _kn_sc_raw=$(hsin_node_read "$_kn_sc_node" 2>/dev/null)
            _kn_num "$_kn_sc_raw"
            _kn_sc_cur="$_kn_n"
            [ -w "$_kn_sc_node" ] && _kn_sc_w=true || _kn_sc_w=false
            _kn_sc_sup=true
        else
            _kn_sc_cur=0
            _kn_sc_w=false
            _kn_sc_sup=false
        fi
        [ -n "$_kn_sc_all" ] && _kn_sc_all="${_kn_sc_all},"
        _kn_sc_all="${_kn_sc_all}\"${_kn_sc_f}\":{\"min\":${_kn_sc_min},\"max\":${_kn_sc_max},\"cur\":${_kn_sc_cur},\"writable\":${_kn_sc_w},\"supported\":${_kn_sc_sup}}"
    done
    # uclamp
    _kn_uc_dir="${HSIN_UCLAMP_DIR:-/dev/cpuctl}/foreground"
    _kn_uc_all=""
    for _kn_uc_spec in "uclamp_min|cpu.uclamp.min" "uclamp_max|cpu.uclamp.max"; do
        _kn_uc_key="${_kn_uc_spec%%|*}"
        _kn_uc_file="${_kn_uc_spec#*|}"
        _kn_uc_node="$_kn_uc_dir/$_kn_uc_file"
        if [ -r "$_kn_uc_node" ]; then
            _kn_uc_raw=$(hsin_node_read "$_kn_uc_node" 2>/dev/null)
            _kn_num "$_kn_uc_raw"
            _kn_uc_cur="$_kn_n"
            [ -w "$_kn_uc_node" ] && _kn_uc_w=true || _kn_uc_w=false
            _kn_uc_sup=true
        else
            _kn_uc_cur=0
            _kn_uc_w=false
            _kn_uc_sup=false
        fi
        [ -n "$_kn_uc_all" ] && _kn_uc_all="${_kn_uc_all},"
        _kn_uc_all="${_kn_uc_all}\"${_kn_uc_key}\":{\"min\":0,\"max\":1024,\"cur\":${_kn_uc_cur},\"writable\":${_kn_uc_w},\"supported\":${_kn_uc_sup}}"
    done
    _kn_out_sched="{\"child_runs_first\":{\"min\":0,\"max\":1,\"cur\":${_kn_sc_crf_cur},\"writable\":${_kn_sc_crf_w},\"supported\":${_kn_sc_crf_sup}},\"sysctl\":{${_kn_sc_all}},\"uclamp\":{${_kn_uc_all}}}"
    return 0
}

# K3: parameter Mali KBase (jika device punya).
_kn_kbase_json() {
    _kn_kb_all=""
    for _kn_kb_spec in "mali_boost_level2|gpu_boost_level2|0|1" "mali_pollingtime|gpu_pollingtime|1|10" "mali_upthreshold|gpu_upthreshold|10|100"; do
        _kn_kb_key="${_kn_kb_spec%%|*}"
        _kn_kb_rest="${_kn_kb_spec#*|}"
        _kn_kb_file="${_kn_kb_rest%%|*}"
        _kn_kb_rest2="${_kn_kb_rest#*|}"
        _kn_kb_min="${_kn_kb_rest2%%|*}"
        _kn_kb_max="${_kn_kb_rest2#*|}"
        _kn_kb_node="${HSIN_SYSFS_KBASE:-/sys/module/mali_kbase/parameters}/$_kn_kb_file"
        if [ -r "$_kn_kb_node" ]; then
            _kn_kb_raw=$(hsin_node_read "$_kn_kb_node" 2>/dev/null)
            _kn_num "$_kn_kb_raw"
            _kn_kb_cur="$_kn_n"
            [ -w "$_kn_kb_node" ] && _kn_kb_w=true || _kn_kb_w=false
            _kn_kb_sup=true
        else
            _kn_kb_cur=0
            _kn_kb_w=false
            _kn_kb_sup=false
        fi
        [ -n "$_kn_kb_all" ] && _kn_kb_all="${_kn_kb_all},"
        _kn_kb_all="${_kn_kb_all}\"${_kn_kb_key}\":{\"min\":${_kn_kb_min},\"max\":${_kn_kb_max},\"cur\":${_kn_kb_cur},\"writable\":${_kn_kb_w},\"supported\":${_kn_kb_sup}}"
    done
    _kn_out_kbase="{${_kn_kb_all}}"
    return 0
}

_kn_net_json() {
    _kn_tcp="[]"
    _kn_tcp_sup=false
    _kn_tfo_cur=0
    _kn_tfo_sup=false
    if [ -n "$HSIN_PROC" ]; then
        _kn_tcp_node="$HSIN_PROC/$_kn_sysdir/net/ipv4/tcp_available_congestion_control"
        if [ -r "$_kn_tcp_node" ]; then
            _kn_tcp_raw=$(hsin_node_read "$_kn_tcp_node" 2>/dev/null)
            _kn_arr_list "$_kn_tcp_raw"
            _kn_tcp="[${_kn_arr}]"
            _kn_tcp_sup=true
        fi
        _kn_tfo_node="$HSIN_PROC/$_kn_sysdir/net/ipv4/tcp_fastopen"
        if [ -r "$_kn_tfo_node" ]; then
            _kn_tfo_raw=$(hsin_node_read "$_kn_tfo_node" 2>/dev/null)
            _kn_num "$_kn_tfo_raw"
            _kn_tfo_cur="$_kn_n"
            _kn_tfo_sup=true
        fi
    fi

    _kn_out_net="{\"supported\":${_kn_tcp_sup},\"tcp_cc\":${_kn_tcp},\"tfo\":{\"min\":0,\"max\":3,\"cur\":${_kn_tfo_cur},\"supported\":${_kn_tfo_sup}}}"
    return 0
}

# K1: netdev_max_backlog (satu knob, rentang 128-16384 sesuai keputusan
# user; angka ini sama dengan batas yang diterima hsin_uk_val_ok di
# core/user_knobs.sh dan yang dicek ulang engine/network/tcp.sh).
# Node hilang = supported:false + cur 0, bukan crash.
_kn_backlog_json() {
    _kn_bl_sup=false
    _kn_bl_w=false
    _kn_bl_cur=0
    if [ -n "$HSIN_PROC" ]; then
        _kn_bl_node="$HSIN_PROC/$_kn_sysdir/net/core/netdev_max_backlog"
        if [ -r "$_kn_bl_node" ]; then
            _kn_bl_raw=$(hsin_node_read "$_kn_bl_node" 2>/dev/null)
            _kn_num "$_kn_bl_raw"
            _kn_bl_cur="$_kn_n"
            [ -w "$_kn_bl_node" ] && _kn_bl_w=true
            _kn_bl_sup=true
        fi
    fi
    _kn_out_backlog="{\"min\":128,\"max\":16384,\"cur\":${_kn_bl_cur},\"writable\":${_kn_bl_w},\"supported\":${_kn_bl_sup}}"
    return 0
}

# display: mode Hz dan Hz aktif dibaca dari sumber yang sama dengan
# refresh-lock/status (dumpsys display), BUKAN daftar tebakan; kalau tidak
# terbaca -> [] dan ditandai tidak tersedia. Renderer memakai whitelist
# yang sama dengan aksi renderer-apply (hsin_render_valid_target() +
# config-set), nilai live dari getprop debug.hwui.renderer lewat
# hsin_render_current(). Downscale 1..99 = rentang yang benar-benar diterima
# aksi downscale-enable dan _hsin_downscale_valid_percent(); 100% =
# resolusi native = fitur mati, jadi bukan pilihan slider.
_kn_disp_json() {
    _kn_modes="[]"
    _kn_modes_sup=false
    if command -v hsin_refresh_detect_supported >/dev/null 2>&1; then
        _kn_modes_raw=$(hsin_refresh_detect_supported 2>/dev/null)
        _kn_arr_num_list "$_kn_modes_raw"
        if [ -n "$_kn_arr" ]; then
            _kn_modes="[${_kn_arr}]"
            _kn_modes_sup=true
        fi
    fi

    # Precedence sama dengan status WebUI: renderFrameRate (jawaban dumpsys
    # untuk mode yang aktif sekarang) > refreshRateOverride > fps= pertama.
    _kn_cur_hz=0
    if command -v dumpsys >/dev/null 2>&1; then
        _kn_dump=$(dumpsys display 2>/dev/null)
        _kn_r=$(printf '%s\n' "$_kn_dump" | grep -o 'renderFrameRate [0-9.]*' | head -n 1 | cut -d' ' -f2 | cut -d. -f1)
        if [ -z "$_kn_r" ] || [ "$_kn_r" = "0" ]; then
            _kn_r=$(printf '%s\n' "$_kn_dump" | grep -o 'refreshRateOverride [0-9.]*' | head -n 1 | cut -d' ' -f2 | cut -d. -f1)
        fi
        if [ -z "$_kn_r" ] || [ "$_kn_r" = "0" ]; then
            _kn_r=$(printf '%s\n' "$_kn_dump" | grep -o 'fps=[0-9.]*' | head -n 1 | cut -d= -f2 | cut -d. -f1)
        fi
        _kn_num "$_kn_r"
        _kn_cur_hz="$_kn_n"
    fi

    _kn_arr_reset
    for _kn_rd in skiagl skiavk system; do
        hsin_render_valid_target "$_kn_rd" >/dev/null 2>&1 || continue
        _kn_arr_add "$_kn_rd"
    done
    _kn_rends="[${_kn_arr}]"
    _kn_rend_cur=$(hsin_render_current 2>/dev/null)
    # Prop kosong = default vendor yang belum disentuh = pilihan "system".
    [ -z "$_kn_rend_cur" ] && _kn_rend_cur="system"
    _kn_esc "$_kn_rend_cur"
    _kn_rend_cur_json="$_kn_e"

    _kn_ds_sup=false
    command -v wm >/dev/null 2>&1 && _kn_ds_sup=true
    _kn_num "$_kn_c_ds"
    _kn_ds_cur="$_kn_n"
    [ "$_kn_ds_cur" = "0" ] && _kn_ds_cur=30

    _kn_disp_sup=false
    if [ "$_kn_modes_sup" = "true" ] || [ "$_kn_cur_hz" -gt 0 ] 2>/dev/null; then
        _kn_disp_sup=true
    fi
    _kn_out_disp="{\"supported\":${_kn_disp_sup},\"modes_hz\":${_kn_modes},\"cur_hz\":${_kn_cur_hz},\"renderers\":${_kn_rends},\"cur_renderer\":\"${_kn_rend_cur_json}\",\"downscale\":{\"min\":1,\"max\":99,\"cur\":${_kn_ds_cur},\"supported\":${_kn_ds_sup}}}"
    return 0
}

# features: true hanya kalau fiturnya benar-benar bisa dipakai di device ini
# - switch di conf menyala DAN alatnya ada (policy CPU yang bisa ditulis
# untuk DVFS, binary settings/cmd untuk refresh rate, resetprop/setprop untuk
# SurfaceFlinger dan frame limit). Switch yang off di conf tetap false walau
# alatnya ada, supaya aplikasi tidak menampilkan fitur yang sebenarnya tidak
# aktif. gaming/extreme memakai nilai yang sudah dibaca action.sh
# (HSIN_GAM_BOOST/ALLOW_EXTREME) kalau tersedia, jadi opt-in sesi dari WebUI
# ikut tercermin.
_kn_feat_json() {
    _kn_f_dvfs=false
    _kn_f_rr=false
    _kn_f_frl=false
    _kn_f_sf=false
    # gaming/extreme: true kalau switch di conf menyala ATAU nilai yang
    # sudah dibaca action.sh (HSIN_GAM_BOOST/ALLOW_EXTREME) menyala - yang
    # kedua itu ikut membawa opt-in satu sesi dari WebUI, yang dikirim lewat
    # environment dan tidak pernah ditulis ke conf.
    _kn_f_gam=false
    if [ "$_kn_c_gam" = "true" ] || [ "$HSIN_GAM_BOOST" = "true" ]; then
        _kn_f_gam=true
    fi
    _kn_f_ext=false
    if [ "$_kn_c_ext" = "true" ] || [ "$ALLOW_EXTREME" = "true" ]; then
        _kn_f_ext=true
    fi

    _kn_have_settings=false
    command -v settings >/dev/null 2>&1 && _kn_have_settings=true
    if [ "$_kn_have_settings" != "true" ]; then
        command -v cmd >/dev/null 2>&1 && _kn_have_settings=true
    fi
    _kn_have_prop=false
    command -v resetprop >/dev/null 2>&1 && _kn_have_prop=true
    if [ "$_kn_have_prop" != "true" ]; then
        command -v setprop >/dev/null 2>&1 && _kn_have_prop=true
    fi

    # Limiter DVFS butuh policy CPU dengan scaling_max_freq yang bisa ditulis
    # (persis syarat hsin_dvfs_cpu_apply()).
    if [ "$_kn_c_dvfs" = "true" ] && [ "$_kn_any_wmax" = "true" ]; then
        _kn_f_dvfs=true
    fi
    if [ "$_kn_c_rr" = "true" ] && [ "$_kn_have_settings" = "true" ]; then
        _kn_f_rr=true
    fi
    if [ "$_kn_c_frl" = "true" ] && [ "$_kn_have_prop" = "true" ]; then
        _kn_f_frl=true
    fi
    if [ "$_kn_c_sf" = "true" ] && [ "$_kn_have_prop" = "true" ]; then
        _kn_f_sf=true
    fi

    _kn_out_feat="{\"dvfs\":${_kn_f_dvfs},\"global_rr\":${_kn_f_rr},\"frame_limit\":${_kn_f_frl},\"surfaceflinger\":${_kn_f_sf},\"gaming\":${_kn_f_gam},\"extreme_optin\":${_kn_f_ext}}"
    return 0
}

# capabilities: dari mana daftar frekuensi/topologi diambil - cache
# scan-sekali-simpan (topologi statis, tidak perlu glob ulang) atau scan
# live. "live" kalau salah satu jalurnya scan, supaya aplikasi tahu angka
# yang dibacanya bukan dari cache.
_kn_caps_json() {
    _kn_src="live"
    if [ "$HSIN_SCAN_CPU_SOURCE" = "cache" ] && [ "$HSIN_SCAN_DEVFREQ_SOURCE" = "cache" ]; then
        _kn_src="cache"
    fi
    _kn_out_caps="{\"available_frequencies_source\":\"${_kn_src}\"}"
    return 0
}

# --- entry point -----------------------------------------------------------

# Cetak SATU BARIS JSON inventaris knob. Selalu exit 0: bagian yang tidak
# bisa dibaca di perangkat ini hanya dilaporkan sebagai tidak tersedia,
# tidak pernah menggagalkan seluruh output.
hsin_knobs_json() {
    [ -n "$HSIN_KN_CR" ] || HSIN_KN_CR="$(printf '\r')"

    # Helper engine yang dipakai ulang, dimuat di dalam fungsi (bukan saat
    # file di-source) supaya tidak menambah beban pada aksi action.sh yang
    # lain - terutama status yang dipoll WebUI tiap ~2 detik.
    . "$HSIN_MODULE_PATH/engine/cpu/detect.sh" 2>/dev/null
    . "$HSIN_MODULE_PATH/engine/gpu/detector.sh" 2>/dev/null
    . "$HSIN_MODULE_PATH/engine/memory/detect.sh" 2>/dev/null
    . "$HSIN_MODULE_PATH/engine/io/scheduler.sh" 2>/dev/null
    . "$HSIN_MODULE_PATH/engine/display/refresh_rate.sh" 2>/dev/null
    . "$HSIN_MODULE_PATH/engine/render/renderer.sh" 2>/dev/null

    _kn_conf_load

    _kn_profiles_json
    _kn_cpu_json
    _kn_gpu_json
    _kn_mem_json
    _kn_vm_knobs_json
    _kn_io_json
    _kn_net_json
    _kn_backlog_json
    _kn_gpu_tunables_json
    _kn_sched_json
    _kn_kbase_json
    _kn_disp_json
    _kn_feat_json
    _kn_caps_json

    printf '{"v":1,"profiles":%s,"cpu":%s,"gpu":%s,"memory":%s,"vm":%s,"io":%s,"network":%s,"backlog":%s,"sched":%s,"gpu_tunables":%s,"mali_kbase":%s,"display":%s,"features":%s,"capabilities":%s}\n' \
        "$_kn_out_profiles" "$_kn_out_cpu" "$_kn_out_gpu" "$_kn_out_mem" \
        "$_kn_out_vm" "$_kn_out_io" "$_kn_out_net" "$_kn_out_backlog" \
        "$_kn_out_sched" "$_kn_out_gt" "$_kn_out_kbase" \
        "$_kn_out_disp" "$_kn_out_feat" "$_kn_out_caps"
    return 0
}

return 0 2>/dev/null || true
