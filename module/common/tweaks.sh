#!/system/bin/sh
# HSIN - tweaks: fitur global (bukan per game) yang belum ditangani engine.
# Library (di-source), bukan CLI. Pintu CLI ada di hsinctl.sh: "tweak ...".
#
# Kategori (dipakai UI): display, perf, tools.
#   display : refresh, night_light, font_scale, density
#   perf    : turbo, mali, thermal_trip, cpuidle
#   tools   : dac_gain, bypass_charging, led
#
# Scan kemampuan device SEKALI (device_profile.env). Apply hanya membaca hasil scan.
# Per game TIDAK ditangani di sini; opsi per game tetap di gamehooks/gamefx.

TW_STATE="${HSIN_STATE_DIR:-/data/adb/hsin}"
TW_CAPS="$TW_STATE/device_profile.env"
TW_CONF="$TW_STATE/tweaks.conf"
TW_ORIG="$TW_STATE/.tweaks_orig"
TW_LOG="${HSIN_LOG_FILE:-$TW_STATE/hsin.log}"

tw_rd() { [ -r "$1" ] && tr -d '\r\n' < "$1" 2>/dev/null; }
tw_num() { case "$1" in ''|*[!0-9]*) return 1 ;; *) return 0 ;; esac; }
tw_wr() { [ -e "$1" ] || return 1; printf '%s\n' "$2" > "$1" 2>/dev/null; }
tw_log() { printf '[%s] [TWEAK] [%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date)" "$1" "$2" >> "$TW_LOG" 2>/dev/null; }

tw_has() {
    [ -f "$TW_CAPS" ] || return 1
    _th=$(sed -n "s/^$1=//p" "$TW_CAPS" 2>/dev/null | tail -n 1)
    [ "$_th" = "1" ]
}

# ---------------------------------------------------------------- scan sekali
tw_caps_scan() {
    mkdir -p "$TW_STATE" 2>/dev/null
    _tmp="$TW_CAPS.tmp.$$"
    {
        echo "# HSIN device capability - di-scan sekali, jangan diedit manual"
        echo "CAPS_VER=2"
        echo "# $(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date)"
        printf 'SOC=%s\n' "$(getprop ro.board.platform 2>/dev/null)"
        printf 'ANDROID=%s\n' "$(getprop ro.build.version.release 2>/dev/null)"

        if command -v settings >/dev/null 2>&1; then echo "HAS_SETTINGS=1"; else echo "HAS_SETTINGS=0"; fi
        echo "HAS_REFRESH=1"
        _maxhz=60
        command -v dumpsys >/dev/null 2>&1 && _maxhz=$(dumpsys display 2>/dev/null | grep -oE 'fps=[0-9]+' | cut -d= -f2 | sort -n | tail -n 1)
        tw_num "$_maxhz" || _maxhz=60
        printf 'REFRESH_MAX=%s\n' "$_maxhz"

        if command -v tinymix >/dev/null 2>&1 && tinymix -D 0 >/dev/null 2>&1; then echo "HAS_AUDIO_MIXER=1"; else echo "HAS_AUDIO_MIXER=0"; fi
        if [ -w /sys/class/leds/sc27xx:red/brightness ]; then echo "HAS_LED=1"; else echo "HAS_LED=0"; fi
        if [ -w /sys/kernel/turbo/common/turbo_enable ]; then echo "HAS_TURBO=1"; else echo "HAS_TURBO=0"; fi
        if [ -w /sys/module/mali_kbase/parameters/gpu_boost_level2 ]; then echo "HAS_MALI=1"; else echo "HAS_MALI=0"; fi

        _z=/sys/class/thermal/thermal_zone0
        if [ -w "$_z/trip_point_0_temp" ]; then
            echo "HAS_TRIP=1"
            printf 'TRIP0=%s\n' "$(tw_rd "$_z/trip_point_0_temp")"
            printf 'TRIP1=%s\n' "$(tw_rd "$_z/trip_point_1_temp")"
        else
            echo "HAS_TRIP=0"
        fi

        if [ -w /sys/devices/system/cpu/cpu6/cpuidle/state1/disable ]; then echo "HAS_CPUIDLE=1"; else echo "HAS_CPUIDLE=0"; fi
        if settings get global game_bypass_charging >/dev/null 2>&1; then echo "HAS_BYPASS=1"; else echo "HAS_BYPASS=0"; fi

        _sc=""
        for _n in /sys/class/power_supply/*/stop_chg /sys/devices/platform/*/stop_chg; do
            [ -w "$_n" ] && { _sc=$_n; break; }
        done
        if [ -n "$_sc" ]; then
            echo "HAS_STOPCHG=1"
            printf 'STOPCHG_NODE=%s\n' "$_sc"
        else
            echo "HAS_STOPCHG=0"
        fi

        if settings get secure night_display_activated >/dev/null 2>&1; then echo "HAS_NIGHT=1"; else echo "HAS_NIGHT=0"; fi
        if command -v wm >/dev/null 2>&1; then echo "HAS_WM=1"; else echo "HAS_WM=0"; fi
    } > "$_tmp" 2>/dev/null && mv -f "$_tmp" "$TW_CAPS" 2>/dev/null
    chmod 600 "$TW_CAPS" 2>/dev/null
    tw_log SCAN "device_profile.env diperbarui"
}

tw_caps_ensure() {
    if [ ! -f "$TW_CAPS" ] || ! grep -q '^CAPS_VER=2$' "$TW_CAPS" 2>/dev/null; then
        tw_caps_scan
    fi
}

# ---------------------------------------------------------------- penulis nilai
tw_refresh_set() {
    _hz="$1"; tw_num "$_hz" || return 0
    [ "$_hz" -ge 30 ] && [ "$_hz" -le 240 ] || return 0
    _mx=$(sed -n 's/^REFRESH_MAX=//p' "$TW_CAPS" 2>/dev/null | tail -n 1)
    tw_num "$_mx" && [ "$_hz" -gt "$_mx" ] && _hz="$_mx"
    settings put system peak_refresh_rate "$_hz" >/dev/null 2>&1
    settings put system min_refresh_rate "$_hz" >/dev/null 2>&1
    settings put system tran_refresh_mode "$_hz" >/dev/null 2>&1
    _sz=$(wm size 2>/dev/null | sed -n 's/.*: //p' | tail -n 1)
    _w=${_sz%x*}; _h=${_sz#*x}
    if tw_num "$_w" && tw_num "$_h"; then
        cmd display set-user-preferred-display-mode "$_w" "$_h" "$_hz" >/dev/null 2>&1
    fi
}

tw_dac_set() {
    _v="$1"; tw_num "$_v" || return 0
    [ "$_v" -ge 0 ] && [ "$_v" -le 127 ] || return 0
    command -v tinymix >/dev/null 2>&1 || return 0
    _id=$(tinymix -D 0 2>/dev/null | awk '/VBC DAC0 DG Set/{print $1; exit}')
    tw_num "$_id" || return 0
    tinymix -D 0 "$_id" "$_v" "$_v" >/dev/null 2>&1
}

tw_mali_set() { # $1=boost $2=poll $3=upthreshold
    _mm=/sys/module/mali_kbase/parameters
    tw_num "$1" && tw_wr "$_mm/gpu_boost_level2" "$1"
    tw_num "$2" && tw_wr "$_mm/gpu_pollingtime" "$2"
    tw_num "$3" && tw_wr "$_mm/gpu_upthreshold" "$3"
}

tw_trip_set() { # $1=offset derajat (0 atau 10000)
    _off="$1"; tw_num "$_off" || return 0
    _z=/sys/class/thermal/thermal_zone0
    [ -f "$TW_ORIG" ] || {
        printf 'TRIP0=%s\nTRIP1=%s\n' "$(tw_rd "$_z/trip_point_0_temp")" "$(tw_rd "$_z/trip_point_1_temp")" > "$TW_ORIG" 2>/dev/null
    }
    _b0=$(sed -n 's/^TRIP0=//p' "$TW_ORIG" 2>/dev/null)
    _b1=$(sed -n 's/^TRIP1=//p' "$TW_ORIG" 2>/dev/null)
    tw_num "$_b0" || _b0=70000
    tw_num "$_b1" || _b1=85000
    tw_wr "$_z/trip_point_0_temp" "$((_b0 + _off))"
    tw_wr "$_z/trip_point_1_temp" "$((_b1 + _off))"
}

tw_idle_set() { # $1=0/1
    _v="$1"; tw_num "$_v" || return 0
    for _c in 6 7; do
        tw_wr "/sys/devices/system/cpu/cpu$_c/cpuidle/state1/disable" "$_v"
    done
}

tw_bypass_set() { settings put global game_bypass_charging "$1" >/dev/null 2>&1; }
tw_night_set() { settings put secure night_display_activated "$1" >/dev/null 2>&1; }
tw_turbo_set() { tw_wr /sys/kernel/turbo/common/turbo_enable "$1"; }
tw_font_set() { settings put system font_scale "$1" >/dev/null 2>&1; }
tw_density_set() { wm density "$1" >/dev/null 2>&1; }

tw_led_set() { # $1=off|red|green|blue
    case "$1" in
        off) for _c in red green blue; do tw_wr "/sys/class/leds/sc27xx:$_c/brightness" 0; done ;;
        red|green|blue)
            _l="/sys/class/leds/sc27xx:$1"
            _mx=$(tw_rd "$_l/max_brightness"); tw_num "$_mx" || _mx=1
            tw_wr "$_l/brightness" "$_mx" ;;
    esac
}

