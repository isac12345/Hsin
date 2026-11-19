#!/system/bin/sh
# HSIN - hsinctl: satu pintu CLI untuk aplikasi HSIN.
# Semua tombol di APK memanggil script ini (atau script modul yang sudah ada),
# jadi logika ada di modul dan APK hanya remote.
#
# Pemakaian: hsinctl.sh <perintah> [argumen]
#   status                    key=value kondisi live (profil, suhu, baterai, game)
#   profile <battery|balanced|performance>
#   flag get|set|clear <NAMA> flag fitur di STATE_DIR (daftar putih)
#   flags                     status semua flag
#   conf get <KEY> [def] | conf set <KEY> <VAL>     pengaturan app.conf
#   thermal get | thermal set <60-90>               batas warm (derajat C)
#   games                     JSON daftar game (package, profile, fps)
#   game add <pkg> <fps_csv> <profile> | game remove <pkg>
#   sessions [N]              riwayat sesi game
#   health                    status komponen modul
#   device                    isi detected.conf
#   redetect                  deteksi ulang hardware
#   render get | render set <default|skiagl|skiavk>
#   gamerender get <pkg> | set <pkg> <default|skiagl|skiavk> | list    render per game
#   gameopt list <pkg> | set <pkg> <PRIO|DND|LITE> <on|off|1|default>   opsi per game
#   game launch <pkg>         pasang render per game lalu buka game
#   refresh list | get | set <off|Hz> | modes   refresh rate yang dikunci selama game (modes = "indeks_SF Hz")
#   features                  peta kemampuan perangkat (key=value): cmd game, SF, ANGLE, hosts, ...
#   gamefx get <pkg> | set <pkg> <gamemode|downscale|fps|preload|render> <nilai> | list    opsi per game
#   mitigation list | add <pola> <fitur> | remove <pola> <fitur> | check    matikan fitur per perangkat
#   game scan [add [profil] [fps]] | game seed <pkg>   cari game terpasang dari daftar seed, daftarkan sekaligus
#   shield status|lists|import|enable|disable|remove|allow|on|off|apply   pemblokir iklan berbasis hosts
#   bugreport                 arsip log + state ke /sdcard/Download untuk dilaporkan
#   livecheck                 cek langsung semua fitur (STATUS|nama|ket), ~10 dtk
#   trim [force]              fstrim semua partisi (tidak saat game aktif / baterai < 15%)
#   mem status                tekanan memori (PSI), RAM, kemampuan kernel (hanya baca)
#   mglru status|on|off       MGLRU eksperimental (default off; on = nyalakan, off = pulihkan nilai asli)
#   memclean status|on|off    pembersih adaptif saat game bila PSI tinggi (default off)
#   hud sample <pkg>          satu sampel metrik HUD (FPS, GPU, CPU, suhu)
#   rec start|stop|status|list   rekam layar (screenrecord)
#   autoctl start|stop|status daemon auto-profile
#   log [N]                   N baris terakhir hsin.log
#   restore                   kembalikan semua ke normal (Puncak, DND, refresh rate, render, resolusi, frekuensi game)
#   tweak caps|list|get <KEY>|set <KEY> <VAL>|reset|profile <mode>   tweak global (display/perf/tools), BUKAN per game
#   gamefps get <pkg> | set <pkg> <10-240|off>   satu nilai FPS: batas FPS game + refresh layar (digabung)
#   adapt own on|off|get      Adapt memegang frekuensi CPU/GPU selama game (bawaan on)
#   engine mode freeze|off|get   uperf/fas-rs: dibekukan hanya saat Adapt/Puncak (freeze) atau permanen (off)
#   modinfo                   module.prop
#   diagnose                  ringkasan satu kali baca: mode, pemilik CPU, suhu, FPS/1% low, gagal apply terakhir

COMMON="$(dirname "$(readlink -f "$0")")"
MODDIR="$(dirname "$COMMON")"
STATE_DIR="${HSIN_STATE_DIR:-/data/adb/hsin}"
CONF_FILE="$STATE_DIR/app.conf"
LOG_FILE="${HSIN_LOG_FILE:-$STATE_DIR/hsin.log}"
SYS_THERMAL="${SYSFS_THERMAL_PREFIX:-/sys/class/thermal}"
SYS_POWER="${SYSFS_POWER_PREFIX:-/sys/class/power_supply}"
FASRS_NODE="${HSIN_FASRS_MODE_NODE:-/dev/fas_rs/mode}"
mkdir -p "$STATE_DIR" 2>/dev/null
HSIN_STATE_DIR="$STATE_DIR"
[ -f "$COMMON/gamehooks.sh" ] && . "$COMMON/gamehooks.sh"
[ -f "$COMMON/gamescan.sh" ] && . "$COMMON/gamescan.sh"
# Tweaks global (display/perf/tools). Per game tetap di gamehooks.
[ -f "$COMMON/tweaks.sh" ] && . "$COMMON/tweaks.sh"

FLAG_WHITELIST="GB_FASRS_FORCE_HSIN GB_COOLDOWN_EXTREME NO_CPUSET THERMAL_GUARD_OFF BOOT_GUARD_OFF GAME_PRIO_OFF GAME_DND_ON"

rd() { [ -r "$1" ] && tr -d '\r\n' < "$1" 2>/dev/null; }

uptime_secs() { cut -d. -f1 /proc/uptime 2>/dev/null; }

pid_alive() {
    # $1 = pidfile, $2 = pola cmdline
    _pf="$1"; _pat="$2"
    [ -f "$_pf" ] || return 1
    _p=$(tr -d '[:space:]' < "$_pf" 2>/dev/null)
    [ -n "$_p" ] || return 1
    kill -0 "$_p" 2>/dev/null || return 1
    [ -r "/proc/$_p/cmdline" ] || return 1
    _c=$(tr '\000' ' ' < "/proc/$_p/cmdline" 2>/dev/null)
    case "$_c" in *"$_pat"*) return 0 ;; esac
    return 1
}

# suhu maks zona termal dalam mC. Nilai ngawur (>=125C) dibuang.
max_temp_mc() {
    _max=0
    for _z in "$SYS_THERMAL"/thermal_zone*; do
        [ -r "$_z/temp" ] || continue
        if command -v timeout >/dev/null 2>&1; then
            _v=$(timeout 1 cat "$_z/temp" 2>/dev/null | tr -d '[:space:]')
        else
            _v=$(tr -d '[:space:]' < "$_z/temp" 2>/dev/null)
        fi
        case "$_v" in ''|*[!0-9-]*) continue ;; esac
        [ "${_v#-}" -le 1000 ] 2>/dev/null && _v=$((_v * 1000))
        [ "$_v" -ge 0 ] 2>/dev/null || continue
        [ "$_v" -lt 125000 ] 2>/dev/null || continue
        [ "$_v" -gt "$_max" ] && _max=$_v
    done
    printf '%s' "$_max"
}

# suhu baterai dalam mC (sysfs battery/temp = per 0.1 C). Dipakai untuk tampilan di app.
batt_temp_mc() {
    _bt=$(rd "$SYS_POWER/battery/temp")
    case "$_bt" in ''|*[!0-9-]*) printf '%s' "$(max_temp_mc)"; return ;; esac
    printf '%s' $((_bt * 100))
}

valid_profile() { case "$1" in adapt|puncak|battery|balanced|performance) return 0 ;; *) return 1 ;; esac; }
valid_pkg() {
    case "$1" in ''|*[!A-Za-z0-9._]*) return 1 ;; esac
    case "$1" in *.*) return 0 ;; *) return 1 ;; esac
}
in_whitelist() { for _w in $FLAG_WHITELIST; do [ "$_w" = "$1" ] && return 0; done; return 1; }

conf_get() {
    _k="$1"; _d="$2"
    _v=""
    [ -f "$CONF_FILE" ] && _v=$(sed -n "s/^${_k}=//p" "$CONF_FILE" 2>/dev/null | tail -n 1)
    [ -n "$_v" ] && printf '%s' "$_v" || printf '%s' "$_d"
}

