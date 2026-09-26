#!/system/bin/sh
# HSIN CPU Engine - Detection

[ -z "$HSIN_MODULE_PATH" ] && HSIN_MODULE_PATH="/data/adb/modules/hsin"

# Detect all CPU clusters and properties
hsin_cpu_detect() {
    # Reset
    HSIN_CPU_CORES=""
    HSIN_CPU_CLUSTERS=""
    HSIN_CPU_GOVS=""
    HSIN_CPU_CORE_COUNT=0
    HSIN_CPU_CLUSTER_COUNT=0
    HSIN_CPU_FREQ_MIN=""
    HSIN_CPU_FREQ_MAX=""
    HSIN_CPU_FREQ_LIST=""
    HSIN_CPU_WRITABLE_MIN="false"
    HSIN_CPU_WRITABLE_MAX="false"
    HSIN_CPU_WRITABLE_GOV="false"

    # Count cores
    for _cpu in /sys/devices/system/cpu/cpu[0-9]*; do
        [ -d "$_cpu" ] || continue
        _base="${_cpu##*/}"
        _num="${_base#cpu}"
        HSIN_CPU_CORES="${HSIN_CPU_CORES}${_num} "
        HSIN_CPU_CORE_COUNT=$((HSIN_CPU_CORE_COUNT + 1))
    done

    # Detect clusters via cpufreq policies
    for _policy in /sys/devices/system/cpu/cpufreq/policy*; do
        [ -d "$_policy" ] || continue
        _name="${_policy##*/}"

        # Get CPUs in this policy
        _cpus=""
        if [ -f "$_policy/cpus" ]; then
            read -r _cpus < "$_policy/cpus" 2>/dev/null
        elif [ -f "$_policy/related_cpus" ]; then
            read -r _cpus < "$_policy/related_cpus" 2>/dev/null
        fi

        # Get freq range
        _min=""
        _max=""
        [ -f "$_policy/cpuinfo_min_freq" ] && read -r _min < "$_policy/cpuinfo_min_freq" 2>/dev/null
        [ -f "$_policy/cpuinfo_max_freq" ] && read -r _max < "$_policy/cpuinfo_max_freq" 2>/dev/null

        # Get current freq
        _cur_min=""
        _cur_max=""
        [ -f "$_policy/scaling_min_freq" ] && read -r _cur_min < "$_policy/scaling_min_freq" 2>/dev/null
        [ -f "$_policy/scaling_max_freq" ] && read -r _cur_max < "$_policy/scaling_max_freq" 2>/dev/null

        # Get available frequencies
        _avail_freqs=""
        [ -f "$_policy/scaling_available_frequencies" ] && \
            read -r _avail_freqs < "$_policy/scaling_available_frequencies" 2>/dev/null

        # Get available governors
        _avail_govs=""
        [ -f "$_policy/scaling_available_governors" ] && \
            read -r _avail_govs < "$_policy/scaling_available_governors" 2>/dev/null

        # Get current governor
        _cur_gov=""
        [ -f "$_policy/scaling_governor" ] && read -r _cur_gov < "$_policy/scaling_governor" 2>/dev/null

        # Check writability
        _w_min="false"
        _w_max="false"
        _w_gov="false"
        [ -w "$_policy/scaling_min_freq" ] && _w_min="true"
        [ -w "$_policy/scaling_max_freq" ] && _w_max="true"
        [ -w "$_policy/scaling_governor" ] && _w_gov="true"

        # Determine cluster type by max freq - guard against empty
        # value so an unset/zero doesn't trip the `[ -ge 2000000 ]` check
        # on a string.
        _type="little"
        if [ -n "$_max" ] && [ "$_max" -gt 0 ] 2>/dev/null; then
            if [ "$_max" -ge 2000000 ] 2>/dev/null; then
                _type="big"
            elif [ "$_max" -ge 1500000 ] 2>/dev/null; then
                _type="mid"
            fi
        fi

        # Store cluster: name|type|cpus|min_freq|max_freq|cur_min|cur_max|cur_gov|avail_govs|avail_freqs|w_min|w_max|w_gov
        HSIN_CPU_CLUSTERS="${HSIN_CPU_CLUSTERS}${_name}|${_type}|${_cpus}|${_min}|${_max}|${_cur_min}|${_cur_max}|${_cur_gov}|${_avail_govs}|${_avail_freqs}|${_w_min}|${_w_max}|${_w_gov}
"
        HSIN_CPU_CLUSTER_COUNT=$((HSIN_CPU_CLUSTER_COUNT + 1))

        # Accumulate governors
        for _g in $_avail_govs; do
            case " $HSIN_CPU_GOVS " in
                *" $_g "*) ;;
                *) HSIN_CPU_GOVS="${HSIN_CPU_GOVS} $_g" ;;
            esac
        done

        # Track global min/max - guard against empty values so the
        # arithmetic compare never trips on an unset string (which on
        # Android's sh can produce a spurious zero match or, worse, an
        # error that aborts the loop).
        if [ -n "$_min" ]; then
            if [ -z "$HSIN_CPU_FREQ_MIN" ] || [ "$_min" -lt "$HSIN_CPU_FREQ_MIN" ] 2>/dev/null; then
                HSIN_CPU_FREQ_MIN="$_min"
            fi
        fi
        if [ -n "$_max" ]; then
            if [ -z "$HSIN_CPU_FREQ_MAX" ] || [ "$_max" -gt "$HSIN_CPU_FREQ_MAX" ] 2>/dev/null; then
                HSIN_CPU_FREQ_MAX="$_max"
            fi
        fi

        # Track writability
        [ "$_w_min" = "true" ] && HSIN_CPU_WRITABLE_MIN="true"
        [ "$_w_max" = "true" ] && HSIN_CPU_WRITABLE_MAX="true"
        [ "$_w_gov" = "true" ] && HSIN_CPU_WRITABLE_GOV="true"

        # Collect unique frequencies from the list we already read above -
        # no need for a second pass re-reading scaling_available_frequencies.
        for _f in $_avail_freqs; do
            case " $HSIN_CPU_FREQ_LIST " in
                *" $_f "*) ;;
                *) HSIN_CPU_FREQ_LIST="${HSIN_CPU_FREQ_LIST} $_f" ;;
            esac
        done
    done
}

