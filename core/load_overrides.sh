#!/system/bin/sh
# HSIN Override Loader (STEP 9 / PQ Step 9) — capability signature match.
#
# Membaca HASIL detector.sh yang BENERAN ada (device.txt: CPU_POLICIES,
# GOVS, THERMAL, THERMAL_W) + satu cek writability live (devfreq), lalu
# mencocokkan ke signatures di capability/capability_overrides.json.
# Cocok pertama menang -> export profile_hints. Tidak ada yang cocok
# (atau data cacat/hilang) -> default_fallback + log WAJIB
# "no signature match, using default fallback".
#
# KONTRAK KERAS: file ini TIDAK PERNAH menulis sysfs/proc. Hanya export
# variabel + log. Apply layer (safe_apply.sh) yang memakai hints.
# TIDAK PERNAH membaca SOC/VENDOR/GPU (nama chipset/vendor) — match murni
# capability. detector.sh TIDAK diubah (kontrak stabil).
#
# Export:
#   HSIN_OV_MATCHED (1/0), HSIN_OV_SOURCE (signature:<name>/default_fallback),
#   HSIN_OV_CPU_GOV_PREF (daftar spasi), HSIN_OV_GPU_PCT_BATTERY/_BALANCED/
#   _PERFORMANCE (int), HSIN_OV_THERMAL_CLASS (managed/unmanaged).

[ -z "$HSIN_MODULE_PATH" ] && HSIN_MODULE_PATH="/data/adb/modules/hsin"
HSIN_DATA="${HSIN_DATA:-/data/adb/hsin}"
# shellcheck disable=SC1091
. "$HSIN_MODULE_PATH/core/sysfs.sh" 2>/dev/null

HSIN_OVERRIDES_FILE="${HSIN_OVERRIDES_FILE:-$HSIN_MODULE_PATH/capability/capability_overrides.json}"
HSIN_DEVICE_TXT="${HSIN_DEVICE_TXT:-$HSIN_DATA/device.txt}"
HSIN_SYSFS_DEVFREQ="${HSIN_SYSFS_DEVFREQ:-/sys/class/devfreq}"

HSIN_OV_MATCHED=0
HSIN_OV_SOURCE="default_fallback"
HSIN_OV_CPU_GOV_PREF="schedutil"
HSIN_OV_GPU_PCT_BATTERY=50
HSIN_OV_GPU_PCT_BALANCED=65
HSIN_OV_GPU_PCT_PERFORMANCE=80
HSIN_OV_THERMAL_CLASS="unmanaged"

_hlo_log() {
    _hlo_lvl="$1"
    _hlo_msg="$2"
    if command -v hsin_log_info >/dev/null 2>&1; then
        case "$_hlo_lvl" in
            WARN) hsin_log_warn "overrides" "$_hlo_msg" 2>/dev/null || hsin_log_info "overrides" "$_hlo_msg" ;;
            *) hsin_log_info "overrides" "$_hlo_msg" ;;
        esac
    else
        echo "[overrides] [$_hlo_lvl] $_hlo_msg" >&2
    fi
    return 0
}

# Angka aman: kosong/non-numerik -> "" (artinya "unknown", kondisi gagal).
_hlo_num() {
    printf '%s' "$1" | tr -cd '0-9'
}

# Token exact-match dalam daftar spasi.
_hlo_token_in() {
    case " $2 " in
        *" $1 "*) return 0 ;;
    esac
    return 1
}