conf_set() {
    _k="$1"; _v="$2"
    case "$_k" in ''|*[!A-Z0-9_]*) echo "ERROR: key tidak valid"; return 1 ;; esac
    case "$_v" in *[!A-Za-z0-9._,:-]*) echo "ERROR: value tidak valid"; return 1 ;; esac
    touch "$CONF_FILE" 2>/dev/null
    _t="$CONF_FILE.tmp.$$"
    grep -v "^${_k}=" "$CONF_FILE" > "$_t" 2>/dev/null
    printf '%s=%s\n' "$_k" "$_v" >> "$_t"
    mv -f "$_t" "$CONF_FILE" && echo "OK: $_k=$_v"
}

# memfx: tekanan memori (PSI) dan MGLRU opt-in. Default tidak menyentuh apa pun.
HSIN_STATE_DIR="$STATE_DIR"
[ -f "$COMMON/memfx.sh" ] && . "$COMMON/memfx.sh"

cmd_mem() {
    command -v mf_memstat >/dev/null 2>&1 || { echo "ERROR: memfx.sh tidak ada"; return 1; }
    case "$1" in
        ''|status) mf_memstat; mf_caps ;;
        *) echo "Usage: mem status"; return 1 ;;
    esac
}

cmd_mglru() {
    command -v mf_mglru_status >/dev/null 2>&1 || { echo "ERROR: memfx.sh tidak ada"; return 1; }
    case "$1" in
        ''|status) mf_mglru_status; printf 'mode=%s\n' "$(conf_get MGLRU_MODE off)" ;;
        on)  conf_set MGLRU_MODE on  >/dev/null && mf_mglru_apply; mf_mglru_status ;;
        off) conf_set MGLRU_MODE off >/dev/null && mf_mglru_restore; mf_mglru_status ;;
        *) echo "Usage: mglru status|on|off"; return 1 ;;
    esac
}

cmd_memclean() {
    case "$1" in
        ''|status) printf 'memclean=%s\nhits=%s\ncooldown=%s\n' "$(conf_get MEMCLEAN 0)" "$(conf_get MEMCLEAN_HITS 3)" "$(conf_get MEMCLEAN_COOLDOWN 180)" ;;
        on)  conf_set MEMCLEAN 1 ;;
        off) conf_set MEMCLEAN 0 ;;
        *) echo "Usage: memclean status|on|off"; return 1 ;;
    esac
}

cmd_status() {
    command -v tw_idle_reassert >/dev/null 2>&1 && tw_idle_reassert
    _cur=$(rd "$STATE_DIR/current_state"); [ -n "$_cur" ] || _cur=none
    _act=$(rd "$STATE_DIR/active_profile"); [ -n "$_act" ] || _act=none
    printf 'profile=%s\nactive=%s\n' "$_cur" "$_act"
    pid_alive "$STATE_DIR/monitor.pid" monitor.sh && echo monitor=1 || echo monitor=0
    pid_alive "$STATE_DIR/watchdog.pid" watchdog.sh && echo watchdog=1 || echo watchdog=0
    pid_alive "$STATE_DIR/autoctl.pid" autoctl.sh && echo auto=1 || echo auto=0
    if [ -r "$FASRS_NODE" ]; then
        echo fasrs_node=1
        printf 'fasrs_mode=%s\n' "$(rd "$FASRS_NODE")"
        echo cpu_owner=fas-rs
    else
        echo fasrs_node=0
        echo fasrs_mode=
        if pidof fas-rs >/dev/null 2>&1; then echo cpu_owner=fas-rs; else echo cpu_owner=hsin; fi
    fi
    printf 'temp_mc=%s\n' "$(batt_temp_mc)"
    printf 'soc_temp_mc=%s\n' "$(max_temp_mc)"
    printf 'batt=%s\n' "$(rd "$SYS_POWER/battery/capacity")"
    printf 'batt_status=%s\n' "$(rd "$SYS_POWER/battery/status")"
    printf 'gb_active=%s\n' "$(rd "$STATE_DIR/.gb_active")"
    printf 'boost_level=%s\n' "$(rd "$STATE_DIR/boost_level")"
    _gp=""; _gs=0
    if [ -f "$STATE_DIR/.game_t0" ]; then
        read -r _t0 _gp < "$STATE_DIR/.game_t0" 2>/dev/null
        _now=$(uptime_secs)
        case "$_t0" in ''|*[!0-9]*) ;; *) [ -n "$_now" ] && _gs=$((_now - _t0)) ;; esac
        [ "$_gs" -ge 0 ] 2>/dev/null || _gs=0
    fi
    printf 'game_pkg=%s\ngame_secs=%s\n' "$_gp" "$_gs"
    printf 'adapt_now=%s\n' "$(rd "$STATE_DIR/.adapt_now")"
    # Adapt memegang frekuensi: penanda berisi paket, epoch, lantai CPU/GPU (persen)
    _ao=0; _acp=""; _aop=""
    if [ -f "$STATE_DIR/.adapt_own" ]; then
        _ao=1; _aop=$(sed -n 1p "$STATE_DIR/.adapt_own" 2>/dev/null | tr -d '[:space:]')
        _acp=$(sed -n 3p "$STATE_DIR/.adapt_own" 2>/dev/null | tr -d '[:space:]')
    fi
    _ap=${_aop:-$_gp}
    _ads=""; _afp=""
    if [ -n "$_ap" ]; then _ads=$(gh_opt_get "$_ap" downscale ""); _afp=$(gh_opt_get "$_ap" fps ""); fi
    _atr=$(sed -n 's/^AD_DEV_TIER=//p' "$STATE_DIR/device_profile.env" 2>/dev/null | tail -n 1 | tr -d '[:space:]')
    [ -n "$_atr" ] || _atr=$(sed -n 's/^DEVICE_TIER=//p' "$STATE_DIR/detected.conf" 2>/dev/null | tail -n 1 | tr -d '"[:space:]')
    printf 'adapt_own=%s\nadapt_own_pkg=%s\nadapt_cpu=%s\nadapt_ds=%s\nadapt_fps=%s\nadapt_tier=%s\n' "$_ao" "$_aop" "$_acp" "$_ads" "$_afp" "$_atr"
    printf 'adapt_own_switch=%s\nengine_mode=%s\n' \
        "$([ "$(rd "$STATE_DIR/ADAPT_OWN")" = "off" ] && echo off || echo on)" \
        "$([ "$(rd "$STATE_DIR/ENGINE_MODE")" = "off" ] && echo off || echo freeze)"
    _sf="$STATE_DIR/adapt/$_gp.conf"; _sv=""; _sw=""
    if [ -n "$_gp" ] && [ -f "$_sf" ] && [ "$(gh_opt_get "$_gp" AUTO on)" = "off" ] && [ "$(sed -n 's/^saran_tampil=//p' "$_sf" | tail -n 1)" != "1" ]; then
        _sv=$(sed -n 's/^saran=//p' "$_sf" | tail -n 1 | tr -d '[:space:]')
        _sw=$(sed -n 's/^saran_why=//p' "$_sf" | tail -n 1)
    fi
    printf 'saran_pkg=%s\nsaran_nilai=%s\nsaran_why=%s\n' "${_sv:+$_gp}" "$_sv" "$_sw"
    printf 'hud_pkg=%s\n' "$(rd "$STATE_DIR/.gh_active")"
    pid_alive "$STATE_DIR/.rec_pid" screenrec.sh && echo rec=1 || echo rec=0
    printf 'thermal_warm_c=%s\n' "$(cmd_thermal_get)"
    if [ -f "$COMMON/overdrive.sh" ]; then
        HSIN_STATE_DIR="$STATE_DIR" sh "$COMMON/overdrive.sh" status 2>/dev/null
    else
        printf 'ovd=0\novd_pkg=\novd_level=\novd_last=\n'
    fi
    if command -v mf_psi_x100 >/dev/null 2>&1; then
        printf 'psi_some10_x100=%s\n' "$(mf_psi_x100 some avg10 2>/dev/null)"
        printf 'mglru=%s\n' "$([ -r "$MF_LRU/enabled" ] && { _mf_raw_on "$(tr -d '[:space:]' < "$MF_LRU/enabled")" && echo 1 || echo 0; } || echo na)"
        printf 'mglru_mode=%s\nmemclean=%s\n' "$(conf_get MGLRU_MODE off)" "$(conf_get MEMCLEAN 0)"
    fi
    printf 'ver=%s\n' "$(sed -n 's/^versionCode=//p' "$MODDIR/module.prop" 2>/dev/null | head -n 1)"
}

