#!/system/bin/sh
# ============================================================
# core/apply_engines.sh - UNIFIED SEQUENTIAL PIPELINE
# Pipeline apply SATU-SATUNYA untuk SEMUA path:
#   - action.sh bg job (manual apply + boost revert)
#   - monitor.sh (game boost + revert)
# Engine dijalankan SEQUENTIAL (satu per satu) - tidak ada subshell
# `&` + `wait`. Pola paralel diuji di v4.0 lama dan menyebabkan:
#   - trap yang salah diwarisi subshell
#   - staleness check gak jalan di toybox
#   - race antar engine yang nulis ke sysfs node overlap
#     (contoh: GPU apply & thermal-apply-gpu sama-sama nulis
#     ke /sys/class/devfreq/*/max_freq di waktu yang sama)
# Display/render + DVFS di-apply LIVE (sebelumnya cuma pas boot).
# Gate ALLOW_EXTREME konsisten di semua jalur.
# Semua engine guard internal (skip halus kalau node nggak ada).
#
# Pemakaian: hsin_apply_all_engines <profile> [prev_profile] [unused] [source]
#   source="boost" -> SF props-only (aman pas game jalan); renderer &
#   downscale DILEWATI (restart app/UI - nggak aman di tengah game).
# Note: 3rd arg (thermal_mode) is kept for backward compat but ignored.
# Thermal policy is now driven by the profile name itself.
# ============================================================

