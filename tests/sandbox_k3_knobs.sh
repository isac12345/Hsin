#!/system/bin/sh
# Sandbox test K3: knob tier-2 capability-gated (sched sysctl, uclamp,
# devfreq tunables, parameter Mali KBase).
#
# Dibuktikan:
#   A. tiap knob set satu-per-satu -> hanya node itu berubah (snapshot md5)
#   B. manual tanpa override = nol penulisan
#   C. profil non-manual: knob tanpa nilai profil tidak ditulis
#   D. node hilang = UNAVAILABLE tanpa crash (VARIAN 2: sebagian hilang)
#   E. nilai di luar rentang ditolak (knob-set + file cacat)
#   F. dua varian: node lengkap (semua ada) + node hilang sebagian
#   G. backup -> rollback per knob
#   H. knobs JSON field baru (sched, gpu_tunables, mali_kbase)
#   I. knob-list kategori benar
#
# Cara pakai: sh tests/sandbox_k3_knobs.sh

_HSIN_REPO=$(cd "${0%/*}/.." 2>/dev/null && pwd)
HSIN_SANDBOX_DIR="${HSIN_SANDBOX_DIR:-/usr/tmp/opencode/hsin-k3-test}"
SB_SYS="$HSIN_SANDBOX_DIR/sys"
SB_PROC="$HSIN_SANDBOX_DIR/proc"
SB_UC="$HSIN_SANDBOX_DIR/cpuctl"
SB_KB="$HSIN_SANDBOX_DIR/kbase"
export HSIN_MODULE_PATH="$_HSIN_REPO"
export HSIN_DATA="$HSIN_SANDBOX_DIR/data"
export HSIN_SANDBOX=1
export HSIN_SYSFS_DEVFREQ="$SB_SYS/class/devfreq"
export HSIN_SYSFS_KBASE="$SB_KB"
export HSIN_SYSFS_CPU="$SB_SYS/cpu"
export HSIN_UCLAMP_DIR="$SB_UC"
# Path absolut dipakai subshell pada skenario J (variabel lokal shell tidak
# diwarisi ke sh -c).
HSIN_SYSFS_KBASE_ABS="$SB_KB"
export HSIN_SYSFS_KBASE_ABS
export SYSFS_DEVFREQ_PREFIX="$SB_SYS/class/devfreq"
export SYSFS_KBASE_PREFIX="$SB_KB"
export SYSFS_CPU_PREFIX="$SB_SYS/cpu"
export SYSFS_PROC_PREFIX="$SB_PROC"
export HSIN_PROC="$SB_PROC"

_PASS=0
_FAIL=0
_ok() { _PASS=$((_PASS + 1)); echo "PASS: $1"; }
_bad() { _FAIL=$((_FAIL + 1)); echo "FAIL: $1"; }

