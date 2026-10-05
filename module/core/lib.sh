#!/system/bin/sh
# HSIN v5 core. POSIX sh (mksh/ash/dash). Di-source oleh action.sh, service.sh, daemon.sh.
# Tanpa awk/grep/sed: hanya builtin shell + sort/tr/ls/cat/date/uname/head/tail.

HSIN_VER="v5.0.0"
HSIN_DATA="${HSIN_DATA:-/data/adb/hsin5}"
SYS="${HSIN_SYS:-/sys}"
PROC="${HSIN_PROC:-/proc}"
CPUSET="${HSIN_CPUSET:-/dev/cpuset}"
MODS="${HSIN_MODS:-/data/adb/modules}"
OVR="$HSIN_DATA/overrides.env"
BASE="$HSIN_DATA/baseline.env"
CFG="$HSIN_DATA/config.env"
SAFEF="$HSIN_DATA/safe_mode"
CNTF="$HSIN_DATA/boot_count"
TRIPF="$HSIN_DATA/thermal_trip"
ACTF="$HSIN_DATA/game_active"
GAMEDIR="$HSIN_DATA/games"
LOGD="$HSIN_DATA/logs"
[ -d "$LOGD" ] || mkdir -p "$LOGD" 2>/dev/null
[ -d "$GAMEDIR" ] || mkdir -p "$GAMEDIR" 2>/dev/null
set -f   # glob mati; fungsi yang butuh glob menyalakannya sendiri lalu mematikannya lagi

# ---------- util dasar ----------
rd() { # baca baris pertama file, tanpa newline
    [ -r "$1" ] || return 1
    _rd_l=""
    { IFS= read -r _rd_l; } 2>/dev/null < "$1" || [ -n "$_rd_l" ] || return 1
    printf '%s' "$_rd_l"
}
wr() { { printf '%s\n' "$2" > "$1"; } 2>/dev/null; }
gp() { command -v getprop >/dev/null 2>&1 && getprop "$1" 2>/dev/null; }
sp() { command -v setprop >/dev/null 2>&1 && setprop "$1" "$2" 2>/dev/null; }
safe() { printf '%s' "$1" | tr -cd 'A-Za-z0-9_.:+ -'; }
isint() { case "$1" in ''|*[!0-9]*) return 1 ;; esac; return 0; }
canw() { # owner-write bit (root mengabaikan mode, jadi cek bit saja)
    [ -e "$1" ] || return 1
    set -- $(ls -ld "$1" 2>/dev/null)
    case "$1" in ??w*) return 0 ;; esac
    return 1
}
log() { printf '%s %s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1" "$3" >> "$LOGD/$2.log" 2>/dev/null; }
trim_log() {
    [ -f "$LOGD/$1.log" ] || return 0
    _tl_n=0
    while IFS= read -r _tl_x; do _tl_n=$((_tl_n + 1)); done < "$LOGD/$1.log"
    if [ "$_tl_n" -gt "$2" ]; then
        tail -n "$2" "$LOGD/$1.log" > "$LOGD/$1.log.tmp" 2>/dev/null && mv "$LOGD/$1.log.tmp" "$LOGD/$1.log"
    fi
}
sorted_nums() {
    _sn=$(printf '%s\n' $1 | sort -nu | tr '\n' ' ')
    set -- $_sn
    printf '%s' "$*"
}

# ---------- key=value ----------
kv_get() { # file key
    [ -f "$1" ] || return 1
    while IFS='=' read -r _kv_k _kv_v; do
        [ "$_kv_k" = "$2" ] && { printf '%s' "$_kv_v"; return 0; }
    done < "$1"
    return 1
}
kv_set() { # file key val
    _kv_t="$1.tmp"; : > "$_kv_t"
    if [ -f "$1" ]; then
        while IFS= read -r _kv_l; do
            case "$_kv_l" in "$2="*) ;; *) printf '%s\n' "$_kv_l" >> "$_kv_t" ;; esac
        done < "$1"
    fi
    printf '%s=%s\n' "$2" "$3" >> "$_kv_t"
    mv "$_kv_t" "$1"
}
kv_del() { # file key
    [ -f "$1" ] || return 0
    _kv_t="$1.tmp"; : > "$_kv_t"
    while IFS= read -r _kv_l; do
        case "$_kv_l" in "$2="*) ;; *) printf '%s\n' "$_kv_l" >> "$_kv_t" ;; esac
    done < "$1"
    mv "$_kv_t" "$1"
}
cfg_get() { kv_get "$CFG" "$1" || printf '%s' "$2"; }
cfg_set() { kv_set "$CFG" "$1" "$2"; }

