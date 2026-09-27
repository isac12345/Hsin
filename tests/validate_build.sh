#!/system/bin/sh
# HSIN Build Validation Script
# Usage: sh validate_build.sh <zip_path>

set -e

if [ -z "${1:-}" ]; then
    echo "ERROR: missing ZIP path argument"
    exit 1
fi

ZIP="$1"

if [ ! -f "$ZIP" ]; then
    echo "ERROR: file not found: $ZIP"
    exit 1
fi

# Mandatory contents check
for _f in action.sh service.sh core/runtime.sh module.prop; do
    if ! unzip -l "$ZIP" | grep -q "$_f"; then
        echo "ERROR: missing mandatory file in ZIP: $_f"
        exit 1
    fi
    echo "OK: $_f present in ZIP"
done

# Runtime functions check
if ! unzip -p "$ZIP" core/runtime.sh | grep -q 'hsin_scan_cache_load'; then
    echo "ERROR: core/runtime.sh missing hsin_scan_cache_load"
    exit 1
fi

if ! unzip -p "$ZIP" core/runtime.sh | grep -q 'hsin_uk_set'; then
    echo "ERROR: core/runtime.sh missing hsin_uk_set"
    exit 1
fi

echo "OK: core/runtime.sh contains required functions"

# Size check (< 50MB = 52428800 bytes)
SIZE=$(stat -c %s "$ZIP" 2>/dev/null || stat -f %z "$ZIP" 2>/dev/null || echo 0)
if [ "$SIZE" -ge 52428800 ]; then
    echo "ERROR: ZIP size ${SIZE} bytes exceeds 50MB limit"
    exit 1
fi

echo "OK: ZIP size ${SIZE} bytes (<50MB)"

echo "VALID: $ZIP"
exit 0