# $1 = "lengkap" | "sebagian"
_mknodes() {
    _mode="${1:-lengkap}"
    rm -rf "$SB_SYS" "$SB_PROC" "$SB_UC" "$SB_KB"
    mkdir -p "$SB_SYS/block/sda/queue" "$SB_PROC/sys/vm" "$SB_PROC/sys/kernel" \
        "$SB_PROC/sys/net/core" "$SB_PROC/sys/net/ipv4" "$HSIN_DATA/logs" \
        "$SB_UC/foreground" "$SB_KB" \
        "$SB_SYS/cpu/cpufreq/policy0" "$SB_SYS/class/devfreq/23100000.gpu"
    printf '128\n' > "$SB_SYS/block/sda/queue/read_ahead_kb"
    printf 'mq-deadline [none] kyber\n' > "$SB_SYS/block/sda/queue/scheduler"
    printf '0\n' > "$SB_SYS/block/sda/queue/add_random"
    printf '0\n' > "$SB_SYS/block/sda/queue/iostats"
    printf '2\n' > "$SB_SYS/block/sda/queue/nomerges"
    printf '60\n' > "$SB_PROC/sys/vm/swappiness"
    printf '10\n' > "$SB_PROC/sys/vm/stat_interval"
    printf '0\n' > "$SB_PROC/sys/vm/page-cluster"
    printf '1000\n' > "$SB_PROC/sys/net/core/netdev_max_backlog"
    # scheduler
    printf '0\n' > "$SB_PROC/sys/kernel/sched_child_runs_first"
    # uclamp (format vendor: pecahan + "max")
    printf '0.00\n' > "$SB_UC/foreground/cpu.uclamp.min"
    printf 'max\n' > "$SB_UC/foreground/cpu.uclamp.max"
    # devfreq GPU
    printf '50\n' > "$SB_SYS/class/devfreq/23100000.gpu/polling_interval"
    printf 'simple_ondemand\n' > "$SB_SYS/class/devfreq/23100000.gpu/governor"
    printf '500000000\n' > "$SB_SYS/class/devfreq/23100000.gpu/max_freq"
    printf '100000000\n' > "$SB_SYS/class/devfreq/23100000.gpu/min_freq"
    # mali kbase
    printf '0\n' > "$SB_KB/gpu_boost_level2"
    printf '8\n' > "$SB_KB/gpu_pollingtime"
    printf '88\n' > "$SB_KB/gpu_upthreshold"
    if [ "$_mode" = "sebagian" ]; then
        # Varian node hilang sebagian: 3 sysctl sched + 2 tunable devfreq +
        # 1 param kbase hilang, uclamp min read-only.
        rm -f "$SB_SYS/class/devfreq/23100000.gpu/up_threshold" \
            "$SB_SYS/class/devfreq/23100000.gpu/down_differential" \
            "$SB_KB/gpu_upthreshold"
        chmod 444 "$SB_UC/foreground/cpu.uclamp.min"
    fi
    return 0
}

_snapshot() {
    for _f in \
        "$SB_PROC/sys/kernel/sched_child_runs_first" \
        "$SB_PROC/sys/kernel/sched_latency_ns" \
        "$SB_PROC/sys/kernel/sched_min_granularity_ns" \
        "$SB_PROC/sys/kernel/sched_wakeup_granularity_ns" \
        "$SB_UC/foreground/cpu.uclamp.min" \
        "$SB_UC/foreground/cpu.uclamp.max" \
        "$SB_SYS/class/devfreq/23100000.gpu/polling_interval" \
        "$SB_SYS/class/devfreq/23100000.gpu/up_threshold" \
        "$SB_SYS/class/devfreq/23100000.gpu/down_differential" \
        "$SB_KB/gpu_boost_level2" \
        "$SB_KB/gpu_pollingtime" \
        "$SB_KB/gpu_upthreshold" \
        "$SB_PROC/sys/vm/swappiness"; do
        if [ -f "$_f" ]; then
            printf '%s=%s\n' "$_f" "$(cat "$_f" 2>/dev/null)"
        else
            printf '%s=<hilang>\n' "$_f"
        fi
    done
    return 0
}

_diffnodes() {
    printf '%s\n' "$1" > "$HSIN_SANDBOX_DIR/.sb"
    printf '%s\n' "$2" > "$HSIN_SANDBOX_DIR/.sa"
    paste -d'|' "$HSIN_SANDBOX_DIR/.sb" "$HSIN_SANDBOX_DIR/.sa" | while IFS='|' read -r _l _r; do
        [ "$_l" = "$_r" ] || printf '%s\n' "${_l%%=*}"
    done
    return 0
}

# Reset TOTAL sebelum tiap skenario. ALASAN (bug nyata K3): variabel shell
# di dash bersifat global per proses, jadi satu engine yang menyetel
# _profile bisa "menolong" engine lain yang salah nama variabel dan
# membuat harness memberi PASS palsu. Fungsi _isolate() di bawah secara
# membatalkan semua variabel global yang dipakai engine K1/K2/K3, dan
# dipanggil di awal SETIAP skenario + tiap _apply_one.
_reset_state() {
    rm -f "$HSIN_DATA/user_knobs.env" "$HSIN_DATA/knob_results.env"
    _uk_inited=""; _uk_cache=""; _uk_cache_done=""; _uk_used_n=0; _uk_sum_done=""
    return 0
}