# Print detection report
hsin_cpu_print() {
    [ -z "$HSIN_CPU_CLUSTERS" ] && hsin_cpu_detect

    echo ""
    echo "╔══════════════════════════════════════╗"
    echo "║   HSIN CPU Detection                 ║"
    echo "╚══════════════════════════════════════╝"
    echo ""

    printf "  Cores:     %s\n" "$HSIN_CPU_CORES"
    printf "  Clusters:  %s\n" "$HSIN_CPU_CLUSTER_COUNT"
    echo ""

    # Print each cluster
    echo "$HSIN_CPU_CLUSTERS" | while IFS='|' read -r _name _type _cpus _min _max _cmin _cmax _cgov _agovs _afreq _wm _wmg _wg; do
        [ -z "$_name" ] && continue
        printf "  %s:\n" "$_type"
    done
    echo ""

    echo "$HSIN_CPU_CLUSTERS" | while IFS='|' read -r _name _type _cpus _min _max _cmin _cmax _cgov _agovs _afreq _wm _wmg _wg; do
        [ -z "$_name" ] && continue
        # Guard arithmetic against empty values - some cpufreq policies
        # lack cpuinfo_min_freq or scaling_min_freq entirely.
        _min_mhz=0
        [ -n "$_min" ] && [ "$_min" -gt 0 ] 2>/dev/null && _min_mhz=$((_min / 1000))
        _max_mhz=0
        [ -n "$_max" ] && [ "$_max" -gt 0 ] 2>/dev/null && _max_mhz=$((_max / 1000))
        _cmin_mhz=0
        [ -n "$_cmin" ] && [ "$_cmin" -gt 0 ] 2>/dev/null && _cmin_mhz=$((_cmin / 1000))
        _cmax_mhz=0
        [ -n "$_cmax" ] && [ "$_cmax" -gt 0 ] 2>/dev/null && _cmax_mhz=$((_cmax / 1000))
        printf "    %s:\n" "$_name"
        printf "      CPUs:   %s\n" "$_cpus"
        printf "      Freq:   %s-%s MHz\n" "$_min_mhz" "$_max_mhz"
        printf "      Current: %s MHz - %s MHz\n" "$_cmin_mhz" "$_cmax_mhz"
        printf "      Governor: %s\n" "$_cgov"
        printf "      Available: %s\n" "$_agovs"
        echo ""
    done

    printf "  Governor: %s\n" "${HSIN_CPU_GOVS:-none}"
    printf "  Freq Range: %s-%s kHz\n" "${HSIN_CPU_FREQ_MIN:-?}" "${HSIN_CPU_FREQ_MAX:-?}"
    echo ""

    echo "  Writable:"
    printf "    min_freq: %s\n" "$HSIN_CPU_WRITABLE_MIN"
    printf "    max_freq: %s\n" "$HSIN_CPU_WRITABLE_MAX"
    printf "    governor: %s\n" "$HSIN_CPU_WRITABLE_GOV"
    echo ""
}

return 0 2>/dev/null || true