tw_mali_set_str() { # $1=boost:poll:up (satu string, divalidasi lalu dipecah)
    case "$1" in ''|*[!0-9:]*|*:*:*:*) return 1 ;; esac
    _a=${1%%:*}; _rest=${1#*:}; _b=${_rest%%:*}; _c=${_rest#*:}
    [ -n "$_a" ] && [ -n "$_b" ] && [ -n "$_c" ] || return 1
    tw_mali_set "$_a" "$_b" "$_c"
}

tw_conf_get() { sed -n "s/^TW_$1=//p" "$TW_CONF" 2>/dev/null | tail -n 1; }

# ---------------------------------------------------------------- profil
# Nilai default per profil. thermal_trip TIDAK otomatis di Puncak: harus
# diaktifkan user lewat Performance (risiko overheat).
# $2=force: terapkan refresh walau game aktif (dipakai Puncak saat game tidak punya Hz sendiri).
tw_apply_profile() {
    _p="$1"; _force="$2"
    case "$_p" in battery|balanced|performance|peak) ;; *) return 0 ;; esac
    tw_caps_ensure

    case "$_p" in
        battery)     _r=60;  _d=28; _t=0; _m="0:8:88" ;;
        balanced)    _r=90;  _d=28; _t=0; _m="0:8:88" ;;
        performance) _r=120; _d=32; _t=0; _m="50:4:90" ;;
        peak)        _r=144; _d=36; _t=1; _m="100:1:100" ;;
    esac

    # Baca override tanpa source file (tidak ada variabel bocor / eksekusi shell).
    _v=$(tw_conf_get REFRESH_HZ); [ -n "$_v" ] && _r="$_v"
    _v=$(tw_conf_get DAC_GAIN);  [ -n "$_v" ] && _d="$_v"
    _v=$(tw_conf_get TURBO);     [ -n "$_v" ] && _t="$_v"
    _v=$(tw_conf_get MALI);      [ -n "$_v" ] && _m="$_v"

    # Refresh per mode; saat game aktif refresh dipegang gamehooks.
    if command -v settings >/dev/null 2>&1 && { [ "$_force" = force ] || [ ! -f "$TW_STATE/.gh_active" ]; }; then tw_refresh_set "$_r"; fi
    tw_has HAS_AUDIO_MIXER && tw_dac_set "$_d"
    tw_has HAS_TURBO && tw_turbo_set "$_t"
    tw_has HAS_MALI && tw_mali_set_str "$_m"

    _v=$(tw_conf_get NIGHT);      [ -n "$_v" ] && tw_night_set "$_v"
    _v=$(tw_conf_get FONT_SCALE); [ -n "$_v" ] && tw_font_set "$_v"
    _v=$(tw_conf_get DENSITY);    [ -n "$_v" ] && tw_density_set "$_v"
    _v=$(tw_conf_get LED);        [ -n "$_v" ] && tw_led_set "$_v"
    _v=$(tw_conf_get BYPASS);     [ -n "$_v" ] && tw_bypass_set "$_v"
    _v=$(tw_conf_get CPUIDLE);    [ -n "$_v" ] && tw_idle_set "$_v"

    # Thermal trip hanya kalau user menyalakannya (default 0), dengan batas aman.
    _tr=$(tw_conf_get TRIP)
    tw_num "$_tr" && [ "$_tr" -gt 0 ] && [ "$_tr" -le 20000 ] && tw_has HAS_TRIP && tw_trip_set "$_tr"

    tw_log APPLIED "profile=$_p refresh=$_r dac=$_d turbo=$_t mali=$_m"
}