_isolate() {
    # Override knob: HANYA cache per-proses yang di-unset (agar di-load
    # ulang dari file). JANGAN unset _uk_file - itu variabel KONFIGURASI
    # yang di-set saat source; menghapusnya membuat knob-set menulis ke
    # path salah (harness jadi gagal sendiri, bukan produknya).
    unset _uk_inited _uk_cache _uk_cache_done _uk_used_n _uk_sum_done
    unset _uk_sn _uk_kind _uk_num _uk_tk _uk_tfield _uk_tid _uk_v
    unset _uk_e _uk_kn _uk_ve
    # Varian + node yang dibaca engine.
    unset _profile _mk_profile _mk_manual _mk_v _mk_v_bat _mk_v_bal _mk_v_perf _mk_v_ext
    unset _gt_profile _gt_manual _gt_applied _gt_skipped _gt_spec _gt_uk
    unset _dl_profile _dl_manual _dl_applied _dl_skipped
    unset _uc_dir _uc_node _uc_f _uc_uk _uc_prof _uc_req _uc_applied _uc_before _uc_after
    unset _hl_uk_lat _hl_uk_min _hl_uk_wake _hl_uk _hl_key _hl_var _hl_canon _hl_bad _hl_req
    unset _scrf_node _scrf_uk _scrf
    unset _qt_profile _qt_manual _qt_applied _qt_skipped _qt_uk _qt_req _qt_key _qt_node _qt_bad
    unset _qt_rc _qt_why _HSIN_QT_ONE_OK _HSIN_QT_ONE_SKIP _HSIN_GT_APPLIED _HSIN_GT_SKIP
    unset _n _val _mn _mx _def_b _def_bal _def_p _def_e _prof_val _bg_rejected _bg_why
    unset _eff_ratio _cur_bg _uk_key _is_knob
    # Cache deteksi: HAPUS guard-nya juga. Kalau hanya HSIN_GPU_DEVFRES
    # yang di-unset sementara guard HSIN_GPU_NODES_READY masih 1, deteksi
    # tidak pernah jalan ulang dan daftar node jadi kosong (harness sendiri
    # yang salah, bukan produk).
    unset HSIN_GPU_KBASE HSIN_SYSFS_KBASE
    unset HSIN_GPU_NODES_READY
    unset HSIN_IO_BLOCKS HSIN_IO_BLOCKS_READY HSIN_IO_BLOCK_SOURCE
    unset HSIN_CPU_POLICY_IDS HSIN_CPU_CLUSTERS HSIN_CPU_POLICY_SOURCE
    unset HSIN_GPU_DEVFRES HSIN_GPU_DEVFREQ HSIN_GPU_VENDOR HSIN_GPU_NODES
    unset _fkn_obs
    # HSIN_SANDBOX_DIR juga KONFIGURASI harness (dipakai _snapshot/
    # _diffnodes) - tidak boleh di-unset.
    return 0
}

_load_all() {
    for _f in core/logger.sh core/sysfs.sh core/scan_cache.sh core/safe_apply.sh \
        core/user_knobs.sh core/knobs.sh engine/cpu/detect.sh engine/cpu/governor.sh \
        engine/cpu/frequency.sh engine/cpu/scheduler.sh engine/memory/detect.sh \
        engine/memory/vm.sh engine/io/scheduler.sh engine/io/readahead.sh \
        engine/io/queue_tuning.sh engine/gpu/detector.sh engine/gpu/generic.sh \
        engine/gpu/devfreq_tuning.sh engine/gpu/mali.sh engine/gpu/apply.sh \
        engine/display/refresh_rate.sh engine/render/renderer.sh; do
        . "$_HSIN_REPO/$_f" 2>/dev/null
    done
    return 0
}

_apply_all() {
    # Set ulang nama variabel yang dibaca tiap engine, lalu panggil dengan
    # argumen. Engine tidak boleh bergantung pada global pemanggil.
    _profile="$1"
    hsin_cpu_governor_apply "$1" >/dev/null 2>&1
    hsin_cpu_uclamp_apply "$1" >/dev/null 2>&1
    hsin_cpu_sched_lat_apply "$1" >/dev/null 2>&1
    hsin_gpu_devfreq_tunables_apply "$1" >/dev/null 2>&1
    hsin_gpu_detect >/dev/null 2>&1
    hsin_gpu_kbase_knobs_apply "$1" >/dev/null 2>&1
    return 0
}

