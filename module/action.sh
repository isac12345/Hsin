#!/system/bin/sh
# HSIN v5 action API. Dipanggil app: su -c "sh /data/adb/modules/hsin/action.sh <perintah> [arg]"
# Hampir semua perintah mencetak SATU baris JSON. Lihat docs/CONTRACT.md.
MODDIR="${HSIN_MODULE_PATH:-${0%/*}}"
. "$MODDIR/core/lib.sh" || { echo '{"error":"lib.sh tidak bisa dimuat"}'; exit 2; }

cmd="${1:-ping}"
[ $# -gt 0 ] && shift

jstr() { printf '%s' "$1" | tr -cd 'A-Za-z0-9_.:+ -'; }
num() { if isint "$1"; then printf '%s' "$1"; else printf '0'; fi; }

cmd_device() {
    _model=$(jstr "$(gp ro.product.model)"); _brand=$(jstr "$(gp ro.product.brand)")
    _soc=$(gp ro.soc.model); [ -n "$_soc" ] || _soc=$(gp ro.board.platform); [ -n "$_soc" ] || _soc=$(gp ro.hardware)
    _soc=$(jstr "$_soc"); _kern=$(jstr "$(uname -r 2>/dev/null)"); _and=$(jstr "$(gp ro.build.version.release)")
    printf '{"v":5,"module":"%s","model":"%s","brand":"%s","soc":"%s","kernel":"%s","android":"%s"}\n' \
        "$HSIN_VER" "$_model" "$_brand" "$_soc" "$_kern" "$_and"
}

cmd_status() {
    set +f
    _pol=""; _sum=0; _cnt=0
    for _p in "$SYS"/devices/system/cpu/cpufreq/policy[0-9]*; do
        [ -d "$_p" ] || continue
        _id=${_p##*policy}
        _c=$(num "$(rd "$_p/scaling_cur_freq")"); _mn=$(num "$(rd "$_p/scaling_min_freq")")
        _mx=$(num "$(rd "$_p/scaling_max_freq")"); _hw=$(num "$(rd "$_p/cpuinfo_max_freq")")
        _g=$(jstr "$(rd "$_p/scaling_governor")")
        [ "$_hw" = 0 ] && _hw=$_mx
        _pol="$_pol{\"id\":$(num "$_id"),\"cur\":$_c,\"min\":$_mn,\"max\":$_mx,\"hw\":$_hw,\"gov\":\"$_g\"},"
        [ "$_c" -gt 0 ] && { _sum=$((_sum + _c)); _cnt=$((_cnt + 1)); }
    done
    _cpu=0; [ "$_cnt" -gt 0 ] && _cpu=$((_sum / _cnt))
    _cores=0
    for _c in "$SYS"/devices/system/cpu/cpu[0-9]*; do [ -d "$_c" ] && _cores=$((_cores + 1)); done
    _gpu=0; _gmax=0; _ggov=""
    for _d in "$SYS"/class/devfreq/*gpu* "$SYS"/class/devfreq/*mali* "$SYS"/class/kgsl/kgsl-3d0/devfreq; do
        [ -f "$_d/cur_freq" ] || continue
        _gpu=$(num "$(rd "$_d/cur_freq")"); _gmax=$(num "$(rd "$_d/max_freq")")
        _ggov=$(jstr "$(rd "$_d/governor")")
        break
    done
    set -f
    read_temps
    _bp=-1; _bt=-1; _chg=0
    _b=$(rd "$SYS/class/power_supply/battery/capacity"); isint "$_b" && _bp=$_b
    _b=$(rd "$SYS/class/power_supply/battery/temp"); isint "$_b" && _bt=$((_b / 10))
    case "$(rd "$SYS/class/power_supply/battery/status")" in Charging|Full) _chg=1 ;; esac
    _mt=0; _ma=0; _st=0; _sf=0
    if [ -r "$PROC/meminfo" ]; then
        while read -r _k _v _u; do
            case "$_k" in MemTotal:) _mt=$_v ;; MemAvailable:) _ma=$_v ;; SwapTotal:) _st=$_v ;; SwapFree:) _sf=$_v ;; esac
        done < "$PROC/meminfo"
    fi
    _ld=0
    if [ -r "$PROC/loadavg" ]; then
        read -r _l _rest < "$PROC/loadavg"
        _i=${_l%%.*}; _fr=${_l#*.}; _fr=${_fr%"${_fr#??}"}
        isint "$_i" && isint "$_fr" && _ld=$((_i * 100 + _fr))
    fi
    _ct=0; _ci=0
    if [ -r "$PROC/stat" ]; then
        read -r _n _u _ni _s _id2 _w _q _sq _stl _rest < "$PROC/stat"
        _u=$(num "$_u"); _ni=$(num "$_ni"); _s=$(num "$_s"); _id2=$(num "$_id2"); _w=$(num "$_w")
        _q=$(num "$_q"); _sq=$(num "$_sq"); _stl=$(num "$_stl")
        _ct=$((_u + _ni + _s + _id2 + _w + _q + _sq + _stl)); _ci=$((_id2 + _w))
    fi
    _safe=0; [ -f "$SAFEF" ] && _safe=1
    _trip=0; [ -f "$TRIPF" ] && _trip=1
    _gm=$(cfg_get game_mode 0); _ga=$(jstr "$(rd "$ACTF")")
    _oc=0
    if [ -f "$OVR" ]; then while IFS= read -r _x; do [ -n "$_x" ] && _oc=$((_oc + 1)); done < "$OVR"; fi
    printf '{"cpu_khz":%s,"cores":%s,"policies":[%s],"gpu_hz":%s,"gpu_max_hz":%s,"gpu_gov":"%s",' \
        "$_cpu" "$_cores" "${_pol%,}" "$_gpu" "$_gmax" "$_ggov"
    printf '"cpu_temp":%s,"gpu_temp":%s,"temp_max":%s,"bat_pct":%s,"bat_temp":%s,"bat_charging":%s,' \
        "$T_CPU" "$T_GPU" "$T_MAX" "$_bp" "$_bt" "$_chg"
    printf '"ram_total_kb":%s,"ram_used_kb":%s,"swap_total_kb":%s,"swap_used_kb":%s,"load_x100":%s,"cpu_total":%s,"cpu_idle":%s,' \
        "$_mt" "$((_mt - _ma))" "$_st" "$((_st - _sf))" "$_ld" "$_ct" "$_ci"
    printf '"safe_mode":%s,"thermal_trip":%s,"game_mode":%s,"game_active":"%s","overrides":%s}\n' \
        "$_safe" "$_trip" "$_gm" "$_ga" "$_oc"
}

cmd_knobs() {
    [ -s "$BASE" ] || snapshot_baseline
    load_defs
    _cats=""
    for _c in cpu:CPU gpu:GPU mem:Memori io:I/O net:Jaringan display:Layar; do
        _id=${_c%%:*}; _title=${_c#*:}; _items=""
        _old=$IFS
        IFS='
'
        for _line in $DEFS; do
            IFS=$_old
            IFS='|' read -r D_CAT D_KEY D_LABEL D_TYPE D_KIND D_NODE D_OPTS D_UNIT <<EOT
$_line
EOT
            [ "$D_CAT" = "$_id" ] || continue
            _lb=$(jstr "$D_LABEL")
            case "$D_TYPE" in
                locked)
                    _items="$_items{\"key\":\"$D_KEY\",\"label\":\"$_lb\",\"type\":\"locked\",\"reason\":\"$(jstr "$D_OPTS")\"}," ;;
                *)
                    _cur=$(cur_of "$D_KIND" "$D_NODE"); _def=$(kv_get "$BASE" "$D_KEY"); [ -n "$_def" ] || _def=$_cur
                    if [ "$D_TYPE" = "choice" ]; then
                        _arr=""; for _w in $D_OPTS; do _arr="$_arr\"$_w\","; done
                        _extra="\"options\":[${_arr%,}]"
                    else
                        set -- $D_OPTS
                        _extra="\"min\":$1,\"max\":$2,\"step\":$3"
                    fi
                    _items="$_items{\"key\":\"$D_KEY\",\"label\":\"$_lb\",\"type\":\"$D_TYPE\",\"unit\":\"$D_UNIT\",$_extra,\"cur\":\"$(jstr "$_cur")\",\"def\":\"$(jstr "$_def")\"}," ;;
            esac
        done
        IFS=$_old
        [ -n "$_items" ] && _cats="$_cats{\"id\":\"$_id\",\"title\":\"$_title\",\"knobs\":[${_items%,}]},"
    done
    printf '{"v":5,"categories":[%s]}\n' "${_cats%,}"
}

cmd_conflicts() {
    scan_conflicts
    _l=""
    while IFS= read -r _n; do
        [ -n "$_n" ] && _l="$_l\"$_n\","
    done <<EOT
$CONF_NAMES
EOT
    printf '{"list":[%s]}\n' "${_l%,}"
}

cmd_thermal_get() {
    _t=0; [ -f "$TRIPF" ] && _t=1
    printf '{"on":%s,"limit":%s,"trip":%s}\n' "$(cfg_get thermal 1)" "$(cfg_get thermal_limit 90)" "$_t"
}
cmd_thermal_set() { # on(0/1) limit
    _on=$1; _lim=$2
    case "$_on" in 0|1) ;; *) echo '{"ok":0,"error":"nilai on harus 0 atau 1"}'; return 1 ;; esac
    if ! isint "$_lim" || [ "$_lim" -lt 60 ] || [ "$_lim" -gt 110 ]; then
        echo '{"ok":0,"error":"batas suhu harus 60 sampai 110"}'; return 1
    fi
    cfg_set thermal "$_on"; cfg_set thermal_limit "$_lim"
    log INFO thermal "pengaman panas on=$_on batas=$_lim"
    echo '{"ok":1}'
}
cmd_thermal_ack() {
    rm -f "$TRIPF"
    log INFO thermal "dikonfirmasi user: setelan diterapkan lagi"
    apply_overrides
    printf '{"ok":%s,"fail":%s,"results":[%s]}\n' "${RES_OK:-0}" "${RES_FAIL:-0}" "$RES_JSON"
}

cmd_game_list() {
    set +f
    _g=""
    for _f in "$GAMEDIR"/*.env; do
        [ -f "$_f" ] || continue
        _pk=${_f##*/}; _pk=${_pk%.env}
        _n=0
        while IFS= read -r _x; do [ -n "$_x" ] && _n=$((_n + 1)); done < "$_f"
        _g="$_g{\"pkg\":\"$(jstr "$_pk")\",\"n\":$_n},"
    done
    set -f
    printf '{"mode":%s,"active":"%s","games":[%s]}\n' "$(cfg_get game_mode 0)" "$(jstr "$(rd "$ACTF")")" "${_g%,}"
}
cmd_game_set() { # pkg [k=v ...]
    _pk=$1; shift
    valid_pkg "$_pk" || { echo '{"ok":0,"fail":0,"error":"nama paket tidak valid","results":[]}'; return 1; }
    _ok=0; _fail=0; _out=""; _new=""
    for _a in "$@"; do
        _k=${_a%%=*}; _v=${_a#*=}
        if check_knob "$_k" "$_v"; then
            _new="$_new$_k=$_v
"
            _ok=$((_ok + 1))
            _out="$_out{\"key\":\"$(jstr "$_k")\",\"ok\":1,\"value\":\"$(jstr "$_v")\",\"msg\":\"\"},"
        else
            _fail=$((_fail + 1))
            _out="$_out{\"key\":\"$(jstr "$_k")\",\"ok\":0,\"value\":\"$(jstr "$_v")\",\"msg\":\"$(jstr "$R_MSG")\"},"
        fi
    done
    _active=0; [ "$(rd "$ACTF")" = "$_pk" ] && _active=1
    [ "$_active" = 1 ] && game_restore "$_pk"
    printf '%s' "$_new" > "$GAMEDIR/$_pk.env.tmp" && mv "$GAMEDIR/$_pk.env.tmp" "$GAMEDIR/$_pk.env"
    [ "$_active" = 1 ] && game_apply "$_pk"
    log INFO game "profil $_pk disimpan: $_ok knob"
    printf '{"ok":%s,"fail":%s,"results":[%s]}\n' "$_ok" "$_fail" "${_out%,}"
}
cmd_game_del() {
    _pk=$1
    valid_pkg "$_pk" || { echo '{"ok":0}'; return 1; }
    if [ "$(rd "$ACTF")" = "$_pk" ]; then game_restore "$_pk"; rm -f "$ACTF"; fi
    rm -f "$GAMEDIR/$_pk.env"
    log INFO game "profil $_pk dihapus"
    echo '{"ok":1}'
}
cmd_game_mode() {
    case "$1" in 0|1) ;; *) echo '{"ok":0}'; return 1 ;; esac
    cfg_set game_mode "$1"
    if [ "$1" = 0 ] && [ -f "$ACTF" ]; then game_restore "$(rd "$ACTF")"; rm -f "$ACTF"; fi
    log INFO game "mode per game = $1"
    echo '{"ok":1}'
}
cmd_detect() {
    if fg_game; then echo '{"ok":1,"src":"cpuset"}'; else echo '{"ok":0,"src":"none"}'; fi
}