# ---------------------------------------------------------------- status
tw_list() {
    tw_caps_ensure
    printf 'display_refresh=%s\n' "$(settings get system peak_refresh_rate 2>/dev/null | tr -d '\r\n')"
    printf 'display_night=%s\n' "$(settings get secure night_display_activated 2>/dev/null | tr -d '\r\n')"
    printf 'display_font_scale=%s\n' "$(settings get system font_scale 2>/dev/null | tr -d '\r\n')"
    printf 'display_density=%s\n' "$(wm density 2>/dev/null | sed -n 's/Override density: //p' | tail -n 1)"
    printf 'perf_turbo=%s\n' "$(tw_rd /sys/kernel/turbo/common/turbo_enable)"
    printf 'perf_mali=%s:%s:%s\n' "$(tw_rd /sys/module/mali_kbase/parameters/gpu_boost_level2)" "$(tw_rd /sys/module/mali_kbase/parameters/gpu_pollingtime)" "$(tw_rd /sys/module/mali_kbase/parameters/gpu_upthreshold)"
    printf 'perf_trip=%s\n' "$(tw_rd /sys/class/thermal/thermal_zone0/trip_point_0_temp)"
    printf 'perf_cpuidle=%s\n' "$(tw_rd /sys/devices/system/cpu/cpu6/cpuidle/state1/disable)"
    printf 'tools_dac=%s\n' "$(tinymix -D 0 2>/dev/null | awk '/VBC DAC0 DG Set/{print $NF; exit}')"
    printf 'tools_bypass=%s\n' "$(settings get global game_bypass_charging 2>/dev/null | tr -d '\r\n')"
    sed -n 's/^\(HAS_[A-Z_]*\)=\(.*\)/\1=\2/p' "$TW_CAPS" 2>/dev/null
}

