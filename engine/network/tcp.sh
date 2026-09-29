#!/system/bin/sh
# HSIN Network Engine - TCP Management

[ -z "$HSIN_MODULE_PATH" ] && HSIN_MODULE_PATH="/data/adb/modules/hsin"
# /proc via $HSIN_PROC supaya bisa di-sandbox (prefix palsu), default /proc.
[ -n "$HSIN_PROC" ] || HSIN_PROC="${SYSFS_PROC_PREFIX:-/proc}"
# Override knob user (tcp_cc, tfo) + logger untuk mencatat override yang
# dipakai/ditolak.
. "$HSIN_MODULE_PATH/core/logger.sh" 2>/dev/null
. "$HSIN_MODULE_PATH/core/user_knobs.sh" 2>/dev/null

# Pick best TCP congestion control for profile
hsin_network_pick_tcp() {
    _profile="$1"
    _avail="$2"

    case "$_profile" in
        battery|balanced)
            # Default cubic (well-tested, low CPU)
            echo "cubic"
            return 0
            ;;
        performance)
            # Prefer bbr (low latency)
            case " $_avail " in
                *" bbr "*) echo "bbr"; return 0 ;;
            esac
            echo "cubic"
            return 0
            ;;
        extreme)
            case " $_avail " in
                *" bbr "*)  echo "bbr"; return 0 ;;
                *" bbr2 "*) echo "bbr2"; return 0 ;;
            esac
            echo "cubic"
            return 0
            ;;
    esac
    echo "cubic"
}

# Apply TCP congestion control
hsin_network_apply_tcp() {
    _profile="$1"

    [ -f $HSIN_PROC/sys/net/ipv4/tcp_congestion_control ] || return 1
    [ -w $HSIN_PROC/sys/net/ipv4/tcp_congestion_control ] || return 1

    _avail=""
    [ -f $HSIN_PROC/sys/net/ipv4/tcp_available_congestion_control ] && \
        _avail=$(cat $HSIN_PROC/sys/net/ipv4/tcp_available_congestion_control 2>/dev/null)

    _target=$(hsin_network_pick_tcp "$_profile" "$_avail")

    # Mode manual: tanpa override, lewati penulisan (tanpa kecuali).
    _uk_cc=$(hsin_uk_get tcp_cc 2>/dev/null)
    if [ "$_profile" = "manual" ] && [ -z "$_uk_cc" ]; then
        hsin_uk_result "tcp_cc" "(manual)" "-" "SKIPPED" "tidak diatur (mode manual)" 2>/dev/null || true
        echo "    tcp_congestion: dilewati (mode manual, tanpa override)"
        return 0
    fi

    # Override knob user: hanya dipakai kalau ada di
    # tcp_available_congestion_control - kernel menolak CC tak dikenal,
    # jadi lebih baik SKIP + bilang ke user daripada menulis terus.
    _uk_cc=$(hsin_uk_get tcp_cc 2>/dev/null)
    if [ -n "$_uk_cc" ]; then
        if [ -z "$_avail" ]; then
            hsin_log_warn "network" "override tcp_cc=$_uk_cc ditolak: tcp_available_congestion_control tidak terbaca (pakai profil)"
            hsin_uk_result "tcp_cc" "$_uk_cc" "$_target" "FALLBACK" "ditolak: daftar CC tidak terbaca (pakai profil)" 2>/dev/null || true
        else
            case " $_avail " in
                *" $_uk_cc "*)
                    _target="$_uk_cc"
                    hsin_uk_used "network" "tcp_cc" "$_uk_cc"
                    ;;
                *)
                    hsin_log_warn "network" "override tcp_cc=$_uk_cc ditolak: tidak ada di tcp_available_congestion_control (pakai profil)"
                    hsin_uk_result "tcp_cc" "$_uk_cc" "$_target" "FALLBACK" "ditolak: tidak ada di daftar CC (pakai profil)" 2>/dev/null || true
                    ;;
            esac
        fi
    fi
    if [ -z "$_uk_cc" ]; then
        hsin_uk_result "tcp_cc" "(profil)" "$_target" "APPLIED" "nilai profil (tanpa override)" 2>/dev/null || true
    fi

    _current=$(cat $HSIN_PROC/sys/net/ipv4/tcp_congestion_control 2>/dev/null)

    [ "$_current" = "$_target" ] && return 0

    echo "$_target" > $HSIN_PROC/sys/net/ipv4/tcp_congestion_control 2>/dev/null || return 1

    _verify=$(cat $HSIN_PROC/sys/net/ipv4/tcp_congestion_control 2>/dev/null)
    [ "$_verify" = "$_target" ] && return 0 || return 1
}

