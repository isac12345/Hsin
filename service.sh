#!/system/bin/sh
# HSIN Service Script
# Credit: HSIN engine foundation evolved from RaiRin

MODPATH="${0%/*}"
HSIN_ID="hsin"
HSIN_DATA="/data/adb/${HSIN_ID}"
HSIN_USER="/sdcard/Android/${HSIN_ID}"
HSIN_LOG_DIR="$HSIN_DATA/logs"
HSIN_LOG_FILE="$HSIN_LOG_DIR/hsin.log"
HSIN_FLAG_DIR="$HSIN_DATA/flags"
HSIN_MODULE_PATH="$MODPATH"

# Export untuk library
export HSIN_DATA HSIN_USER HSIN_LOG_DIR HSIN_LOG_FILE HSIN_MODULE_PATH

# Logger awal (gunakan path absolut, karena service.sh dijalankan sebelum PATH lengkap)
mkdir -p "$HSIN_LOG_DIR"
export HSIN_LOG_LEVEL="${HSIN_LOG_LEVEL:-3}"

# shellcheck disable=SC1091
. "$MODPATH/core/logger.sh"

# PATCH v4.0: bersihkan log tiap boot (permintaan user - debug.log numpuk
# hampir 1 juta baris karena spam poll). Truncate, bukan rotate: bukti
# debugging sesi sebelumnya jarang dibutuhkan, dan boot.log ditulis ulang
# dari nol di sesi ini juga.
for _hsin_boot_log in "$HSIN_DATA"/logs/debug.log "$HSIN_DATA"/logs/monitor.log \
                      "$HSIN_DATA"/logs/boot.log "$HSIN_DATA"/logs/apply.log \
                      "$HSIN_DATA"/logs/error.log; do
    [ -f "$_hsin_boot_log" ] && : > "$_hsin_boot_log" 2>/dev/null