tw_set_global() { # $1=KEY $2=VALUE
    _k="$1"; _v="$2"
    case "$_v" in *[!A-Za-z0-9._,:-]*) echo "ERROR: nilai tidak valid"; return 1 ;; esac
    case "$_k" in
        display_refresh)
            tw_num "$_v" && [ "$_v" -ge 30 ] && [ "$_v" -le 240 ] || { echo "ERROR: refresh 30-240"; return 1; } ;;
        display_night|tools_bypass|perf_turbo|perf_cpuidle)
            case "$_v" in 0|1) ;; *) echo "ERROR: $_k = 0|1"; return 1 ;; esac ;;
        display_font_scale)
            tw_num "${_v%%.*}" || { echo "ERROR: font_scale angka"; return 1; } ;;
        display_density)
            case "$_v" in reset) ;; ''|*[!0-9]*) echo "ERROR: density = reset|angka"; return 1 ;; esac ;;
        perf_trip)
            tw_num "$_v" && [ "$_v" -ge 0 ] && [ "$_v" -le 20000 ] || { echo "ERROR: trip 0-20000"; return 1; } ;;
        perf_mali)
            case "$_v" in *:*:*) ;; *) echo "ERROR: mali=boost:poll:up"; return 1 ;; esac ;;
        tools_dac)
            tw_num "$_v" && [ "$_v" -ge 0 ] && [ "$_v" -le 127 ] || { echo "ERROR: dac 0-127"; return 1; } ;;
        tools_led)
            case "$_v" in off|red|green|blue) ;; *) echo "ERROR: led = off|red|green|blue"; return 1 ;; esac ;;
        *) echo "ERROR: KEY tidak dikenal"; return 1 ;;
    esac

    # nama variabel di tweaks.conf
    case "$_k" in
        display_refresh) _sk=REFRESH_HZ ;;
        display_night) _sk=NIGHT ;;
        display_font_scale) _sk=FONT_SCALE ;;
        display_density) _sk=DENSITY ;;
        perf_turbo) _sk=TURBO ;;
        perf_mali) _sk=MALI ;;
        perf_trip) _sk=TRIP ;;
        perf_cpuidle) _sk=CPUIDLE ;;
        tools_dac) _sk=DAC_GAIN ;;
        tools_bypass) _sk=BYPASS ;;
        tools_led) _sk=LED ;;
    esac

    touch "$TW_CONF" 2>/dev/null || { echo "ERROR: gagal tulis tweaks.conf"; return 1; }
    grep -v "^TW_${_sk}=" "$TW_CONF" > "$TW_CONF.tmp.$$" 2>/dev/null
    printf 'TW_%s=%s\n' "$_sk" "$_v" >> "$TW_CONF.tmp.$$"
    mv -f "$TW_CONF.tmp.$$" "$TW_CONF" 2>/dev/null || { echo "ERROR: gagal simpan"; return 1; }
    chmod 600 "$TW_CONF" 2>/dev/null

    case "$_k" in
        display_refresh)
            tw_refresh_set "$_v" ;;
        display_night) tw_night_set "$_v" ;;
        display_font_scale) tw_font_set "$_v" ;;
        display_density)
            case "$_v" in reset) wm density reset >/dev/null 2>&1 ;; *) tw_density_set "$_v" ;; esac ;;
        perf_turbo) tw_turbo_set "$_v" ;;
        perf_mali) tw_mali_set_str "$_v" ;;
        perf_trip) if [ "$_v" = 0 ]; then tw_trip_restore; else tw_trip_set "$_v"; fi ;;
        perf_cpuidle) tw_idle_set "$_v" ;;
        tools_dac) tw_dac_set "$_v" ;;
        tools_bypass) tw_bypass_set "$_v" ;;
        tools_led) tw_led_set "$_v" ;;
    esac
    echo "OK: $_k=$_v"
}