hsin_apply_all_engines() {
    _p="${1:-balanced}"
    _prev="${2:-none}"
    _src="${4:-manual}"
    _failed=0

    if [ "$_p" = "extreme" ] && [ "${ALLOW_EXTREME:-${HSIN_ALLOW_EXTREME:-false}}" != "true" ]; then
        echo "SKIP: extreme requires explicit ALLOW_EXTREME=true" >> "$HSIN_DATA/logs/debug.log" 2>/dev/null
        return 1
    fi

    # Extreme is intentionally available on rooted installs.
    # Thermal safety remains vendor/kernel-controlled; this pipeline does not
    # silently downgrade the user's selected performance profile.

    . "$HSIN_MODULE_PATH/core/logger.sh" 2>/dev/null
    . "$HSIN_MODULE_PATH/core/backup.sh" 2>/dev/null
    . "$HSIN_MODULE_PATH/core/state_manager.sh" 2>/dev/null
    . "$HSIN_MODULE_PATH/core/profile_loader.sh" 2>/dev/null

    # PATCH v4.0: timing instrumentation - biar kelihatan fase mana yang
    # nyedot waktu di tiap device (baca APPLY-TIME di debug.log).
    _now_ms() { date +%s%3N 2>/dev/null; }
    _t0=$(_now_ms); _tp=$_t0
    _mark() { _tn=$(_now_ms); echo "APPLY-TIME: $1 $(( _tn - _tp ))ms (total $(( _tn - _t0 ))ms)" >> "$HSIN_DATA/logs/debug.log" 2>/dev/null; _tp=$_tn; }

    # --- FIX (game-mode stuck-at-extreme bug) ---
    # Kalau profil SEBELUMNYA adalah extreme dan target BUKAN extreme,
    # restore extreme harus jalan DI SINI, SEBELUM grup A (cpu/gpu/thermal)
    # menerapkan profil target. Urutan lama menaruh extreme-restore di
    # akhir fungsi (setelah grup A/B/C + wait), jadi nilai gov/freq/GPU
    # dari backup extreme lama MENIMPA hasil hsin_cpu_apply/hsin_gpu_apply
    # untuk profil yang baru dipilih (mis. balanced) - itulah kenapa CPU
    # governor & frequency kelihatan "nyangkut" di extreme setiap keluar
    # dari game padahal profil sudah balik ke pilihan manual user.
    # Dengan restore dijalankan lebih dulu, hasil akhir sysfs adalah
    # output hsin_cpu_apply/hsin_gpu_apply "$_p" (grup A di bawah), yang
    # memang seharusnya menang.
    if [ "$_p" != "extreme" ] && [ "$_prev" = "extreme" ]; then
        . "$HSIN_MODULE_PATH/extreme/safety_monitor.sh" 2>/dev/null
        hsin_safety_monitor_stop >> "$HSIN_DATA/logs/debug.log" 2>&1

        . "$HSIN_MODULE_PATH/extreme/restore_extreme.sh" 2>/dev/null
        hsin_extreme_restore >> "$HSIN_DATA/logs/debug.log" 2>&1
        _mark "extreme-restore(pre-groupA)"
    fi

    # Full snapshots are needed for manual/profile changes, but game-boost
    # transitions can happen repeatedly. Avoid disk-heavy snapshots on the
    # boost hot path; the next manual apply/boot still refreshes the backup.
    if [ "$_src" != "boost" ]; then
        hsin_backup_all >/dev/null 2>&1
        _mark "backup"
    else
        _mark "backup-skip(boost)"
    fi

    # Resolve thermal mode + display/render vars SEKALI (dipakai grup A-C).
    # Profile thermal policy is authoritative. The thermal engine receives the
    # PROFILE NAME (battery/balanced/performance/extreme), not a separate
    # THERMAL_MODE value. This ensures hsin_thermal_apply()'s case statement
    # matches correctly and battery/balanced get aggressive thermal protection
    # (react from warm/hot), performance only reacts at critical, and extreme
    # leaves it to the safety monitor. The old THERMAL_MODE variable could
    # pass "safe" (from battery/balanced confs) which matched NO case →
    # thermal protection became a complete no-op.
    if command -v hsin_profile_load >/dev/null 2>&1; then
        hsin_profile_load "$_p" 2>/dev/null
    fi
    _dvfs_en="false"; _dvfs_cpu="100"; _dvfs_gpu="100"
    _rr_en="false"; _rr_red="false"; _rr_force="false"
    _rr_peak="120"; _rr_min="60"
    _frl_dis="false"; _sf_en="false"
    if command -v hsin_profile_get >/dev/null 2>&1; then
        _dvfs_en="$(hsin_profile_get dvfs enabled 2>/dev/null)"
        _dvfs_cpu="$(hsin_profile_get dvfs cpu_limit 2>/dev/null)"
        _dvfs_gpu="$(hsin_profile_get dvfs gpu_limit 2>/dev/null)"
        _rr_en="$(hsin_profile_get global_rr enabled 2>/dev/null)"
        _rr_red="$(hsin_profile_get global_rr reduced 2>/dev/null)"
        _rr_force="$(hsin_profile_get global_rr force 2>/dev/null)"
        _rr_peak="$(hsin_profile_get global_rr peak_hz 2>/dev/null)"
        _rr_min="$(hsin_profile_get global_rr min_hz 2>/dev/null)"
        _frl_dis="$(hsin_profile_get frame_limit disabled 2>/dev/null)"
        _sf_en="$(hsin_profile_get surfaceflinger enabled 2>/dev/null)"
    fi

    # ================= ENGINE APPLY: SEQUENTIAL (one by one) =================
    # NO subshells, NO & — each engine runs in the main process so traps,
    # sysfs writes, and variable state are all predictable.

    . "$HSIN_MODULE_PATH/engine/cpu/apply.sh" 2>/dev/null
    hsin_cpu_apply "$_p" 2>/dev/null || _failed=$((_failed + 1))
    _mark "cpu-apply"

    . "$HSIN_MODULE_PATH/engine/gpu/apply.sh" 2>/dev/null
    hsin_gpu_apply "$_p" 2>/dev/null || _failed=$((_failed + 1))
    _mark "gpu-apply"

    . "$HSIN_MODULE_PATH/engine/thermal/apply.sh" 2>/dev/null
    hsin_thermal_engine_apply "$_p" 2>/dev/null || _failed=$((_failed + 1))
    _mark "thermal-apply"

    . "$HSIN_MODULE_PATH/engine/memory/apply.sh" 2>/dev/null
    hsin_memory_apply "$_p" 2>/dev/null || _failed=$((_failed + 1))
    _mark "memory-apply"

    . "$HSIN_MODULE_PATH/engine/io/io_manager.sh" 2>/dev/null
    hsin_io_apply "$_p" 2>/dev/null || _failed=$((_failed + 1))
    _mark "io-apply"

    . "$HSIN_MODULE_PATH/engine/network/network_manager.sh" 2>/dev/null
    hsin_network_apply "$_p" 2>/dev/null || _failed=$((_failed + 1))
    _mark "network-apply"

    if [ "$_dvfs_en" = "true" ]; then
        . "$HSIN_MODULE_PATH/engine/gpu/dvfs.sh" 2>/dev/null
        hsin_dvfs_apply "${_dvfs_cpu:-100}" "${_dvfs_gpu:-100}" >/dev/null 2>&1 || _failed=$((_failed + 1))
    fi
    _mark "dvfs-apply"

    # Display/render: settings provider + props independen dari sysfs.
    # SF tetap props-only (aman saat game foreground; *_live yang restart
    # SF sengaja tidak dipakai).
    . "$HSIN_MODULE_PATH/engine/display/refresh_rate.sh" 2>/dev/null
    if [ "$_rr_en" = "true" ]; then
        if [ "$_rr_red" = "true" ]; then
            hsin_refresh_reduced_apply "${_rr_peak:-120}" "${_rr_force:-false}" >/dev/null 2>&1 || _failed=$((_failed + 1))
        else
            hsin_refresh_set_range "${_rr_peak:-120}" "${_rr_min:-60}" "${_rr_force:-false}" >/dev/null 2>&1 || _failed=$((_failed + 1))
        fi
    fi
    . "$HSIN_MODULE_PATH/engine/display/frame_limit.sh" 2>/dev/null
    if [ "$_frl_dis" = "true" ]; then
        hsin_frame_limit_disable >/dev/null 2>&1 || _failed=$((_failed + 1))
    else
        hsin_frame_limit_restore >/dev/null 2>&1 || _failed=$((_failed + 1))
    fi
    . "$HSIN_MODULE_PATH/engine/render/surfaceflinger.sh" 2>/dev/null
    hsin_sf_apply_boot "$_sf_en" >/dev/null 2>&1 || _failed=$((_failed + 1))
    _mark "display+render-apply"

    # ================= Extreme wiring (sequential, sama seperti semula) ======
    if [ "$_p" = "extreme" ]; then
        . "$HSIN_MODULE_PATH/extreme/frequency_unlock.sh" 2>/dev/null
        hsin_extreme_freq_backup >/dev/null 2>&1
        hsin_extreme_freq_apply >> "$HSIN_DATA/logs/debug.log" 2>&1

        . "$HSIN_MODULE_PATH/extreme/gpu_override.sh" 2>/dev/null
        hsin_extreme_gpu_detect >/dev/null 2>&1
        hsin_extreme_gpu_backup >/dev/null 2>&1
        hsin_extreme_gpu_apply >> "$HSIN_DATA/logs/debug.log" 2>&1

        . "$HSIN_MODULE_PATH/extreme/thermal_override.sh" 2>/dev/null
        hsin_extreme_thermal_apply "extreme" >> "$HSIN_DATA/logs/debug.log" 2>&1

        mkdir -p "$HSIN_DATA/logs" 2>/dev/null
        touch "$HSIN_DATA/extreme_active" 2>/dev/null
        echo "$(date '+%Y-%m-%d %H:%M:%S') [EXTREME] Aggressive overrides applied" >> "$HSIN_DATA/logs/extreme.log" 2>/dev/null

        . "$HSIN_MODULE_PATH/extreme/safety_monitor.sh" 2>/dev/null
        hsin_safety_monitor_stop >/dev/null 2>&1
        if command -v setsid >/dev/null 2>&1; then
            setsid sh -c ". \"$HSIN_MODULE_PATH/extreme/safety_monitor.sh\"; hsin_safety_monitor_start" </dev/null >> "$HSIN_DATA/logs/extreme.log" 2>&1 &
        elif [ -x /data/adb/ksu/bin/busybox ]; then
            /data/adb/ksu/bin/busybox setsid sh -c ". \"$HSIN_MODULE_PATH/extreme/safety_monitor.sh\"; hsin_safety_monitor_start" </dev/null >> "$HSIN_DATA/logs/extreme.log" 2>&1 &
        else
            sh -c ". \"$HSIN_MODULE_PATH/extreme/safety_monitor.sh\"; hsin_safety_monitor_start" </dev/null >> "$HSIN_DATA/logs/extreme.log" 2>&1 &
        fi
    fi
    # (catatan: cabang "prev=extreme, target!=extreme" sudah ditangani DI
    # ATAS, sebelum grup A, supaya tidak menimpa hasil cpu/gpu apply.)

    _mark "extreme-wiring+done"
    echo "APPLY_RESULT failed=$_failed" >> "$HSIN_DATA/logs/debug.log" 2>/dev/null
    [ "$_failed" -eq 0 ]
}
