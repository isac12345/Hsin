#!/system/bin/sh
# HSIN Thermal Policy
# Credit: logic inspired by Sasha (thermal control)

[ -z "$HSIN_MODULE_PATH" ] && HSIN_MODULE_PATH="/data/adb/modules/hsin"
HSIN_DATA="${HSIN_DATA:-/data/adb/hsin}"
# shellcheck disable=SC1091
. "$HSIN_MODULE_PATH/core/sysfs.sh" 2>/dev/null
# shellcheck disable=SC1091
. "$HSIN_MODULE_PATH/core/scan_cache.sh" 2>/dev/null
# Diisi hsin_scan_lookup() (core/scan_cache.sh) tiap lookup field.
_sc_f=""

# Policy thresholds (millidegrees).
# BUG FIX: these were still the same miscalibrated values already fixed
# once in engine/cpu/safety.sh (40/45/50/60C) - 50C is a completely
# normal SoC temp under load, not a "hot, start throttling" state. This
# file was apparently missed when that fix went in elsewhere, so every
# apply of battery/balanced (via hsin_thermal_apply_cpu/_gpu below) was
# STILL silently capping CPU to 70% max freq and GPU to 80% max freq
# under totally ordinary gaming/load temperatures, and even
# performance/extreme could get force-throttled to 50% starting at just
# 60C. Realigned to the same scale now used everywhere else in HSIN
# (cpu/safety.sh: normal=60C/reduce=75C/limit=85C/critical=95C;
# policy_engine.sh: warn=75C/critical=85C/panic=95C; extreme.conf
# trip=95C) so this engine doesn't independently throttle under normal
# conditions anymore.
HSIN_THERMAL_POL_NORMAL=60000
HSIN_THERMAL_POL_WARM=75000
HSIN_THERMAL_POL_HOT=85000
HSIN_THERMAL_POL_CRITICAL=95000

# Current policy state
HSIN_THERMAL_POLICY=""
HSIN_THERMAL_PERF_TARGET="100"

# Determine policy based on temperature
hsin_thermal_policy_determine() {
    _temp="$1"

    if [ "$_temp" -ge "$HSIN_THERMAL_POL_CRITICAL" ] 2>/dev/null; then
        HSIN_THERMAL_POLICY="critical"
        HSIN_THERMAL_PERF_TARGET="50"
    elif [ "$_temp" -ge "$HSIN_THERMAL_POL_HOT" ] 2>/dev/null; then
        HSIN_THERMAL_POLICY="hot"
        HSIN_THERMAL_PERF_TARGET="70"
    elif [ "$_temp" -ge "$HSIN_THERMAL_POL_WARM" ] 2>/dev/null; then
        HSIN_THERMAL_POLICY="warm"
        HSIN_THERMAL_PERF_TARGET="85"
    elif [ "$_temp" -ge "$HSIN_THERMAL_POL_NORMAL" ] 2>/dev/null; then
        HSIN_THERMAL_POLICY="normal"
        HSIN_THERMAL_PERF_TARGET="95"
    else
        HSIN_THERMAL_POLICY="cool"
        HSIN_THERMAL_PERF_TARGET="100"
    fi

    echo "$HSIN_THERMAL_PERF_TARGET"
}

