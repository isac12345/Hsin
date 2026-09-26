#!/system/bin/sh
# HSIN - Validator & Node Checker

HSIN_DATA="${HSIN_DATA:-/data/adb/hsin}"
[ -z "$HSIN_MODULE_PATH" ] && HSIN_MODULE_PATH="/data/adb/modules/hsin"

# --- Blacklist System ---
HSIN_BLACKLIST="$HSIN_MODULE_PATH/config/blacklist.conf"

# Check if a path matches any blacklist pattern
hsin_is_blacklisted() {
    _path="$1"
    [ -f "$HSIN_BLACKLIST" ] || return 1
    while IFS= read -r _pattern; do
        # Skip comments and empty lines
        case "$_pattern" in
            ''|'#'*) continue ;;
        esac
        # Simple glob match: check if path starts with pattern prefix
        case "$_path" in
            "${_pattern}"*) return 0 ;;
        esac
        # Also check if the pattern directory is a prefix of the path
        _dir=$(dirname "$_path")
        case "$_dir" in
            "${_pattern}"*) return 0 ;;
        esac
    done < "$HSIN_BLACKLIST"
    return 1
}

# Validate path dapat ditulis dengan aman
hsin_validate_path() {
    _p="$1"
    # Blacklist check FIRST
    hsin_is_blacklisted "$_p" && return 5
    [ -e "$_p" ] || return 1
    [ -w "$_p" ] || return 2
    return 0
}

# Full node validation: exists + readable + writable + valid value + not blacklisted
hsin_node_check() {
    _path="$1"
    _status=""
    _read_val=""

    # 1. Blacklist check
    if hsin_is_blacklisted "$_path"; then
        echo "BLACKLISTED"
        return 5
    fi

    # 2. Existence check
    if [ ! -e "$_path" ]; then
        echo "NOT_FOUND"
        return 1
    fi
    _status="EXISTS"

    # 3. Readability check
    if [ -r "$_path" ]; then
        _read_val=$(cat "$_path" 2>/dev/null | head -c 256 | tr '\n' ' ')
        _status="${_status}|READABLE"
    else
        echo "${_status}|NOT_READABLE"
        return 2
    fi

    # 4. Writability check
    if [ -w "$_path" ]; then
        _status="${_status}|WRITABLE"
    else
        echo "${_status}|NOT_WRITABLE"
        return 2
    fi

    # 5. Safe value check (not empty, not obviously broken)
    _trimmed=$(echo "$_read_val" | tr -d ' \t\n\r')
    if [ -n "$_trimmed" ]; then
        _status="${_status}|SAFE"
    else
        _status="${_status}|EMPTY_VALUE"
    fi

    echo "$_status"
    return 0
}

# Comprehensive engine check: validate an entire engine's requirements
hsin_engine_check() {
    _engine="$1"; shift
    _usable=0
    _total=0
    _blacklisted=0
    _readonly=0

    for _node in "$@"; do
        _total=$((_total + 1))
        _result=$(hsin_node_check "$_node")
        # Order matters here: BLACKLISTED and NOT_WRITABLE have to come
        # before the generic WRITABLE match, since "NOT_WRITABLE" contains
        # the substring "WRITABLE" and would otherwise be miscounted as
        # usable. Previous version had them in the wrong order.
        case "$_result" in
            *BLACKLISTED*)
                _blacklisted=$((_blacklisted + 1))
                ;;
            *NOT_WRITABLE*)
                _readonly=$((_readonly + 1))
                ;;
            *WRITABLE*|*SAFE*)
                _usable=$((_usable + 1))
                ;;
        esac
    done

    echo "engine=$_engine total=$_total usable=$_usable readonly=$_readonly blacklisted=$_blacklisted"
}

# Validate numeric value dalam batas min..max (inklusif)
hsin_validate_number() {
    _v="$1"; _min="$2"; _max="$3"
    # Harus numeric
    case "$_v" in
        ''|*[!0-9]*) return 3 ;;
    esac
    [ "$_v" -ge "$_min" ] && [ "$_v" -le "$_max" ] || return 3
    return 0
}

