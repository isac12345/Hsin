#!/system/bin/sh
# Sandbox test K2: knob tier-1 (I/O queue boolean, VM stat_interval +
# page_cluster, schedutil rate_limit_us per policy).
#
# Dibuktikan:
#   A. tiap knob set satu-per-satu -> hanya node itu berubah (snapshot md5)
#   B. manual tanpa override = nol penulisan (termasuk 6 knob baru)
#   C. profil non-manual = nilai profil, dan knob tanpa nilai profil
#      (stat_interval + 3 queue + rate_limit_us) TIDAK ditulis
#   D. node hilang = UNAVAILABLE tanpa crash
#   E. nilai ditolak: boolean selain 0/1, di luar rentang, rate_limit_us
#      > 100000 (knob-set + file cacat)
#   F. rate_limit_us: governor schedutil -> APPLIED; governor lain ->
#      UNAVAILABLE; node absen -> UNAVAILABLE
#   G. backup -> rollback per knob (6 roundtrip)
#   H. knobs JSON memuat field baru (queue_tuning, stat_interval,
#      page_cluster, rate_limit_us) dengan cur dari node palsu
#   I. knob-list kategori benar
#
# Cara pakai: sh tests/sandbox_k2_knobs.sh

_HSIN_REPO=$(cd "${0%/*}/.." 2>/dev/null && pwd)
HSIN_SANDBOX_DIR="${HSIN_SANDBOX_DIR:-/usr/tmp/opencode/hsin-k2-test}"
SB_SYS="$HSIN_SANDBOX_DIR/sys"
SB_PROC="$HSIN_SANDBOX_DIR/proc"
export HSIN_MODULE_PATH="$_HSIN_REPO"
export HSIN_DATA="$HSIN_SANDBOX_DIR/data"
export HSIN_SANDBOX=1
export HSIN_SYSFS_BLOCK="$SB_SYS/block"
export HSIN_SYSFS_CPU="$SB_SYS/cpu"
export SYSFS_BLOCK_PREFIX="$SB_SYS/block"
export SYSFS_CPU_PREFIX="$SB_SYS/cpu"
export SYSFS_PROC_PREFIX="$SB_PROC"
export HSIN_PROC="$SB_PROC"

_PASS=0
_FAIL=0

_ok() { _PASS=$((_PASS + 1)); echo "PASS: $1"; }
_bad() { _FAIL=$((_FAIL + 1)); echo "FAIL: $1"; }

# $1 = 1: governor schedutil + node rate_limit_us ADA.
# $2 = 2: governor schedutil tapi node rate_limit_us ABSEN.
# $3 = 3: governor bukan schedutil (default uscfreq), node absen.
_mknodes() {
    _gov="uscfreq"
    [ "${1:-3}" = "1" ] && _gov="schedutil"
    rm -rf "$SB_SYS" "$SB_PROC"
    mkdir -p "$SB_SYS/block/sda/queue" "$SB_PROC/sys/vm" "$SB_PROC/sys/net/core" \
        "$SB_PROC/sys/net/ipv4" "$HSIN_DATA/logs" \
        "$SB_SYS/cpu/cpufreq/policy0" "$SB_SYS/cpu/cpufreq/policy6"
    printf '128\n' > "$SB_SYS/block/sda/queue/read_ahead_kb"
    printf 'mq-deadline [none] kyber\n' > "$SB_SYS/block/sda/queue/scheduler"
    printf '0\n' > "$SB_SYS/block/sda/queue/add_random"
    printf '0\n' > "$SB_SYS/block/sda/queue/iostats"
    printf '2\n' > "$SB_SYS/block/sda/queue/nomerges"
    printf '100\n' > "$SB_PROC/sys/vm/vfs_cache_pressure"
    printf '20\n' > "$SB_PROC/sys/vm/dirty_ratio"
    printf '5\n' > "$SB_PROC/sys/vm/dirty_background_ratio"
    printf '60\n' > "$SB_PROC/sys/vm/swappiness"
    printf '10\n' > "$SB_PROC/sys/vm/stat_interval"
    printf '0\n' > "$SB_PROC/sys/vm/page-cluster"
    printf '1000\n' > "$SB_PROC/sys/net/core/netdev_max_backlog"
    for _p in policy0 policy6; do
        printf '%s\n' "$_gov" > "$SB_SYS/cpu/cpufreq/$_p/scaling_governor"
        printf 'userspace %s conservative powersave performance schedutil\n' "$_gov" \
            > "$SB_SYS/cpu/cpufreq/$_p/scaling_available_governors"
        printf '1612000\n' > "$SB_SYS/cpu/cpufreq/$_p/scaling_max_freq"
        printf '300000\n' > "$SB_SYS/cpu/cpufreq/$_p/scaling_min_freq"
        printf '1612000\n' > "$SB_SYS/cpu/cpufreq/$_p/cpuinfo_max_freq"
        printf '300000 1612000\n' > "$SB_SYS/cpu/cpufreq/$_p/related_cpus"
        if [ "${2:-2}" != "2" ]; then
            mkdir -p "$SB_SYS/cpu/cpufreq/$_p/schedutil"
            printf '20000\n' > "$SB_SYS/cpu/cpufreq/$_p/schedutil/rate_limit_us"
        fi
    done
    return 0
}

