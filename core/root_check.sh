#!/system/bin/sh
# HSIN - Root Detection

HSIN_DATA="${HSIN_DATA:-/data/adb/hsin}"

# Detect root method
hsin_detect_root() {
    # 1. Check Magisk
    if [ -d /data/adb/magisk ] || [ -f /data/adb/magisk ]; then
        echo "magisk"
        return 0
    fi
    # Check Magisk manager
    if [ -f /data/adb/modules ] || [ -d /data/adb/modules ]; then
        # Could be Magisk or KernelSU
        if [ -f /data/adb/magisk_init ]; then
            echo "magisk"
            return 0
        fi
    fi

    # 2. Check KernelSU
    if [ -f /data/adb/ksu ] || [ -d /data/adb/ksu ]; then
        echo "kernelsu"
        return 0
    fi
    # Check KernelSU manager
    if [ -f /data/adb/modules/ksu ] || [ -d /data/adb/modules/ksu ]; then
        echo "kernelsu"
        return 0
    fi
    # Check KernelSU kernel
    if [ -f /proc/version ] && grep -qi "kernelsu\|ksu" /proc/version 2>/dev/null; then
        echo "kernelsu"
        return 0
    fi

    # 3. Check common root binaries
    for bin in /system/bin/su /system/xbin/su /sbin/su /su/bin/su; do
        if [ -f "$bin" ] && [ -x "$bin" ]; then
            echo "generic"
            return 0
        fi
    done

    # 4. Check if running as root already
    if [ "$(id -u)" = "0" ]; then
        echo "direct"
        return 0
    fi

    # No root found
    echo "none"
    return 1
}

# Check if we can actually use root (test su -c)
hsin_root_test() {
    _method=$(hsin_detect_root)
    case "$_method" in
        direct)
            # Already root
            return 0
            ;;
        magisk|kernelsu|generic)
            # Test su -c
            su -c "id" 2>/dev/null | grep -q "uid=0" && return 0 || return 1
            ;;
        *)
            return 1
            ;;
    esac
}

# Set global variables
hsin_root_init() {
    HSIN_ROOT_METHOD=$(hsin_detect_root)
    HSIN_ROOT_AVAILABLE="false"
    hsin_root_test && HSIN_ROOT_AVAILABLE="true"
    export HSIN_ROOT_METHOD HSIN_ROOT_AVAILABLE
}

return 0 2>/dev/null || true