# Validate string ada dalam list
hsin_validate_in_list() {
    _v="$1"; _list="$2"
    case " $_list " in
        *" $_v "*) return 0 ;;
        *) return 3 ;;
    esac
}

# Safe write: cek dulu sebelum tulis
hsin_safe_write() {
    _val="$1"; _path="$2"; _tries="${3:-3}"
    hsin_validate_path "$_path" || return $?
    _i=0
    while [ "$_i" -lt "$_tries" ]; do
        echo "$_val" > "$_path" 2>/dev/null || {
            _i=$((_i + 1)); sleep 0.2; continue;
        }
        # Verifikasi
        _cur=$(cat "$_path" 2>/dev/null | tr -d ' \n')
        if [ "$_cur" = "$_val" ]; then
            return 0
        fi
        _i=$((_i + 1))
        sleep 0.2
    done
    return 4
}

# Validate frekuensi: harus ada di scaling_available_frequencies, atau >= min && <= max
hsin_validate_freq() {
    _f="$1"; _p="$2"
    # 1. Cek di list available frekuensi
    if [ -f "$_p/scaling_available_frequencies" ]; then
        _avail=$(cat "$_p/scaling_available_frequencies" 2>/dev/null)
        case " $_avail " in
            *" $_f "*) return 0 ;;
        esac
    fi
    # 2. Fallback: harus di antara cpuinfo_min_freq dan cpuinfo_max_freq
    if [ -f "$_p/cpuinfo_min_freq" ] && [ -f "$_p/cpuinfo_max_freq" ]; then
        _min=$(cat "$_p/cpuinfo_min_freq" 2>/dev/null)
        _max=$(cat "$_p/cpuinfo_max_freq" 2>/dev/null)
        [ "$_f" -ge "$_min" ] && [ "$_f" -le "$_max" ] && return 0
    fi
    return 3
}

# Pick highest available frequency
hsin_pick_freq_max() {
    _p="$1"
    if [ -f "$_p/scaling_available_frequencies" ]; then
        cat "$_p/scaling_available_frequencies" 2>/dev/null | \
            tr ' ' '\n' | grep -v '^$' | sort -nr | head -1
        return 0
    fi
    if [ -f "$_p/cpuinfo_max_freq" ]; then
        cat "$_p/cpuinfo_max_freq" 2>/dev/null
        return 0
    fi
    return 1
}

# Pick middle OPP (50% dari available list)
hsin_pick_freq_mid() {
    _p="$1"
    if [ -f "$_p/scaling_available_frequencies" ]; then
        _list=$(cat "$_p/scaling_available_frequencies" 2>/dev/null)
        _total=$(echo "$_list" | wc -w)
        [ "$_total" -eq 0 ] && return 1
        _mid=$(( (_total + 1) / 2 ))
        echo "$_list" | tr ' ' '\n' | grep -v '^$' | sort -nr | \
            head -n "$_mid" | tail -n 1
        return 0
    fi
    return 1
}

# Pick lowest available
hsin_pick_freq_min() {
    _p="$1"
    if [ -f "$_p/scaling_available_frequencies" ]; then
        cat "$_p/scaling_available_frequencies" 2>/dev/null | \
            tr ' ' '\n' | grep -v '^$' | sort -n | head -1
        return 0
    fi
    if [ -f "$_p/cpuinfo_min_freq" ]; then
        cat "$_p/cpuinfo_min_freq" 2>/dev/null
        return 0
    fi
    return 1
}

# Validate core index (0..N-1, must exist and be online-able)
hsin_validate_core() {
    _c="$1"
    [ -d "/sys/devices/system/cpu/cpu$_c" ] || return 1
    return 0
}

# Validate storage device
hsin_validate_blockdev() {
    _d="$1"
    [ -d "/sys/block/$_d" ] || return 1
    return 0
}

# === MODE SYSTEM ===

HSIN_MODE="${HSIN_MODE:-balanced}"