# ---------- suhu ----------
norm_temp() {
    isint "$1" || { printf '%s' -1; return; }
    if [ "$1" -gt 1000 ]; then printf '%s' $(($1 / 1000))
    elif [ "$1" -gt 0 ]; then printf '%s' "$1"
    else printf '%s' -1; fi
}
T_CPU=-1; T_GPU=-1; T_MAX=-1
read_temps() { # isi T_CPU (tertinggi di zona cpu/soc), T_GPU, T_MAX (semua zona)
    T_CPU=-1; T_GPU=-1; T_MAX=-1; _first=-1
    set +f
    for _z in "$SYS"/class/thermal/thermal_zone*; do
        [ -f "$_z/temp" ] || continue
        _ty=$(rd "$_z/type"); _t=$(norm_temp "$(rd "$_z/temp")")
        [ "$_t" -gt 0 ] || continue
        [ "$_first" = -1 ] && _first=$_t
        [ "$_t" -gt "$T_MAX" ] && T_MAX=$_t
        case "$_ty" in
            *gpu*|*GPU*) [ "$_t" -gt "$T_GPU" ] && T_GPU=$_t ;;
            *cpu*|*CPU*|*soc*|*tsens*|*mtktscpu*|*big*|*little*|*core*) [ "$_t" -gt "$T_CPU" ] && T_CPU=$_t ;;
        esac
    done
    set -f
    [ "$T_CPU" = -1 ] && T_CPU=$_first
}

# ---------- modul lain yang ikut mengatur performa ----------
CONF_NAMES=""; CONF_DONE=0
scan_conflicts() { # CONF_NAMES = satu nama per baris
    [ "$CONF_DONE" = 1 ] && return 0
    CONF_DONE=1; CONF_NAMES=""
    set +f
    for _m in "$MODS"/*; do
        [ -d "$_m" ] || continue
        _id=${_m##*/}
        [ "$_id" = hsin ] && continue
        [ -e "$_m/disable" ] && continue
        [ -e "$_m/remove" ] && continue
        _nm=""
        if [ -r "$_m/module.prop" ]; then
            while IFS='=' read -r _k _v; do
                [ "$_k" = name ] && _nm=$_v
            done < "$_m/module.prop"
        fi
        _low=$(printf '%s %s' "$_id" "$_nm" | tr 'A-Z' 'a-z')
        case "$_low" in
            *alpha*|*uperf*|*fas-rs*|*fasrs*|*fas_rs*|*scene*|*lktweak*|*perf*|*tweak*|*governor*)
                [ -n "$_nm" ] || _nm=$_id
                CONF_NAMES="$CONF_NAMES$(safe "$_nm")
" ;;
        esac
    done
    set -f
}
conf_phrase() { # "A atau B"
    scan_conflicts
    _cp=""
    while IFS= read -r _n; do
        [ -n "$_n" ] || continue
        if [ -z "$_cp" ]; then _cp=$_n; else _cp="$_cp atau $_n"; fi
    done <<EOT
$CONF_NAMES
EOT
    printf '%s' "$_cp"
}
node_mounted() { # 0 bila node ditimpa bind-mount (biasanya oleh modul lain)
    [ -r "$PROC/mounts" ] || return 1
    while read -r _a _b _rest; do
        [ "$_b" = "$1" ] && return 0
    done < "$PROC/mounts"
    return 1
}
reject_msg() { # alasan penolakan, untuk node $1
    if node_mounted "$1"; then printf '%s' "node ditimpa mount modul lain"; return; fi
    _ph=$(conf_phrase)
    if [ -n "$_ph" ]; then printf 'ditolak: kemungkinan dipegang modul lain %s' "$_ph"; else printf '%s' "ditolak kernel"; fi
}

