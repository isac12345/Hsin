#!/system/bin/sh
# HSIN - Monitor (monitor.sh)

HSIN_DATA="${HSIN_DATA:-/data/adb/hsin}"
HSIN_MONITOR_LOG="$HSIN_DATA/logs/monitor.log"
HSIN_MONITOR_INTERVAL="${HSIN_MONITOR_INTERVAL:-10}"
HSIN_PROFILE_FILE="$HSIN_DATA/current_profile"

hsin_monitor_loop() {
    _last_profile=""
    _last_pkg=""
    # Module path is passed in via the nohup env; keep it stable.
    HSIN_MODULE_PATH="${HSIN_MODULE_PATH:-/data/adb/modules/hsin}"
    export HSIN_MODULE_PATH
    HSIN_CONF="${HSIN_CONF:-/sdcard/Android/hsin/hsin.conf}"
    while :; do
        # Stop jika service diminta stop (file flag)
        [ -f "$HSIN_DATA/.monitor.stop" ] && break

        # Re-read GAM_BOOST_ENABLED directly from config every iteration so
        # a WebUI toggle takes effect without reboot/restart of the monitor.
        _gam="false"
        if [ -f "$HSIN_CONF" ]; then
            while IFS='=' read -r _ck _cv || [ -n "$_ck" ]; do
                [ "$_ck" = "GAM_BOOST_ENABLED" ] && { _gam="${_cv:-false}"; break; }
            done < "$HSIN_CONF"
        fi

        # Global refresh rate re-apply (only when GLOBAL_RR_FORCE=true - some
        # ROMs silently revert peak/min_refresh_rate on screen-on/doze-exit,
        # so force mode needs a periodic re-assert instead of a one-shot
        # boot apply). Every 6th iteration (~1 min at default 10s interval)
        # to avoid hammering the settings provider on every tick.
        _rr_iter=$(( ${_rr_iter:-0} + 1 ))
        if [ $((_rr_iter % 6)) -eq 0 ] && [ -f "$HSIN_CONF" ]; then
            _rr_enabled="false"; _rr_force="false"; _rr_reduced="false"
            _rr_peak="120"; _rr_min="60"
            while IFS='=' read -r _ck _cv || [ -n "$_ck" ]; do
                case "$_ck" in
                    GLOBAL_RR_ENABLED) _rr_enabled="${_cv:-false}" ;;
                    GLOBAL_RR_FORCE) _rr_force="${_cv:-false}" ;;
                    GLOBAL_RR_REDUCED) _rr_reduced="${_cv:-false}" ;;
                    GLOBAL_RR_PEAK_HZ) _rr_peak="${_cv:-120}" ;;
                    GLOBAL_RR_MIN_HZ) _rr_min="${_cv:-60}" ;;
                esac
            done < "$HSIN_CONF"
            if [ "$_rr_enabled" = "true" ] && [ "$_rr_force" = "true" ]; then
                . "$HSIN_MODULE_PATH/engine/display/refresh_rate.sh" 2>/dev/null
                if [ "$_rr_reduced" = "true" ]; then
                    hsin_refresh_reduced_apply "$_rr_peak" "true" >/dev/null 2>&1
                else
                    hsin_refresh_set_range "$_rr_peak" "$_rr_min" "true" >/dev/null 2>&1
                fi
            fi
        fi

        _profile="unknown"
        [ -f "$HSIN_PROFILE_FILE" ] && read -r _profile < "$HSIN_PROFILE_FILE" 2>/dev/null

        # Skip logging jika profile belum di-apply
        [ "$_profile" = "unknown" ] && sleep "$HSIN_MONITOR_INTERVAL" && continue

        # Sampling
        _ts=$(date '+%H:%M:%S')
        _cur_freq=""
        read -r _cur_freq < /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq 2>/dev/null
        _gov=""
        read -r _gov < /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null
        _temp_max=0
        for z in /sys/class/thermal/thermal_zone*/temp; do
            [ -f "$z" ] || continue
            _t=""
            read -r _t < "$z" 2>/dev/null
            [ -n "$_t" ] && [ "$_t" -gt "$_temp_max" ] 2>/dev/null && _temp_max="$_t"
        done
        # Kalau temp 0, fallback ke cpu_thermal kalau ada
        if [ "$_temp_max" -eq 0 ] 2>/dev/null && [ -f /sys/class/thermal/thermal_zone0/temp ]; then
            read -r _temp_max < /sys/class/thermal/thermal_zone0/temp 2>/dev/null
        fi
        _temp_c=0
        [ -n "$_temp_max" ] && [ "$_temp_max" -gt 0 ] 2>/dev/null && _temp_c=$((_temp_max / 1000))

        echo "[$_ts][$_profile] gov=$_gov freq=$_cur_freq temp=${_temp_c}C" >> "$HSIN_MONITOR_LOG"

        # Throttle detection: jika scaling_cur_freq anjlok dari max
        _max=""
        read -r _max < /sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq 2>/dev/null
        if [ -n "$_max" ] && [ "$_max" -gt 0 ]; then
            _ratio=$(( _cur_freq * 100 / _max ))
            if [ "$_ratio" -lt 50 ]; then
                echo "[$_ts][$_profile] THROTTLE freq=${_cur_freq}/${_max} (${_ratio}%)" >> "$HSIN_MONITOR_LOG"
            fi
        fi

        # Game auto-boost check - also runs here (not just in action.sh)
        # so the WebUI doesn't have to be open. _gam is re-read from
        # hsin.conf above each iteration so toggles take effect immediately.
        if [ "$_gam" = "true" ]; then
            . "${HSIN_MODULE_PATH:-/data/adb/modules/hsin}/engine/game/detector.sh" 2>/dev/null
            . "${HSIN_MODULE_PATH:-/data/adb/modules/hsin}/engine/game/game_manager.sh" 2>/dev/null
            . "${HSIN_MODULE_PATH:-/data/adb/modules/hsin}/core/state_manager.sh" 2>/dev/null
            . "${HSIN_MODULE_PATH:-/data/adb/modules/hsin}/core/logger.sh" 2>/dev/null
            . "${HSIN_MODULE_PATH:-/data/adb/modules/hsin}/core/policy_engine.sh" 2>/dev/null
            _cur_pkg=$(hsin_game_detect 2>/dev/null)
            _cur_pkg=$(printf '%s' "$_cur_pkg" | tr -d '\r\n')
            # Only treat _cur_pkg as "game" if it actually qualifies:
            # listed in games.conf OR has "game" in the package name
            # (same check as hsin_game_is_running in detector.sh).
            # Non-game foreground apps are treated as empty so they
            # never trigger boost or notifications.
            if [ -n "$_cur_pkg" ]; then
                _hsin_is_game=1
                hsin_game_is_known "$_cur_pkg" 2>/dev/null && _hsin_is_game=0
                if [ "$_hsin_is_game" -ne 0 ]; then
                    case "$_cur_pkg" in
                        *game*|*Game*|*GAME*) _hsin_is_game=0 ;;
                    esac
                fi
                if [ "$_hsin_is_game" -ne 0 ]; then
                    _cur_pkg=""
                fi
            fi
            _last_pkg_stored=""
            [ -f "$HSIN_DATA/.last_game_pkg" ] && read -r _last_pkg_stored < "$HSIN_DATA/.last_game_pkg" 2>/dev/null
            _last_pkg_stored=$(printf '%s' "$_last_pkg_stored" | tr -d '\r\n')
            if [ "$_cur_pkg" != "$_last_pkg_stored" ] && [ -n "$_cur_pkg" ]; then
                # PATCH v4.2: bersihin sisa grace timer kalau game balik lagi
                rm -f "$HSIN_DATA/.game_boost_grace" 2>/dev/null
                # Game appeared. Determine base profile from hsin.conf
                # (NOT state.lock - state.lock has the boosted value from
                # the previous game, not what the user actually picked).
                _base="balanced"
                _conf="/sdcard/Android/hsin/hsin.conf"
                if [ -f "$_conf" ]; then
                    while IFS='=' read -r _ck _cv || [ -n "$_ck" ]; do
                        [ "$_ck" = "PROFILE" ] && { _base="${_cv:-balanced}"; break; }
                    done < "$_conf"
                fi
                case "$_base" in
                    battery|balanced|performance|extreme) ;;
                    *) _base="balanced" ;;
                esac
                _eff=$(hsin_game_effective_profile "$_base" "$_cur_pkg" 2>/dev/null)
                [ -z "$_eff" ] && _eff="$_base"
                # Policy check: game-boost must respect the same safety
                # constraints as manual apply (thermal panic → battery,
                # battery saver → balanced, stability → battery). Without
                # this, a game mapped to extreme could force it even when
                # the device is already at thermal-warning/critical.
                hsin_policy_check "engine" "$_eff" >/dev/null 2>&1 || _eff="$HSIN_POLICY_ACTIVE_PROFILE"
                # Extreme is intentionally available on rooted installs.
                # The extreme backend preserves OEM/kernel thermal protection.
                if [ "$_eff" != "$_base" ]; then
                    printf '%s' "$_base" > "$HSIN_DATA/.game_boost_state" 2>/dev/null
                    hsin_state_init 2>/dev/null
                    hsin_state_profile "$_eff" 2>/dev/null
                    echo "$_eff" > "$HSIN_PROFILE_FILE" 2>/dev/null
                    hsin_notify "HSIN" "Game boost: $_cur_pkg -> $_eff" 2>/dev/null
                    # PATCH v4.3: pipeline unified via core/apply_engines.sh
                    # (thermal + display/render + DVFS ikut, sama kayak
                    # action.sh - sebelumnya subshell ini tanpa thermal).
                    (
                        HSIN_MODULE_PATH="${HSIN_MODULE_PATH:-/data/adb/modules/hsin}"
                        . "${HSIN_MODULE_PATH}/core/apply_engines.sh" 2>/dev/null
                        hsin_apply_all_engines "$_eff" "$_base" "" "boost"
                    ) &
                fi
                printf '%s' "$_cur_pkg" > "$HSIN_DATA/.last_game_pkg" 2>/dev/null
            elif [ "$_cur_pkg" != "$_last_pkg_stored" ] && [ -z "$_cur_pkg" ]; then
                # PATCH v4.2: GRACE PERIOD (mirrors action.sh). Tanpa ini,
                # tiap foreground berubah sebentar pas main (notif shade,
                # recents, buka WebUI) langsung revert -> profile flip-flop.
                _grace_file="$HSIN_DATA/.game_boost_grace"
                _grace_seconds="${HSIN_GAME_BOOST_GRACE_SECONDS:-12}"
                _now_g=$(date +%s 2>/dev/null)
                _do_revert=1
                if [ ! -f "$_grace_file" ]; then
                    printf '%s' "$_now_g" > "$_grace_file" 2>/dev/null
                    _do_revert=0
                else
                    _gs=""
                    read -r _gs < "$_grace_file" 2>/dev/null
                    case "$_gs" in ''|*[!0-9]*) _gs="$_now_g" ;; esac
                    [ $(( _now_g - _gs )) -lt "$_grace_seconds" ] && _do_revert=0
                fi
                if [ "$_do_revert" -eq 1 ]; then
                rm -f "$_grace_file" 2>/dev/null
                    # Game disappeared. Revert to base profile.
                    _revert=""
                    [ -f "$HSIN_DATA/.game_boost_state" ] && read -r _revert < "$HSIN_DATA/.game_boost_state" 2>/dev/null
                    _revert=$(printf '%s' "$_revert" | tr -d '\r\n')
                    if [ -n "$_revert" ]; then
                        _hsin_prev_prof="$(grep "^ACTIVE_PROFILE=" "$HSIN_DATA/state.lock" 2>/dev/null | cut -d= -f2)"
                        [ -z "$_hsin_prev_prof" ] && _hsin_prev_prof="none"
                        # Policy check on revert too: even the base profile
                        # might need downgrading if device conditions changed
                        # while the game was running (e.g. thermal climbed).
                        hsin_policy_check "engine" "$_revert" >/dev/null 2>&1 || _revert="$HSIN_POLICY_ACTIVE_PROFILE"
                        hsin_state_profile "$_revert" 2>/dev/null
                        echo "$_revert" > "$HSIN_PROFILE_FILE" 2>/dev/null
                        rm -f "$HSIN_DATA/.game_boost_state" 2>/dev/null
                        hsin_notify "HSIN" "Game closed, back to $_revert" 2>/dev/null
                            (
                                HSIN_MODULE_PATH="${HSIN_MODULE_PATH:-/data/adb/modules/hsin}"
                                . "${HSIN_MODULE_PATH}/core/apply_engines.sh" 2>/dev/null
                                hsin_apply_all_engines "$_revert" "$_hsin_prev_prof" "" "boost"
                            ) &
                    fi
                    printf '%s' "" > "$HSIN_DATA/.last_game_pkg" 2>/dev/null
                fi
                fi
        fi

        sleep "$HSIN_MONITOR_INTERVAL"
    done
}

hsin_monitor_start() {
    hsin_log_info "monitor" "Starting monitor loop (interval=${HSIN_MONITOR_INTERVAL}s)"
    nohup sh -c "HSIN_DATA='${HSIN_DATA}' HSIN_MODULE_PATH='${HSIN_MODULE_PATH:-/data/adb/modules/hsin}'; . '${HSIN_MODULE_PATH:-/data/adb/modules/hsin}/core/monitor.sh'; hsin_monitor_loop" \
        >/dev/null 2>&1 &
    # Tulis PID
    echo $! > "$HSIN_DATA/monitor.pid" 2>/dev/null
}

hsin_monitor_stop() {
    touch "$HSIN_DATA/.monitor.stop" 2>/dev/null
    if [ -f "$HSIN_DATA/monitor.pid" ]; then
        _mpid=""
        read -r _mpid < "$HSIN_DATA/monitor.pid" 2>/dev/null
        [ -n "$_mpid" ] && kill "$_mpid" 2>/dev/null
        rm -f "$HSIN_DATA/monitor.pid"
    fi
    hsin_log_info "monitor" "Monitor stopped"
}

return 0 2>/dev/null || true
