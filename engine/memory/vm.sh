#!/system/bin/sh
# HSIN Memory Engine - VM Tuning

[ -z "$HSIN_MODULE_PATH" ] && HSIN_MODULE_PATH="/data/adb/modules/hsin"
. "$HSIN_MODULE_PATH/core/logger.sh" 2>/dev/null
# Override knob user (swappiness).
. "$HSIN_MODULE_PATH/core/user_knobs.sh" 2>/dev/null
# shellcheck disable=SC1091
. "$HSIN_MODULE_PATH/core/scan_cache.sh" 2>/dev/null
# Path proc dari core/scan_cache.sh (satu-satunya definisi), default sama
# dengan path yang sebelumnya ditulis langsung di file ini.
[ -n "$HSIN_PROC" ] || HSIN_PROC="${SYSFS_PROC_PREFIX:-/proc}"

# Safe VM tunables with ranges
HSIN_VM_SAFE="
swappiness|0|200|120|100|60|40
vfs_cache_pressure|0|1000|50|100|150|200
dirty_ratio|1|90|40|30|20|10
dirty_background_ratio|1|50|10|5|3|1
page-cluster|0|5|3|3|2|0
"

# Read VM node
hsin_vm_read() {
    _name="$1"
    _path="$HSIN_PROC/sys/vm/$_name"
    [ -f "$_path" ] && cat "$_path" 2>/dev/null || echo ""
}

# Write VM node with validation
hsin_vm_write() {
    _name="$1"
    _val="$2"
    _path="$HSIN_PROC/sys/vm/$_name"

    # Check node exists
    [ -f "$_path" ] || return 1

    # Check writable
    [ -w "$_path" ] || return 1

    # Guard against empty value - nothing to write, would blank the
    # node on some shells.
    [ -n "$_val" ] || return 1

    # Find min/max from safe list.
    # BUG FIX: piping into `while` (`echo ... | while ...`) runs the loop
    # in a subshell, so _min/_max set inside it never survived past the
    # loop's end - they always stayed at the 0/999999 fallback below,
    # which means the range check further down effectively never
    # rejected anything. Switched to a heredoc-fed loop (no pipe, no
    # subshell) so the match actually updates _min/_max in this
    # function's own scope.
    _min=0; _max=999999
    while IFS='|' read -r _n _mn _mx _def_b _def_bal _def_p _def_e; do
        [ "$_n" = "$_name" ] && { _min="$_mn"; _max="$_mx"; break; }
    done <<EOF
$HSIN_VM_SAFE
EOF

    # Validate range
    [ "$_val" -lt "$_min" ] 2>/dev/null && return 1
    [ "$_val" -gt "$_max" ] 2>/dev/null && return 1

    # Write
    echo "$_val" > "$_path" 2>/dev/null || return 1

    # Verify
    _verify=$(cat "$_path" 2>/dev/null)
    [ "$_verify" = "$_val" ] && return 0 || return 1
}

# Get recommended value for profile
hsin_vm_recommended() {
    _name="$1"
    _profile="$2"

    while IFS='|' read -r _n _mn _mx _def_b _def_bal _def_p _def_e; do
        [ "$_n" = "$_name" ] || continue
        case "$_profile" in
            battery)     printf '%s\n' "$_def_b"; return 0 ;;
            balanced)    printf '%s\n' "$_def_bal"; return 0 ;;
            performance) printf '%s\n' "$_def_p"; return 0 ;;
            extreme)     printf '%s\n' "$_def_e"; return 0 ;;
        esac
    done <<EOF
$HSIN_VM_SAFE
EOF
}

# Backup current VM state
hsin_vm_backup() {
    _backup_dir="$1"
    [ -d "$_backup_dir" ] || mkdir -p "$_backup_dir" 2>/dev/null

    {
        while IFS='|' read -r _n _mn _mx _def_b _def_bal _def_p _def_e; do
            [ -z "$_n" ] && continue
            _cur=$(hsin_vm_read "$_n")
            [ -n "$_cur" ] && echo "$_n=$_cur"
        done <<EOF
$HSIN_VM_SAFE
EOF
    } > "$_backup_dir/vm_state" 2>/dev/null

    echo "$_backup_dir"
}

# Restore VM state from backup
hsin_vm_restore() {
    _backup_dir="$1"
    [ -f "$_backup_dir/vm_state" ] || return 1

    while IFS='=' read -r _name _val; do
        [ -n "$_name" ] && hsin_vm_write "$_name" "$_val" 2>/dev/null
    done < "$_backup_dir/vm_state"

    return 0
}