# Cek live: ada devfreq kandidat GPU yang writable (max_freq/governor)?
_hlo_devfreq_writable() {
    _hlo_d=""
    for _hlo_d in "$HSIN_SYSFS_DEVFREQ"/*; do
        [ -d "$_hlo_d" ] || continue
        if command -v hsin_devfreq_gpu_candidate >/dev/null 2>&1; then
            hsin_devfreq_gpu_candidate "$_hlo_d" 2>/dev/null || continue
        else
            _hlo_n=$(basename "$_hlo_d" 2>/dev/null | tr '[:upper:]' '[:lower:]')
            case "$_hlo_n" in
                *gpu*|*gfx*|*mali*|*kgsl*|*adreno*) ;;
                *) continue ;;
            esac
        fi
        if [ -w "$_hlo_d/max_freq" ] || [ -w "$_hlo_d/governor" ]; then
            return 0
        fi
    done
    return 1
}

# Parse JSON schema capability_overrides.json -> baris flat:
#   M|<idx>|<key>|<value>   (match conditions)
#   H|<idx>|<key>|<value>   (profile hints; idx=DEF = default_fallback)
# Parser key-based (tahan reindent json.tool), khusus schema ini.
_hlo_parse_json() {
    awk '
    function emit(tag, idx, k, v) { print tag "|" idx "|" k "|" v }
    function sval(line,    a, n) {
        n = split(line, a, "\"")
        if (n >= 4) return a[4]
        sub(/.*:[ \t]*/, "", line); gsub(/[,} \t]/, "", line)
        return line
    }
    BEGIN { sig = -1; mode = ""; inarr = 0; arr = ""; ingpu = 0 }
    /"default_fallback"/ { sig = -1; isdef = 1; mode = "hints"; next }
    /"signatures"/ { next }
    /"name"/ && mode != "hints" && isdef != 1 {
        sig++; mode = "head"; emit("M", sig, "name", sval($0)); next
    }
    /"match"/ && mode != "hints" { mode = "match"; next }
    /"profile_hints"/ { mode = "hints"; next }
    mode == "match" && /"cpu_policy_count_min"/ { emit("M", sig, "cpu_policy_count_min", sval($0)); next }
    mode == "match" && /"governor_list_contains"/ { emit("M", sig, "governor_list_contains", sval($0)); next }
    mode == "match" && /"devfreq_writable"/ { emit("M", sig, "devfreq_writable", sval($0)); next }
    mode == "match" && /"thermal_zone_count_min"/ { emit("M", sig, "thermal_zone_count_min", sval($0)); next }
    mode == "hints" && /"cpu_gov_preference"/ {
        if ($0 ~ /\]/) {
            arr = $0; gsub(/.*\[/, "", arr); gsub(/\].*/, "", arr)
            gsub(/"/, "", arr); gsub(/,/, " ", arr); gsub(/^ +| +$/, "", arr)
            if (isdef == 1) emit("H", "DEF", "gov_pref", arr); else emit("H", sig, "gov_pref", arr)
        } else { inarr = 1; arr = "" }
        next
    }
    inarr == 1 {
        l = $0; gsub(/"/, "", l); gsub(/,/, " ", l); gsub(/^ +| +$/, "", l)
        if ($0 ~ /\]/) { inarr = 0 }
        else { arr = (arr == "" ? l : arr " " l); next }
        if (arr == "") { arr = l }
        if (isdef == 1) emit("H", "DEF", "gov_pref", arr); else emit("H", sig, "gov_pref", arr)
        arr = ""; next
    }
    mode == "hints" && /"gpu_max_percent"/ && $0 !~ /\}/ { ingpu = 1; next }
    ingpu == 1 && /"battery"/ { if (isdef == 1) emit("H", "DEF", "gpu_battery", sval($0)); else emit("H", sig, "gpu_battery", sval($0)); next }
    ingpu == 1 && /"balanced"/ { if (isdef == 1) emit("H", "DEF", "gpu_balanced", sval($0)); else emit("H", sig, "gpu_balanced", sval($0)); next }
    ingpu == 1 && /"performance"/ { if (isdef == 1) emit("H", "DEF", "gpu_performance", sval($0)); else emit("H", sig, "gpu_performance", sval($0)); next }
    mode == "hints" && /"thermal_class"/ { if (isdef == 1) emit("H", "DEF", "thermal_class", sval($0)); else emit("H", sig, "thermal_class", sval($0)); next }
    /\}/ { if (ingpu == 1) ingpu = 0; else if (mode == "hints") mode = ""; else if (mode == "match") mode = "" }
    ' "$1" 2>/dev/null
    return 0
}