# ---------- daftar knob ----------
# Baris: cat|key|label|type|kind|node|opts|unit
freqs_of() {
    _fo=$(rd "$1/scaling_available_frequencies")
    if [ -z "$_fo" ] && [ -r "$1/stats/time_in_state" ]; then
        _fo=""
        while read -r _f _t; do _fo="$_fo $_f"; done < "$1/stats/time_in_state"
    fi
    [ -n "$_fo" ] || _fo="$(rd "$1/cpuinfo_min_freq") $(rd "$1/cpuinfo_max_freq")"
    sorted_nums "$_fo"
}
defs_cpu() {
    _n=0
    for _p in "$SYS"/devices/system/cpu/cpufreq/policy[0-9]*; do
        [ -d "$_p" ] || continue
        _id=${_p##*policy}
        _n=$((_n + 1))
        _g=$(rd "$_p/scaling_available_governors")
        [ -n "$_g" ] && [ -f "$_p/scaling_governor" ] && \
            printf 'cpu|cpu.p%s.governor|Governor policy%s|choice|gen|%s|%s|\n' "$_id" "$_id" "$_p/scaling_governor" "$(safe "$_g")"
        _f=$(freqs_of "$_p")
        if [ -f "$_p/scaling_max_freq" ] && [ -n "$_f" ]; then
            printf 'cpu|cpu.p%s.max_freq|Maks frekuensi policy%s|choice|gen|%s|%s|khz\n' "$_id" "$_id" "$_p/scaling_max_freq" "$_f"
            printf 'cpu|cpu.p%s.min_freq|Min frekuensi policy%s|choice|gen|%s|%s|khz\n' "$_id" "$_id" "$_p/scaling_min_freq" "$_f"
        fi
    done
    [ "$_n" -gt 0 ] || printf 'cpu|cpu.none|CPU|locked|gen||Tidak ada cpufreq policy|\n'
}
defs_gpu() {
    _i=0; _seen=" "
    for _d in "$SYS"/class/devfreq/*gpu* "$SYS"/class/devfreq/*mali* "$SYS"/class/kgsl/kgsl-3d0/devfreq; do
        [ -f "$_d/governor" ] || continue
        case "$_seen" in *" $_d "*) continue ;; esac
        _seen="$_seen$_d "
        _nm=${_d%/devfreq}; _nm=${_nm##*/}
        _g=$(rd "$_d/available_governors")
        [ -n "$_g" ] && printf 'gpu|gpu.%s.governor|Governor GPU (%s)|choice|gen|%s|%s|\n' "$_i" "$(safe "$_nm")" "$_d/governor" "$(safe "$_g")"
        _f=$(sorted_nums "$(rd "$_d/available_frequencies")")
        if [ -n "$_f" ] && [ -f "$_d/max_freq" ]; then
            printf 'gpu|gpu.%s.max_freq|Maks frekuensi GPU (%s)|choice|gen|%s|%s|hz\n' "$_i" "$(safe "$_nm")" "$_d/max_freq" "$_f"
            [ -f "$_d/min_freq" ] && printf 'gpu|gpu.%s.min_freq|Min frekuensi GPU (%s)|choice|gen|%s|%s|hz\n' "$_i" "$(safe "$_nm")" "$_d/min_freq" "$_f"
        fi
        _i=$((_i + 1))
    done
    [ "$_i" -gt 0 ] || printf 'gpu|gpu.none|GPU|locked|gen||GPU tidak terdeteksi|\n'
}
defs_mem() {
    _v="$PROC/sys/vm"
    if [ -f "$_v/swappiness" ]; then
        _c=$(rd "$_v/swappiness"); _m=100; isint "$_c" && [ "$_c" -gt 100 ] && _m=200
        printf 'mem|vm.swappiness|Swappiness|range|gen|%s|0 %s 1|\n' "$_v/swappiness" "$_m"
    fi
    [ -f "$_v/vfs_cache_pressure" ] && printf 'mem|vm.vfs_cache_pressure|VFS cache pressure|range|gen|%s|10 400 10|\n' "$_v/vfs_cache_pressure"
    [ -f "$_v/dirty_ratio" ] && printf 'mem|vm.dirty_ratio|Dirty ratio|range|gen|%s|1 90 1|\n' "$_v/dirty_ratio"
    [ -f "$_v/dirty_background_ratio" ] && printf 'mem|vm.dirty_background_ratio|Dirty background ratio|range|gen|%s|1 90 1|\n' "$_v/dirty_background_ratio"
    [ -f "$_v/page-cluster" ] && printf 'mem|vm.page_cluster|Page cluster|choice|gen|%s|0 1 2 3 4|\n' "$_v/page-cluster"
    printf 'mem|mem.zram|ZRAM algoritma|locked|gen||Belum didukung|\n'
}
io_dev() {
    set +f
    for _b in "$SYS"/block/sd[a-z] "$SYS"/block/mmcblk[0-9] "$SYS"/block/nvme[0-9]n[0-9]; do
        [ -f "$_b/queue/scheduler" ] && { printf '%s' "$_b"; return 0; }
    done
    return 1
}
defs_io() {
    _b=$(io_dev) || return 0
    _nm=${_b##*/}
    _s=$(rd "$_b/queue/scheduler"); _s=$(printf '%s' "$_s" | tr -d '[]')
    [ -n "$_s" ] && printf 'io|io.scheduler|Scheduler %s|choice|sched|%s|%s|\n' "$_nm" "$_b/queue/scheduler" "$(safe "$_s")"
    [ -f "$_b/queue/read_ahead_kb" ] && printf 'io|io.read_ahead|Read ahead %s|range|gen|%s|0 4096 64|\n' "$_nm" "$_b/queue/read_ahead_kb"
}
defs_net() {
    _n="$PROC/sys/net/ipv4"
    _a=$(rd "$_n/tcp_available_congestion_control")
    [ -n "$_a" ] && [ -f "$_n/tcp_congestion_control" ] && printf 'net|net.tcp_cc|TCP congestion|choice|gen|%s|%s|\n' "$_n/tcp_congestion_control" "$(safe "$_a")"
    [ -f "$_n/tcp_fastopen" ] && printf 'net|net.tcp_fastopen|TCP fast open|choice|gen|%s|0 1 2 3|\n' "$_n/tcp_fastopen"
}
defs_display() {
    command -v getprop >/dev/null 2>&1 || return 0
    printf 'display|display.renderer|Renderer HWUI (berlaku di app yang baru dibuka)|choice|prop|debug.hwui.renderer|skiavk skiagl system|\n'
}
defs_all() { set +f; defs_cpu; defs_gpu; defs_mem; defs_io; defs_net; defs_display; }

cur_of() { # kind node
    case "$1" in
        sched)
            _x=$(rd "$2")
            case "$_x" in *\[*\]*) _x=${_x#*\[}; _x=${_x%%\]*} ;; esac
            printf '%s' "$_x" ;;
        prop)
            _x=$(gp "$2"); [ -n "$_x" ] || _x="system"
            printf '%s' "$_x" ;;
        *) rd "$2" ;;
    esac
}