_snapshot() {
    for _f in \
        "$SB_SYS/block/sda/queue/read_ahead_kb" \
        "$SB_SYS/block/sda/queue/scheduler" \
        "$SB_SYS/block/sda/queue/add_random" \
        "$SB_SYS/block/sda/queue/iostats" \
        "$SB_SYS/block/sda/queue/nomerges" \
        "$SB_PROC/sys/vm/vfs_cache_pressure" \
        "$SB_PROC/sys/vm/dirty_ratio" \
        "$SB_PROC/sys/vm/dirty_background_ratio" \
        "$SB_PROC/sys/vm/swappiness" \
        "$SB_PROC/sys/vm/stat_interval" \
        "$SB_PROC/sys/vm/page-cluster" \
        "$SB_PROC/sys/net/core/netdev_max_backlog" \
        "$SB_SYS/cpu/cpufreq/policy0/scaling_governor" \
        "$SB_SYS/cpu/cpufreq/policy0/schedutil/rate_limit_us" \
        "$SB_SYS/cpu/cpufreq/policy6/schedutil/rate_limit_us"; do
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

_reset_state() {
    rm -f "$HSIN_DATA/user_knobs.env" "$HSIN_DATA/knob_results.env"
    _uk_inited=""; _uk_cache=""; _uk_cache_done=""; _uk_used_n=0; _uk_sum_done=""
    return 0
}

_load_all() {
    for _f in core/logger.sh core/sysfs.sh core/scan_cache.sh core/safe_apply.sh \
        core/user_knobs.sh core/knobs.sh engine/cpu/detect.sh engine/cpu/governor.sh \
        engine/cpu/frequency.sh engine/memory/detect.sh engine/memory/vm.sh \
        engine/io/scheduler.sh engine/io/readahead.sh engine/io/queue_tuning.sh \
        engine/display/refresh_rate.sh engine/render/renderer.sh; do
        . "$_HSIN_REPO/$_f" 2>/dev/null
    done
    return 0
}

_apply_all() {
    hsin_vm_apply "$1" >/dev/null 2>&1
    hsin_io_apply_readahead "$1" >/dev/null 2>&1
    hsin_io_apply_queue_tuning "$1" >/dev/null 2>&1
    hsin_cpu_governor_apply "$1" >/dev/null 2>&1
    hsin_network_apply_sysctl "$1" >/dev/null 2>&1
    return 0
}

# $1 key, $2 nilai, $3 path node, $4 nilai akhir
_apply_one() {
    _k="$1"; _v="$2"; _node="$3"; _want="$4"
    _reset_state
    hsin_uk_set "$_k" "$_v" >/dev/null 2>&1
    _before=$(_snapshot)
    _apply_all manual
    _after=$(_snapshot)
    _changed=$(_diffnodes "$_before" "$_after")
    _cnt=$(printf '%s' "$_changed" | grep -c .)
    if [ "$_cnt" = "1" ] && [ "$_changed" = "$_node" ] && [ "$(cat "$_node" 2>/dev/null)" = "$_want" ]; then
        _ok "$_k=$_v: hanya node itu berubah -> $_want"
    else
        _bad "$_k=$_v: hanya node itu berubah (jumlah=$_cnt [$(printf '%s' "$_changed" | tr '\n' ' ')] isi=$(cat "$_node" 2>/dev/null))"
    fi
}

# --- A. snapshot byte per knob ---
_mknodes 1 1
_load_all
_apply_one "io_block_sda_add_random" "1" "$SB_SYS/block/sda/queue/add_random" "1"
_apply_one "io_block_sda_iostats" "1" "$SB_SYS/block/sda/queue/iostats" "1"
_apply_one "io_block_sda_nomerges" "1" "$SB_SYS/block/sda/queue/nomerges" "1"
_apply_one "stat_interval" "30" "$SB_PROC/sys/vm/stat_interval" "30"
_apply_one "page_cluster" "4" "$SB_PROC/sys/vm/page-cluster" "4"
_apply_one "cpu_policy_0_rate_limit_us" "40000" "$SB_SYS/cpu/cpufreq/policy0/schedutil/rate_limit_us" "40000"

# --- B. manual tanpa override = nol penulisan ---
_mknodes 1 1
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

# --- C. profil balanced: knob tanpa nilai profil TIDAK ditulis ---
_mknodes 1 1
_load_all
_reset_state
_before=$(_snapshot)
_apply_all balanced
_after=$(_snapshot)
_c_changed=$(_diffnodes "$_before" "$_after")
# Yang BOLEH berubah di balanced: scheduler? tidak (sudah cocok), vm profil
# (vfs/dirty/bg/swappiness/page-cluster), readahead 512, backlog 1000.
_c_forbidden=$(printf '%s' "$_c_changed" | grep -E 'add_random|iostats|nomerges|stat_interval|rate_limit_us' || true)
if [ -z "$_c_forbidden" ]; then
    _ok "C. balanced: knob tanpa nilai profil tidak ditulis (queue/stat/rate_limit utuh)"
else
    _bad "C. balanced: knob tanpa nilai profil tidak ditulis (berubah: $(printf '%s' "$_c_forbidden" | tr '\n' ' '))"
fi
if [ "$(cat "$SB_PROC/sys/vm/page-cluster")" = "3" ] \
    && [ "$(cat "$SB_PROC/sys/vm/stat_interval")" = "10" ] \
    && [ "$(cat "$SB_SYS/block/sda/queue/nomerges")" = "2" ]; then
    _ok "C2. balanced: page-cluster=3 (profil), stat_interval=10 (tak ditulis), nomerges=2 (tak ditulis)"
else
    _bad "C2. balanced (page=$(cat "$SB_PROC/sys/vm/page-cluster") stat=$(cat "$SB_PROC/sys/vm/stat_interval") nomerges=$(cat "$SB_SYS/block/sda/queue/nomerges"))"
fi

# --- D. node hilang = UNAVAILABLE, tanpa crash ---
_mknodes 1 2
rm -f "$SB_PROC/sys/vm/stat_interval" "$SB_SYS/block/sda/queue/iostats"
_load_all
_reset_state
hsin_uk_set "stat_interval" "20" >/dev/null 2>&1
hsin_uk_set "io_block_sda_iostats" "1" >/dev/null 2>&1
_apply_all manual
_rc=$?
if [ "$_rc" -eq 0 ] && [ "$(cat "$SB_PROC/sys/vm/page-cluster")" = "0" ] \
    && [ "$(cat "$SB_SYS/block/sda/queue/add_random")" = "0" ]; then
    _ok "D. node hilang: tidak crash, node lain tak ditulis"
else
    _bad "D. node hilang: tidak crash (rc=$_rc pc=$(cat "$SB_PROC/sys/vm/page-cluster") ar=$(cat "$SB_SYS/block/sda/queue/add_random"))"
fi
if grep -q '^stat_interval=.*UNAVAILABLE' "$HSIN_DATA/knob_results.env" 2>/dev/null \
    && grep -q '^io_block_sda_iostats=.*UNAVAILABLE' "$HSIN_DATA/knob_results.env" 2>/dev/null; then
    _ok "D2. stat_interval + iostats UNAVAILABLE tercatat"
else
    _bad "D2. UNAVAILABLE tercatat (hasil: $(tr '\n' '|' < "$HSIN_DATA/knob_results.env" 2>/dev/null))"
fi

# --- E. nilai ditolak ---
_mknodes 1 1
_load_all
for _pair in "io_block_sda_add_random 2" "io_block_sda_iostats abc" "io_block_sda_nomerges 3" \
    "stat_interval 0" "stat_interval 61" "page_cluster 10" "page_cluster -1" \
    "cpu_policy_0_rate_limit_us 100001" "gpu_node_mali0_add_random 1" \
    "io_block_sda_rate_limit_us 100"; do
    _sk=$(printf '%s' "$_pair" | cut -d' ' -f1)
    _sv=$(printf '%s' "$_pair" | cut -d' ' -f2)
    if hsin_uk_set "$_sk" "$_sv" >/dev/null 2>&1; then
        _bad "E. $_sk=$_sv ditolak knob-set (justru diterima)"
    else
        _ok "E. $_sk=$_sv: knob-set MENOLAK"
    fi
done
# File override cacat -> ditolak engine, nol penulisan.
_reset_state
printf 'io_block_sda_add_random=7\ncpu_policy_0_rate_limit_us=999999\n' > "$HSIN_DATA/user_knobs.env"
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

# --- F. rate_limit_us: gate governor + node ---
# F1: schedutil + node ada -> APPLIED.
_mknodes 1 1
_load_all
_reset_state
hsin_uk_set "cpu_policy_0_rate_limit_us" "50000" >/dev/null 2>&1
_apply_all manual
if [ "$(cat "$SB_SYS/cpu/cpufreq/policy0/schedutil/rate_limit_us")" = "50000" ] \
    && grep -q '^cpu_policy_0_rate_limit_us=50000|50000|APPLIED' "$HSIN_DATA/knob_results.env"; then
    _ok "F1. schedutil + node ada: APPLIED 50000"
else
    _bad "F1. schedutil + node ada (node=$(cat "$SB_SYS/cpu/cpufreq/policy0/schedutil/rate_limit_us"); hasil: $(grep rate_limit "$HSIN_DATA/knob_results.env" 2>/dev/null | tr '\n' '|'))"
fi
# F2: governor bukan schedutil -> UNAVAILABLE + nol tulis.
_mknodes 3 2
_load_all
_reset_state
hsin_uk_set "cpu_policy_0_rate_limit_us" "50000" >/dev/null 2>&1
_before=$(_snapshot)
_apply_all manual
_after=$(_snapshot)
if [ "$_before" = "$_after" ] \
    && grep -q '^cpu_policy_0_rate_limit_us=.*UNAVAILABLE.*governor aktif bukan schedutil' "$HSIN_DATA/knob_results.env"; then
    _ok "F2. governor bukan schedutil: UNAVAILABLE + nol penulisan"
else
    _bad "F2. governor bukan schedutil (hasil: $(grep rate_limit "$HSIN_DATA/knob_results.env" 2>/dev/null | tr '\n' '|'))"
fi
# F3: governor schedutil tapi node absen -> UNAVAILABLE.
_mknodes 1 2
_load_all
_reset_state
hsin_uk_set "cpu_policy_0_rate_limit_us" "50000" >/dev/null 2>&1
_apply_all manual
if grep -q '^cpu_policy_0_rate_limit_us=.*UNAVAILABLE.*tidak ada' "$HSIN_DATA/knob_results.env"; then
    _ok "F3. schedutil tapi node absen: UNAVAILABLE"
else
    _bad "F3. schedutil tapi node absen (hasil: $(grep rate_limit "$HSIN_DATA/knob_results.env" 2>/dev/null | tr '\n' '|'))"
fi

# --- G. backup -> rollback per knob (6 roundtrip) ---
for _knob in add_random iostats nomerges stat_interval page_cluster rate_limit_us; do
    _mknodes 1 1
    _load_all
    . "$_HSIN_REPO/core/backup.sh" 2>/dev/null
    _o=$(cat "$SB_PROC/sys/vm/stat_interval")
    _op=$(cat "$SB_PROC/sys/vm/page-cluster")
    _oar=$(cat "$SB_SYS/block/sda/queue/add_random")
    _oi=$(cat "$SB_SYS/block/sda/queue/iostats")
    _on=$(cat "$SB_SYS/block/sda/queue/nomerges")
    _orl=$(cat "$SB_SYS/cpu/cpufreq/policy0/schedutil/rate_limit_us")
    HSIN_BACKUP_ROOT="$HSIN_DATA/backup"
    hsin_backup_init "k2test"
    hsin_backup_io
    hsin_backup_memory
    hsin_backup_cpu_freqs
    case "$_knob" in
        add_random)   printf '1\n' > "$SB_SYS/block/sda/queue/add_random" ;;
        iostats)      printf '1\n' > "$SB_SYS/block/sda/queue/iostats" ;;
        nomerges)     printf '1\n' > "$SB_SYS/block/sda/queue/nomerges" ;;
        stat_interval) printf '55\n' > "$SB_PROC/sys/vm/stat_interval" ;;
        page_cluster) printf '8\n' > "$SB_PROC/sys/vm/page-cluster" ;;
        rate_limit_us) printf '90000\n' > "$SB_SYS/cpu/cpufreq/policy0/schedutil/rate_limit_us" ;;
    esac
    hsin_restore_session "k2test" >/dev/null 2>&1
    if [ "$(cat "$SB_PROC/sys/vm/stat_interval")" = "$_o" ] \
        && [ "$(cat "$SB_PROC/sys/vm/page-cluster")" = "$_op" ] \
        && [ "$(cat "$SB_SYS/block/sda/queue/add_random")" = "$_oar" ] \
        && [ "$(cat "$SB_SYS/block/sda/queue/iostats")" = "$_oi" ] \
        && [ "$(cat "$SB_SYS/block/sda/queue/nomerges")" = "$_on" ] \
        && [ "$(cat "$SB_SYS/cpu/cpufreq/policy0/schedutil/rate_limit_us")" = "$_orl" ]; then
        _ok "G. rollback $_knob: semua nilai kembali"
    else
        _bad "G. rollback $_knob (stat=$(cat "$SB_PROC/sys/vm/stat_interval")/$o pc=$(cat "$SB_PROC/sys/vm/page-cluster")/$op ar=$(cat "$SB_SYS/block/sda/queue/add_random")/$oar io=$(cat "$SB_SYS/block/sda/queue/iostats")/$oi nm=$(cat "$SB_SYS/block/sda/queue/nomerges")/$on rl=$(cat "$SB_SYS/cpu/cpufreq/policy0/schedutil/rate_limit_us")/$orl)"
    fi
    rm -rf "$HSIN_DATA/backup"
