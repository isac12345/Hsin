#!/system/bin/sh
# HSIN - Backup & Restore

HSIN_DATA="${HSIN_DATA:-/data/adb/hsin}"
[ -z "$HSIN_MODULE_PATH" ] && HSIN_MODULE_PATH="/data/adb/modules/hsin"
. "$HSIN_MODULE_PATH/core/sysfs.sh" 2>/dev/null
# /proc via $HSIN_PROC supaya bisa di-sandbox (prefix palsu), default /proc.
[ -n "$HSIN_PROC" ] || HSIN_PROC="${SYSFS_PROC_PREFIX:-/proc}"
HSIN_BACKUP_ROOT="$HSIN_DATA/backup"

hsin_backup_init() {
    # $1=nama sesi (default: timestamp)
    _name="${1:-$(date '+%Y%m%d_%H%M%S')}"
    HSIN_BACKUP_CUR="$HSIN_BACKUP_ROOT/$_name"
    mkdir -p "$HSIN_BACKUP_CUR"
    {
        echo "# HSIN backup session: $_name"
        echo "# Created: $(date '+%Y-%m-%d %H:%M:%S')"
    } > "$HSIN_BACKUP_CUR/META"
    export HSIN_BACKUP_CUR
    [ -n "$HSIN_LOG_FILE" ] && {
        hsin_log_info "backup" "session=$_name dir=$HSIN_BACKUP_CUR"
    }
}

# Simpan 1 node. Skip kalau file tidak ada.
hsin_backup_node() {
    # $1=path absolut
    _bn_p="$1"
    [ -z "$HSIN_BACKUP_CUR" ] && hsin_backup_init
    [ -f "$_bn_p" ] || return 0
    # PATCH v4.0: baca pakai builtin read (tanpa fork cat), dan BUANG
    # md5sum|awk per node - hasilnya (_h) ternyata TIDAK PERNAH dipakai
    # (dead code) tapi nge-fork 2 proses tiap node. Di low-end, snapshot
    # penuh (~100 node) berarti ~300 fork = 7-15 detik murni sia-sia.
    _v=""
    IFS= read -r _v < "$_bn_p" 2>/dev/null
    echo "$_bn_p=$_v" >> "$HSIN_BACKUP_CUR/nodes.list"
}

# Backup banyak node sekaligus (multi-arg)
hsin_backup_nodes() {
    for p in "$@"; do
        hsin_backup_node "$p"
    done
}

# Restore satu sesi backup ke nilai asli
hsin_restore_session() {
    # $1=nama sesi atau "latest"
    _name="$1"
    [ "$_name" = "latest" ] && {
        _name=$(ls -1 "$HSIN_BACKUP_ROOT" 2>/dev/null | sort | tail -1)
    }
    [ -z "$_name" ] && {
        echo "No backup session found"
        return 1
    }
    _dir="$HSIN_BACKUP_ROOT/$_name"
    [ -d "$_dir" ] || {
        echo "Backup dir not found: $_dir"
        return 1
    }
    [ -f "$_dir/nodes.list" ] || {
        echo "nodes.list missing in $_dir"
        return 1
    }
    _count=0; _fail=0
    while IFS='=' read -r p v; do
        [ -z "$p" ] && continue
        [ -f "$p" ] || { _fail=$((_fail + 1)); continue; }
        echo "$v" > "$p" 2>/dev/null
        _cur=$(cat "$p" 2>/dev/null)
        if [ "$_cur" = "$v" ]; then
            _count=$((_count + 1))
        else
            _fail=$((_fail + 1))
        fi
    done < "$_dir/nodes.list"
    echo "Restore $_name done. ok=$_count fail=$_fail"
    return 0
}

# List sesi backup
hsin_backup_list() {
    ls -1 "$HSIN_BACKUP_ROOT" 2>/dev/null
}

# Backup selektif: hanya node yang match pattern tertentu (untuk CPU freq dsb)
hsin_backup_cpu_freqs() {
    for p in /sys/devices/system/cpu/cpufreq/policy*; do
        [ -d "$p" ] || continue
        hsin_backup_node "$p/scaling_governor"
        hsin_backup_node "$p/scaling_min_freq"
        hsin_backup_node "$p/scaling_max_freq"
        # Beberapa SoC punya node boost
        [ -f "$p/scaling_boost_freq" ] && hsin_backup_node "$p/scaling_boost_freq"
    done
}

hsin_backup_gpu_freqs() {
    # devfreq GPU nodes
    for d in /sys/class/devfreq/*; do
        [ -d "$d" ] || continue
        hsin_devfreq_gpu_candidate "$d" || continue
        hsin_backup_node "$d/governor"
        hsin_backup_node "$d/min_freq"
        hsin_backup_node "$d/max_freq"
    done
    # KGSL
    for k in /sys/class/kgsl/kgsl-3d0/*; do
        hsin_backup_node "$k"
    done
    # Mali platform
    for m in /sys/devices/platform/*.mali; do
        [ -d "$m" ] || continue
        hsin_backup_node "$m/power_policy"
        hsin_backup_node "$m/dvfs_governor"
        hsin_backup_node "$m/tmu"
        hsin_backup_node "$m/dvfs"
    done
}

hsin_backup_thermal() {
    for z in /sys/class/thermal/thermal_zone*; do
        [ -d "$z" ] || continue
        [ -w "$z/mode" ] && hsin_backup_node "$z/mode"
    done
}

hsin_backup_io() {
    for b in /sys/block/*; do
        [ -d "$b" ] || continue
        _name=$(basename "$b")
        case "$_name" in loop*|ram*|zram*|dm-*) continue ;; esac
        hsin_backup_node "$b/queue/scheduler"
        hsin_backup_node "$b/queue/read_ahead_kb"
    done
}

hsin_backup_memory() {
    [ -f "$HSIN_PROC/sys/vm/swappiness" ] && hsin_backup_node "$HSIN_PROC/sys/vm/swappiness"
}

hsin_backup_network() {
    [ -f "$HSIN_PROC/sys/net/ipv4/tcp_congestion_control" ] && hsin_backup_node "$HSIN_PROC/sys/net/ipv4/tcp_congestion_control"
    [ -f "$HSIN_PROC/sys/net/ipv4/tcp_fastopen" ] && hsin_backup_node "$HSIN_PROC/sys/net/ipv4/tcp_fastopen"
}

# Backup all (dipakai sebelum apply profile)
hsin_backup_all() {
    hsin_backup_init "${1:-$(date '+%Y%m%d_%H%M%S')}"
    hsin_log_info "backup" "Capturing full snapshot..."
    hsin_backup_cpu_freqs
    hsin_backup_gpu_freqs
    hsin_backup_thermal
    hsin_backup_io
    hsin_backup_memory
    hsin_backup_network
    _count=$(wc -l < "$HSIN_BACKUP_CUR/nodes.list" 2>/dev/null)
    hsin_log_ok "backup" "Snapshot captured: $_count nodes"
}

return 0 2>/dev/null || true