DEFS=""
load_defs() { [ -n "$DEFS" ] || DEFS=$(defs_all); }
find_def() {
    load_defs
    D_KEY=""
    _fd_old=$IFS
    IFS='
'
    for _line in $DEFS; do
        case "$_line" in
            *"|$1|"*)
                IFS=$_fd_old
                IFS='|' read -r D_CAT D_KEY D_LABEL D_TYPE D_KIND D_NODE D_OPTS D_UNIT <<EOT
$_line
EOT
                IFS=$_fd_old
                [ "$D_KEY" = "$1" ] && return 0
                IFS='
' ;;
        esac
    done
    IFS=$_fd_old
    return 1
}
in_list() { case " $2 " in *" $1 "*) return 0 ;; esac; return 1; }

# ---------- validasi + tulis satu knob ----------
R_MSG=""
check_knob() { # key value -> isi D_*, R_MSG; 0 bila valid
    R_MSG=""
    case "$2" in ''|*[!A-Za-z0-9_.:+-]*) R_MSG="nilai tidak valid"; return 1 ;; esac
    find_def "$1" || { R_MSG="knob tidak dikenal"; return 1; }
    case "$D_TYPE" in
        locked) R_MSG="tidak didukung"; return 1 ;;
        choice) in_list "$2" "$D_OPTS" || { R_MSG="nilai di luar pilihan"; return 1; } ;;
        range)
            isint "$2" || { R_MSG="harus angka"; return 1; }
            set -- $D_OPTS "$2"
            { [ "$4" -ge "$1" ] && [ "$4" -le "$2" ]; } || { R_MSG="di luar rentang $1-$2"; return 1; } ;;
    esac
    return 0
}
write_knob() { # key value -> 0 bila terverifikasi
    _wk_v=$2
    check_knob "$1" "$2" || return 1
    case "$D_KIND" in
        prop)
            if [ "$_wk_v" = "system" ]; then sp "$D_NODE" ""; else sp "$D_NODE" "$_wk_v"; fi ;;
        *)
            canw "$D_NODE" || { R_MSG="node read-only"; return 1; }
            wr "$D_NODE" "$_wk_v" || { R_MSG=$(reject_msg "$D_NODE"); return 1; } ;;
    esac
    _got=$(cur_of "$D_KIND" "$D_NODE")
    if [ "$_got" != "$_wk_v" ]; then
        R_MSG="nilai kembali ke $(safe "$_got") karena ada yang menahan"
        _ph=$(conf_phrase); [ -n "$_ph" ] && R_MSG="$R_MSG kemungkinan $_ph"
        return 1
    fi
    return 0
}