# ---------- mode: Hemat / Bawaan / Seimbang / Boost ----------
cmd_mode() { # nama
    case "$1" in hemat|bawaan|seimbang|boost) ;; *) echo '{"ok":0,"error":"mode tidak dikenal"}'; return 1 ;; esac
    [ -s "$BASE" ] || snapshot_baseline
    restore_baseline >/dev/null 2>&1
    RES_OK=0; RES_FAIL=0; RES_JSON=""
    if [ "$1" != bawaan ]; then
        _a=$(mode_args "$1")
        # shellcheck disable=SC2086
        [ -n "$_a" ] && batch_write 1 $_a
    fi
    # Boost: pengaman panas dinaikkan ke 100 C supaya performa tidak dibatasi; mode lain mengembalikan batas user
    if [ "$1" = boost ]; then
        [ -n "$(cfg_get thermal_prev '')" ] || cfg_set thermal_prev "$(cfg_get thermal_limit 90)"
        cfg_set thermal_limit 100
    elif [ -n "$(cfg_get thermal_prev '')" ]; then
        cfg_set thermal_limit "$(cfg_get thermal_prev 90)"; kv_del "$CFG" thermal_prev
    fi
    cfg_set mode "$1"
    log INFO apply "mode $1: ok=$RES_OK gagal=$RES_FAIL"
    printf '{"ok":%s,"fail":%s,"mode":"%s","results":[%s]}\n' "$RES_OK" "$RES_FAIL" "$1" "$RES_JSON"
}
cmd_mode_get() { printf '{"mode":"%s"}\n' "$(cfg_get mode bawaan)"; }