_apply_one() {
    _k="$1"; _v="$2"; _node="$3"; _want="$4"
    _isolate
    _reset_state
    hsin_uk_set "$_k" "$_v" >/dev/null 2>&1
    _before=$(_snapshot)
    _apply_all manual
    _after=$(_snapshot)
    _changed=$(_diffnodes "$_before" "$_after")
    _cnt=$(printf '%s' "$_changed" | grep -c .)
    _got=$(cat "$_node" 2>/dev/null)
    if [ "$_cnt" = "1" ] && [ "$_changed" = "$_node" ] && [ "$_got" = "$_want" ]; then
        _ok "$_k=$_v: hanya node itu berubah -> $_want"
    else
        _bad "$_k=$_v: hanya node itu berubah (jumlah=$_cnt [$(printf '%s' "$_changed" | tr '\n' ' ')] isi=$_got)"
    fi
}

# --- A. snapshot byte per knob (varian node lengkap) ---
_mknodes lengkap
_isolate
_load_all
_apply_one "sched_child_runs_first" "1" "$SB_PROC/sys/kernel/sched_child_runs_first" "1"
_apply_one "uclamp_min" "512" "$SB_UC/foreground/cpu.uclamp.min" "512"
_apply_one "uclamp_max" "800" "$SB_UC/foreground/cpu.uclamp.max" "800"
_apply_one "gpu_node_23100000_gpu_polling_interval" "100" "$SB_SYS/class/devfreq/23100000.gpu/polling_interval" "100"
_apply_one "mali_boost_level2" "1" "$SB_KB/gpu_boost_level2" "1"
_apply_one "mali_pollingtime" "3" "$SB_KB/gpu_pollingtime" "3"
_apply_one "mali_upthreshold" "60" "$SB_KB/gpu_upthreshold" "60"

# --- B. manual tanpa override = nol penulisan ---
_mknodes lengkap
_isolate
_load_all
_reset_state
_before=$(_snapshot)
_apply_all manual
_after=$(_snapshot)
if [ "$_before" = "$_after" ]; then
    _ok "B. manual tanpa override: nol penulisan"
else
    _bad "B. manual tanpa override: nol penulisan (berubah: $(_diffnodes "$_before" "$_after" | tr '\n' ' '))"
fi

# --- C. profil balanced: knob tanpa nilai profil tidak ditulis ---
_mknodes lengkap
_isolate
_load_all
_reset_state
_before=$(_snapshot)
_apply_all balanced
_after=$(_snapshot)
_c_changed=$(_diffnodes "$_before" "$_after")
# Yang boleh berubah di balanced: profil lama (child_runs_first=0 sudah 0,
# uclamp min=0/max=100, kbase profil battery/balanced). TIDAK boleh:
# polling_interval (tidak ada nilai profil), 3 sysctl sched (tidak ada).
_c_bad=$(printf '%s' "$_c_changed" | grep -E 'polling_interval|sched_latency|granularity' || true)
if [ -z "$_c_bad" ] && [ "$(cat "$SB_SYS/class/devfreq/23100000.gpu/polling_interval")" = "50" ]; then
    _ok "C. balanced: knob tanpa nilai profil tidak ditulis (polling_interval tetap 50)"
else
    _bad "C. balanced: knob tanpa nilai profil (berubah: $(printf '%s' "$_c_bad" | tr '\n' ' '); polling=$(cat "$SB_SYS/class/devfreq/23100000.gpu/polling_interval"))"
fi
if [ "$(cat "$SB_KB/gpu_boost_level2")" = "0" ] && [ "$(cat "$SB_KB/gpu_pollingtime")" = "4" ] \
    && [ "$(cat "$SB_KB/gpu_upthreshold")" = "72" ]; then
    _ok "C2. balanced: kbase profil (0/4/72) - perilaku lama utuh"