# Set mode with validation
hsin_set_mode() {
    _mode="$1"
    case "$_mode" in
        strict|balanced)
            HSIN_MODE="$_mode"
            export HSIN_MODE
            return 0
            ;;
        extreme)
            if [ "${ALLOW_EXTREME:-false}" = "true" ]; then
                HSIN_MODE="extreme"
                export HSIN_MODE
                return 0
            else
                echo "[ERROR] Extreme mode requires ALLOW_EXTREME=true"
                return 1
            fi
            ;;
        *)
            echo "[ERROR] Unknown mode: $_mode (use strict|balanced|extreme)"
            return 1
            ;;
    esac
}

# Check if a risk level is allowed in current mode
hsin_risk_allowed() {
    _risk="$1"
    case "$HSIN_MODE" in
        strict)
            [ "$_risk" = "low" ] && return 0 || return 1
            ;;
        balanced)
            case "$_risk" in
                low|medium) return 0 ;;
                *) return 1 ;;
            esac
            ;;
        extreme)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# === DRY RUN MODE ===

HSIN_DRY_RUN="${HSIN_DRY_RUN:-false}"
HSIN_DRY_RUN_LOG=""

# Begin dry-run session
hsin_dry_run_begin() {
    HSIN_DRY_RUN="true"
    HSIN_DRY_RUN_LOG=""
    echo "[DRY RUN] Session started -- no changes will be made"
    echo ""
}

# End dry-run session and print summary
hsin_dry_run_end() {
    HSIN_DRY_RUN="false"
    if [ -n "$HSIN_DRY_RUN_LOG" ]; then
        echo ""
        echo "═══════════════════════════════════════"
        echo "  DRY RUN SUMMARY"
        echo "═══════════════════════════════════════"
        echo ""
        echo "$HSIN_DRY_RUN_LOG"
        echo ""
        echo "═══════════════════════════════════════"
        echo "  Total writes avoided: $(echo "$HSIN_DRY_RUN_LOG" | grep -c '^WOULD WRITE')"
        echo "═══════════════════════════════════════"
    else
        echo "[DRY RUN] No operations planned"
    fi
    echo ""
}

# Dry-run aware write: show what would happen without writing
hsin_dry_run() {
    _dr_path="$1"
    _dr_new="$2"
    _dr_risk="${3:-low}"
    _dr_desc="${4:-}"

    # Get current value
    _dr_old=""
    [ -f "$_dr_path" ] && [ -r "$_dr_path" ] && _dr_old=$(cat "$_dr_path" 2>/dev/null | head -c 128 | tr '\n' ' ')

    # Blacklist check
    if hsin_is_blacklisted "$_dr_path"; then
        echo "[DRY RUN] BLOCKED: $_dr_path is blacklisted"
        return 5
    fi

    # Risk check based on mode
    case "$HSIN_MODE" in
        strict)
            case "$_dr_risk" in
                high|medium)
                    echo "[DRY RUN] SKIP (strict mode): $_dr_path [risk=$_dr_risk]"
                    return 6
                    ;;
            esac
            ;;
        extreme)
            # Extreme mode allows everything (with ALLOW_EXTREME=true)
            ;;
        *)
            # balanced mode: skip high risk
            case "$_dr_risk" in
                high)
                    echo "[DRY RUN] SKIP (balanced mode): $_dr_path [risk=$_dr_risk]"
                    return 6
                    ;;
            esac
            ;;
    esac

    # Print dry-run output
    echo "WOULD WRITE:"
    echo "  PATH:  $_dr_path"
    echo "  OLD:   ${_dr_old:-<empty>}"
    echo "  NEW:   $_dr_new"
    echo "  RISK:  $_dr_risk"
    [ -n "$_dr_desc" ] && echo "  INFO:  $_dr_desc"
    if [ -n "$_dr_old" ]; then
        echo "  BACKUP: created (would restore on rollback)"
    else
        echo "  BACKUP: N/A (node did not exist or was empty)"
    fi
    echo ""

    # Append to dry-run log
    HSIN_DRY_RUN_LOG="${HSIN_DRY_RUN_LOG}WOULD WRITE: $_dr_path
  OLD: ${_dr_old:-<empty>}
  NEW: $_dr_new
  RISK: $_dr_risk
  $([ -n "$_dr_desc" ] && echo "INFO: $_dr_desc" || true)

"

    return 0
}

return 0 2>/dev/null || true