# Pengaturan per game: mode (hemat|bawaan|seimbang|boost|global) dan resolusi 50-100
cmd_game_cfg() { # pkg mode res
    _pk=$1; _md=$2; _rs=$3
    valid_pkg "$_pk" || { echo '{"ok":0,"error":"nama paket tidak valid"}'; return 1; }
    case "$_md" in hemat|bawaan|seimbang|boost|global) ;; *) echo '{"ok":0,"error":"mode tidak dikenal"}'; return 1 ;; esac
    if [ -n "$_rs" ]; then
        if ! isint "$_rs" || [ "$_rs" -lt 50 ] || [ "$_rs" -gt 100 ]; then echo '{"ok":0,"error":"resolusi 50 sampai 100"}'; return 1; fi
    fi
    _active=0; [ "$(rd "$ACTF")" = "$_pk" ] && _active=1
    [ "$_active" = 1 ] && game_restore "$_pk"
    if [ "$_md" = global ] || [ "$_md" = bawaan ]; then : > "$GAMEDIR/$_pk.env"
    else printf '%s\n' $(mode_args "$_md") > "$GAMEDIR/$_pk.env"; fi
    printf '%s\n' "$_md" > "$GAMEDIR/$_pk.mode"
    if [ -n "$_rs" ] && [ "$_rs" -lt 100 ]; then printf '%s\n' "$_rs" > "$GAMEDIR/$_pk.res"; else rm -f "$GAMEDIR/$_pk.res"; fi
    [ "$_active" = 1 ] && game_apply "$_pk"
    log INFO game "cfg $_pk mode=$_md res=${_rs:-100}"
    echo '{"ok":1}'
}
cmd_game_get() { # pkg
    _pk=$1
    valid_pkg "$_pk" || { echo '{"ok":0}'; return 1; }
    _md=$(rd "$GAMEDIR/$_pk.mode"); [ -n "$_md" ] || _md=global
    _rs=$(rd "$GAMEDIR/$_pk.res"); [ -n "$_rs" ] || _rs=100
    _in=0; [ -f "$GAMEDIR/$_pk.env" ] && _in=1
    printf '{"ok":1,"pkg":"%s","mode":"%s","res":%s,"listed":%s}\n' "$_pk" "$(jstr "$_md")" "$(num "$_rs")" "$_in"
}