cmd_profile() {
    valid_profile "$1" || { echo "ERROR: profil tidak valid (adapt|puncak)"; return 1; }
    sh "$COMMON/apply_now.sh" "$1" manual >/dev/null 2>&1
    _rc=$?
    # apply_now bisa SKIPPED (sudah current) -> tetap exit 0
    [ "$_rc" -eq 0 ] && echo "OK: profile=$1" || echo "ERROR: apply_now rc=$_rc"
    return "$_rc"
}

cmd_flag() {
    _op="$1"; _n="$2"
    in_whitelist "$_n" || { echo "ERROR: flag tidak dikenal: $_n"; return 1; }
    case "$_op" in
        get) [ -f "$STATE_DIR/$_n" ] && echo 1 || echo 0 ;;
        set) printf '' > "$STATE_DIR/$_n" 2>/dev/null && echo "OK: $_n=1" || { echo "ERROR: gagal tulis"; return 1; } ;;
        clear) rm -f "$STATE_DIR/$_n" 2>/dev/null; echo "OK: $_n=0" ;;
        *) echo "Usage: flag get|set|clear <NAMA>"; return 1 ;;
    esac
}

cmd_flags() {
    for _n in $FLAG_WHITELIST; do
        [ -f "$STATE_DIR/$_n" ] && echo "$_n=1" || echo "$_n=0"
    done
}

cmd_thermal_get() {
    _t=$(tr -cd '0-9' 2>/dev/null < "$STATE_DIR/THERMAL_WARM_C")
    case "$_t" in ''|*[!0-9]*) _t=75 ;; esac
    [ "$_t" -ge 60 ] 2>/dev/null && [ "$_t" -le 90 ] 2>/dev/null || _t=75
    printf '%s' "$_t"
}

cmd_thermal() {
    case "$1" in
        get) cmd_thermal_get; echo ;;
        set)
            case "$2" in ''|*[!0-9]*) echo "ERROR: angka derajat"; return 1 ;; esac
            if [ "$2" -lt 60 ] || [ "$2" -gt 90 ]; then echo "ERROR: rentang 60-90"; return 1; fi
            printf '%s\n' "$2" > "$STATE_DIR/THERMAL_WARM_C" && echo "OK: warm=$2"
            ;;
        *) echo "Usage: thermal get|set <60-90>"; return 1 ;;
    esac
}

fps_of() {
    # nilai fps game dari games.toml, dinormalkan "30,60"
    _f="$MODDIR/fasrs/games.toml"
    [ -f "$_f" ] || return 0
    sed -n "s/^\"$1\"[[:space:]]*=[[:space:]]*//p" "$_f" 2>/dev/null | head -n 1 | tr -d '[] "' 
}

cmd_games() {
    _map="$STATE_DIR/game_profile_map.conf"
    _toml="$MODDIR/fasrs/games.toml"
    _seen=" "
    _first=1
    printf '['
    if [ -f "$_map" ]; then
        while IFS= read -r _l || [ -n "$_l" ]; do
            _l=$(printf '%s' "$_l" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
            case "$_l" in ''|'#'*) continue ;; esac
            _pkg=${_l%%:*}; _pr=${_l#*:}
            valid_pkg "$_pkg" || continue
            valid_profile "$_pr" || continue
            [ "$_first" = 1 ] || printf ','
            _first=0
            _seen="$_seen$_pkg "
            printf '{"package":"%s","profile":"%s","fps":"%s"}' "$_pkg" "$_pr" "$(fps_of "$_pkg")"
        done < "$_map"
    fi
    if [ -f "$_toml" ]; then
        _pk=$(sed -n '/^\[game_list\]/,/^\[/p' "$_toml" | sed -n 's/^"\([^"]*\)".*/\1/p')
        for _pkg in $_pk; do
            valid_pkg "$_pkg" || continue
            case "$_seen" in *" $_pkg "*) continue ;; esac
            [ "$_first" = 1 ] || printf ','
            _first=0
            printf '{"package":"%s","profile":"balanced","fps":"%s"}' "$_pkg" "$(fps_of "$_pkg")"
        done
    fi
    printf ']\n'
}

cmd_game() {
    case "$1" in
        add)
            valid_pkg "$2" || { echo "ERROR: package tidak valid"; return 1; }
            _fps="${3:-30,60}"; _pr="${4:-performance}"
            sh "$COMMON/game_add.sh" add "$2" "$_fps" "$_pr"
            ;;
        remove)
            valid_pkg "$2" || { echo "ERROR: package tidak valid"; return 1; }
            sh "$COMMON/game_add.sh" remove "$2"
            ;;
        launch)
            valid_pkg "$2" || { echo "ERROR: package tidak valid"; return 1; }
            gh_launch "$2"
            ;;
        scan)
            command -v gs_candidates >/dev/null 2>&1 || { echo "ERROR: gamescan.sh tidak ada"; return 1; }
            case "$2" in
                add) gs_add_all "$3" "$4" ;;
                *) gs_candidates ;;
            esac
            ;;
        seed) gs_user_add "$2" ;;
        *) echo "Usage: game add <pkg> <fps_csv> <profile> | game remove <pkg> | game launch <pkg> | game scan [add [profil] [fps]] | game seed <pkg>"; return 1 ;;
    esac
}

cmd_gamerender() {
    case "$1" in
        get)
            valid_pkg "$2" || { echo "ERROR: package tidak valid"; return 1; }
            _gr=$(gh_render_get "$2"); printf '%s\n' "${_gr:-default}"
            ;;
        set)
            valid_pkg "$2" || { echo "ERROR: package tidak valid"; return 1; }
            gh_render_set "$2" "$3"
            ;;
        list) gh_render_list ;;
        *) echo "Usage: gamerender get <pkg> | set <pkg> <default|skiagl|skiavk|angle> | list"; return 1 ;;
    esac
}

cmd_gameauto() {
    case "$1" in
        get)
            valid_pkg "$2" || { echo "ERROR: package tidak valid"; return 1; }
            printf 'auto=%s\n' "$(gh_opt_get "$2" AUTO on)"
            printf 'downscale=%s\nfps=%s\ngamemode=%s\n' "$(gh_opt_get "$2" downscale off)" "$(gh_opt_get "$2" fps off)" "$(gh_opt_get "$2" gamemode off)"
            printf 'data_n=%s\n' "$(sed -n 's/^n=//p' "$STATE_DIR/adapt/$2.conf" 2>/dev/null | tail -n 1)"
            ;;
        set)    # dipanggil adapt.sh: <pkg> <downscale|off> <fps|keep>
            valid_pkg "$2" || { echo "ERROR: package tidak valid"; return 1; }
            [ "$(gh_opt_get "$2" AUTO on)" = "off" ] && { echo "OK: auto mati untuk $2"; return 0; }
            gh_opt_set "$2" downscale "$3" >/dev/null || return 1
            case "$4" in ''|keep) ;; *) tw_game_fps "$2" "$4" >/dev/null || return 1 ;; esac
            gh_opt_set "$2" gamemode performance >/dev/null
            gh_opt_set "$2" PRESET auto >/dev/null
            gh_prearm "$2"
            echo "OK: $2 auto downscale=$3 fps=${4:-keep}" ;;
        mode)   # <pkg> on|off
            valid_pkg "$2" || { echo "ERROR: package tidak valid"; return 1; }
            case "$3" in
                on) gh_opt_set "$2" AUTO default >/dev/null; echo "OK: auto aktif untuk $2" ;;
                off)
                    gh_opt_set "$2" AUTO off >/dev/null
                    for _k in downscale gamemode PRESET; do gh_opt_set "$2" "$_k" default >/dev/null; done
                    tw_game_fps "$2" off >/dev/null
                    pidof "$2" >/dev/null 2>&1 || gh_unarm "$2"
                    echo "OK: auto mati untuk $2, semua kembali bawaan" ;;
                *) echo "Usage: gameauto mode <pkg> on|off"; return 1 ;;
            esac ;;
        reset)  # hapus data + nilai, mulai belajar dari awal
            valid_pkg "$2" || { echo "ERROR: package tidak valid"; return 1; }
            _pf="$STATE_DIR/adapt/$2.conf"
            [ -f "$_pf" ] && { grep -v -E '^(n|sum_p1|p1_min|stall_max|jank_n|p1_avg|jank_pct|saran|saran_why|saran_ts|saran_tampil|saran_ditawarkan|pre_[a-z]+)=' "$_pf" > "$_pf.tmp.$$" 2>/dev/null; mv -f "$_pf.tmp.$$" "$_pf"; }
            # penanda untuk monitor: buang sampel yang masih di memori (adapt.sh membacanya)
            mkdir -p "$STATE_DIR/adapt" 2>/dev/null; printf '' > "$STATE_DIR/adapt/$2.reset"
            for _k in downscale gamemode PRESET; do gh_opt_set "$2" "$_k" default >/dev/null; done
            tw_game_fps "$2" off >/dev/null
            pidof "$2" >/dev/null 2>&1 || gh_unarm "$2"
            echo "OK: data dan pengaturan otomatis $2 dihapus" ;;
        *) echo "Usage: gameauto get <pkg> | mode <pkg> on|off | reset <pkg>"; return 1 ;;
    esac
}

