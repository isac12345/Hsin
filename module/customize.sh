#!/system/bin/sh
SKIPUNZIP=0
ui_print ""
ui_print "== HSIN v6.0.0 · game booster =="
ui_print "Hanya knob yang kamu ubah di app yang ditulis."
mkdir -p /data/adb/hsin5/logs 2>/dev/null
set_perm_recursive "$MODPATH" 0 0 0755 0644
set_perm "$MODPATH/action.sh" 0 0 0755
set_perm "$MODPATH/service.sh" 0 0 0755
set_perm "$MODPATH/daemon.sh" 0 0 0755
set_perm "$MODPATH/uninstall.sh" 0 0 0755
set_perm "$MODPATH/core/lib.sh" 0 0 0755
set_perm "$MODPATH/core/hud.sh" 0 0 0755
ui_print "Reboot dulu, lalu buka app HSIN."
ui_print "Data lama di /data/adb/hsin tidak dipakai lagi."
