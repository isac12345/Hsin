#!/system/bin/sh
# HSIN v5 daemon: pengaman panas + profil per game. Dimulai oleh service.sh setelah boot stabil.
MODDIR=${0%/*}
. "$MODDIR/core/lib.sh" || exit 0

tick() {
    [ -f "$SAFEF" ] && return 0
    if [ "$(cfg_get thermal 1)" = 1 ] && [ ! -f "$TRIPF" ]; then
        _lim=$(cfg_get thermal_limit 90); isint "$_lim" || _lim=90
        read_temps
        if [ "$T_CPU" -ge "$_lim" ]; then thermal_trip "$T_CPU" "$_lim"; fi
    fi
    if [ -f "$TRIPF" ]; then return 0; fi
    if [ "$(cfg_get game_mode 0)" = 1 ]; then
        if fg_game; then
            _cur=$(rd "$ACTF")
            if [ -n "$FG_PKG" ]; then
                if [ "$_cur" != "$FG_PKG" ]; then
                    [ -n "$_cur" ] && game_restore "$_cur"
                    game_apply "$FG_PKG"
                    printf '%s\n' "$FG_PKG" > "$ACTF"
                fi
            elif [ -n "$_cur" ]; then
                game_restore "$_cur"
                rm -f "$ACTF"
            fi
        fi
    elif [ -f "$ACTF" ]; then
        game_restore "$(rd "$ACTF")"
        rm -f "$ACTF"
    fi
}

if [ "${HSIN_ONESHOT:-0}" = 1 ]; then tick; exit 0; fi
while :; do
    tick
    if [ "$(cfg_get game_mode 0)" = 1 ]; then sleep 3; else sleep 10; fi
done