cmd_gamepreset() {
    case "$1" in
        get)
            valid_pkg "$2" || { echo "ERROR: package tidak valid"; return 1; }
            _pf="$STATE_DIR/adapt/$2.conf"
            printf 'preset=%s\n' "$(gh_opt_get "$2" PRESET manual)"
            for _n in grafik stabil performa; do
                printf '%s=%s\n' "$_n" "$(sed -n "s/^pre_$_n=//p" "$_pf" 2>/dev/null | tail -n 1 | tr -d '[:space:]')"
            done ;;
        set)
            valid_pkg "$2" || { echo "ERROR: package tidak valid"; return 1; }
            case "$3" in
                manual)
                    gh_opt_set "$2" PRESET default >/dev/null
                    pidof "$2" >/dev/null 2>&1 || gh_unarm "$2"
                    echo "OK: $2 preset=manual" ;;
                grafik|stabil|performa)
                    _pv=$(sed -n "s/^pre_$3=//p" "$STATE_DIR/adapt/$2.conf" 2>/dev/null | tail -n 1 | tr -d '[:space:]')
                    [ -n "$_pv" ] || { echo "ERROR: belum ada data untuk $2, main sekali dulu"; return 1; }
                    _pd=${_pv%%,*}; _pr=${_pv#*,}; _pfp=${_pr%%,*}; _pm=${_pr#*,}
                    gh_opt_set "$2" downscale "$_pd" >/dev/null || return 1
                    gh_opt_set "$2" fps "$_pfp" >/dev/null || return 1
                    gh_opt_set "$2" gamemode "$_pm" >/dev/null || return 1
                    gh_opt_set "$2" PRESET "$3" >/dev/null || return 1
                    gh_prearm "$2"
                    echo "OK: $2 preset=$3 downscale=$_pd fps=$_pfp mode=$_pm (berlaku di buka berikutnya)" ;;
                *) echo "ERROR: preset = grafik|stabil|performa|manual"; return 1 ;;
            esac ;;
        learn)   # hitung ulang dari statistik tersimpan; $3 = resolusi acuan (persen) yang kamu pakai saat main
            valid_pkg "$2" || { echo "ERROR: package tidak valid"; return 1; }
            case "$3" in ''|*[!0-9]*) echo "ERROR: resolusi acuan = angka persen 10-100"; return 1 ;; esac
            [ "$3" -ge 10 ] && [ "$3" -le 100 ] || { echo "ERROR: resolusi acuan = angka persen 10-100"; return 1; }
            [ -f "$STATE_DIR/adapt/$2.conf" ] || { echo "ERROR: belum ada data untuk $2, main sekali dulu"; return 1; }
            ( AD_STATE="$STATE_DIR"; AD_DIR="$STATE_DIR/adapt"; . "$COMMON/adapt.sh" >/dev/null 2>&1; ad_preset_learn "$2" "$3" )
            [ -n "$(sed -n 's/^pre_stabil=//p' "$STATE_DIR/adapt/$2.conf")" ] || { echo "ERROR: data belum cukup (minimal 60 sampel, sekitar 10 menit main)"; return 1; }
            echo "OK: preset dihitung ulang dari resolusi $3%" ;;
        reset)
            valid_pkg "$2" || { echo "ERROR: package tidak valid"; return 1; }
            _pf="$STATE_DIR/adapt/$2.conf"
            [ -f "$_pf" ] && { grep -v '^pre_' "$_pf" > "$_pf.tmp.$$" 2>/dev/null; mv -f "$_pf.tmp.$$" "$_pf"; }
            gh_opt_set "$2" PRESET default >/dev/null
            pidof "$2" >/dev/null 2>&1 || gh_unarm "$2"
            echo "OK: preset $2 dihapus" ;;
        *) echo "Usage: gamepreset get <pkg> | set <pkg> <grafik|stabil|performa|manual> | learn <pkg> <persen> | reset <pkg>"; return 1 ;;
    esac
}

cmd_gamefx() {
    case "$1" in
        get)
            valid_pkg "$2" || { echo "ERROR: package tidak valid"; return 1; }
            printf 'gamemode=%s\n' "$(gh_opt_get "$2" gamemode off)"
            printf 'downscale=%s\n' "$(gh_opt_get "$2" downscale off)"
            printf 'fps=%s\n' "$(gh_opt_get "$2" fps off)"
            printf 'preload=%s\n' "$(gh_opt_get "$2" preload off)"
            printf 'preset=%s\n' "$(gh_opt_get "$2" PRESET manual)"
            _gx=$(gh_render_get "$2"); printf 'render=%s\n' "${_gx:-default}"
            ;;
        set)
            valid_pkg "$2" || { echo "ERROR: package tidak valid"; return 1; }
            case "$3" in
                gamemode|downscale|fps|preload) gh_opt_set "$2" "$3" "$4" ;;
                render) gh_render_set "$2" "$4" ;;
                *) echo "ERROR: kunci = gamemode|downscale|fps|preload|render"; return 1 ;;
            esac
            ;;
        list) gh_opt_list; gh_render_list | sed 's/^\([^:]*\):/\1:render=/' ;;
        *) echo "Usage: gamefx get <pkg> | set <pkg> <gamemode|downscale|fps|preload|render> <nilai> | list"; return 1 ;;
    esac
}

cmd_mitigation() {
    case "$1" in
        list) gh_mit_list ;;
        add) gh_mit_add "$2" "$3" ;;
        remove) gh_mit_remove "$2" "$3" ;;
        check) gh_mit_check ;;
        *) echo "Usage: mitigation list | add <pola> <fitur> | remove <pola> <fitur> | check"; return 1 ;;
    esac
}