# Apply TCP Fast Open
hsin_network_apply_tfo() {
    _profile="$1"
    _path="$HSIN_PROC/sys/net/ipv4/tcp_fastopen"

    [ -f "$_path" ] || return 1
    [ -w "$_path" ] || return 1

    # Mode manual: tanpa override, lewati penulisan.
    _uk_tfo=$(hsin_uk_get tfo 2>/dev/null)
    if [ "$_profile" = "manual" ] && [ -z "$_uk_tfo" ]; then
        hsin_uk_result "tfo" "(manual)" "-" "SKIPPED" "tidak diatur (mode manual)" 2>/dev/null || true
        echo "    tfo: dilewati (mode manual, tanpa override)"
        return 0
    fi
    case "$_profile" in
        battery)     _v="0" ;;
        balanced)    _v="1" ;;
        performance) _v="3" ;;
        extreme)     _v="3" ;;
    esac

    # Override knob user tfo (0-3). Rentang dicek ulang di sini, bukan
    # hanya di hsin_uk_val_ok, supaya file yang diisi manual di luar
    # modul tidak bisa menulis angka yang kernel tolak.
    _uk_tfo=$(hsin_uk_get tfo 2>/dev/null)
    if [ -n "$_uk_tfo" ]; then
        case "$_uk_tfo" in
            0|1|2|3)
                _v="$_uk_tfo"
                hsin_uk_used "network" "tfo" "$_uk_tfo"
                ;;
            *)
                hsin_log_warn "network" "override tfo=$_uk_tfo ditolak: harus 0-3 (pakai profil)"
                hsin_uk_result "tfo" "$_uk_tfo" "$_v" "FALLBACK" "ditolak: harus 0-3 (pakai profil)" 2>/dev/null || true
                ;;
        esac
    fi
    if [ -z "$_uk_tfo" ]; then
        hsin_uk_result "tfo" "(profil)" "$_v" "APPLIED" "nilai profil (tanpa override)" 2>/dev/null || true
    fi

    echo "$_v" > "$_path" 2>/dev/null || return 1
    return 0
}

