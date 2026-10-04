#!/system/bin/sh
# HSIN v5 action API. Dipanggil app lewat: su -c "sh /data/adb/modules/hsin/action.sh <cmd> [args]"
# Semua perintah mencetak SATU baris JSON (kecuali logs/ping). Lihat docs/CONTRACT.md.
MODDIR="${HSIN_MODULE_PATH:-${0%/*}}"
. "$MODDIR/core/lib.sh" || { echo '{"error":"lib.sh tidak bisa dimuat"}'; exit 2; }

cmd="${1:-ping}"
[ $# -gt 0 ] && shift

jstr() { printf '%s' "$1" | tr -cd 'A-Za-z0-9_.:+ -'; }

cmd_device() {
    _model=$(jstr "$(gp ro.product.model)"); _brand=$(jstr "$(gp ro.product.brand)")
    _soc=$(gp ro.soc.model); [ -n "$_soc" ] || _soc=$(gp ro.board.platform); [ -n "$_soc" ] || _soc=$(gp ro.hardware)
    _soc=$(jstr "$_soc"); _kern=$(jstr "$(uname -r 2>/dev/null)"); _and=$(jstr "$(gp ro.build.version.release)")
    _ram=0
    if [ -r "$PROC/meminfo" ]; then
        while read -r _k _v _u; do [ "$_k" = "MemTotal:" ] && { _ram=$_v; break; }; done < "$PROC/meminfo"
    fi
    printf '{"v":5,"module":"%s","model":"%s","brand":"%s","soc":"%s","kernel":"%s","android":"%s","ram_kb":%s}\n' \
        "$HSIN_VER" "$_model" "$_brand" "$_soc" "$_kern" "$_and" "${_ram:-0}"
}

norm_temp() { # nilai mentah -> derajat C bulat, atau -1
    isint "$1" || { printf '%s' -1; return; }
    if [ "$1" -gt 1000 ]; then printf '%s' $(($1 / 1000))
    elif [ "$1" -gt 0 ]; then printf '%s' "$1"
    else printf '%s' -1; fi
}

cmd_status() {
    set +f
    _sum=0; _cnt=0
    for _p in "$SYS"/devices/system/cpu/cpufreq/policy[0-9]*; do
        [ -d "$_p" ] || continue
        _f=$(rd "$_p/scaling_cur_freq")
        isint "$_f" && { _sum=$((_sum + _f)); _cnt=$((_cnt + 1)); }
    done
    _cpu=0; [ "$_cnt" -gt 0 ] && _cpu=$((_sum / _cnt))
    _gpu=0
    for _d in "$SYS"/class/devfreq/*gpu* "$SYS"/class/devfreq/*mali* "$SYS"/class/kgsl/kgsl-3d0/devfreq; do
        [ -f "$_d/cur_freq" ] || continue
        _g=$(rd "$_d/cur_freq"); isint "$_g" && { _gpu=$_g; break; }
    done
    _ct=-1; _gt=-1; _first=-1
    for _z in "$SYS"/class/thermal/thermal_zone*; do
        [ -f "$_z/temp" ] || continue
        _ty=$(rd "$_z/type"); _t=$(norm_temp "$(rd "$_z/temp")")
        [ "$_first" = -1 ] && _first=$_t
        case "$_ty" in
            *gpu*|*GPU*) [ "$_gt" = -1 ] && _gt=$_t ;;
            *cpu*|*CPU*|*soc*|*tsens*|*ap*|*big*|*little*|*mtktscpu*) [ "$_ct" = -1 ] && _ct=$_t ;;
        esac
    done
    [ "$_ct" = -1 ] && _ct=$_first
    set -f
    _bp=-1; _bt=-1
    _b=$(rd "$SYS/class/power_supply/battery/capacity"); isint "$_b" && _bp=$_b
    _b=$(rd "$SYS/class/power_supply/battery/temp"); isint "$_b" && _bt=$((_b / 10))
    _mt=0; _ma=0
    if [ -r "$PROC/meminfo" ]; then
        while read -r _k _v _u; do
            case "$_k" in MemTotal:) _mt=$_v ;; MemAvailable:) _ma=$_v; break ;; esac
        done < "$PROC/meminfo"
    fi
    _ld=0
    if [ -r "$PROC/loadavg" ]; then
        read -r _l _rest < "$PROC/loadavg"
        _i=${_l%%.*}; _fr=${_l#*.}; _fr=${_fr%"${_fr#??}"}
        isint "$_i" && isint "$_fr" && _ld=$((_i * 100 + _fr))
    fi
    _sf=0; [ -f "$SAFEF" ] && _sf=1
    _oc=0
    if [ -f "$OVR" ]; then while IFS= read -r _x; do [ -n "$_x" ] && _oc=$((_oc + 1)); done < "$OVR"; fi
    printf '{"cpu_khz":%s,"gpu_hz":%s,"cpu_temp":%s,"gpu_temp":%s,"bat_pct":%s,"bat_temp":%s,"ram_total_kb":%s,"ram_used_kb":%s,"load_x100":%s,"safe_mode":%s,"overrides":%s}\n' \
        "$_cpu" "$_gpu" "$_ct" "$_gt" "$_bp" "$_bt" "$_mt" "$((_mt - _ma))" "$_ld" "$_sf" "$_oc"
}

cmd_knobs() {
    [ -s "$BASE" ] || snapshot_baseline
    load_defs
    _o='{"v":5,"categories":['
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
    printf '%s%s]}\n' "$_o" "${_cats%,}"
}

cmd_set_many() {
    [ $# -gt 0 ] || { printf '{"ok":0,"fail":0,"error":"tidak ada knob","results":[]}\n'; return 1; }
    batch_write 1 "$@"
    printf '{"ok":%s,"fail":%s,"results":[%s]}\n' "$RES_OK" "$RES_FAIL" "$RES_JSON"
    [ "$RES_FAIL" -eq 0 ]
}

case "$cmd" in
    ping) echo "pong $HSIN_VER" ;;
    device) cmd_device ;;
    status) cmd_status ;;
    knobs) cmd_knobs ;;
    set-many) cmd_set_many "$@" ;;
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
    guard)
        _n=$(rd "$CNTF"); isint "$_n" || _n=0
        _sf=0; [ -f "$SAFEF" ] && _sf=1
        printf '{"safe_mode":%s,"boot_count":%s}\n' "$_sf" "$_n" ;;
    guard-reset)
        rm -f "$SAFEF"; echo 0 > "$CNTF"; log INFO boot "mode aman dimatikan oleh user"
        echo '{"ok":1}' ;;
    logs)
        _w="${1:-apply}"; _n="${2:-60}"
        case "$_w" in boot|apply) ;; *) _w=apply ;; esac
        isint "$_n" || _n=60
        [ -f "$LOGD/$_w.log" ] && tail -n "$_n" "$LOGD/$_w.log" ;;
    *) echo '{"error":"perintah tidak dikenal"}'; exit 3 ;;
esac