else
    _bad "C2. balanced: kbase profil (dapat $(cat "$SB_KB/gpu_boost_level2")/$(cat "$SB_KB/gpu_pollingtime")/$(cat "$SB_KB/gpu_upthreshold"))"
fi

# --- F+D. VARIAN 2: node hilang sebagian -> UNAVAILABLE tanpa crash ---
_mknodes sebagian
_isolate
_load_all
_reset_state
hsin_uk_set "gpu_node_23100000_gpu_up_threshold" "80" >/dev/null 2>&1
hsin_uk_set "gpu_node_23100000_gpu_down_differential" "20" >/dev/null 2>&1
hsin_uk_set "mali_upthreshold" "50" >/dev/null 2>&1
hsin_uk_set "uclamp_min" "400" >/dev/null 2>&1
_before=$(_snapshot)
_apply_all manual
_after=$(_snapshot)
_rc=$?
if [ "$_rc" -eq 0 ]; then
    _ok "D. varian node hilang sebagian: tidak crash (rc=0)"
else
    _bad "D. varian node hilang sebagian: rc=0 (dapat $_rc)"
fi
_miss=$(grep -c "UNAVAILABLE" "$HSIN_DATA/knob_results.env" 2>/dev/null || echo 0)
if [ "$_miss" -ge 3 ]; then
    _ok "D2. node hilang/read-only: UNAVAILABLE tercatat ($_miss kunci)"
else
    _bad "D2. UNAVAILABLE tercatat (hanya $_miss; hasil: $(tr '\n' '|' < "$HSIN_DATA/knob_results.env" 2>/dev/null))"
fi
if [ "$(cat "$SB_PROC/sys/kernel/sched_child_runs_first")" = "0" ] \
    && [ "$(cat "$SB_KB/gpu_boost_level2")" = "0" ]; then
    _ok "D3. node yang ada tidak ikut ditulis karena yang lain hilang"
else
    _bad "D3. node yang ada tetap utuh"
fi

# --- E. nilai di luar rentang ditolak ---
_mknodes lengkap
_isolate
_load_all
for _pair in "sched_child_runs_first 2" "uclamp_min 1025" "uclamp_max -1" \
    "gpu_node_23100000_gpu_polling_interval 0" "gpu_node_23100000_gpu_polling_interval 1001" \
    "gpu_node_23100000_gpu_up_threshold 0" "gpu_node_23100000_gpu_up_threshold 101" \
    "gpu_node_23100000_gpu_down_differential 101" \
    "mali_boost_level2 2" "mali_pollingtime 0" "mali_pollingtime 11" \
    "mali_upthreshold 9" "mali_upthreshold 101" "sched_latency_pct 9" "sched_latency_pct 201"; do
    _sk=$(printf '%s' "$_pair" | cut -d' ' -f1)
    _sv=$(printf '%s' "$_pair" | cut -d' ' -f2)
    if hsin_uk_set "$_sk" "$_sv" >/dev/null 2>&1; then
        _bad "E. $_sk=$_sv ditolak knob-set (justru diterima)"
    else
        _ok "E. $_sk=$_sv: knob-set MENOLAK"
    fi
done
_reset_state
printf 'uclamp_max=9999\nmali_pollingtime=99\n' > "$HSIN_DATA/user_knobs.env"
chmod 600 "$HSIN_DATA/user_knobs.env"
_uk_inited=""; _uk_cache=""; _uk_cache_done=""; _uk_load
_before=$(_snapshot)
_apply_all manual
_after=$(_snapshot)
if [ "$_before" = "$_after" ]; then
    _ok "E2. file override cacat: ditolak engine, nol penulisan"
else
    _bad "E2. file override cacat: ditolak engine (berubah: $(_diffnodes "$_before" "$_after" | tr '\n' ' '))"
fi