# Apply VM tunables for profile
hsin_vm_apply() {
    _profile="$1"
    _ok=0
    _skip=0

    while IFS='|' read -r _n _mn _mx _def_b _def_bal _def_p _def_e; do
        [ -z "$_n" ] && continue

        # Knob user (K1): swappiness + 3 VM baru. page-cluster bukan knob
        # (echo saja, tanpa baris hasil).
        _is_knob=0
        case "$_n" in
            swappiness|vfs_cache_pressure|dirty_ratio|dirty_background_ratio)
                _is_knob=1 ;;
        esac

        _val=""
        case "$_profile" in
            battery)     _val="$_def_b" ;;
            balanced)    _val="$_def_bal" ;;
            performance) _val="$_def_p" ;;
            extreme)     _val="$_def_e" ;;
        esac

        # Override knob user, tetap lewat hsin_vm_write: rentang diambil
        # dari HSIN_VM_SAFE di fungsi itu, jadi tidak ada rentang kedua
        # yang bisa tidak sinkron dengan yang sudah ada di file ini.
        _uk_val=""
        [ "$_is_knob" = "1" ] && _uk_val=$(hsin_uk_get "$_n" 2>/dev/null)
        # Validasi silang K1 (keputusan user): dirty_background_ratio
        # WAJIB < dirty_ratio (strict). Langgar = FALLBACK beralasan,
        # bukan tulis buta. Non-manual: pakai nilai profil. Manual:
        # TANPA TULIS (applied = nilai live saat ini).
        _bg_rejected=0
        if [ "$_n" = "dirty_background_ratio" ] && [ -n "$_uk_val" ]; then
            _eff_ratio=$(hsin_uk_get dirty_ratio 2>/dev/null)
            if [ -z "$_eff_ratio" ]; then
                if [ "$_profile" = "manual" ]; then
                    _eff_ratio=$(hsin_vm_read dirty_ratio)
                else
                    _eff_ratio=$(hsin_vm_recommended dirty_ratio "$_profile")
                fi
            fi
            case "$_eff_ratio" in ''|*[!0-9]*) _eff_ratio="" ;; esac
            if [ -n "$_eff_ratio" ] && [ "$_uk_val" -ge "$_eff_ratio" ] 2>/dev/null; then
                _bg_why="ditolak: dirty_background_ratio ($_uk_val) >= dirty_ratio ($_eff_ratio)"
                hsin_log_warn "vm" "override dirty_background_ratio=$_uk_val $_bg_why"
                if [ "$_profile" = "manual" ]; then
                    _cur_bg=$(hsin_vm_read dirty_background_ratio)
                    [ -n "$_cur_bg" ] || _cur_bg="-"
                    hsin_uk_result "dirty_background_ratio" "$_uk_val" "$_cur_bg" "FALLBACK" "$_bg_why (mode manual, tidak ditulis)" 2>/dev/null || true
                    _uk_val=""
                    _bg_rejected=1
                    continue
                else
                    _val=$(hsin_vm_recommended dirty_background_ratio "$_profile")
                    hsin_uk_result "dirty_background_ratio" "$_uk_val" "$_val" "FALLBACK" "$_bg_why, pakai profil" 2>/dev/null || true
                    _uk_val=""
                    _bg_rejected=1
                fi
            fi
        fi
        if [ -n "$_uk_val" ]; then
            _val="$_uk_val"
            hsin_uk_used "vm" "$_n" "$_val"
        fi
        if [ "$_is_knob" = "1" ] && [ -z "$_uk_val" ] && [ "$_bg_rejected" -eq 0 ] && [ "$_profile" != "manual" ]; then
            hsin_uk_result "$_n" "(profil)" "$_val" "APPLIED" "nilai profil (tanpa override)" 2>/dev/null || true
        fi

        # Mode manual: tanpa override, dilewati. Knob mencatat SKIPPED
        # (baris hasil); non-knob echo saja (bukan namespace knob).
        if [ "$_profile" = "manual" ] && [ -z "$_uk_val" ]; then
            if [ "$_is_knob" = "1" ]; then
                [ "$_bg_rejected" -eq 0 ] && hsin_uk_result "$_n" "(manual)" "-" "SKIPPED" "tidak diatur (mode manual)" 2>/dev/null || true
            else
                echo "    vm.$_n dilewati (mode manual)"
            fi
            continue
        fi

        if [ -n "$_val" ]; then
            # Check if already set
            _cur=$(hsin_vm_read "$_n")
            [ "$_cur" = "$_val" ] && {
                echo "    vm.$_n = $_val (already set)"
                continue
            }

            if hsin_vm_write "$_n" "$_val"; then
                echo "    vm.$_n = $_val ✓"
            else
                echo "    vm.$_n: skip (not writable or invalid)"
                if [ -n "$_uk_val" ]; then
                    hsin_log_warn "vm" "override $_n=$_uk_val gagal ditulis/tidak valid"
                    # Node hilang/tidak writable = UNAVAILABLE; selain itu
                    # (nilai di luar rentang, kernel menolak) = FAILED.
                    # Baris hasil sebelumnya sudah APPLIED dari hsin_uk_used
                    # saat override diterima, jadi ditulis ulang di sini -
                    # hsin_uk_result mengganti baris key yang sama.
                    if [ -f "$HSIN_PROC/sys/vm/$_n" ] && [ -w "$HSIN_PROC/sys/vm/$_n" ]; then
                        hsin_uk_result "$_n" "$_uk_val" "-" "FAILED" "nilai ditolak kernel / tulis gagal" 2>/dev/null || true
                    else
                        hsin_uk_result "$_n" "$_uk_val" "-" "UNAVAILABLE" "node hilang atau tidak writable" 2>/dev/null || true
                    fi
                fi
            fi
        fi
    done <<EOF
$HSIN_VM_SAFE
EOF
}

# Get current VM state
hsin_vm_state() {
    echo "  VM State:"
    while IFS='|' read -r _n _mn _mx _def_b _def_bal _def_p _def_e; do
        [ -z "$_n" ] && continue
        _cur=$(hsin_vm_read "$_n")
        _w="false"
        [ -w "$HSIN_PROC/sys/vm/$_n" ] && _w="true"
        printf "    %-30s = %-10s (writable=%s)\n" "$_n" "${_cur:-?}" "$_w"
    done <<EOF
$HSIN_VM_SAFE
EOF
}

return 0 2>/dev/null || true