# Nilai bawaan untuk tweak yang tidak dipegang profil: dikembalikan langsung saat override dihapus.
tw_default_of() {
    case "$1" in
        NIGHT) tw_night_set 0 ;;
        FONT_SCALE) tw_font_set 1.0 ;;
        DENSITY) wm density reset >/dev/null 2>&1 ;;
        LED) tw_led_set off ;;
        BYPASS) tw_bypass_set 0 ;;
        CPUIDLE) tw_idle_set 0 ;;
        TRIP) tw_trip_restore ;;
    esac
}

tw_trip_restore() {
    [ -s "$TW_ORIG" ] || return 0
    _z=/sys/class/thermal/thermal_zone0
    _b0=$(sed -n 's/^TRIP0=//p' "$TW_ORIG" 2>/dev/null)
    _b1=$(sed -n 's/^TRIP1=//p' "$TW_ORIG" 2>/dev/null)
    tw_num "$_b0" && tw_wr "$_z/trip_point_0_temp" "$_b0"
    tw_num "$_b1" && tw_wr "$_z/trip_point_1_temp" "$_b1"
}

# Hapus satu override (kembali ke nilai otomatis per profil).
tw_unset() {
    case "$1" in
        display_refresh) _sk=REFRESH_HZ ;; display_night) _sk=NIGHT ;; display_font_scale) _sk=FONT_SCALE ;;
        display_density) _sk=DENSITY ;; perf_turbo) _sk=TURBO ;; perf_mali) _sk=MALI ;; perf_trip) _sk=TRIP ;;
        perf_cpuidle) _sk=CPUIDLE ;; tools_dac) _sk=DAC_GAIN ;; tools_bypass) _sk=BYPASS ;; tools_led) _sk=LED ;;
        *) echo "ERROR: KEY tidak dikenal"; return 1 ;;
    esac
    [ -f "$TW_CONF" ] && { grep -v "^TW_${_sk}=" "$TW_CONF" > "$TW_CONF.tmp.$$" 2>/dev/null; mv -f "$TW_CONF.tmp.$$" "$TW_CONF" 2>/dev/null; chmod 600 "$TW_CONF" 2>/dev/null; }
    tw_default_of "$_sk"
    _p=$(sed -n '1p' "$TW_STATE/active_profile" 2>/dev/null | tr -d '[:space:]')
    case "$_p" in battery|balanced|performance|peak) ;; *) _p=balanced ;; esac
    tw_apply_profile "$_p"
    echo "OK: $1 otomatis"
}