snapshot_baseline() {
    load_defs
    : > "$BASE.tmp"
    _old=$IFS
    IFS='
'
    for _line in $DEFS; do
        IFS=$_old
        IFS='|' read -r _c _k _lb _ty _kd _nd _op _un <<EOT
$_line
EOT
        [ "$_ty" = "locked" ] && continue
        _v=$(cur_of "$_kd" "$_nd")
        [ -n "$_v" ] && printf '%s=%s\n' "$_k" "$_v" >> "$BASE.tmp"
    done
    IFS=$_old
    mv "$BASE.tmp" "$BASE"
}

# Tulis banyak "key=value" dengan dua putaran (urutan min/max freq tidak peduli).
# Hasil: RES_JSON, RES_OK, RES_FAIL. $1 = persist (1/0).
batch_write() {
    _persist=$1; shift
    RES_JSON=""; RES_OK=0; RES_FAIL=0
    _pending=""; _out=""
    for _a in "$@"; do
        _k=${_a%%=*}; _v=${_a#*=}
        if write_knob "$_k" "$_v"; then
            _out="$_out{\"key\":\"$(safe "$_k")\",\"ok\":1,\"value\":\"$(safe "$_v")\",\"msg\":\"\"},"
            RES_OK=$((RES_OK + 1))
            [ "$_persist" = 1 ] && persist_knob "$_k" "$_v"
            log INFO apply "$_k = $_v"
        else
            _pending="$_pending $_a"
        fi
    done
    for _a in $_pending; do
        _k=${_a%%=*}; _v=${_a#*=}
        if write_knob "$_k" "$_v"; then
            _out="$_out{\"key\":\"$(safe "$_k")\",\"ok\":1,\"value\":\"$(safe "$_v")\",\"msg\":\"\"},"
            RES_OK=$((RES_OK + 1))
            [ "$_persist" = 1 ] && persist_knob "$_k" "$_v"
            log INFO apply "$_k = $_v (putaran 2)"
        else
            _out="$_out{\"key\":\"$(safe "$_k")\",\"ok\":0,\"value\":\"$(safe "$_v")\",\"msg\":\"$(safe "$R_MSG")\"},"
            RES_FAIL=$((RES_FAIL + 1))
            log WARN apply "$_k = $_v gagal: $R_MSG"
        fi
    done
    RES_JSON=${_out%,}
}
persist_knob() {
    _b=$(kv_get "$BASE" "$1")
    if [ -n "$_b" ] && [ "$_b" = "$2" ]; then kv_del "$OVR" "$1"; else kv_set "$OVR" "$1" "$2"; fi
}
file_pairs() { # file -> " k=v k=v"
    _fp=""
    [ -f "$1" ] || { printf ''; return 0; }
    while IFS='=' read -r _k _v; do
        [ -n "$_k" ] && [ -n "$_v" ] && _fp="$_fp $_k=$_v"
    done < "$1"
    printf '%s' "$_fp"
}
apply_overrides() {
    [ -s "$OVR" ] || { RES_JSON=""; RES_OK=0; RES_FAIL=0; log INFO apply "tidak ada override tersimpan"; return 0; }
    _list=$(file_pairs "$OVR")
    # shellcheck disable=SC2086
    batch_write 0 $_list
    log INFO apply "override diterapkan: ok=$RES_OK gagal=$RES_FAIL"
}
revert_runtime() { # tulis baseline TANPA menghapus override tersimpan (dipakai pengaman panas)
    [ -s "$BASE" ] || { RES_JSON=""; RES_OK=0; RES_FAIL=0; return 1; }
    _list=$(file_pairs "$BASE")
    # shellcheck disable=SC2086
    batch_write 0 $_list
    return 0
}
restore_baseline() {
    revert_runtime || return 1
    : > "$OVR"
    log INFO apply "pulihkan bawaan: ok=$RES_OK gagal=$RES_FAIL"
    return 0
}

# ---------- profil per game ----------
valid_pkg() {
    case "$1" in ''|*[!A-Za-z0-9_.]*|.*|*.) return 1 ;; esac
    case "$1" in *.*) return 0 ;; esac
    return 1
}
global_value() { # nilai Global untuk key: override tersimpan, kalau tidak ada baseline
    _g=$(kv_get "$OVR" "$1") || _g=$(kv_get "$BASE" "$1") || _g=""
    printf '%s' "$_g"
}
game_apply() {
    _list=$(file_pairs "$GAMEDIR/$1.env")
    [ -n "$_list" ] || return 0
    # shellcheck disable=SC2086
    batch_write 0 $_list
    log INFO game "$1 dibuka: ok=$RES_OK gagal=$RES_FAIL"
}
game_restore() {
    _list=""
    if [ -f "$GAMEDIR/$1.env" ]; then
        while IFS='=' read -r _k _v; do
            [ -n "$_k" ] || continue
            _gv=$(global_value "$_k")
            [ -n "$_gv" ] && _list="$_list $_k=$_gv"
        done < "$GAMEDIR/$1.env"
    fi
    if [ -n "$_list" ]; then
        # shellcheck disable=SC2086
        batch_write 0 $_list
    fi
    log INFO game "$1 ditutup: kembali ke Global ok=${RES_OK:-0} gagal=${RES_FAIL:-0}"
}
FG_SIG=""; FG_PKG=""
fg_game() { # isi FG_PKG (paket game di depan, atau kosong); return 1 bila deteksi tidak tersedia
    _f="$CPUSET/top-app/cgroup.procs"
    [ -r "$_f" ] || _f="$CPUSET/top-app/tasks"
    [ -r "$_f" ] || { FG_PKG=""; return 1; }
    _sig=""
    while read -r _p; do _sig="$_sig $_p"; done < "$_f"
    [ "$_sig" = "$FG_SIG" ] && return 0
    FG_SIG=$_sig; FG_PKG=""
    for _p in $_sig; do
        [ -r "$PROC/$_p/cmdline" ] || continue
        _c=$(tr '\000' ' ' < "$PROC/$_p/cmdline")
        set -- $_c
        _n=${1%%:*}
        if [ -n "$_n" ] && [ -f "$GAMEDIR/$_n.env" ]; then FG_PKG=$_n; break; fi
    done
    return 0
}
thermal_trip() { # $1 = suhu, $2 = batas
    revert_runtime
    : > "$TRIPF"
    rm -f "$ACTF"
    log WARN thermal "suhu CPU $1 C melewati batas $2 C: setelan dikembalikan ke bawaan sementara"
}