done

# --- H. knobs JSON field baru ---
_mknodes 1 1
_load_all
_hj=$(hsin_knobs_json 2>/dev/null)
if printf '%s' "$_hj" | python3 -c "import sys,json; json.load(sys.stdin)" 2>/dev/null; then
    _ok "H. knobs JSON valid"
else
    _bad "H. knobs JSON valid (output: $(printf '%s' "$_hj" | head -c 200))"
fi
if printf '%s' "$_hj" | grep -q '"add_random":{"options":\[0,1\],"cur":0,"writable":true,"supported":true}'; then
    _ok "H2. JSON queue_tuning.add_random 0/1 live"
else
    _bad "H2. JSON queue_tuning (dapat: $(printf '%s' "$_hj" | python3 -c "import sys,json; print(json.load(sys.stdin)['io']['blocks'][0].get('queue_tuning'))" 2>/dev/null))"
fi
if printf '%s' "$_hj" | grep -q '"nomerges":{"options":\[0,1\],"cur":2,"writable":true,"supported":true}'; then
    _ok "H3. JSON nomerges cur=2 (live) dengan options 0/1"
else
    _bad "H3. JSON nomerges (dapat: $(printf '%s' "$_hj" | python3 -c "import sys,json; print(json.load(sys.stdin)['io']['blocks'][0]['queue_tuning']['nomerges'])" 2>/dev/null))"