# MULAI GAME: terapkan pengaturan game (mode, resolusi, jangan ganggu), lalu buka game
cmd_launch() { # pkg
    _pk=$1
    valid_pkg "$_pk" || { echo '{"ok":0,"error":"nama paket tidak valid"}'; return 1; }
    if [ -n "$(pidof "$_pk" 2>/dev/null)" ]; then echo '{"ok":0,"error":"game sedang jalan, tutup dulu lalu mulai lagi dari HSIN"}'; return 1; fi
    if [ ! -f "$GAMEDIR/$_pk.env" ]; then : > "$GAMEDIR/$_pk.env"; fi
    cfg_set game_mode 1
    game_apply "$_pk"
    printf '%s\n' "$_pk" > "$ACTF"
    # Jangan pakai resolve-activity: game dengan banyak pintu (Roblox) mengembalikan chooser sistem
    monkey -p "$_pk" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
    log INFO game "$_pk dibuka dari HSIN"
    echo '{"ok":1}'
}

cmd_dnd_cfg() { # 0|1 : Jangan ganggu otomatis saat game
    case "$1" in 0|1) ;; *) echo '{"ok":0}'; return 1 ;; esac
    cfg_set dnd_game "$1"
    echo '{"ok":1}'
}
cmd_dnd_now() { # 0|1
    case "$1" in 0|1) ;; *) echo '{"ok":0}'; return 1 ;; esac
    dnd_set "$1" && echo '{"ok":1}' || echo '{"ok":0,"error":"perintah DND tidak tersedia"}'
}

