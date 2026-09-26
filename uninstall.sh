#!/system/bin/sh
# HSIN Uninstall Script

HSIN_ID="hsin"
HSIN_DATA="/data/adb/${HSIN_ID}"
HSIN_USER="/sdcard/Android/${HSIN_ID}"

# Restore backup terakhir (best-effort)
if [ -d "$HSIN_DATA/backup" ]; then
    _latest=$(ls -1 "$HSIN_DATA/backup" 2>/dev/null | sort | tail -1)
    if [ -n "$_latest" ] && [ -f "$HSIN_DATA/backup/$_latest/nodes.list" ]; then
        echo "[HSIN uninstall] Restoring backup: $_latest"
        while IFS='=' read -r p v; do
            [ -z "$p" ] && continue
            [ -f "$p" ] || continue
            [ -w "$p" ] || continue
            echo "$v" > "$p" 2>/dev/null
        done < "$HSIN_DATA/backup/$_latest/nodes.list"
    fi
fi

# Kill monitor jika masih jalan
if [ -f "$HSIN_DATA/monitor.pid" ]; then
    kill "$(cat "$HSIN_DATA/monitor.pid" 2>/dev/null)" 2>/dev/null
fi

# Hapus semua data persistent
rm -rf "$HSIN_DATA" 2>/dev/null
rm -rf "$HSIN_USER" 2>/dev/null

echo "[HSIN uninstall] Complete. Original state restored."
exit 0
