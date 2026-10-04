#!/system/bin/sh
MODDIR=${0%/*}
. "$MODDIR/core/lib.sh" 2>/dev/null && restore_baseline >/dev/null 2>&1
rm -rf /data/adb/hsin5 2>/dev/null