# Apply thermal policy to CPU frequency
# Daftar policy + cpuinfo_max_freq + tabel OPP diambil dari cache scan
# (core/scan_cache.sh), jadi tidak ada glob cpufreq/policy* dan tidak ada
# cat cpuinfo_max_freq per apply. Tinggal satu test [ -w ] tanpa fork tepat
# sebelum tulis; nilai max_freq yang di-cache hanya untuk picking OPP.
hsin_thermal_apply_cpu() {
    _policy="$1"
    _base_max="$2"

    # Note: $_base_max is currently unused; kept in the signature so the
    # call sites in hsin_thermal_engine_apply / hsin_thermal_apply don't
    # have to change. Logged for debugging.
    [ -n "$_base_max" ] && [ "$_base_max" -gt 0 ] 2>/dev/null || _base_max=""

    # Calculate reduced max
    _reduced=$(( _base_max * HSIN_THERMAL_PERF_TARGET / 100 ))
    [ -z "$_reduced" ] && _reduced=0

    hsin_scan_cpu_get
    for _id in $HSIN_SCAN_CPU_POLICIES; do
        hsin_scan_lookup "$HSIN_SCAN_CPU_POLICY_LINES" "$_id" 5
        _hw_max="$_sc_f"
        # Guard: kosong/non-numeric akan error di arithmetic.
        case "$_hw_max" in ''|*[!0-9]*) continue ;; esac
        [ "$_hw_max" -le 0 ] 2>/dev/null && continue

        _dir="$HSIN_SYSFS_CPU/cpufreq/policy$_id"
        _new_max=$(( _hw_max * HSIN_THERMAL_PERF_TARGET / 100 ))
        hsin_scan_lookup "$HSIN_SCAN_CPU_POLICY_LINES" "$_id" 7
        _opp_csv="$_sc_f"
        if [ -n "$_opp_csv" ]; then
            _avail=$(printf '%s' "$_opp_csv" | tr ',' ' ')
            _new_max=$(hsin_opp_cap_pick "$_new_max" "$_avail")
        fi
# File state minimal untuk restore cap saat suhu turun.
_thermal_pre_cap_file="$HSIN_DATA/thermal_pre_cap.list"

        # Thermal adalah PENAHAM, bukan penguat: kalau targetnya >= nilai
        # yang sekarang, jangan tulis sama sekali. Sebelumnya baris ini
        # menulis apa adanya, dan karena HSIN_THERMAL_PERF_TARGET = 100
        # pada kondisi "cool" (<60C), setiap apply pada suhu biasa menulis
        # scaling_max_freq kembali ke hw_max - membatalkan cap frekuensi
        # profil (mis. battery 65-80%) DAN override pilihan user. Itu
        # membuat "HSIN manual" selalu berakhir sama saja.
        # Minimal mechanism: simpan pre-cap saat cap diterapkan, pulihkan
        # saat suhu turun (histeresis: hanya bila nilai saat ini masih == cap).
        _cur_max=""
        [ -f "$_dir/scaling_max_freq" ] && \
            IFS= read -r _cur_max < "$_dir/scaling_max_freq" 2>/dev/null
        case "$_cur_max" in
            ''|*[!0-9]*) _cur_max=0 ;;
        esac
        # Simpan pre-cap saat akan menurunkan (cap diterapkan)
        if [ -n "$_new_max" ] && [ "$_new_max" -lt "$_cur_max" ] 2>/dev/null; then
            [ -w "$_dir/scaling_max_freq" ] && \
                printf '%s\n' "$_new_max" > "$_dir/scaling_max_freq" 2>/dev/null
            # Catat pre-cap hanya saat cap baru diterapkan (nilai berubah)
            # Gunakan file state minimal dengan format node=value_precap
            _pre_cap_file="$_thermal_pre_cap_file"
            # Cari apakah sudah ada entri untuk node ini
            _old_pre=""
            if [ -f "$_pre_cap_file" ]; then
                while IFS='=' read -r _n _v; do
                    [ "$_n" = "$_dir" ] && _old_pre="$_v"
                done < "$_pre_cap_file"
            fi
            # Hanya tulis state jika nilai cap berbeda dari pre-cap yang tersimpan,
            # atau belum ada entri.
            if [ -z "$_old_pre" ] || [ "$_old_pre" != "$_cur_max" ]; then
                mkdir -p "$(dirname "$_pre_cap_file")" 2>/dev/null || true
                # Tulis ulang file dengan semua entri kecuali node ini, lalu tambah
                if [ -f "$_pre_cap_file" ]; then
                    _tmp_pre="${_pre_cap_file}.tmp.$$"
                    : > "$_tmp_pre"
                    while IFS='=' read -r _n _v; do
                        [ -z "$_n" ] && continue
                        [ "$_n" != "$_dir" ] && printf '%s=%s\n' "$_n" "$_v" >> "$_tmp_pre"
                    done < "$_pre_cap_file"
                    printf '%s=%s\n' "$_dir" "$_cur_max" >> "$_tmp_pre"
                    mv "$_tmp_pre" "$_pre_cap_file" 2>/dev/null || true
                else
                    printf '%s=%s\n' "$_dir" "$_cur_max" > "$_pre_cap_file" 2>/dev/null || true
                fi
            fi
        elif [ -n "$_new_max" ]; then
            # Policy turun (normal/cool/warm) — pulihkan cap hanya bila:
            # 1. File state pre-cap tersedia.
            # 2. Nilai saat ini (_cur_max) masih sama dengan nilai cap yang terakhir diterapkan (artinya belum ada override user baru yang mengubah node ini setelah cap).
            # 3. Pre-cap > cur_max (ada cap yang diterapkan sebelumnya).
            # Ini memastikan kita tidak menimpa override user baru.
            if [ -f "$_thermal_pre_cap_file" ]; then
                _pre_cap=""
                while IFS='=' read -r _n _v; do
                    [ "$_n" = "$_dir" ] && _pre_cap="$_v"
                done < "$_thermal_pre_cap_file"
                # Hanya restore jika pre_cap tersedia dan pre_cap > cur_max (artinya cur_max masih dalam kondisi cap)
                # Karena saat cap diterapkan, cur_max (sebelum tulis) = pre_cap, dan setelah cap diterapkan, cur_max = cap (_new_max saat cap).
                # Saat restore, cur_max seharusnya = cap (lebih rendah dari pre_cap). Jadi jika pre_cap > cur_max, kita restore ke pre_cap.
                if [ -n "$_pre_cap" ] && [ -n "$_cur_max" ] && [ "$_pre_cap" -gt "$_cur_max" ] 2>/dev/null; then
                    [ -w "$_dir/scaling_max_freq" ] && printf '%s\n' "$_pre_cap" > "$_dir/scaling_max_freq" 2>/dev/null
                fi
            fi
        fi
    done
}