# Ekspor satu berkas teks berisi semua yang dibutuhkan untuk diagnosa. Tidak berisi data pribadi (tanpa isi app/chat).
cmd_logexport() {
    _ld="/sdcard/Download"
    [ -d "$_ld" ] && [ -w "$_ld" ] || _ld="$STATE_DIR"
    _lf="$_ld/hsin-log-$(date '+%Y%m%d-%H%M%S' 2>/dev/null).txt"
    {
        echo "=== HSIN log export $(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null) ==="
        echo "module versionCode: $(sed -n 's/^versionCode=//p' "$MODDIR/module.prop" 2>/dev/null | head -n 1)"
        echo "model: $(getprop ro.product.model 2>/dev/null)  android: $(getprop ro.build.version.release 2>/dev/null)  platform: $(getprop ro.board.platform 2>/dev/null)"
        echo "kernel: $(uname -r 2>/dev/null)"
        echo; echo "=== status ==="; cmd_status 2>/dev/null
        echo; echo "=== health ==="; cmd_health 2>/dev/null
        echo; echo "=== flags ==="; cmd_flags 2>/dev/null
        echo; echo "=== app.conf ==="; [ -f "$CONF_FILE" ] && cat "$CONF_FILE"
        echo; echo "=== opsi per game (game_opts.conf) ==="; [ -f "$STATE_DIR/game_opts.conf" ] && cat "$STATE_DIR/game_opts.conf"
        echo; echo "=== overdrive ==="; [ -f "$COMMON/overdrive.sh" ] && HSIN_STATE_DIR="$STATE_DIR" sh "$COMMON/overdrive.sh" status
        echo; echo "=== frekuensi saat ini ==="
        for _p in /sys/devices/system/cpu/cpufreq/policy*; do
            [ -d "$_p" ] && echo "$(basename "$_p") gov=$(cat "$_p/scaling_governor" 2>/dev/null) min=$(cat "$_p/scaling_min_freq" 2>/dev/null) max=$(cat "$_p/scaling_max_freq" 2>/dev/null) cur=$(cat "$_p/scaling_cur_freq" 2>/dev/null)"
        done
        for _g in /sys/class/devfreq/*gpu*; do
            [ -d "$_g" ] && echo "gpu $(basename "$_g") min=$(cat "$_g/min_freq" 2>/dev/null) max=$(cat "$_g/max_freq" 2>/dev/null) cur=$(cat "$_g/cur_freq" 2>/dev/null)"
        done
        echo; echo "=== hsin.log (400 baris terakhir) ==="; tail -n 400 "$STATE_DIR/hsin.log" 2>/dev/null
        echo; echo "=== hud_debug.log ==="; tail -n 120 "$STATE_DIR/hud_debug.log" 2>/dev/null
    } > "$_lf" 2>&1
    echo "OK: $_lf"
}

cmd_saran() {   # saran done <pkg>: tandai sudah ditawarkan (Pakai/Tetap)
    case "$1" in
        done) valid_pkg "$2" || { echo "ERROR: package tidak valid"; return 1; }
              _sf="$STATE_DIR/adapt/$2.conf"; [ -f "$_sf" ] || { echo "OK"; return 0; }
              _v=$(sed -n 's/^saran=//p' "$_sf" | tail -n 1 | tr -d '[:space:]')
              case "$_v" in 1.00) _v=100 ;; 0.[0-9][0-9]) _v=${_v#0.}; _v=${_v#0} ;; *) _v="" ;; esac
              grep -v -E '^(saran_tampil|saran_ditawarkan)=' "$_sf" > "$_sf.tmp.$$" 2>/dev/null
              printf 'saran_tampil=1\n' >> "$_sf.tmp.$$"
              case "$_v" in ''|*[!0-9]*) ;; *) printf 'saran_ditawarkan=%s\n' "$_v" >> "$_sf.tmp.$$" ;; esac
              mv -f "$_sf.tmp.$$" "$_sf"; echo "OK" ;;
        *) echo "Usage: saran done <pkg>"; return 1 ;;
    esac
}

cmd_cfgbackup() {
    _bd="${HSIN_BACKUP_DIR:-/sdcard/Download}"
    _bf="$_bd/hsin-backup-$(date +%Y%m%d-%H%M%S).tar.gz"
    mkdir -p "$_bd" 2>/dev/null
    _l=""
    for _f in game_opts.conf game_render.conf game_profile_map.conf app.conf tweaks.conf device_mitigation.conf adapt; do
        [ -e "$STATE_DIR/$_f" ] && _l="$_l $_f"
    done
    [ -n "$_l" ] || { echo "ERROR: tidak ada konfigurasi untuk dicadangkan"; return 1; }
    # shellcheck disable=SC2086
    tar -C "$STATE_DIR" -czf "$_bf" $_l 2>/dev/null || { echo "ERROR: gagal membuat cadangan"; return 1; }
    echo "OK: $_bf"
}

cmd_cfgrestore() {
    _rf="$1"
    [ -f "$_rf" ] || { echo "ERROR: berkas tidak ada"; return 1; }
    tar -tzf "$_rf" >/dev/null 2>&1 || { echo "ERROR: cadangan rusak"; return 1; }
    _bad=$(tar -tzf "$_rf" 2>/dev/null | grep -vE '^(game_opts\.conf|game_render\.conf|game_profile_map\.conf|app\.conf|tweaks\.conf|device_mitigation\.conf|adapt(/[A-Za-z0-9._-]+)?/?)$')
    [ -z "$_bad" ] || { echo "ERROR: cadangan berisi berkas tidak dikenal"; return 1; }
    _t=$(date +%Y%m%d-%H%M%S)
    for _f in game_opts.conf game_render.conf game_profile_map.conf app.conf tweaks.conf device_mitigation.conf; do
        [ -f "$STATE_DIR/$_f" ] && cp "$STATE_DIR/$_f" "$STATE_DIR/$_f.bak-$_t" 2>/dev/null
    done
    tar -C "$STATE_DIR" -xzf "$_rf" 2>/dev/null || { echo "ERROR: gagal memulihkan"; return 1; }
    echo "OK: dipulihkan (berkas lama disimpan *.bak-$_t)"
}

cmd_ovd() {
    [ -f "$COMMON/overdrive.sh" ] || { echo "ERROR: overdrive.sh tidak ada"; return 1; }
    case "$1" in
        start) [ -z "$2" ] || valid_pkg "$2" || { echo "ERROR: package tidak valid"; return 1; }
               HSIN_STATE_DIR="$STATE_DIR" sh "$COMMON/overdrive.sh" start "$2" ;;
        stop) HSIN_STATE_DIR="$STATE_DIR" sh "$COMMON/overdrive.sh" stop "${2:-manual}" ;;
        status) HSIN_STATE_DIR="$STATE_DIR" sh "$COMMON/overdrive.sh" status ;;
        *) echo "Usage: ovd start [pkg] | ovd stop | ovd status"; return 1 ;;
    esac
}

cmd_gameopt() {
    case "$1" in
        list)
            valid_pkg "$2" || { echo "ERROR: package tidak valid"; return 1; }
            gh_opt_list "$2"
            ;;
        set)
            valid_pkg "$2" || { echo "ERROR: package tidak valid"; return 1; }
            gh_opt_set "$2" "$3" "$4"
            ;;
        *) echo "Usage: gameopt list <pkg> | set <pkg> <PRIO|DND|LITE> <on|off|1|default>"; return 1 ;;
    esac
}

cmd_refresh() {
    case "$1" in
        list) gh_refresh_list ;;
        modes) gh_sf_modes ;;
        get) conf_get GAME_REFRESH_HZ off; echo ;;
        set)
            case "$2" in
                off) ;;
                ''|*[!0-9]*) echo "ERROR: isi off atau angka Hz"; return 1 ;;
                *)
                    if [ "$2" -lt 30 ] || [ "$2" -gt 240 ]; then echo "ERROR: rentang 30-240 Hz"; return 1; fi
                    _rl=$(gh_refresh_list)
                    if [ -n "$_rl" ]; then
                        case " $(echo $_rl) " in *" $2 "*) ;; *) echo "ERROR: layar ini tidak mendukung $2 Hz"; return 1 ;; esac
                    fi
                    ;;
            esac
            conf_set GAME_REFRESH_HZ "$2" || return 1
            # game sedang jalan: terapkan langsung
            if [ -f "$STATE_DIR/.gh_active" ]; then _gh_refresh_off; _gh_refresh_on "$(cat "$STATE_DIR/.gh_active" 2>/dev/null)"; fi
            ;;
        *) echo "Usage: refresh list | get | set <off|Hz>"; return 1 ;;
    esac
}

cmd_hud() {
    case "$1" in
        sample)
            valid_pkg "$2" || { echo "ERROR: package tidak valid"; return 1; }
            sh "$COMMON/hud_sample.sh" --once "$2"
            ;;
        diag) valid_pkg "$2" || { echo "ERROR: package tidak valid"; return 1; }; sh "$COMMON/hud_sample.sh" --diag "$2" ;;
        *) echo "Usage: hud sample|diag <pkg>"; return 1 ;;
    esac
}

# Bekukan app: pm disable-user (data aman, ikon hilang, tidak jalan di latar). Hanya app pengguna yang boleh.
FREEZE_LIST="$STATE_DIR/frozen.list"
freeze_protected() {
    case "$1" in
        android|com.hsin|com.android.*|com.google.android.gms*|com.google.android.gsf*|*launcher*|*inputmethod*|*keyboard*|com.unisoc.*|com.sprd.*|com.topjohnwu.magisk|me.weishu.kernelsu|*.systemui|*.settings|*.dialer|*.phone) return 0 ;;
    esac
    return 1
}
cmd_freeze() {
    case "$1" in
        list) [ -f "$FREEZE_LIST" ] && cat "$FREEZE_LIST"; return 0 ;;
        on)
            valid_pkg "$2" || { echo "ERROR: package tidak valid"; return 1; }
            freeze_protected "$2" && { echo "ERROR: app sistem/penting tidak boleh dibekukan"; return 1; }
            pm path "$2" >/dev/null 2>&1 || { echo "ERROR: app tidak terpasang"; return 1; }
            am force-stop "$2" >/dev/null 2>&1
            pm disable-user --user 0 "$2" >/dev/null 2>&1 || { echo "ERROR: gagal membekukan"; return 1; }
            grep -qx "$2" "$FREEZE_LIST" 2>/dev/null || echo "$2" >> "$FREEZE_LIST"
            echo "OK: $2 dibekukan"
            ;;
        off)
            valid_pkg "$2" || { echo "ERROR: package tidak valid"; return 1; }
            pm enable --user 0 "$2" >/dev/null 2>&1
            [ -f "$FREEZE_LIST" ] && grep -vx "$2" "$FREEZE_LIST" > "$FREEZE_LIST.tmp" 2>/dev/null; [ -f "$FREEZE_LIST.tmp" ] && mv "$FREEZE_LIST.tmp" "$FREEZE_LIST"
            echo "OK: $2 dicairkan"
            ;;
        alloff)
            [ -f "$FREEZE_LIST" ] || { echo "OK: tidak ada yang dibekukan"; return 0; }
            while IFS= read -r _fz; do [ -n "$_fz" ] && pm enable --user 0 "$_fz" >/dev/null 2>&1; done < "$FREEZE_LIST"
            rm -f "$FREEZE_LIST"
            echo "OK: semua dicairkan"
            ;;
        *) echo "Usage: freeze list|on <pkg>|off <pkg>|alloff"; return 1 ;;
    esac
}

cmd_restore() {
    sh "$COMMON/overdrive.sh" stop darurat >/dev/null 2>&1
    gh_recover >/dev/null 2>&1
    (
        HSIN_CONF_DIR="$STATE_DIR"; HSIN_LOG_FILE=/dev/null; export HSIN_CONF_DIR HSIN_LOG_FILE
        [ -f "$COMMON/detect.sh" ] && . "$COMMON/detect.sh" 2>/dev/null
        [ -f "$COMMON/gameboost.sh" ] && . "$COMMON/gameboost.sh" 2>/dev/null
        command -v gb_restore >/dev/null 2>&1 && gb_restore
    ) >/dev/null 2>&1
    wm size reset >/dev/null 2>&1
    sh "$COMMON/charge.sh" off >/dev/null 2>&1
    echo "OK: semua dikembalikan ke normal"
}

cmd_sessions() {
    _n="${1:-20}"
    case "$_n" in ''|*[!0-9]*) _n=20 ;; esac
    [ -f "$STATE_DIR/sessions.log" ] && tail -n "$_n" "$STATE_DIR/sessions.log"
    return 0
}

cmd_health() {
    pidof uperf >/dev/null 2>&1 && echo uperf=1 || echo uperf=0
    pidof fas-rs >/dev/null 2>&1 && echo fasrs=1 || echo fasrs=0
    pid_alive "$STATE_DIR/monitor.pid" monitor.sh && echo monitor=1 || echo monitor=0
    pid_alive "$STATE_DIR/watchdog.pid" watchdog.sh && echo watchdog=1 || echo watchdog=0
    pid_alive "$STATE_DIR/autoctl.pid" autoctl.sh && echo auto=1 || echo auto=0
    [ -f "$STATE_DIR/BOOT_GUARD_OFF" ] && echo bootguard=0 || echo bootguard=1
    _bf=$(tr -cd '0-9' 2>/dev/null < "$STATE_DIR/.boot_fail_count"); echo "boot_fail=${_bf:-0}"
    [ -f "$STATE_DIR/.disable_tweaks" ] && echo disable_tweaks=1 || echo disable_tweaks=0
    printf 'ver=%s\n' "$(sed -n 's/^versionCode=//p' "$MODDIR/module.prop" 2>/dev/null | head -n 1)"
}

# Statistik frame dari fpsd.out: rata-rata FPS, 1% low, dan jeda terpanjang.
# Hanya baca berkas, tidak menjalankan apa pun ke perangkat.
diag_fps_stats() {
    [ -r "$1" ] || return 1
    _dfs_lat=$(sed -n 's/^lat=//p' "$1" 2>/dev/null | head -n 1)
    [ -n "$_dfs_lat" ] || return 1
    printf '%s\n' "$_dfs_lat" | awk '
        {
            n = 0
            for (i = 1; i <= NF; i++) { v = $i + 0; if (v > 0) { n++; t[n] = v } }
            if (n < 3) exit 1
            m = 0
            for (i = 2; i <= n; i++) { d = t[i] - t[i - 1]; if (d > 0) { m++; dt[m] = d } }
            if (m < 3) exit 1
            tot = 0
            for (i = 1; i <= m; i++) { tot += dt[i]; a[i] = dt[i] }
            for (i = 2; i <= m; i++) { k = a[i]; j = i - 1; while (j > 0 && a[j] > k) { a[j + 1] = a[j]; j-- } a[j + 1] = k }
            idx = int(m * 0.99); if (idx < 1) idx = 1; if (idx > m) idx = m
            printf "fps_avg=%d\nfps_p1=%d\nstall_ms=%d\nframes=%d\n", int(1000000000 * m / tot), int(1000000000 / a[idx]), int(a[m] / 1000000), m
        }'
}

cmd_diagnose() {
    _dg_cur=$(rd "$STATE_DIR/current_state"); [ -n "$_dg_cur" ] || _dg_cur=none
    _dg_act=$(rd "$STATE_DIR/active_profile"); [ -n "$_dg_act" ] || _dg_act=none
    echo "diag=1"
    printf 'ver=%s\n' "$(sed -n 's/^versionCode=//p' "$MODDIR/module.prop" 2>/dev/null | head -n 1)"
    printf 'profile=%s\nactive=%s\n' "$_dg_cur" "$_dg_act"

    if [ -r "$FASRS_NODE" ] || pidof fas-rs >/dev/null 2>&1; then
        echo cpu_owner=fas-rs
    else
        echo cpu_owner=hsin
    fi

    if [ -f "$STATE_DIR/.ovd_active" ]; then _dg_ovd=1; else _dg_ovd=0; fi
    printf 'ovd=%s\n' "$_dg_ovd"

    _dg_pkg=$(rd "$STATE_DIR/.gh_active")
    _dg_secs=0
    if [ -f "$STATE_DIR/.game_t0" ]; then
        read -r _dg_t0 _dg_gp < "$STATE_DIR/.game_t0" 2>/dev/null
        [ -n "$_dg_gp" ] && _dg_pkg=$_dg_gp
        _dg_now=$(uptime_secs)
        case "$_dg_t0" in
            ''|*[!0-9]*) ;;
            *) [ -n "$_dg_now" ] && _dg_secs=$((_dg_now - _dg_t0)) ;;
        esac
        [ "$_dg_secs" -ge 0 ] 2>/dev/null || _dg_secs=0
    fi
    printf 'game_pkg=%s\ngame_secs=%s\n' "${_dg_pkg:-none}" "$_dg_secs"

    _dg_soc=$(max_temp_mc); case "$_dg_soc" in ''|*[!0-9]*) _dg_soc=0 ;; esac
    _dg_bat=$(batt_temp_mc); case "$_dg_bat" in ''|*[!0-9]*) _dg_bat=0 ;; esac
    printf 'soc_temp_c=%s\n' "$((_dg_soc / 1000))"
    printf 'batt_temp_c=%s\n' "$((_dg_bat / 1000))"
    printf 'thermal_warm_c=%s\n' "$(cmd_thermal_get)"

    _dg_fs=$(rd "$STATE_DIR/fpsd.status")
    printf 'fps_src=%s\n' "${_dg_fs:-na}"
    diag_fps_stats "$STATE_DIR/fpsd.out" || printf 'fps_avg=na\nfps_p1=na\nstall_ms=na\nframes=0\n'

    if [ -r "$LOG_FILE" ]; then
        _dg_tail=$(tail -n 500 "$LOG_FILE" 2>/dev/null)
        printf 'apply_applied=%s\n' "$(printf '%s\n' "$_dg_tail" | grep -c '\[APPLIED\]')"
        printf 'apply_skipped=%s\n' "$(printf '%s\n' "$_dg_tail" | grep -c '\[SKIPPED\]')"
        printf 'apply_failed=%s\n' "$(printf '%s\n' "$_dg_tail" | grep -c '\[FAILED\]')"
    else
        printf 'apply_applied=na\napply_skipped=na\napply_failed=na\n'
    fi

    _dg_sl=$(tail -n 1 "$STATE_DIR/sessions.log" 2>/dev/null)
    printf 'sessions_last=%s\n' "${_dg_sl:-na}"

    _dg_warn=""
    # Lantai 20 FPS hanya untuk sesi game (keputusan #4). Aplikasi biasa yang sedang
    # di depan memang boleh lambat; jangan bikin peringatan palsu.
    _dg_p1=$(diag_fps_stats "$STATE_DIR/fpsd.out" 2>/dev/null | sed -n 's/^fps_p1=//p')
    if [ "${_dg_pkg:-none}" != none ]; then
        case "$_dg_p1" in
            ''|na) ;;
            *) [ "$_dg_p1" -lt 20 ] 2>/dev/null && _dg_warn="below_20_fps" ;;
        esac
    fi
    [ "$_dg_soc" -ge 100000 ] 2>/dev/null && _dg_warn="${_dg_warn:+$_dg_warn,}soc_hot"
    if [ "$_dg_ovd" = 1 ] && [ "$_dg_cur" != performance ]; then
        _dg_warn="${_dg_warn:+$_dg_warn,}ovd_profile_mismatch"
    fi
    printf 'warn=%s\n' "${_dg_warn:-none}"
    return 0
}

cmd_device() { [ -f "$STATE_DIR/detected.conf" ] && cat "$STATE_DIR/detected.conf"; return 0; }

# Beban adaptif semua aplikasi (adapt.sh): lihat apa yang modul pelajari.
cmd_adapt() {
    _ad="$STATE_DIR/adapt"
    case "$1" in
        ''|list)
            if [ -z "$(ls "$_ad"/*.conf 2>/dev/null)" ]; then
                echo "adapt=belum ada data (buka aplikasi sekali)"
                return 0
            fi
            for _f in "$_ad"/*.conf; do
                [ -f "$_f" ] || continue
                _p=${_f##*/}; _p=${_p%.conf}
                _cas=$(sed -n 's/^beban_cas=//p' "$_f" | tail -n 1)
                printf '%s beban=%s cas=%s sesi=%s p1_min=%s rata=%s fps=%s tersendat=%s%% stall=%sms terakhir=%s\n' \
                    "$_p" \
                    "$(sed -n 's/^beban=//p' "$_f" | tail -n 1)" \
                    "${_cas:--}" \
                    "$(sed -n 's/^sesi=//p' "$_f" | tail -n 1)" \
                    "$(sed -n 's/^p1_min=//p' "$_f" | tail -n 1)" \
                    "$(sed -n 's/^p1_avg=//p' "$_f" | tail -n 1)" \
                    "$(sed -n 's/^fps_avg=//p' "$_f" | tail -n 1)" \
                    "$(sed -n 's/^jank_pct=//p' "$_f" | tail -n 1)" \
                    "$(sed -n 's/^stall_max=//p' "$_f" | tail -n 1)" \
                    "$(sed -n 's/^terakhir=//p' "$_f" | tail -n 1)"
            done
            ;;
        get) [ -n "$2" ] && cat "$_ad/$2.conf" 2>/dev/null ;;
        reset) rm -rf "$_ad" 2>/dev/null; echo "OK: data adaptasi dihapus, beban awal dari DEVICE_TIER" ;;
        own)
            case "$2" in
                on)  rm -f "$STATE_DIR/ADAPT_OWN"; echo "OK: Adapt memegang frekuensi saat game (berlaku di sesi berikutnya)" ;;
                off) printf 'off\n' > "$STATE_DIR/ADAPT_OWN"; echo "OK: Adapt tidak memegang frekuensi (tabel profil + gameboost, berlaku di sesi berikutnya)" ;;
                ''|get) [ "$(rd "$STATE_DIR/ADAPT_OWN")" = "off" ] && echo "adapt_own=off" || echo "adapt_own=on" ;;
                *) echo "Usage: hsinctl adapt own [on|off|get]"; return 1 ;;
            esac ;;
        *) echo "Usage: hsinctl adapt [list|get <paket>|reset|own on|off]"; return 1 ;;
    esac
}

