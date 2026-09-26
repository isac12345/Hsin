#!/system/bin/sh
# HSIN Conflict Checker (Doctor)

[ -z "$HSIN_MODULE_PATH" ] && HSIN_MODULE_PATH="/data/adb/modules/hsin"
HSIN_DATA="${HSIN_DATA:-/data/adb/hsin}"

# Known performance modules
HSIN_KNOWN_MODULES="UPerf Rairin GTurbo FAS-RS Sasha"

# Check for other modules
hsin_doctor_check_modules() {
    echo ""
    echo "╔══════════════════════════════════════╗"
    echo "║   HSIN Doctor                         ║"
    echo "╚══════════════════════════════════════╝"
    echo ""
    echo "  Checking modules..."
    echo ""

    _found=0
    _conflicts=0

    # Check Magisk modules directory
    for _dir in /data/adb/modules/*/; do
        [ -d "$_dir" ] || continue

        _name=$(basename "$_dir")

        # Skip HSIN itself
        case "$_name" in
            hsin*) continue ;;
        esac

        # Check if it's a known performance module
        _is_known=false
        for _known in $HSIN_KNOWN_MODULES; do
            case "$_name" in
                *$_known*|*$_known*)
                    _is_known=true
                    ;;
            esac
        done

        if [ "$_is_known" = "true" ]; then
            _found=$((_found + 1))

            # Check if active (no disable file)
            if [ ! -f "$_dir/disable" ]; then
                printf "  %-20s ACTIVE\n" "$_name"
                _conflicts=$((_conflicts + 1))
            else
                printf "  %-20s disabled\n" "$_name"
            fi
        fi
    done

    echo ""

    if [ "$_conflicts" -gt 0 ]; then
        echo "  WARNING: $_conflicts active performance module(s) detected"
        echo ""
        echo "  Recommendation: Disable other modules to avoid conflicts"
        echo "  Command: touch /data/adb/modules/<module>/disable"
    else
        if [ "$_found" -gt 0 ]; then
            echo "  OK: Other modules are disabled"
        else
            echo "  OK: No conflicting modules found"
        fi
    fi

    echo ""
}

# Check for conflicting governors
hsin_doctor_check_governors() {
    echo "  Checking governors..."
    echo ""

    _conflicts=0
    for _policy in /sys/devices/system/cpu/cpufreq/policy*; do
        [ -d "$_policy" ] || continue
        [ -f "$_policy/scaling_governor" ] || continue

        _gov=$(cat "$_policy/scaling_governor" 2>/dev/null)
        _policy_num=$(basename "$_policy" | sed 's/policy//')

        # Check for known conflicting governors
        case "$_gov" in
            performance|powersave|conservative|ondemand|userspace)
                printf "    policy%s: %s (standard)\n" "$_policy_num" "$_gov"
                ;;
            schedutil)
                printf "    policy%s: %s (HSIN preferred)\n" "$_policy_num" "$_gov"
                ;;
            *)
                printf "    policy%s: %s (custom)\n" "$_policy_num" "$_gov"
                _conflicts=$((_conflicts + 1))
                ;;
        esac
    done

    echo ""

    if [ "$_conflicts" -gt 0 ]; then
        echo "  WARNING: $_conflicts custom governor(s) detected"
        echo "  Recommendation: Use schedutil for best compatibility"
    else
        echo "  OK: Governors look standard"
    fi

    echo ""
}

# Check for conflicting tweaks
hsin_doctor_check_tweaks() {
    echo "  Checking for external tweaks..."
    echo ""

    # Check common tweak locations
    _tweaks_found=0

    # Check init.d
    if [ -d /system/etc/init.d ]; then
        _count=$(ls /system/etc/init.d/*.sh 2>/dev/null | wc -l)
        [ "$_count" -gt 0 ] && {
            printf "    init.d: %s scripts\n" "$_count"
            _tweaks_found=$((_tweaks_found + _count))
        }
    fi

    # Check sysctl.d
    if [ -d /system/etc/sysctl.d ]; then
        _count=$(ls /system/etc/sysctl.d/*.conf 2>/dev/null | wc -l)
        [ "$_count" -gt 0 ] && {
            printf "    sysctl.d: %s configs\n" "$_count"
            _tweaks_found=$((_tweaks_found + _count))
        }
    fi

    echo ""

    if [ "$_tweaks_found" -gt 0 ]; then
        echo "  WARNING: $_tweaks_found external tweak(s) found"
        echo "  Recommendation: Review and disable conflicting tweaks"
    else
        echo "  OK: No external tweaks detected"
    fi

    echo ""
}

# Generate report
hsin_doctor_report() {
    hsin_doctor_check_modules
    hsin_doctor_check_governors
    hsin_doctor_check_tweaks

    echo "╔══════════════════════════════════════╗"
    echo "║   Summary                            ║"
    echo "╚══════════════════════════════════════╝"
    echo ""

    # Check HSIN status
    if [ -f "$HSIN_DATA/state.lock" ]; then
        _owner=$(grep "^OWNER=" "$HSIN_DATA/state.lock" 2>/dev/null | cut -d= -f2)
        _profile=$(grep "^ACTIVE_PROFILE=" "$HSIN_DATA/state.lock" 2>/dev/null | cut -d= -f2)
        printf "  HSIN Status:  Active (owner=%s, profile=%s)\n" "${_owner:-unknown}" "${_profile:-none}"
    else
        printf "  HSIN Status:  Not initialized\n"
    fi

    echo ""
}

return 0 2>/dev/null || true