fi
if printf '%s' "$_hj" | grep -q '"stat_interval":{"min":1,"max":60,"cur":10,"writable":true,"supported":true}'; then
    _ok "H4. JSON stat_interval 1-60 cur 10"
else
    _bad "H4. JSON stat_interval (dapat: $(printf '%s' "$_hj" | python3 -c "import sys,json; print(json.load(sys.stdin)['vm'].get('stat_interval'))" 2>/dev/null))"
fi
if printf '%s' "$_hj" | grep -q '"page_cluster":{"min":0,"max":9,"cur":0,"writable":true,"supported":true}'; then
    _ok "H5. JSON page_cluster 0-9 cur 0"
else
    _bad "H5. JSON page_cluster (dapat: $(printf '%s' "$_hj" | python3 -c "import sys,json; print(json.load(sys.stdin)['vm'].get('page_cluster'))" 2>/dev/null))"
fi
if printf '%s' "$_hj" | grep -q '"rate_limit_us":{"min":0,"max":100000,"cur":20000,"writable":true,"supported":true}'; then
    _ok "H6. JSON cpu.policies[].rate_limit_us live"
else
    _bad "H6. JSON rate_limit_us (dapat: $(printf '%s' "$_hj" | python3 -c "import sys,json; print(json.load(sys.stdin)['cpu']['policies'][0].get('rate_limit_us'))" 2>/dev/null))"