# Apply network sysctl tunables
# K1: netdev_max_backlog jadi knob user `backlog` (rentang 128-16384).
# tcp_sack / tcp_window_scaling / tcp_ecn BUKAN knob (konstanta per profil)
# dan perilakunya tidak berubah sama sekali.
hsin_network_apply_sysctl() {
    _profile="$1"

    _bl_path="$HSIN_PROC/sys/net/core/netdev_max_backlog"
    _bl_req="(manual)"
    [ "$_profile" = "manual" ] || _bl_req="(profil)"

    # netdev_max_backlog: hanya node yang diminta user yang ditulis. Mode
    # manual tanpa override = nol penulisan; sack/scaling/ecn (bukan knob)
    # tetap dilewati di manual seperti sebelumnya.
    if [ "$_profile" = "manual" ]; then
        echo "  Sysctl: dilewati (mode manual)"
        _uk_bl=$(hsin_uk_get backlog 2>/dev/null)
        if [ -z "$_uk_bl" ]; then
            hsin_uk_result "backlog" "(manual)" "-" "SKIPPED" "tidak diatur (mode manual)" 2>/dev/null || true
            return 0
        fi
    else
        case "$_profile" in
            battery|balanced) _v="1000" ;;
            performance)      _v="5000" ;;
            extreme)          _v="16384" ;;
        esac
    fi

    # Node hilang/tidak writable = UNAVAILABLE beralasan, tanpa crash.
    if [ ! -f "$_bl_path" ] || [ ! -w "$_bl_path" ]; then
        hsin_uk_result "backlog" "$_bl_req" "-" "UNAVAILABLE" "netdev_max_backlog hilang atau read-only" 2>/dev/null || true
    else
        # Validasi ulang di engine (pola tfo): file bisa diedit manual.
        _uk_bl=$(hsin_uk_get backlog 2>/dev/null)
        if [ -n "$_uk_bl" ]; then
            case "$_uk_bl" in ''|*[!0-9]*)
                hsin_log_warn "network" "override backlog=$_uk_bl ditolak: harus angka 128-16384"
                if [ "$_profile" = "manual" ]; then
                    hsin_uk_result "backlog" "$_uk_bl" "-" "SKIPPED" "ditolak: bukan angka (mode manual, tidak ditulis)" 2>/dev/null || true
                    _uk_bl=""
                else
                    hsin_uk_result "backlog" "$_uk_bl" "$_v" "FALLBACK" "ditolak: bukan angka, pakai profil" 2>/dev/null || true
                    _uk_bl=""
                fi
                ;;
            *)
                if [ "$_uk_bl" -lt 128 ] 2>/dev/null || [ "$_uk_bl" -gt 16384 ] 2>/dev/null; then
                    hsin_log_warn "network" "override backlog=$_uk_bl ditolak: harus 128-16384"
                    if [ "$_profile" = "manual" ]; then
                        hsin_uk_result "backlog" "$_uk_bl" "-" "SKIPPED" "ditolak: di luar 128-16384 (mode manual, tidak ditulis)" 2>/dev/null || true
                        _uk_bl=""
                    else
                        hsin_uk_result "backlog" "$_uk_bl" "$_v" "FALLBACK" "ditolak: di luar 128-16384, pakai profil" 2>/dev/null || true
                        _uk_bl=""
                    fi
                fi
                ;;
        esac
        fi

        if [ -n "$_uk_bl" ]; then
            _wval="$_uk_bl"
            if echo "$_wval" > "$_bl_path" 2>/dev/null && [ "$(cat "$_bl_path" 2>/dev/null)" = "$_wval" ]; then
                hsin_uk_used "network" "backlog" "$_wval"
            else
                _cur=$(cat "$_bl_path" 2>/dev/null)
                [ -n "$_cur" ] || _cur="tidak terbaca"
                hsin_log_warn "network" "override backlog=$_wval gagal (node tetap $_cur)"
                hsin_uk_result "backlog" "$_wval" "$_cur" "FAILED" "tulis/readback gagal" 2>/dev/null || true
            fi
        elif [ "$_profile" != "manual" ]; then
            echo "$_v" > "$_bl_path" 2>/dev/null
            hsin_uk_result "backlog" "(profil)" "$_v" "APPLIED" "nilai profil (tanpa override)" 2>/dev/null || true
        fi
    fi

    if [ "$_profile" != "manual" ]; then
        # tcp_sack
        [ -w $HSIN_PROC/sys/net/ipv4/tcp_sack ] && echo 1 > $HSIN_PROC/sys/net/ipv4/tcp_sack 2>/dev/null

        # tcp_window_scaling
        [ -w $HSIN_PROC/sys/net/ipv4/tcp_window_scaling ] && echo 1 > $HSIN_PROC/sys/net/ipv4/tcp_window_scaling 2>/dev/null

        # tcp_ecn
        if [ -w $HSIN_PROC/sys/net/ipv4/tcp_ecn ]; then
            case "$_profile" in
                battery) echo "0" > $HSIN_PROC/sys/net/ipv4/tcp_ecn 2>/dev/null ;;
                *)       echo "1" > $HSIN_PROC/sys/net/ipv4/tcp_ecn 2>/dev/null ;;
            esac
        fi
    fi

    # Ringkasan override ke apply.log dipanggil di titik TERAKHIR pipeline
    # apply yang punya-knob (engine network = engine terakhir di
    # core/apply_engines.sh), jadi hitungan override yang dipakai sudah
    # final. Dipanggil sekali per proses (guard di user_knobs.sh).
    hsin_uk_log_summary

    return 0
}

# Get current network state
hsin_network_state() {
    echo "  Network State:"
    [ -f $HSIN_PROC/sys/net/ipv4/tcp_congestion_control ] && {
        _tcp=$(cat $HSIN_PROC/sys/net/ipv4/tcp_congestion_control 2>/dev/null)
        printf "    tcp_congestion:     %s\n" "$_tcp"
    }
    [ -f $HSIN_PROC/sys/net/ipv4/tcp_available_congestion_control ] && {
        _avail=$(cat $HSIN_PROC/sys/net/ipv4/tcp_available_congestion_control 2>/dev/null)
        printf "    tcp_available:      %s\n" "$_avail"
    }
    [ -f $HSIN_PROC/sys/net/ipv4/tcp_fastopen ] && {
        _tfo=$(cat $HSIN_PROC/sys/net/ipv4/tcp_fastopen 2>/dev/null)
        printf "    tcp_fastopen:       %s\n" "$_tfo"
    }
}

return 0 2>/dev/null || true
