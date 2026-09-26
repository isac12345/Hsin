#!/system/bin/sh
# HSIN Post-FS-Data

MODPATH="${0%/*}"
HSIN_ID="hsin"
HSIN_DATA="/data/adb/${HSIN_ID}"
HSIN_FLAG_DIR="$HSIN_DATA/flags"

# Failsafe permission re-apply, every boot.
chmod 0755 "$MODPATH/action.sh" 2>/dev/null
chmod 0755 "$MODPATH/service.sh" 2>/dev/null
chmod 0755 "$MODPATH/post-fs-data.sh" 2>/dev/null
chmod 0755 "$MODPATH/bin/hsin" 2>/dev/null
[ -f "$MODPATH/bin/hsin-cli" ] && chmod 0755 "$MODPATH/bin/hsin-cli" 2>/dev/null
[ -f "$MODPATH/bin/hsin-verify" ] && chmod 0755 "$MODPATH/bin/hsin-verify" 2>/dev/null
[ -f "$MODPATH/bin/hsin-verify-full" ] && chmod 0755 "$MODPATH/bin/hsin-verify-full" 2>/dev/null
find "$MODPATH/core" "$MODPATH/engine" -name "*.sh" -exec chmod 0755 {} + 2>/dev/null
find "$MODPATH/extreme" -name "*.sh" -exec chmod 0755 {} + 2>/dev/null

mkdir -p "$HSIN_DATA" 2>/dev/null
mkdir -p "$HSIN_DATA/logs" 2>/dev/null
mkdir -p "$HSIN_DATA/backup" 2>/dev/null
mkdir -p "$HSIN_FLAG_DIR" 2>/dev/null

# Third independent integrity checkpoint (see core/protect.sh). Runs once
# at boot, so it's fine for this to use the FULL check (engine/extreme
# included) even though action.sh's per-click check stays light.
HSIN_MODULE_PATH="$MODPATH"
. "$MODPATH/core/protect.sh" 2>/dev/null
if command -v hsin_protect_integrity_full >/dev/null 2>&1; then
    hsin_protect_integrity_full || {
        touch "$MODPATH/disable" 2>/dev/null
        echo "$(date '+%Y-%m-%d %H:%M:%S') post-fs-data: FULL integrity check failed, module disabled" >> "$HSIN_DATA/logs/hsin.log" 2>/dev/null
        exit 0
    }
fi

# Self-disable pattern (UPerf-style):
if [ -f "$HSIN_FLAG_DIR/.need_disable" ]; then
    rm -f "$HSIN_FLAG_DIR/.need_disable"
    # Disable: buat file disable agar Magisk skip module
    touch "$MODPATH/disable" 2>/dev/null
    exit 0
fi

# Tandai: kalau service.sh crash sebelum selesai, next boot akan disable
touch "$HSIN_FLAG_DIR/.need_disable" 2>/dev/null
echo "started" > "$HSIN_DATA/service.state" 2>/dev/null

# Render backend: apply the user's saved choice before Zygote spawns the
# first app, so every app just inherits the right renderer on first launch
# - no force-stop / manual "apply" tap needed after reboot.
HSIN_CONF="/sdcard/Android/hsin/hsin.conf"
[ -f "$HSIN_CONF" ] || HSIN_CONF="$MODPATH/config/hsin.conf"
if [ -f "$HSIN_CONF" ]; then
    _renderer_target=""
    while IFS='=' read -r _rk _rv || [ -n "$_rk" ]; do
        [ "$_rk" = "RENDERER" ] && _renderer_target="$_rv"
    done < "$HSIN_CONF"
    if [ -n "$_renderer_target" ]; then
        HSIN_MODULE_PATH="$MODPATH"
        . "$MODPATH/engine/render/renderer.sh" 2>/dev/null
        command -v hsin_render_apply_boot >/dev/null 2>&1 && hsin_render_apply_boot "$_renderer_target"
    fi
fi

exit 0