fi
# H7: node rate_limit_us absen -> supported:false, bukan crash.
_mknodes 1 2
_load_all
_hj2=$(hsin_knobs_json 2>/dev/null)
if printf '%s' "$_hj2" | grep -q '"rate_limit_us":{"min":0,"max":100000,"cur":0,"writable":false,"supported":false}'; then
    _ok "H7. JSON rate_limit_us node absen: supported:false"
else
    _bad "H7. JSON rate_limit_us node absen (dapat: $(printf '%s' "$_hj2" | python3 -c "import sys,json; print(json.load(sys.stdin)['cpu']['policies'][0].get('rate_limit_us'))" 2>/dev/null))"
fi

# --- I. knob-list kategori benar ---
_mknodes 1 1
_load_all
_reset_state
hsin_uk_set "stat_interval" "45" >/dev/null 2>&1
hsin_uk_set "io_block_sda_nomerges" "1" >/dev/null 2>&1
hsin_uk_set "cpu_policy_0_rate_limit_us" "15000" >/dev/null 2>&1
_apply_all manual
_i=$(hsin_uk_list 2>/dev/null)
if printf '%s' "$_i" | grep -q '^key=stat_interval requested=45 applied=45 category=APPLIED'; then
    _ok "I. knob-list stat_interval APPLIED"
