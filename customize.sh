#!/system/bin/sh
# HSIN Customize Script - runs at Magisk install time

MODPATH="${0%/*}"
HSIN_ID="hsin"
HSIN_DATA="/data/adb/${HSIN_ID}"
HSIN_USER="/sdcard/Android/${HSIN_ID}"

ui_print ""
ui_print "== HSIN v5.0.0-beta1 by Somwan =="
ui_print "Discord: https://discord.gg/T2HWBFeEN"
ui_print ""

# Setup direktori persistent
mkdir -p "$HSIN_DATA"
mkdir -p "$HSIN_DATA/logs"
mkdir -p "$HSIN_DATA/backup"
chmod 700 "$HSIN_DATA" "$HSIN_DATA/logs" "$HSIN_DATA/backup" 2>/dev/null
mkdir -p "$HSIN_USER"

# Tulis default config kalau belum ada
if [ ! -f "$HSIN_USER/hsin.conf" ]; then
    cp "$MODPATH/config/hsin.conf" "$HSIN_USER/hsin.conf"
    chmod 0644 "$HSIN_USER/hsin.conf"
    ui_print " - Default config written: $HSIN_USER/hsin.conf"
fi

# Sanity check arsitektur
ARCH=$(uname -m)
case "$ARCH" in
    arm64|aarch64) ;;
    *) ui_print "! WARNING: non-arm64 arch ($ARCH). Some features may be skipped." ;;
esac

# Permission untuk semua shell script
set_perm_recursive "$MODPATH" 0 0 0755 0644
set_perm "$MODPATH/service.sh" 0 0 0755
set_perm "$MODPATH/post-fs-data.sh" 0 0 0755
set_perm "$MODPATH/customize.sh" 0 0 0755
set_perm "$MODPATH/uninstall.sh" 0 0 0755
set_perm "$MODPATH/action.sh" 0 0 0755
set_perm "$MODPATH/bin/hsin" 0 0 0755
[ -f "$MODPATH/bin/hsin-cli" ] && set_perm "$MODPATH/bin/hsin-cli" 0 0 0755
[ -f "$MODPATH/bin/hsin-verify" ] && set_perm "$MODPATH/bin/hsin-verify" 0 0 0755
[ -f "$MODPATH/bin/hsin-verify-full" ] && set_perm "$MODPATH/bin/hsin-verify-full" 0 0 0755
set_perm_recursive "$MODPATH/core" 0 0 0755 0644
set_perm "$MODPATH/core/protect.sh" 0 0 0755
set_perm_recursive "$MODPATH/engine" 0 0 0755 0644
set_perm "$MODPATH/profiles" 0 0 0755

ui_print ""
ui_print "4 profiles, adaptive detection, unsupported nodes skipped."
ui_print "Config: $HSIN_USER/hsin.conf"
ui_print ""
ui_print "Please reboot to activate."

exit 0