# Terapkan hints yang sudah tersanitasi ke export.
_hlo_apply_hints() {
    _hlo_gov="$1"
    _hlo_bat="$2"
    _hlo_bal="$3"
    _hlo_prf="$4"
    _hlo_thm="$5"
    # Sanitasi: gov token aman saja; persen numerik 0-100; class dikenal saja.
    _hlo_gov_clean=""
    for _hlo_g in $_hlo_gov; do
        case "$_hlo_g" in
            *[!A-Za-z0-9_-]*) continue ;;
            *) _hlo_gov_clean="${_hlo_gov_clean:+$_hlo_gov_clean }$_hlo_g" ;;
        esac
    done
    [ -n "$_hlo_gov_clean" ] && HSIN_OV_CPU_GOV_PREF="$_hlo_gov_clean"
    _hlo_bat_n=$(_hlo_num "$_hlo_bat")
    _hlo_bal_n=$(_hlo_num "$_hlo_bal")
    _hlo_prf_n=$(_hlo_num "$_hlo_prf")
    if [ -n "$_hlo_bat_n" ] && [ "$_hlo_bat_n" -ge 0 ] 2>/dev/null && [ "$_hlo_bat_n" -le 100 ] 2>/dev/null; then
        HSIN_OV_GPU_PCT_BATTERY="$_hlo_bat_n"
    fi
    if [ -n "$_hlo_bal_n" ] && [ "$_hlo_bal_n" -ge 0 ] 2>/dev/null && [ "$_hlo_bal_n" -le 100 ] 2>/dev/null; then
        HSIN_OV_GPU_PCT_BALANCED="$_hlo_bal_n"
    fi
    if [ -n "$_hlo_prf_n" ] && [ "$_hlo_prf_n" -ge 0 ] 2>/dev/null && [ "$_hlo_prf_n" -le 100 ] 2>/dev/null; then
        HSIN_OV_GPU_PCT_PERFORMANCE="$_hlo_prf_n"
    fi
    case "$_hlo_thm" in
        managed|unmanaged) HSIN_OV_THERMAL_CLASS="$_hlo_thm" ;;
    esac
    return 0
}