# --- G. backup -> rollback per knob ---
for _knob in child_runs_first uclamp_min uclamp_max polling_interval mali_boost mali_polling mali_upthreshold; do
    _mknodes lengkap
    _isolate
    _load_all
    . "$_HSIN_REPO/core/backup.sh" 2>/dev/null
    _oc=$(cat "$SB_PROC/sys/kernel/sched_child_runs_first")
    _ou_min=$(cat "$SB_UC/foreground/cpu.uclamp.min")
    _ou_max=$(cat "$SB_UC/foreground/cpu.uclamp.max")
    _op=$(cat "$SB_SYS/class/devfreq/23100000.gpu/polling_interval")
    _ob=$(cat "$SB_KB/gpu_boost_level2")
    _opt=$(cat "$SB_KB/gpu_pollingtime")
    _ou=$(cat "$SB_KB/gpu_upthreshold")
    HSIN_BACKUP_ROOT="$HSIN_DATA/backup"
    hsin_backup_init "k3test"
    hsin_backup_sched
    hsin_backup_gpu_tuning
    case "$_knob" in
        child_runs_first) printf '1\n' > "$SB_PROC/sys/kernel/sched_child_runs_first" ;;
        uclamp_min)        printf '999\n' > "$SB_UC/foreground/cpu.uclamp.min" ;;
        uclamp_max)        printf '1024\n' > "$SB_UC/foreground/cpu.uclamp.max" ;;
        polling_interval)  printf '900\n' > "$SB_SYS/class/devfreq/23100000.gpu/polling_interval" ;;
        mali_boost)        printf '1\n' > "$SB_KB/gpu_boost_level2" ;;
        mali_polling)      printf '9\n' > "$SB_KB/gpu_pollingtime" ;;
        mali_upthreshold)  printf '20\n' > "$SB_KB/gpu_upthreshold" ;;
    esac
    hsin_restore_session "k3test" >/dev/null 2>&1
    if [ "$(cat "$SB_PROC/sys/kernel/sched_child_runs_first")" = "$_oc" ] \
        && [ "$(cat "$SB_UC/foreground/cpu.uclamp.min")" = "$_ou_min" ] \
        && [ "$(cat "$SB_UC/foreground/cpu.uclamp.max")" = "$_ou_max" ] \
        && [ "$(cat "$SB_SYS/class/devfreq/23100000.gpu/polling_interval")" = "$_op" ] \
        && [ "$(cat "$SB_KB/gpu_boost_level2")" = "$_ob" ] \
        && [ "$(cat "$SB_KB/gpu_pollingtime")" = "$_opt" ] \
        && [ "$(cat "$SB_KB/gpu_upthreshold")" = "$_ou" ]; then
        _ok "G. rollback $_knob: nilai kembali"
    else
        _bad "G. rollback $_knob (crf=$(cat "$SB_PROC/sys/kernel/sched_child_runs_first")/$_oc uc=$(cat "$SB_UC/foreground/cpu.uclamp.min")/$_ou_min,$(cat "$SB_UC/foreground/cpu.uclamp.max")/$_ou_max p=$(cat "$SB_SYS/class/devfreq/23100000.gpu/polling_interval")/$_op k=$(cat "$SB_KB/gpu_boost_level2")/$_ob,$(cat "$SB_KB/gpu_pollingtime")/$_opt,$(cat "$SB_KB/gpu_upthreshold")/$_ou)"
    fi
    rm -rf "$HSIN_DATA/backup"
done

# --- H. knobs JSON field baru ---
_mknodes lengkap
_isolate
_load_all
_hj=$(hsin_knobs_json 2>/dev/null)
if printf '%s' "$_hj" | python3 -c "import sys,json; json.load(sys.stdin)" 2>/dev/null; then
    _ok "H. knobs JSON valid"
else
    _bad "H. knobs JSON valid (output: $(printf '%s' "$_hj" | head -c 200))"
fi
if printf '%s' "$_hj" | grep -q '"child_runs_first":{"min":0,"max":1,"cur":0,"writable":true,"supported":true}'; then
    _ok "H2. JSON sched.child_runs_first live"
else
    _bad "H2. JSON sched.child_runs_first (dapat: $(printf '%s' "$_hj" | python3 -c "import sys,json; print(json.load(sys.stdin)['sched']['child_runs_first'])" 2>/dev/null))"