# engine mode freeze|off: freeze (bawaan) = uperf/fas-rs dibekukan hanya selama Adapt/Puncak memegang
# frekuensi. off = dibekukan permanen dan tidak dijalankan saat boot, sampai diubah kembali.
cmd_engine() {
    case "$1" in
        mode)
            case "$2" in
                off)
                    printf 'off\n' > "$STATE_DIR/ENGINE_MODE"
                    for _ep in $(pidof uperf fas-rs 2>/dev/null); do kill -STOP "$_ep" 2>/dev/null; done
                    echo "OK: uperf dan fas-rs dibekukan permanen (engine_mode=off)" ;;
                freeze)
                    rm -f "$STATE_DIR/ENGINE_MODE"
                    # lanjutkan kecuali Adapt/Puncak sedang memegang (mereka yang melanjutkan saat selesai)
                    if [ ! -f "$STATE_DIR/.adapt_own" ] && [ ! -f "$STATE_DIR/.ovd_stopped" ]; then
                        for _ep in $(pidof uperf fas-rs 2>/dev/null); do kill -CONT "$_ep" 2>/dev/null; done
                    fi
                    echo "OK: uperf dan fas-rs normal di luar game (engine_mode=freeze); jika tidak jalan, mulai ulang HP" ;;
                ''|get) [ "$(rd "$STATE_DIR/ENGINE_MODE")" = "off" ] && echo "engine_mode=off" || echo "engine_mode=freeze" ;;
                *) echo "Usage: hsinctl engine mode [freeze|off|get]"; return 1 ;;
            esac ;;
        *) echo "Usage: hsinctl engine mode [freeze|off|get]"; return 1 ;;
    esac
}