tw_reset() {
    for _rk in $(sed -n 's/^TW_\([A-Z_]*\)=.*/\1/p' "$TW_CONF" 2>/dev/null); do
        tw_default_of "$_rk"
    done
    rm -f "$TW_CONF" 2>/dev/null
    # kembalikan trip thermal ke nilai asli kalau pernah dinaikkan
    if [ -s "$TW_ORIG" ]; then
        _z=/sys/class/thermal/thermal_zone0
        _b0=$(sed -n 's/^TRIP0=//p' "$TW_ORIG" 2>/dev/null)
        _b1=$(sed -n 's/^TRIP1=//p' "$TW_ORIG" 2>/dev/null)
        tw_num "$_b0" && tw_wr "$_z/trip_point_0_temp" "$_b0"
        tw_num "$_b1" && tw_wr "$_z/trip_point_1_temp" "$_b1"
        rm -f "$TW_ORIG" 2>/dev/null
    fi
    # terapkan lagi profil yang sedang aktif supaya nilai live ikut kembali
    _p=$(sed -n '1p' "$TW_STATE/active_profile" 2>/dev/null | tr -d '[:space:]')
    case "$_p" in battery|balanced|performance|peak) ;; *) _p=balanced ;; esac
    tw_apply_profile "$_p"
    echo "OK: override global dihapus (kembali ke nilai profil $_p)"
}

# ---------------------------------------------------------------- fps gabung
# Satu nilai FPS untuk game: batas FPS (gamefx) + refresh layar (gameopt HZ).
# Nilai bebas 10..240; "off" menghapus keduanya.
tw_game_fps() {
    _pkg="$1"; _fps="$2"
    command -v gh_opt_set >/dev/null 2>&1 || { echo "ERROR: gamehooks tidak tersedia"; return 1; }
    case "$_fps" in
        off|default)
            gh_opt_set "$_pkg" fps off >/dev/null 2>&1
            gh_opt_set "$_pkg" HZ default >/dev/null 2>&1
            echo "OK: $_pkg fps=off"; return 0 ;;
    esac
    tw_num "$_fps" && [ "$_fps" -ge 10 ] && [ "$_fps" -le 240 ] || { echo "ERROR: fps 10-240 atau off"; return 1; }
    gh_opt_set "$_pkg" fps "$_fps" >/dev/null 2>&1
    # refresh layar tidak bisa di atas REFRESH_MAX; di bawah 30 Hz tidak didukung, jadi ikut sistem.
    _hz="$_fps"
    _max=$(sed -n 's/^REFRESH_MAX=//p' "$TW_CAPS" 2>/dev/null | tail -n 1)
    tw_num "$_max" && [ "$_hz" -gt "$_max" ] && _hz="$_max"
    if [ "$_hz" -ge 30 ]; then
        gh_opt_set "$_pkg" HZ "$_hz" >/dev/null 2>&1
    else
        gh_opt_set "$_pkg" HZ default >/dev/null 2>&1
        _hz=off
    fi
    echo "OK: $_pkg fps=$_fps hz=$_hz"
}