done
rm -f "$HSIN_DATA"/logs/*.old 2>/dev/null

# 1. Tunggu boot complete
hsin_log_info "main" "Waiting for boot_completed..."
while [ "$(getprop sys.boot_completed)" != "1" ]; do
    sleep 1
done
sleep 2  # Beri waktu sysfs stabil

# 2. Load config user
HSIN_CONF="$HSIN_USER/hsin.conf"
[ -f "$HSIN_CONF" ] || HSIN_CONF="$MODPATH/config/hsin.conf"

HSIN_PROFILE="balanced"
HSIN_ALLOW_EXTREME="false"
HSIN_LOG_LEVEL="3"
HSIN_MONITOR_INTERVAL="15"
HSIN_GAM_ENABLED="false"
HSIN_DOWNSCALE_ENABLED="false"
HSIN_DOWNSCALE_PERCENT="30"
HSIN_REFRESH_LOCK_ENABLED="false"
HSIN_REFRESH_LOCK_HZ="120"
HSIN_GLOBAL_RR_ENABLED="false"
HSIN_GLOBAL_RR_REDUCED="false"
HSIN_GLOBAL_RR_FORCE="false"
HSIN_GLOBAL_RR_PEAK_HZ="120"
HSIN_GLOBAL_RR_MIN_HZ="60"
HSIN_ADVANCED_DVFS_ENABLED="false"
HSIN_ADVANCED_DVFS_CPU_LIMIT="100"
HSIN_ADVANCED_DVFS_GPU_LIMIT="100"
HSIN_FRAME_RATE_LIMIT_DISABLED="false"
HSIN_SURFACEFLINGER_TWEAK_ENABLED="false"

if [ -f "$HSIN_CONF" ]; then
    # Parse simple KEY=VALUE (skip comments and empty lines)
    while IFS='=' read -r key value; do
        case "$key" in
            ''|'#'*) continue ;;
        esac
        case "$key" in
            PROFILE) HSIN_PROFILE="$value" ;;
            ALLOW_EXTREME) HSIN_ALLOW_EXTREME="$value" ;;
            LOG_LEVEL) HSIN_LOG_LEVEL="$value" ;;
            MONITOR_INTERVAL) HSIN_MONITOR_INTERVAL="$value" ;;
            GAM_BOOST_ENABLED) HSIN_GAM_ENABLED="$value" ;;
            DOWNSCALE_ENABLED) HSIN_DOWNSCALE_ENABLED="$value" ;;
            DOWNSCALE_PERCENT) HSIN_DOWNSCALE_PERCENT="$value" ;;
            REFRESH_LOCK_ENABLED) HSIN_REFRESH_LOCK_ENABLED="$value" ;;
            REFRESH_LOCK_HZ) HSIN_REFRESH_LOCK_HZ="$value" ;;
            GLOBAL_RR_ENABLED) HSIN_GLOBAL_RR_ENABLED="$value" ;;
            GLOBAL_RR_REDUCED) HSIN_GLOBAL_RR_REDUCED="$value" ;;
            GLOBAL_RR_FORCE) HSIN_GLOBAL_RR_FORCE="$value" ;;
            GLOBAL_RR_PEAK_HZ) HSIN_GLOBAL_RR_PEAK_HZ="$value" ;;
            GLOBAL_RR_MIN_HZ) HSIN_GLOBAL_RR_MIN_HZ="$value" ;;
            ADVANCED_DVFS_ENABLED) HSIN_ADVANCED_DVFS_ENABLED="$value" ;;
            ADVANCED_DVFS_CPU_LIMIT) HSIN_ADVANCED_DVFS_CPU_LIMIT="$value" ;;
            ADVANCED_DVFS_GPU_LIMIT) HSIN_ADVANCED_DVFS_GPU_LIMIT="$value" ;;
            FRAME_RATE_LIMIT_DISABLED) HSIN_FRAME_RATE_LIMIT_DISABLED="$value" ;;
            SURFACEFLINGER_TWEAK_ENABLED) HSIN_SURFACEFLINGER_TWEAK_ENABLED="$value" ;;
        esac
    done < "$HSIN_CONF"
fi
export HSIN_PROFILE HSIN_ALLOW_EXTREME
export HSIN_LOG_LEVEL HSIN_MONITOR_INTERVAL

# Watermark + integrity check
. "$MODPATH/core/protect.sh" 2>/dev/null
if ! command -v hsin_protect_watermark >/dev/null 2>&1; then
    hsin_log_error "main" "core/protect.sh missing or tampered - refusing to run"
    exit 1
fi
hsin_protect_integrity_full || { hsin_log_error "main" "Integrity check failed - refusing to run"; exit 1; }

# Android 13+ requires this runtime permission for shell-posted notifications
# to actually display (hsin_notify re-grants it too, but doing it once here
# at boot means it's already in place before the first notification fires).
command -v cmd >/dev/null 2>&1 && cmd package grant com.android.shell android.permission.POST_NOTIFICATIONS >/dev/null 2>&1

# Copy the WebUI's optional notification icon (if you've added one under
# webroot/) to a world-readable location on external storage - the
# notification renderer can't read files under /data/adb, so it has to be
# staged somewhere public first. Re-copied every boot so replacing the file
# in webroot/ takes effect on next reboot without any extra steps.
# Reliable fallback for the default user config: customize.sh tries to
# write this too, but it runs at FLASH time when /sdcard often isn't
# mounted yet (a well-known Magisk/KernelSU install-script gotcha), so the
# copy can silently fail. Doing it again here means it will definitely
# succeed on the first real boot after install, since storage is always
# up by the time service.sh runs.
mkdir -p "$HSIN_USER" 2>/dev/null
if [ ! -f "$HSIN_USER/hsin.conf" ] && [ -f "$MODPATH/config/hsin.conf" ]; then
    cp "$MODPATH/config/hsin.conf" "$HSIN_USER/hsin.conf" 2>/dev/null
    chmod 0644 "$HSIN_USER/hsin.conf" 2>/dev/null
fi

HSIN_NOTIF_ICON_DST="/storage/emulated/0/Android/media/.hsin/notif_icon.png"
for _ext in png jpg jpeg; do
    _src=""
    if [ -f "$MODPATH/webroot/notif_icon.$_ext" ]; then
        _src="$MODPATH/webroot/notif_icon.$_ext"
    elif [ -f "$MODPATH/webroot/assets/notif_icon.$_ext" ]; then
        _src="$MODPATH/webroot/assets/notif_icon.$_ext"
    fi
    if [ -n "$_src" ]; then
        mkdir -p "$(dirname "$HSIN_NOTIF_ICON_DST")" 2>/dev/null
        cp -f "$_src" "$HSIN_NOTIF_ICON_DST" 2>/dev/null
        chmod 644 "$HSIN_NOTIF_ICON_DST" 2>/dev/null
        break
    fi
done
hsin_protect_watermark

# 3. Validasi profile
case "$HSIN_PROFILE" in
    battery|balanced|performance|extreme) ;;
    *) HSIN_PROFILE="balanced" ;;
esac

# Extreme is intentionally available on rooted installs. It remains
# aggressive, but HSIN never disables the kernel/OEM thermal safety chain.
HSIN_EXTREME_OK="true"
export HSIN_EXTREME_OK
if [ "$HSIN_PROFILE" = "extreme" ]; then
    if [ "$HSIN_ALLOW_EXTREME" != "true" ]; then
        hsin_log_warn "main" "Extreme requested without opt-in; falling back to performance"
        HSIN_PROFILE="performance"
    else
        hsin_log_warn "main" "EXTREME mode active - native thermal protection preserved"
    fi
fi

hsin_log_section "HSIN Service Boot"
hsin_log_info "main" "Profile: $HSIN_PROFILE"
hsin_log_info "main" "Extreme opt-in: $HSIN_ALLOW_EXTREME"
hsin_log_info "main" "Game boost: $HSIN_GAM_ENABLED"

# Tulis profile aktif untuk monitor
echo "$HSIN_PROFILE" > "$HSIN_DATA/current_profile" 2>/dev/null

# 3b. System-wide display downscale. Capture native res + density
# unconditionally (no-op after the first successful boot), then
# re-apply both overrides every boot if the feature is enabled - the
# kernel/SurfaceFlinger does NOT remember `wm size`/`wm density` across
# a reboot, so without this the device would silently pop back to
# native on every restart.
. "$MODPATH/engine/display/downscale.sh" 2>/dev/null
if command -v hsin_downscale_capture_native >/dev/null 2>&1; then
    hsin_downscale_capture_native
    if [ "$HSIN_DOWNSCALE_ENABLED" = "true" ]; then
        if hsin_downscale_apply "$HSIN_DOWNSCALE_PERCENT"; then
            hsin_log_ok "main" "Display downscale re-applied: $(hsin_downscale_calc_target "$HSIN_DOWNSCALE_PERCENT" 2>/dev/null) @ $(hsin_downscale_calc_density "$HSIN_DOWNSCALE_PERCENT" 2>/dev/null)dpi (${HSIN_DOWNSCALE_PERCENT}%)"
        else
            hsin_log_error "main" "Display downscale enabled but native res not yet known (first boot?)"
        fi
    fi
fi

# 3c. Refresh rate lock. Settings.System keys normally survive reboot on
# their own, but some OEM display-tuning services re-assert their own
# adaptive-refresh values at boot, so we defensively re-apply every boot
# the same way downscale does above - harmless no-op if nothing changed it.
. "$MODPATH/engine/display/refresh_rate.sh" 2>/dev/null
if [ "$HSIN_REFRESH_LOCK_ENABLED" = "true" ] && command -v hsin_refresh_lock >/dev/null 2>&1; then
    _applied_hz="$(hsin_refresh_lock "$HSIN_REFRESH_LOCK_HZ")"
    if [ -n "$_applied_hz" ]; then
        hsin_log_ok "main" "Refresh rate locked: ${_applied_hz}Hz (requested ${HSIN_REFRESH_LOCK_HZ}Hz)"
    else
        hsin_log_error "main" "Refresh rate lock enabled but could not apply (no settings/cmd binary?)"
    fi
fi

# 3d-3g. Fitur baru (global RR, DVFS limiter, frame limit, SF tweak) otomatis
# ikut profil aktif ($HSIN_PROFILE) lewat profiles/*.conf - user gak perlu
# atur manual per fitur. hsin.conf tetap bisa override kalau user memang
# eksplisit ubah nilainya di sana (beda dari default "false"/"100" bawaan).
. "$MODPATH/core/profile_loader.sh" 2>/dev/null
hsin_profile_load "$HSIN_PROFILE" 2>/dev/null

# Override check: hsin.conf menang HANYA kalau nilainya beda dari default
# pabrik (artinya user sengaja ngubah). Kalau masih default, pakai punya profil.
_pf_rr_enabled="$(hsin_profile_get global_rr enabled)"
_pf_rr_reduced="$(hsin_profile_get global_rr reduced)"
_pf_rr_force="$(hsin_profile_get global_rr force)"
_pf_rr_peak="$(hsin_profile_get global_rr peak_hz)"
_pf_rr_min="$(hsin_profile_get global_rr min_hz)"
[ "$HSIN_GLOBAL_RR_ENABLED" != "false" ] && _pf_rr_enabled="$HSIN_GLOBAL_RR_ENABLED"
[ "$HSIN_GLOBAL_RR_REDUCED" != "false" ] && _pf_rr_reduced="$HSIN_GLOBAL_RR_REDUCED"
[ "$HSIN_GLOBAL_RR_FORCE" != "false" ] && _pf_rr_force="$HSIN_GLOBAL_RR_FORCE"
[ "$HSIN_GLOBAL_RR_PEAK_HZ" != "120" ] && _pf_rr_peak="$HSIN_GLOBAL_RR_PEAK_HZ"
[ "$HSIN_GLOBAL_RR_MIN_HZ" != "60" ] && _pf_rr_min="$HSIN_GLOBAL_RR_MIN_HZ"

_pf_dvfs_enabled="$(hsin_profile_get dvfs enabled)"
_pf_dvfs_cpu="$(hsin_profile_get dvfs cpu_limit)"
_pf_dvfs_gpu="$(hsin_profile_get dvfs gpu_limit)"
[ "$HSIN_ADVANCED_DVFS_ENABLED" != "false" ] && _pf_dvfs_enabled="$HSIN_ADVANCED_DVFS_ENABLED"
[ "$HSIN_ADVANCED_DVFS_CPU_LIMIT" != "100" ] && _pf_dvfs_cpu="$HSIN_ADVANCED_DVFS_CPU_LIMIT"
[ "$HSIN_ADVANCED_DVFS_GPU_LIMIT" != "100" ] && _pf_dvfs_gpu="$HSIN_ADVANCED_DVFS_GPU_LIMIT"

_pf_frl_disabled="$(hsin_profile_get frame_limit disabled)"
[ "$HSIN_FRAME_RATE_LIMIT_DISABLED" != "false" ] && _pf_frl_disabled="$HSIN_FRAME_RATE_LIMIT_DISABLED"

_pf_sf_enabled="$(hsin_profile_get surfaceflinger enabled)"
[ "$HSIN_SURFACEFLINGER_TWEAK_ENABLED" != "false" ] && _pf_sf_enabled="$HSIN_SURFACEFLINGER_TWEAK_ENABLED"

# 3d. Global refresh rate control (peak/min independen, mode reduced opsional).
# Beda dari lock di atas: ini gak wajib peak=min, jadi adaptive-refresh
# tetap jalan tapi dibatasi rentangnya.
if [ "$_pf_rr_enabled" = "true" ] && command -v hsin_refresh_set_range >/dev/null 2>&1; then
    if [ "$_pf_rr_reduced" = "true" ]; then
        hsin_refresh_reduced_apply "$_pf_rr_peak" "$_pf_rr_force" >> "$HSIN_LOG_FILE" 2>&1
    else
        hsin_refresh_set_range "$_pf_rr_peak" "$_pf_rr_min" "$_pf_rr_force" >> "$HSIN_LOG_FILE" 2>&1
    fi
    hsin_log_ok "main" "Global refresh rate control applied via profile=$HSIN_PROFILE (peak=$_pf_rr_peak min=$_pf_rr_min reduced=$_pf_rr_reduced)"
fi

# 3e. Advanced DVFS limiter (persen dari freq max hardware, independen governor)
. "$MODPATH/engine/gpu/dvfs.sh" 2>/dev/null
if [ "$_pf_dvfs_enabled" = "true" ] && command -v hsin_dvfs_apply >/dev/null 2>&1; then
    hsin_dvfs_apply "$_pf_dvfs_cpu" "$_pf_dvfs_gpu" >> "$HSIN_LOG_FILE" 2>&1
    hsin_log_ok "main" "Advanced DVFS limiter applied via profile=$HSIN_PROFILE (cpu=${_pf_dvfs_cpu}% gpu=${_pf_dvfs_gpu}%)"
fi

# 3f. Disable frame rate limit (system-wide SurfaceFlinger FPS cap)
. "$MODPATH/engine/display/frame_limit.sh" 2>/dev/null
if command -v hsin_frame_limit_disable >/dev/null 2>&1; then
    if [ "$_pf_frl_disabled" = "true" ]; then
        hsin_frame_limit_disable >> "$HSIN_LOG_FILE" 2>&1
        hsin_log_ok "main" "Frame rate limit disabled via profile=$HSIN_PROFILE (system-wide)"
    else
        hsin_frame_limit_restore >> "$HSIN_LOG_FILE" 2>&1
    fi
fi

# 3g. SurfaceFlinger tweak (scope aman: latch_unsignaled + gl_backpressure)
. "$MODPATH/engine/render/surfaceflinger.sh" 2>/dev/null
if command -v hsin_sf_apply_boot >/dev/null 2>&1; then
    hsin_sf_apply_boot "$_pf_sf_enabled" >> "$HSIN_LOG_FILE" 2>&1
    [ "$_pf_sf_enabled" = "true" ] && hsin_log_ok "main" "SurfaceFlinger tweak applied via profile=$HSIN_PROFILE"
fi

# 4. Detect hardware (FULL SCAN, no hardcode)
. "$MODPATH/core/detector.sh"
hsin_detect_all

# 5. Capability scoring
. "$MODPATH/core/capability.sh"
hsin_capability_run

# 6. Backup semua node yang akan dimodifikasi (sebelum apply apapun)
. "$MODPATH/core/backup.sh"
hsin_backup_all "$(date '+%Y%m%d_%H%M%S')_preapply"

# 7. Apply engine modules
_apply_failed=0

# CPU
if . "$MODPATH/engine/cpu/apply.sh" 2>/dev/null && hsin_cpu_apply "$HSIN_PROFILE"; then
    hsin_log_ok "main" "CPU engine applied"
else
    _apply_failed=$((_apply_failed + 1))
    hsin_log_error "main" "CPU engine failed"
fi

# GPU
if . "$MODPATH/engine/gpu/apply.sh" 2>/dev/null && hsin_gpu_apply "$HSIN_PROFILE"; then
    hsin_log_ok "main" "GPU engine applied"
else
    _apply_failed=$((_apply_failed + 1))
    hsin_log_error "main" "GPU engine failed"
fi

# Thermal
if . "$MODPATH/engine/thermal/apply.sh" 2>/dev/null && hsin_thermal_engine_apply "$HSIN_PROFILE"; then
    hsin_log_ok "main" "Thermal engine applied"
else
    _apply_failed=$((_apply_failed + 1))
    hsin_log_error "main" "Thermal engine failed"
fi

# Memory
if . "$MODPATH/engine/memory/apply.sh" 2>/dev/null && hsin_memory_apply "$HSIN_PROFILE"; then
    hsin_log_ok "main" "Memory engine applied"
else
    _apply_failed=$((_apply_failed + 1))
    hsin_log_error "main" "Memory engine failed"
fi

# IO
if . "$MODPATH/engine/io/io_manager.sh" 2>/dev/null && hsin_io_apply "$HSIN_PROFILE"; then
    hsin_log_ok "main" "IO engine applied"
else
    _apply_failed=$((_apply_failed + 1))
    hsin_log_error "main" "IO engine failed"
fi

# Network
if . "$MODPATH/engine/network/network_manager.sh" 2>/dev/null && hsin_network_apply "$HSIN_PROFILE"; then
    hsin_log_ok "main" "Network engine applied"
else
    _apply_failed=$((_apply_failed + 1))
    hsin_log_error "main" "Network engine failed"
fi

# 7b. Extreme Mode: aggressive overrides (freq unlock / GPU override /
# thermal trip override) + safety monitor watchdog. Only reached when
# HSIN_EXTREME_OK was confirmed above (profile=extreme AND opt-in true);
# otherwise HSIN_PROFILE was already downgraded to "performance".
if [ "$HSIN_PROFILE" = "extreme" ] && [ "$HSIN_EXTREME_OK" = "true" ]; then
    hsin_log_info "main" "Extreme Mode: applying aggressive overrides"

    . "$MODPATH/extreme/frequency_unlock.sh" 2>/dev/null
    hsin_extreme_freq_backup >/dev/null 2>&1
    hsin_extreme_freq_apply >> "$HSIN_LOG_FILE" 2>&1

    . "$MODPATH/extreme/gpu_override.sh" 2>/dev/null
    hsin_extreme_gpu_detect >/dev/null 2>&1
    hsin_extreme_gpu_backup >/dev/null 2>&1
    hsin_extreme_gpu_apply >> "$HSIN_LOG_FILE" 2>&1

    . "$MODPATH/extreme/thermal_override.sh" 2>/dev/null
    hsin_extreme_thermal_apply "extreme" >> "$HSIN_LOG_FILE" 2>&1

    touch "$HSIN_DATA/extreme_active" 2>/dev/null
    echo "$(date '+%Y-%m-%d %H:%M:%S') [EXTREME] Boot: aggressive overrides applied" >> "$HSIN_LOG_DIR/extreme.log" 2>/dev/null

    # Stop any leftover watchdog before starting a fresh one for this boot.
    . "$MODPATH/extreme/safety_monitor.sh" 2>/dev/null
    hsin_safety_monitor_stop >/dev/null 2>&1

    if command -v setsid >/dev/null 2>&1; then
        setsid sh -c ". \"$MODPATH/extreme/safety_monitor.sh\"; hsin_safety_monitor_start" </dev/null >> "$HSIN_LOG_DIR/extreme.log" 2>&1 &
    else
        sh -c ". \"$MODPATH/extreme/safety_monitor.sh\"; hsin_safety_monitor_start" </dev/null >> "$HSIN_LOG_DIR/extreme.log" 2>&1 &
    fi
else
    # Not on Extreme this boot. Sysfs overrides are already gone (the
    # kernel resets them on reboot) - clear a stale flag left over from
    # before the reboot so status reporting doesn't claim an override
    # that no longer exists.
    rm -f "$HSIN_DATA/extreme_active" 2>/dev/null
fi

# 8. Generate status report
hsin_log_section "HSIN Status Report"
hsin_log_info "main" "Device: $(grep '^SOC=' "$HSIN_DATA/device.txt" | cut -d= -f2-)"
hsin_log_info "main" "Vendor: $(grep '^VENDOR=' "$HSIN_DATA/device.txt" | cut -d= -f2-)"
hsin_log_info "main" "GPU:    $(grep '^GPU=' "$HSIN_DATA/device.txt" | cut -d= -f2-)"
hsin_log_info "main" "Kernel: $(grep '^KERNEL=' "$HSIN_DATA/device.txt" | cut -d= -f2-)"
hsin_log_info "main" "Profile: $HSIN_PROFILE"
hsin_log_info "main" "Failed engines: $_apply_failed"

# 9. Cleanup self-disable flag (artinya service.sh selesai tanpa crash)
rm -f "$HSIN_FLAG_DIR/.need_disable"
if [ "$_apply_failed" -eq 0 ]; then
    echo "ready" > "$HSIN_DATA/service.state" 2>/dev/null
else
    echo "degraded" > "$HSIN_DATA/service.state" 2>/dev/null
    hsin_log_warn "main" "Service ready with failed engines=$_apply_failed"
fi

# 9b. Catat profile aktif ke state.lock supaya WebUI Live Monitor langsung
. "$MODPATH/core/state_manager.sh" 2>/dev/null
hsin_state_profile "$HSIN_PROFILE" 2>/dev/null

# 10. Start monitor
# Monitor runs whenever any of:
#   - GAM_BOOST is enabled (it doubles as the game-boost detector)
#   - the active profile is performance / extreme (we want throttle logs)
# We deliberately DON'T gate this on profile = "battery" or "balanced"
# alone - users with those profiles still want the safety net of a
# running monitor that can detect thermal issues. The monitor is fork-
# light and only writes to the log file, so the overhead is negligible.
if [ "${HSIN_GAM_ENABLED:-false}" = "true" ] || [ "$HSIN_PROFILE" = "performance" ] || [ "$HSIN_PROFILE" = "extreme" ]; then
    . "$MODPATH/core/monitor.sh"
    hsin_monitor_start
fi

# 11. Beri sinyal sukses ke Magisk
touch "$HSIN_DATA/.applied"
hsin_protect_harden_data
hsin_log_ok "main" "HSIN service ready"

# 12. Background integrity guard - re-checks the FULL file set (engine/,
# extreme/, profiles/, etc) every 3 minutes for as long as the device is
# up. This is what actually protects engine/*.sh long-term, since the
# WebUI's own per-click check only covers the light set for speed. Runs
# as a fully detached script, same pattern as action.sh's background
# apply job, so it survives independently of service.sh's own lifetime.
mkdir -p "$HSIN_DATA/tmp" 2>/dev/null
_guard_script="$HSIN_DATA/tmp/integrity_guard.sh"
cat > "$_guard_script" << GUARDEOF
#!/system/bin/sh
MODPATH="$MODPATH"
HSIN_MODULE_PATH="$MODPATH"
HSIN_DATA="$HSIN_DATA"
. "\$MODPATH/core/protect.sh" 2>/dev/null
. "\$MODPATH/core/logger.sh" 2>/dev/null
while true; do
    sleep 180
    [ -f "\$MODPATH/disable" ] && break
    # PATCH v4.0.2: rotasi log tiap 3 menit selama device nyala (bukan
    # cuma truncate pas boot) - cegah debug.log/monitor.log numpuk kalau
    # device gaming jarang di-restart. Aman: cuma wc -c 5 file kecil.
    command -v hsin_log_rotate >/dev/null 2>&1 && hsin_log_rotate
    command -v hsin_protect_integrity_full >/dev/null 2>&1 || break
    hsin_protect_integrity_full || {
        touch "\$MODPATH/disable" 2>/dev/null
        echo "\$(date '+%Y-%m-%d %H:%M:%S') guard: FULL integrity check failed, module disabled" >> "\$HSIN_DATA/logs/hsin.log" 2>/dev/null
        break
    }
done
GUARDEOF
chmod 755 "$_guard_script" 2>/dev/null

if command -v setsid >/dev/null 2>&1; then
    setsid sh "$_guard_script" </dev/null >/dev/null 2>&1 &
elif [ -x /data/adb/ksu/bin/busybox ]; then
    /data/adb/ksu/bin/busybox setsid sh "$_guard_script" </dev/null >/dev/null 2>&1 &
else
    sh "$_guard_script" </dev/null >/dev/null 2>&1 &
fi

# BUG FIX (stuck-flow): this block was previously placed AFTER `exit 0`
# below, so it was dead code that never ran. Its whole purpose - clearing
# a "applying:*" APPLY_STATUS left over from a reboot that happened mid-
# apply, so the WebUI isn't stuck waiting for an apply that will never
# confirm - only matters if it actually executes. Moved above the exit.
if command -v hsin_state_update >/dev/null 2>&1; then
    hsin_state_update "APPLY_STATUS" "done:boot" 2>/dev/null
fi

exit 0
