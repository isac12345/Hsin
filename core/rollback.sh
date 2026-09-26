#!/system/bin/sh
# HSIN - Rollback (rollback.sh)

HSIN_DATA="${HSIN_DATA:-/data/adb/hsin}"
HSIN_BACKUP_ROOT="$HSIN_DATA/backup"

# shellcheck disable=SC1091
. "${HSIN_MODULE_PATH:-/data/adb/modules/hsin}/core/backup.sh" 2>/dev/null

hsin_rollback_all() {
    # Restore sesi backup paling baru
    _latest=$(ls -1 "$HSIN_BACKUP_ROOT" 2>/dev/null | sort | tail -1)
    [ -z "$_latest" ] && {
        hsin_log_rollback "No backup sessions found"
        return 1
    }
    hsin_log_rollback "Restoring latest session: $_latest"
    hsin_restore_session "$_latest"
    return $?
}

hsin_rollback_session() {
    hsin_restore_session "$1"
    return $?
}

return 0 2>/dev/null || true