# Entry utama: baca detector output -> match -> export hints/default.
hsin_override_load() {
    # 1. Baca device.txt (sumber JUJUR detector.sh). Hilang = langsung default.
    _hlo_policies=""
    _hlo_govs=""
    _hlo_thermal=""
    if [ -f "$HSIN_DEVICE_TXT" ]; then
        _hlo_policies=$(grep -m1 '^CPU_POLICIES=' "$HSIN_DEVICE_TXT" 2>/dev/null | cut -d= -f2-)
        _hlo_govs=$(grep -m1 '^GOVS=' "$HSIN_DEVICE_TXT" 2>/dev/null | cut -d= -f2-)
        _hlo_thermal=$(grep -m1 '^THERMAL=' "$HSIN_DEVICE_TXT" 2>/dev/null | cut -d= -f2-)
    fi
    # cpu_policy_count = hitung token (TANPA fallback "policy0" ala detector —
    # di sini unknown harus tetap unknown supaya jatuh ke default).
    _hlo_cpu_n=""
    if [ -n "$_hlo_policies" ]; then
        # shellcheck disable=SC2086
        set -- $_hlo_policies
        _hlo_cpu_n="$#"
    fi
    _hlo_thermal_n=$(_hlo_num "$_hlo_thermal")
    if _hlo_devfreq_writable 2>/dev/null; then
        _hlo_df="true"
    else
        _hlo_df="false"
    fi

    # 2. JSON hilang = hardcoded aman + WARN (bukan baca karangan).
    if [ ! -f "$HSIN_OVERRIDES_FILE" ]; then
        _hlo_log "WARN" "overrides file missing ($HSIN_OVERRIDES_FILE) — no signature match, using default fallback"
        HSIN_OV_MATCHED=0
        HSIN_OV_SOURCE="default_fallback"
        return 0
    fi

    # 3. Evaluasi signatures urut (pertama yang cocok menang).
    _hlo_parsed=$(_hlo_parse_json "$HSIN_OVERRIDES_FILE")
    _hlo_idx=0
    while :; do
        _hlo_name=$(printf '%s' "$_hlo_parsed" | awk -F'|' -v i="$_hlo_idx" '$1=="M" && $2==i && $3=="name" {print $4; exit}')
        [ -n "$_hlo_name" ] || break
        _hlo_ok=1
        _hlo_cmin=$(printf '%s' "$_hlo_parsed" | awk -F'|' -v i="$_hlo_idx" '$1=="M" && $2==i && $3=="cpu_policy_count_min" {print $4; exit}')
        if [ -n "$_hlo_cmin" ]; then
            if [ -z "$_hlo_cpu_n" ] || [ "$_hlo_cpu_n" -lt "$_hlo_cmin" ] 2>/dev/null; then
                _hlo_ok=0
            fi
        fi
        _hlo_gneed=$(printf '%s' "$_hlo_parsed" | awk -F'|' -v i="$_hlo_idx" '$1=="M" && $2==i && $3=="governor_list_contains" {print $4; exit}')
        if [ -n "$_hlo_gneed" ]; then
            _hlo_token_in "$_hlo_gneed" "$_hlo_govs" || _hlo_ok=0
        fi
        _hlo_dfneed=$(printf '%s' "$_hlo_parsed" | awk -F'|' -v i="$_hlo_idx" '$1=="M" && $2==i && $3=="devfreq_writable" {print $4; exit}')
        if [ -n "$_hlo_dfneed" ]; then
            [ "$_hlo_df" = "$_hlo_dfneed" ] || _hlo_ok=0
        fi
        _hlo_tmin=$(printf '%s' "$_hlo_parsed" | awk -F'|' -v i="$_hlo_idx" '$1=="M" && $2==i && $3=="thermal_zone_count_min" {print $4; exit}')
        if [ -n "$_hlo_tmin" ]; then
            if [ -z "$_hlo_thermal_n" ] || [ "$_hlo_thermal_n" -lt "$_hlo_tmin" ] 2>/dev/null; then
                _hlo_ok=0
            fi
        fi
        if [ "$_hlo_ok" -eq 1 ]; then
            _hlo_apply_hints \
                "$(printf '%s' "$_hlo_parsed" | awk -F'|' -v i="$_hlo_idx" '$1=="H" && $2==i && $3=="gov_pref" {print $4; exit}')" \
                "$(printf '%s' "$_hlo_parsed" | awk -F'|' -v i="$_hlo_idx" '$1=="H" && $2==i && $3=="gpu_battery" {print $4; exit}')" \
                "$(printf '%s' "$_hlo_parsed" | awk -F'|' -v i="$_hlo_idx" '$1=="H" && $2==i && $3=="gpu_balanced" {print $4; exit}')" \
                "$(printf '%s' "$_hlo_parsed" | awk -F'|' -v i="$_hlo_idx" '$1=="H" && $2==i && $3=="gpu_performance" {print $4; exit}')" \
                "$(printf '%s' "$_hlo_parsed" | awk -F'|' -v i="$_hlo_idx" '$1=="H" && $2==i && $3=="thermal_class" {print $4; exit}')"
            HSIN_OV_MATCHED=1
            case "$_hlo_name" in
                *[!A-Za-z0-9_-]*) _hlo_name="sig$_hlo_idx" ;;
            esac
            HSIN_OV_SOURCE="signature:$_hlo_name"
            _hlo_log "INFO" "signature '$_hlo_name' matched (cpu_policies=${_hlo_cpu_n:-?} govs='${_hlo_govs:-?}' devfreq_writable=$_hlo_df thermal=${_hlo_thermal_n:-?}) -> gov_pref='$HSIN_OV_CPU_GOV_PREF' gpu_pct=$HSIN_OV_GPU_PCT_BATTERY/$HSIN_OV_GPU_PCT_BALANCED/$HSIN_OV_GPU_PCT_PERFORMANCE thermal=$HSIN_OV_THERMAL_CLASS"
            return 0
        fi
        _hlo_idx=$((_hlo_idx + 1))
    done

    # 4. Tidak ada yang cocok -> default_fallback dari JSON + log WAJIB.
    _hlo_apply_hints \
        "$(printf '%s' "$_hlo_parsed" | awk -F'|' '$1=="H" && $2=="DEF" && $3=="gov_pref" {print $4; exit}')" \
        "$(printf '%s' "$_hlo_parsed" | awk -F'|' '$1=="H" && $2=="DEF" && $3=="gpu_battery" {print $4; exit}')" \
        "$(printf '%s' "$_hlo_parsed" | awk -F'|' '$1=="H" && $2=="DEF" && $3=="gpu_balanced" {print $4; exit}')" \
        "$(printf '%s' "$_hlo_parsed" | awk -F'|' '$1=="H" && $2=="DEF" && $3=="gpu_performance" {print $4; exit}')" \
        "$(printf '%s' "$_hlo_parsed" | awk -F'|' '$1=="H" && $2=="DEF" && $3=="thermal_class" {print $4; exit}')"
    HSIN_OV_MATCHED=0
    HSIN_OV_SOURCE="default_fallback"
    _hlo_log "WARN" "no signature match, using default fallback (cpu_policies=${_hlo_cpu_n:-?} govs='${_hlo_govs:-?}' devfreq_writable=$_hlo_df thermal=${_hlo_thermal_n:-?})"
    return 0
}

return 0 2>/dev/null || true