fi
if printf '%s' "$_hj" | grep -q '"uclamp_min":{"min":0,"max":1024,"cur":0,"writable":true,"supported":true}'; then
    _ok "H3. JSON sched.uclamp_min live (format vendor 0.00 -> 0)"
else
    _bad "H3. JSON uclamp_min (dapat: $(printf '%s' "$_hj" | python3 -c "import sys,json; print(json.load(sys.stdin)['sched']['uclamp'])" 2>/dev/null))"
fi
if printf '%s' "$_hj" | grep -q '"polling_interval":{"min":1,"max":1000,"cur":50,"writable":true,"supported":true}'; then
    _ok "H4. JSON gpu_tunables.polling_interval live"
else
    _bad "H4. JSON gpu_tunables (dapat: $(printf '%s' "$_hj" | python3 -c "import sys,json; print(json.load(sys.stdin)['gpu_tunables'])" 2>/dev/null))"
fi
if printf '%s' "$_hj" | grep -q '"up_threshold":{"min":1,"max":100,"cur":0,"writable":false,"supported":false}'; then
    _ok "H5. JSON up_threshold node hilang: supported:false"
else
    _bad "H5. JSON up_threshold node hilang (dapat: $(printf '%s' "$_hj" | python3 -c "import sys,json; print(json.load(sys.stdin)['gpu_tunables'])" 2>/dev/null))"
fi
if printf '%s' "$_hj" | grep -q '"mali_pollingtime":{"min":1,"max":10,"cur":8,"writable":true,"supported":true}'; then
    _ok "H6. JSON mali_kbase live"
else
    _bad "H6. JSON mali_kbase (dapat: $(printf '%s' "$_hj" | python3 -c "import sys,json; print(json.load(sys.stdin)['mali_kbase'])" 2>/dev/null))"
fi
if printf '%s' "$_hj" | grep -q '"sysctl":{"sched_latency_ns":{"min":10,"max":200,"cur":0,"writable":false,"supported":false}'; then
    _ok "H7. JSON sysctl sched (node hilang) supported:false"
else
    _bad "H7. JSON sysctl sched (dapat: $(printf '%s' "$_hj" | python3 -c "import sys,json; print(json.load(sys.stdin)['sched']['sysctl'])" 2>/dev/null))"
fi

# --- I. knob-list kategori benar ---
_mknodes lengkap
_isolate
_load_all
_reset_state
hsin_uk_set "sched_child_runs_first" "1" >/dev/null 2>&1
hsin_uk_set "uclamp_min" "256" >/dev/null 2>&1
hsin_uk_set "gpu_node_23100000_gpu_polling_interval" "120" >/dev/null 2>&1
hsin_uk_set "mali_upthreshold" "40" >/dev/null 2>&1
_apply_all manual
_i=$(hsin_uk_list 2>/dev/null)
for _pair in "sched_child_runs_first 1 1" "uclamp_min 256 256" \
    "gpu_node_23100000_gpu_polling_interval 120 120" "mali_upthreshold 40 40"; do
    set -- $_pair
    if printf '%s' "$_i" | grep -q "^key=$1 requested=$2 applied=$3 category=APPLIED"; then
        _ok "I. knob-list $1 APPLIED"
    else
        _bad "I. knob-list $1 APPLIED (baris: $(printf '%s' "$_i" | grep "^key=$1"))"
    fi
done
if printf '%s' "$_i" | tail -n 1 | python3 -c "import sys,json; d=json.load(sys.stdin); assert d['count']==4" 2>/dev/null; then
    _ok "I5. knob-list JSON count=4"
else
    _bad "I5. knob-list JSON count=4 (baris: $(printf '%s' "$_i" | tail -n 1))"
fi