cmd_redetect() {
    rm -f "$STATE_DIR/detected.conf" 2>/dev/null
    HSIN_FORCE_DETECT=1 sh "$COMMON/detect.sh" >/dev/null 2>&1
    cmd_device
}

cmd_autoctl() {
    case "$1" in
        start)
            if pid_alive "$STATE_DIR/autoctl.pid" autoctl.sh; then echo "OK: sudah jalan"; return 0; fi
            rm -f "$STATE_DIR/autoctl.pid" 2>/dev/null
            HSIN_STATE_DIR="$STATE_DIR" nohup sh "$COMMON/autoctl.sh" >> "$LOG_FILE" 2>&1 &
            echo "OK: autoctl start pid=$!"
            ;;
        stop)
            if pid_alive "$STATE_DIR/autoctl.pid" autoctl.sh; then
                kill "$(tr -d '[:space:]' < "$STATE_DIR/autoctl.pid")" 2>/dev/null
            fi
            rm -f "$STATE_DIR/autoctl.pid" 2>/dev/null
            echo "OK: autoctl stop"
            ;;
        status) pid_alive "$STATE_DIR/autoctl.pid" autoctl.sh && echo 1 || echo 0 ;;
        *) echo "Usage: autoctl start|stop|status"; return 1 ;;
    esac
}

