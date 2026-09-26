#!/system/bin/sh
# HSIN - Common bootstrap untuk semua script core/engine

# Module path detection (cari parent yang ada service.sh)
_hsin_detect_module() {
    # 1. Gunakan HSIN_MODULE_PATH jika sudah di-export
    [ -n "$HSIN_MODULE_PATH" ] && [ -f "$HSIN_MODULE_PATH/service.sh" ] && {
        echo "$HSIN_MODULE_PATH"; return 0
    }
    # 2. Cari di /data/adb/modules/hsin
    [ -f /data/adb/modules/hsin/service.sh ] && {
        echo "/data/adb/modules/hsin"; return 0
    }
    # 3. Cari di /data/adb/modules_update/hsin
    [ -f /data/adb/modules_update/hsin/service.sh ] && {
        echo "/data/adb/modules_update/hsin"; return 0
    }
    # 4. Default fallback
    echo "/data/adb/modules/hsin"
}

HSIN_MODULE_PATH="${HSIN_MODULE_PATH:-$(_hsin_detect_module)}"
export HSIN_MODULE_PATH

# Data dir default
HSIN_DATA="${HSIN_DATA:-/data/adb/hsin}"
export HSIN_DATA

# Source logger otomatis (silent kalau gagal)
. "$HSIN_MODULE_PATH/core/logger.sh" 2>/dev/null

return 0 2>/dev/null || true