cmd_ram_clean() {
    command -v pm >/dev/null 2>&1 || { echo '{"ok":0,"error":"pm tidak tersedia"}'; return 1; }
    _a=$(num "$(meminfo_avail)")
    _ime=$(settings get secure default_input_method 2>/dev/null); _ime=${_ime%%/*}
    _home=$(pm resolve-activity --brief -a android.intent.action.MAIN -c android.intent.category.HOME 2>/dev/null | tail -n 1); _home=${_home%%/*}
    _act=$(rd "$ACTF")
    _n=0
    for _l in $(pm list packages -3 2>/dev/null); do
        _p=${_l#package:}
        case "$_p" in
            ''|com.hsin|"$_ime"|"$_home"|"$_act"|com.termux*|com.topjohnwu.magisk|me.weishu.kernelsu|me.bmax.apatch|com.android.*|com.google.android.inputmethod*) continue ;;
        esac
        am kill "$_p" >/dev/null 2>&1; _n=$((_n + 1))
    done
    sleep 1
    _b=$(num "$(meminfo_avail)")
    _f=$((_b - _a)); [ "$_f" -lt 0 ] && _f=0
    log INFO apply "bersihkan RAM: $_n app, bebas ${_f}KB"
    printf '{"ok":1,"apps":%s,"freed_kb":%s}\n' "$_n" "$_f"
}
meminfo_avail() {
    while read -r _k _v _u; do [ "$_k" = "MemAvailable:" ] && { printf '%s' "$_v"; return 0; }; done < "$PROC/meminfo"
    printf '0'
}

case "$cmd" in
    ping) echo "pong $HSIN_VER" ;;
    device) cmd_device ;;
    status) cmd_status ;;
    knobs) cmd_knobs ;;
    conflicts) cmd_conflicts ;;
    set-many)
        if [ $# -eq 0 ]; then printf '{"ok":0,"fail":0,"error":"tidak ada knob","results":[]}\n'; exit 1; fi
        batch_write 1 "$@"
        printf '{"ok":%s,"fail":%s,"results":[%s]}\n' "$RES_OK" "$RES_FAIL" "$RES_JSON"
        [ "$RES_FAIL" -eq 0 ] ;;
    apply)
        apply_overrides
        printf '{"ok":%s,"fail":%s,"results":[%s]}\n' "${RES_OK:-0}" "${RES_FAIL:-0}" "$RES_JSON" ;;
    restore)
        if restore_baseline; then
            printf '{"ok":%s,"fail":%s,"results":[%s]}\n' "$RES_OK" "$RES_FAIL" "$RES_JSON"
        else
            printf '{"ok":0,"fail":0,"error":"baseline belum ada, reboot dulu","results":[]}\n'
        fi ;;
    snapshot) snapshot_baseline; echo '{"ok":1}' ;;
    guard-reset)
        rm -f "$SAFEF"; echo 0 > "$CNTF"; log INFO boot "mode aman dimatikan oleh user"
        echo '{"ok":1}' ;;
    thermal-get) cmd_thermal_get ;;
    thermal-set) cmd_thermal_set "$1" "$2" ;;
    thermal-ack) cmd_thermal_ack ;;
    game-list) cmd_game_list ;;
    game-set) cmd_game_set "$@" ;;
    game-del) cmd_game_del "$1" ;;
    game-mode) cmd_game_mode "$1" ;;
    detect) cmd_detect ;;
    mode) cmd_mode "$1" ;;
    mode-get) cmd_mode_get ;;
    game-cfg) cmd_game_cfg "$1" "$2" "$3" ;;
    game-get) cmd_game_get "$1" ;;
    launch) cmd_launch "$1" ;;
    dnd-cfg) cmd_dnd_cfg "$1" ;;
    dnd-now) cmd_dnd_now "$1" ;;
    ram-clean) cmd_ram_clean ;;
    logs)
        _w="${1:-apply}"; _n="${2:-60}"
        case "$_w" in boot|apply|game|thermal) ;; *) _w=apply ;; esac
        isint "$_n" || _n=60
        [ -f "$LOGD/$_w.log" ] && tail -n "$_n" "$LOGD/$_w.log" ;;
    *) echo '{"error":"perintah tidak dikenal"}'; exit 3 ;;
esac