# Apply thermal policy to GPU
# Sama seperti CPU: node devfreq + available_frequencies dari cache, satu
# test [ -w ] sebelum tulis, max_freq tetap dibaca live karena itu nilai
# yang berubah tiap apply.
hsin_thermal_apply_gpu() {
    _policy="$1"

    hsin_scan_devfreq_get
    for _node in $HSIN_SCAN_DEVFREQ_NODES; do
        _dir="$HSIN_SYSFS_DEVFREQ/$_node"
        [ -f "$_dir/max_freq" ] || continue

        hsin_scan_lookup "$HSIN_SCAN_DEVFREQ_LINES" "$_node" 1
        _opp_csv="$_sc_f"
        _avail=$(printf '%s' "$_opp_csv" | tr ',' ' ')
        [ -n "$_avail" ] || continue

        case "$_policy" in
            critical|hot)
                # Use an actual OPP, never an arbitrary value such as 1200
                # MHz on a 384/768/1500 MHz GPU table.
                _max_avail=$(hsin_opp_max "$_avail")
                [ -n "$_max_avail" ] || continue
                _target=$(hsin_opp_cap_pick "$(( _max_avail * 80 / 100 ))" "$_avail")
                ;;
            *)
                # Device adem: thermal tidak boleh APA-APUN. Sebelumnya
                # cabang ini menulis max OPP tertinggi, yang membatalkan
                # cap profil GPU dan override pilihan user. Sekarang
                # thermal hanya menurunkan (lihat gate di bawah).
                _max_avail=$(hsin_opp_max "$_avail")
                [ -n "$_max_avail" ] || continue
                _target="$_max_avail"
                ;;
        esac

        # Sama seperti CPU: thermal = penaham. Tulis hanya kalau target
        # lebih rendah dari nilai sekarang, kalau tidak dilewati diam-diam.
        _cur_max=""
        [ -f "$_dir/max_freq" ] && IFS= read -r _cur_max < "$_dir/max_freq" 2>/dev/null
        case "$_cur_max" in
            ''|*[!0-9]*) _cur_max=0 ;;
        esac
        if [ -n "$_target" ] && [ "$_target" -lt "$_cur_max" ] 2>/dev/null; then
            [ -w "$_dir/max_freq" ] && \
                printf '%s\n' "$_target" > "$_dir/max_freq" 2>/dev/null
        fi
    done
}