else
    _bad "I. knob-list stat_interval (baris: $(printf '%s' "$_i" | grep '^key=stat_interval'))"
fi
if printf '%s' "$_i" | grep -q '^key=io_block_sda_nomerges requested=1 applied=1 category=APPLIED'; then
    _ok "I2. knob-list nomerges APPLIED"
else
    _bad "I2. knob-list nomerges (baris: $(printf '%s' "$_i" | grep nomerges))"
fi
if printf '%s' "$_i" | grep -q '^key=cpu_policy_0_rate_limit_us requested=15000 applied=15000 category=APPLIED'; then
    _ok "I3. knob-list rate_limit_us APPLIED"
else
    _bad "I3. knob-list rate_limit_us (baris: $(printf '%s' "$_i" | grep rate_limit))"
fi
if printf '%s' "$_i" | tail -n 1 | python3 -c "import sys,json; d=json.load(sys.stdin); assert d['count']==3" 2>/dev/null; then
    _ok "I4. knob-list JSON count=3"
else
    _bad "I4. knob-list JSON count=3 (baris: $(printf '%s' "$_i" | tail -n 1))"
fi

echo "---"
echo "sandbox_k2_knobs: PASS=$_PASS FAIL=$_FAIL"
rm -rf "$HSIN_SANDBOX_DIR"
[ "$_FAIL" -eq 0 ]