# --- J. REGRESI BUG VARIABEL GLOBAL: fungsi kbase harus mandiri ---
# Cara lama: harness memanggil beberapa engine dalam satu proses, dan
# _profile yang bocor dari engine lain menutupi bug salah-nama-variabel
# (hsin_gpu_kbase_knobs_apply dulu baca $_profile, bukan $_mk_profile).
# Di sini kebocoran itu sengaja dihilangkan: profil TIDAK pernah di-set
# sebagai variabel shell, dan tiap panggilan lewat subshell baru.
_mknodes lengkap
_isolate
_reset_state
_load_all
unset _profile
_j_res=$( sh -c '
    . "'"$_HSIN_REPO"'/core/logger.sh" 2>/dev/null
    . "'"$_HSIN_REPO"'/core/sysfs.sh" 2>/dev/null
    . "'"$_HSIN_REPO"'/core/user_knobs.sh" 2>/dev/null
    . "'"$_HSIN_REPO"'/engine/gpu/mali.sh" 2>/dev/null
    [ -z "${_profile:-}" ] || echo "LEAK:_profile" >&2
    hsin_gpu_kbase_knobs_apply balanced >/dev/null 2>&1
    printf "%s/%s/%s" \
        "$(cat "$HSIN_SYSFS_KBASE_ABS/gpu_boost_level2")" \
        "$(cat "$HSIN_SYSFS_KBASE_ABS/gpu_pollingtime")" \
        "$(cat "$HSIN_SYSFS_KBASE_ABS/gpu_upthreshold")"
' 2>&1 )
if [ "$_j_res" = "0/4/72" ]; then
    _ok "J. kbase mandiri tanpa global pemanggil: balanced -> 0/4/72"
else
    _bad "J. kbase mandiri (dapat: $_j_res)"
fi
# manual tanpa override = nol tulis, dalam kondisi terisolasi
_mknodes lengkap
_isolate
_reset_state
_load_all
unset _profile
_j2=$( sh -c '
    . "'"$_HSIN_REPO"'/core/logger.sh" 2>/dev/null
    . "'"$_HSIN_REPO"'/core/sysfs.sh" 2>/dev/null
    . "'"$_HSIN_REPO"'/core/user_knobs.sh" 2>/dev/null
    . "'"$_HSIN_REPO"'/engine/gpu/mali.sh" 2>/dev/null
    hsin_gpu_kbase_knobs_apply manual >/dev/null 2>&1
    printf "%s/%s/%s" \
        "$(cat "$HSIN_SYSFS_KBASE_ABS/gpu_boost_level2")" \
        "$(cat "$HSIN_SYSFS_KBASE_ABS/gpu_pollingtime")" \
        "$(cat "$HSIN_SYSFS_KBASE_ABS/gpu_upthreshold")"
' 2>&1 )
if [ "$_j2" = "0/8/88" ]; then
    _ok "J2. kbase manual tanpa override: nol tulis (0/8/88 utuh)"
else
    _bad "J2. kbase manual tanpa override (dapat: $_j2)"
fi
# profil tak dikenal = tidak boleh menulis nilai kosong
_mknodes lengkap
_isolate
_reset_state
_load_all
unset _profile
_j3=$( sh -c '
    . "'"$_HSIN_REPO"'/core/logger.sh" 2>/dev/null
    . "'"$_HSIN_REPO"'/core/sysfs.sh" 2>/dev/null
    . "'"$_HSIN_REPO"'/core/user_knobs.sh" 2>/dev/null
    . "'"$_HSIN_REPO"'/engine/gpu/mali.sh" 2>/dev/null
    hsin_gpu_kbase_knobs_apply "profil-ngawur" >/dev/null 2>&1
    printf "%s/%s/%s" \
        "$(cat "$HSIN_SYSFS_KBASE_ABS/gpu_boost_level2")" \
        "$(cat "$HSIN_SYSFS_KBASE_ABS/gpu_pollingtime")" \
        "$(cat "$HSIN_SYSFS_KBASE_ABS/gpu_upthreshold")"
' 2>&1 )
if [ "$_j3" = "0/8/88" ]; then
    _ok "J3. profil tak dikenal: tidak menulis (node tak dikosongkan)"
else
    _bad "J3. profil tak dikenal: tidak menulis (dapat: $_j3)"
fi

echo "---"
echo "sandbox_k3_knobs: PASS=$_PASS FAIL=$_FAIL"
rm -rf "$HSIN_SANDBOX_DIR"
[ "$_FAIL" -eq 0 ]
