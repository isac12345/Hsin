#!/system/bin/sh
# HSIN Profile Loader

[ -z "$HSIN_MODULE_PATH" ] && HSIN_MODULE_PATH="/data/adb/modules/hsin"
HSIN_DATA="${HSIN_DATA:-/data/adb/hsin}"

# Current loaded profile
HSIN_PROFILE_NAME=""
HSIN_PROFILE_LOADED="false"

# Load a profile from conf file
hsin_profile_load() {
    _name="$1"
    _conf="$HSIN_MODULE_PATH/profiles/${_name}.conf"

    [ -f "$_conf" ] || return 1

    # PATCH v4.0: buang sisa HSIN_PROFILE_* dari load sebelumnya. Tanpa ini,
    # key yang absen di profil baru nyangkut nilai profil lama (ketemu pas
    # audit: 'trip_override=false' bocor dari profil sebelumnya).
    for _old_var in $(env | sed -n 's/^\(HSIN_PROFILE_[A-Za-z0-9_]*\)=.*/\1/p'); do
        unset "$_old_var" 2>/dev/null
    done

    # Reset profile values
    HSIN_PROFILE_NAME="$_name"
    HSIN_PROFILE_LOADED="true"

    # Parse INI-style config
    # PERF: this used to run `echo "$_line" | tr -d '[]'` for section
    # headers and `echo "$_line" | cut -d= -f1 | tr -d ' '` (x2, for key
    # and value) for every key=value line - 3 forked processes per line.
    # A typical profile.conf has 30-50+ lines across its sections, so one
    # hsin_profile_load call could spawn 100-150+ processes. This runs on
    # every single Monitor tab poll (every ~2s), which is a real chunk of
    # why polling felt heavy on the T615. Rewritten with pure POSIX
    # parameter expansion + the shell's own word-splitting (`set --`) to
    # trim whitespace - same result, zero forks.
    _section=""
    while IFS= read -r _line; do
        # Skip comments and empty lines
        case "$_line" in
            ''|'#'*) continue ;;
        esac

        # Section header
        case "$_line" in
            \[*\])
                _section="${_line#\[}"
                _section="${_section%\]}"
                _section="${_section#"${_section%%[! ]*}"}"
                _section="${_section%"${_section##*[! ]}"}"
                continue
                ;;
        esac

        # Key=value pair
        case "$_line" in
            *=*)
                _key="${_line%%=*}"
                _val="${_line#*=}"
                # Trim leading/trailing spaces only (pure parameter
                # expansion, no fork) - unlike a naive `set -- $_val`
                # word-split, this keeps multi-word values (e.g. a
                # profile_description like "Default balanced mode")
                # intact instead of truncating to the first word.
                _key="${_key#"${_key%%[! ]*}"}"
                _key="${_key%"${_key##*[! ]}"}"
                _val="${_val#"${_val%%[! ]*}"}"
                _val="${_val%"${_val##*[! ]}"}"

                # Export as HSIN_PROFILE_<SECTION>_<KEY>
                _var="HSIN_PROFILE_${_section}_${_key}"
                eval "$_var=\"$_val\""
                ;;
        esac
    done < "$_conf"

    return 0
}

# Get profile value
hsin_profile_get() {
    _section="$1"
    _key="$2"
    _var="HSIN_PROFILE_${_section}_${_key}"
    eval "echo \"\$$_var\""
}

# List available profiles
hsin_profile_list() {
    for _conf in "$HSIN_MODULE_PATH/profiles"/*.conf; do
        [ -f "$_conf" ] || continue
        basename "$_conf" .conf
    done
}

# Print loaded profile
hsin_profile_print() {
    [ "$HSIN_PROFILE_LOADED" = "true" ] || { echo "No profile loaded"; return 1; }

    echo ""
    echo "╔══════════════════════════════════════╗"
    echo "║   Loaded Profile: $HSIN_PROFILE_NAME"
    echo "╚══════════════════════════════════════╝"
    echo ""

    # CPU
    printf "  CPU:\n"
    printf "    governor:      %s\n" "$(hsin_profile_get cpu governor)"
    printf "    freq_max:      %s%%\n" "$(hsin_profile_get cpu freq_max_percent)"
    printf "    freq_min:      %s%%\n" "$(hsin_profile_get cpu freq_min_percent)"
    printf "    cpuset:        %s\n" "$(hsin_profile_get cpu cpuset)"
    printf "    uclamp_max:    %s\n" "$(hsin_profile_get cpu uclamp_max)"
    echo ""

    # Memory
    printf "  Memory:\n"
    printf "    swappiness:    %s\n" "$(hsin_profile_get memory swappiness)"
    printf "    vfs_cache:     %s\n" "$(hsin_profile_get memory vfs_cache_pressure)"
    printf "    dirty_ratio:   %s\n" "$(hsin_profile_get memory dirty_ratio)"
    echo ""

    # GPU
    printf "  GPU:\n"
    printf "    allow_dvfs:    %s\n" "$(hsin_profile_get gpu allow_dvfs)"
    printf "    max_freq:      %s%%\n" "$(hsin_profile_get gpu max_freq_percent)"
    printf "    boost:         %s\n" "$(hsin_profile_get gpu boost)"
    echo ""

    # IO
    printf "  IO:\n"
    printf "    scheduler:     %s\n" "$(hsin_profile_get io scheduler)"
    printf "    readahead:     %s KB\n" "$(hsin_profile_get io readahead_kb)"
    echo ""

    # Network
    printf "  Network:\n"
    printf "    tcp:           %s\n" "$(hsin_profile_get network tcp_congestion)"
    echo ""

    # Thermal
    printf "  Thermal:\n"
    printf "    mode:          %s\n" "$(hsin_profile_get thermal mode)"
    echo ""
}

return 0 2>/dev/null || true