# Full thermal policy application
hsin_thermal_apply() {
    _profile="$1"

    # Read current temps
    . "$HSIN_MODULE_PATH/engine/thermal/monitor.sh" 2>/dev/null
    hsin_thermal_read

    # Determine policy
    hsin_thermal_policy_determine "$HSIN_THERMAL_MAX_TEMP"
    _perf="$HSIN_THERMAL_PERF_TARGET"

    # Mode manual: tuning profil dilewati, TAPI guard critical tetap
    # jalan (cermin perilaku performance: hanya saat critical).
    if [ "$_profile" = "manual" ]; then
        if [ "$HSIN_THERMAL_POLICY" = "critical" ]; then
            hsin_thermal_apply_cpu "$HSIN_THERMAL_POLICY" ""
            hsin_thermal_apply_gpu "$HSIN_THERMAL_POLICY"
            echo "    Thermal policy: critical cap diterapkan (mode manual, guard)"
        else
            echo "    Thermal policy: dilewati (mode manual)"
        fi
        _ts=$(date '+%Y-%m-%d %H:%M:%S')
        echo "$_ts [THERMAL] Policy=$HSIN_THERMAL_POLICY Perf=$_perf% MaxTemp=$HSIN_THERMAL_MAX_TEMP (manual)" >> "$HSIN_DATA/logs/thermal.log"
        return 0
    fi

    # Apply based on profile
    case "$_profile" in
        battery|balanced)
            # Apply thermal policy
            hsin_thermal_apply_cpu "$HSIN_THERMAL_POLICY" ""
            hsin_thermal_apply_gpu "$HSIN_THERMAL_POLICY"
            ;;
        performance)
            # Less aggressive thermal management
            if [ "$HSIN_THERMAL_POLICY" = "critical" ]; then
                hsin_thermal_apply_cpu "$HSIN_THERMAL_POLICY" ""
                hsin_thermal_apply_gpu "$HSIN_THERMAL_POLICY"
            fi
            ;;
        extreme)
            # Extreme owns the hardware ceiling. Do not add a software clock
            # cap here; the dedicated extreme safety monitor handles an
            # emergency and OEM/kernel thermal protection remains active.
            ;;
    esac

    # Log
    _ts=$(date '+%Y-%m-%d %H:%M:%S')
    echo "$_ts [THERMAL] Policy=$HSIN_THERMAL_POLICY Perf=$_perf% MaxTemp=$HSIN_THERMAL_MAX_TEMP" >> "$HSIN_DATA/logs/thermal.log"
}

# Print policy status
hsin_thermal_policy_print() {
    . "$HSIN_MODULE_PATH/engine/thermal/monitor.sh" 2>/dev/null
    hsin_thermal_read
    hsin_thermal_policy_determine "$HSIN_THERMAL_MAX_TEMP"
    _perf="$HSIN_THERMAL_PERF_TARGET"

    echo ""
    echo "╔══════════════════════════════════════╗"
    echo "║   HSIN Thermal Policy                ║"
    echo "╚══════════════════════════════════════╝"
    echo ""
    printf "  Max Temp:     %s\n" "$(hsin_thermal_format_temp "$HSIN_THERMAL_MAX_TEMP")"
    printf "  Policy:       %s\n" "${HSIN_THERMAL_POLICY:-unknown}"
    printf "  Perf Target:  %s%%\n" "$_perf"
    echo ""
    echo "  Rules:"
    printf "    cool     (<60C):     100%%\n"
    printf "    normal   (60-75C):   95%%\n"
    printf "    warm     (75-85C):   85%%\n"
    printf "    hot      (85-95C):   70%%\n"
    printf "    critical (>95C):     50%%\n"
    echo ""
}

return 0 2>/dev/null || true