cmd_log() {
    _n="${1:-300}"
    case "$_n" in ''|*[!0-9]*) _n=300 ;; esac
    [ "$_n" -le 3000 ] || _n=3000
    [ -f "$LOG_FILE" ] && tail -n "$_n" "$LOG_FILE"
    return 0
}

# Frame pacing/prediction: default mati di system.prop. Keputusan #57 minta uji
# A/B dulu, jadi ada sakelar runtime (bukan ubah system.prop + reboot).
cmd_framepacing() {
    _fp_cfg="$STATE_DIR/app.conf"
    _fp_cur=$(getprop vendor.perf.framepacing.enable 2>/dev/null)
    case "$1" in
        on|off)
            [ "$1" = "on" ] && _fp=1 || _fp=0
            touch "$_fp_cfg" 2>/dev/null
            grep -v '^FRAMEPACING=' "$_fp_cfg" > "$_fp_cfg.tmp.$$" 2>/dev/null
            printf 'FRAMEPACING=%s\n' "$_fp" >> "$_fp_cfg.tmp.$$"
            mv -f "$_fp_cfg.tmp.$$" "$_fp_cfg" 2>/dev/null
            if [ "$_fp" = "1" ]; then _fp_v=true; else _fp_v=false; fi
            if command -v resetprop >/dev/null 2>&1; then
                resetprop vendor.perf.framepacing.enable "$_fp_v" 2>/dev/null
                resetprop persist.sys.framepredict.enable "$_fp_v" 2>/dev/null
            else
                setprop vendor.perf.framepacing.enable "$_fp_v" 2>/dev/null
                setprop persist.sys.framepredict.enable "$_fp_v" 2>/dev/null
            fi
            echo "OK: framepacing=$1 (aktif=$(getprop vendor.perf.framepacing.enable 2>/dev/null), bertahan setelah reboot)"
            ;;
        status|'')
            _fp_saved=$(sed -n 's/^FRAMEPACING=//p' "$_fp_cfg" 2>/dev/null | tail -n 1 | tr -d '[:space:]')
            printf 'framepacing=%s\nframepredict=%s\ntersimpan=%s\n' \
                "${_fp_cur:-na}" "$(getprop persist.sys.framepredict.enable 2>/dev/null || echo na)" "${_fp_saved:-0}"
            ;;
        *) echo "Usage: hsinctl framepacing on|off|status"; return 1 ;;
    esac
}

cmd_tweak() {
    command -v tw_apply_profile >/dev/null 2>&1 || { echo "ERROR: tweaks.sh tidak ada"; return 1; }
    case "$1" in
        caps) tw_caps_ensure; cat "$TW_CAPS" 2>/dev/null ;;
        list|status) tw_list ;;
        get)
            [ -n "$2" ] || { echo "Usage: tweak get <KEY>"; return 1; }
            tw_list | sed -n "s/^$2=//p"
            ;;
        set)
            [ -n "$2" ] || { echo "Usage: tweak set <KEY> <VAL>"; return 1; }
            tw_set_global "$2" "$3"
            ;;
        reset) tw_reset ;;
        unset) tw_unset "$2" ;;
        over) sed -n 's/^TW_\([A-Z_]*\)=\(.*\)/\1=\2/p' "$TW_CONF" 2>/dev/null ;;
        profile) tw_apply_profile "$2" ;;
        *) echo "Usage: tweak caps|list|over|get <KEY>|set <KEY> <VAL>|unset <KEY>|reset|profile <mode>"; return 1 ;;
    esac
}

cmd_gamefps() {
    case "$1" in
        get)
            valid_pkg "$2" || { echo "ERROR: package tidak valid"; return 1; }
            printf 'fps=%s\n' "$(gh_opt_get "$2" fps off)"
            printf 'hz=%s\n' "$(gh_opt_get "$2" HZ default)"
            ;;
        set)
            valid_pkg "$2" || { echo "ERROR: package tidak valid"; return 1; }
            tw_game_fps "$2" "$3"
            ;;
        *) echo "Usage: gamefps get <pkg> | set <pkg> <10-240|off>"; return 1 ;;
    esac
}

case "$1" in
    status) cmd_status ;;
    profile) cmd_profile "$2" ;;
    flag) cmd_flag "$2" "$3" ;;
    flags) cmd_flags ;;
    conf)
        case "$2" in
            get) conf_get "$3" "$4"; echo ;;
            set) conf_set "$3" "$4" ;;
            all) [ -f "$CONF_FILE" ] && cat "$CONF_FILE" ;;
            *) echo "Usage: conf get <KEY> [def] | conf set <KEY> <VAL> | conf all"; exit 1 ;;
        esac
        ;;
    thermal) cmd_thermal "$2" "$3" ;;
    games) cmd_games ;;
    game) cmd_game "$2" "$3" "$4" "$5" ;;
    sessions) cmd_sessions "$2" ;;
    health) cmd_health ;;
    diagnose) cmd_diagnose ;;
    device) cmd_device ;;
    adapt) cmd_adapt "$2" "$3" ;;
    engine) cmd_engine "$2" "$3" ;;
    redetect) cmd_redetect ;;
    render) sh "$COMMON/render_manager.sh" "$2" "$3" ;;
    gamerender) cmd_gamerender "$2" "$3" "$4" ;;
    gameopt) cmd_gameopt "$2" "$3" "$4" "$5" ;;
    ovd) cmd_ovd "$2" "$3" ;;
    logexport) cmd_logexport ;;
    mem) cmd_mem "$2" ;;
    mglru) cmd_mglru "$2" ;;
    memclean) cmd_memclean "$2" ;;
    refresh) cmd_refresh "$2" "$3" ;;
    hud) cmd_hud "$2" "$3" ;;
    charge) sh "$COMMON/charge.sh" "$2" "$3" ;;
    freeze) cmd_freeze "$2" "$3" ;;
    rec) sh "$COMMON/screenrec.sh" "$2" "$3" ;;
    autoctl) cmd_autoctl "$2" ;;
    renderrestore) _gh_render_restore; [ -f "$GH_REND_PREV" ] && echo "pending: $(cat "$GH_REND_PREV")" || echo "OK: tidak ada penanda; renderer=$(getprop debug.hwui.renderer)" ;;
    features) gh_caps; mf_caps ;;
    livecheck) sh "$COMMON/livecheck.sh" ;;
    trim) sh "$COMMON/trim.sh" "$2" ;;
    gameauto) cmd_gameauto "$2" "$3" "$4" "$5" ;;
    gamepreset) cmd_gamepreset "$2" "$3" "$4" ;;
    gamefx) cmd_gamefx "$2" "$3" "$4" "$5" ;;
    gamefps) cmd_gamefps "$2" "$3" "$4" ;;
    tweak) cmd_tweak "$2" "$3" "$4" ;;
    framepacing) cmd_framepacing "$2" ;;
    mitigation) cmd_mitigation "$2" "$3" "$4" ;;
    shield) shift; sh "$COMMON/shield.sh" "$@" ;;
    bugreport) sh "$COMMON/bugreport.sh" ;;
    log) cmd_log "$2" ;;
    restore) cmd_restore ;;
    saran) cmd_saran "$2" "$3" ;;
    cfgbackup) cmd_cfgbackup ;;
    cfgrestore) cmd_cfgrestore "$2" ;;
    modinfo) cat "$MODDIR/module.prop" ;;
    *) sed -n '2,42p' "$0" ;;
esac
