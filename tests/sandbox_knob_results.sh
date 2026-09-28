#!/system/bin/sh
# Sandbox test PQ Step 23: visibilitas hasil knob — file asli, tanpa preset.
# Override dibuat via hsin_uk_set asli (jalur validasi beneran), node via
# pohon sysfs palsu, engine via fungsi asli hsin_cpu_freq_apply /
# hsin_cpu_governor_apply. Tidak ada counter/state yang diarang angka.
#
# Cara pakai: sh tests/sandbox_knob_results.sh
# Keluar 0 = semua skenario PASS, 1 = ada yang FAIL.

_HSIN_REPO=$(cd "${0%/*}/.." 2>/dev/null && pwd)
HSIN_SANDBOX_DIR="${HSIN_SANDBOX_DIR:-/usr/tmp/opencode/hsin-knobres-test}"
export HSIN_MODULE_PATH="$_HSIN_REPO"
export HSIN_DATA="$HSIN_SANDBOX_DIR/data"
export HSIN_SYSFS_CPU="$HSIN_SANDBOX_DIR/sys/cpu"
export SYSFS_CPU_PREFIX="$HSIN_SYSFS_CPU"

# shellcheck disable=SC1091
. "$_HSIN_REPO/core/logger.sh" 2>/dev/null || true
# shellcheck disable=SC1091
. "$_HSIN_REPO/core/user_knobs.sh" 2>/dev/null || true
# shellcheck disable=SC1091
. "$_HSIN_REPO/engine/cpu/detect.sh" 2>/dev/null || true
# shellcheck disable=SC1091
. "$_HSIN_REPO/engine/cpu/frequency.sh" 2>/dev/null || true
# shellcheck disable=SC1091
. "$_HSIN_REPO/engine/cpu/governor.sh" 2>/dev/null || true

_PASS=0
_FAIL=0
_ok() { _PASS=$((_PASS + 1)); echo "PASS: $1"; }
_bad() { _FAIL=$((_FAIL + 1)); echo "FAIL: $1"; }

# Pohon policy0 palsu: OPP 300000-1800000, gov schedutil/performance.
# NOTE: cache override user_knobs dibangun SEKALI saat file di-source
# (pola asli: file override sudah ada sebelum apply). Tiap mutasi env
# di bawah WAJIB _refresh (simulasi proses apply segar) — tanpa ini
# engine membaca cache basi, persis seperti bug yang dihindari di
# produksi dengan selalu source-setelah-file-ada.
_refresh() {
    unset _uk_inited
    # shellcheck disable=SC1091
    . "$_HSIN_REPO/core/user_knobs.sh" 2>/dev/null || true
}
_set() {
    hsin_uk_set "$@" >/dev/null 2>&1
    _refresh
}
_resetenv() {
    hsin_uk_reset >/dev/null 2>&1
    _refresh
}
_mk_tree() {
    _opp="$1"
    rm -rf "$HSIN_SANDBOX_DIR"
    mkdir -p "$HSIN_SYSFS_CPU/cpufreq/policy0" "$HSIN_DATA/logs"
    if [ "$_opp" = "EMPTY" ]; then
        : > "$HSIN_SYSFS_CPU/cpufreq/policy0/scaling_available_frequencies"
    else
        echo "300000 600000 1200000 1800000" > "$HSIN_SYSFS_CPU/cpufreq/policy0/scaling_available_frequencies"
    fi
    echo "schedutil performance" > "$HSIN_SYSFS_CPU/cpufreq/policy0/scaling_available_governors"
    echo "1800000" > "$HSIN_SYSFS_CPU/cpufreq/policy0/cpuinfo_max_freq"
    echo "300000" > "$HSIN_SYSFS_CPU/cpufreq/policy0/cpuinfo_min_freq"
    echo "1800000" > "$HSIN_SYSFS_CPU/cpufreq/policy0/scaling_max_freq"
    echo "300000" > "$HSIN_SYSFS_CPU/cpufreq/policy0/scaling_min_freq"
    echo "powersave" > "$HSIN_SYSFS_CPU/cpufreq/policy0/scaling_governor"
    unset HSIN_CPU_POLICY_READY HSIN_CPU_POLICY_IDS HSIN_CPU_POLICY_SOURCE
}

# Satu siklus apply asli (reset + engine beneran).
_cycle() {
    hsin_uk_results_reset
    hsin_cpu_freq_apply balanced >/dev/null 2>&1
    hsin_cpu_governor_apply balanced >/dev/null 2>&1
}

_state_line() {
    grep "^$1=" "$HSIN_DATA/knob_results.env" 2>/dev/null | tail -n 1
}

# 0. Self-check: test tidak menulis state file langsung.
# Hanya baca/grep/cat, rm untuk simulasi hilang, reset via fungsi asli.
if grep -E '>>?[^|]*knob_results\.env' "$0" 2>/dev/null | grep -qv 'HSIN_UK_RESULTS_FILE'; then
    _bad "0. test menulis state langsung (dilarang)"
else
    _ok "0. test hanya lewat fungsi asli (tanpa tulis state langsung)"
fi

# 1. Override valid -> APPLIED, applied==requested, node berubah beneran.
_mk_tree FULL
_set cpu_policy_0_max_khz 1200000 >/dev/null 2>&1
_cycle
_l=$(_state_line cpu_policy_0_max_khz)
if [ "$_l" = "cpu_policy_0_max_khz=1200000|1200000|APPLIED|dipakai sesuai permintaan" ] \
    && [ "$(cat "$HSIN_SYSFS_CPU/cpufreq/policy0/scaling_max_freq")" = "1200000" ]; then
    _ok "1. valid: APPLIED 1200000, node beneran 1200000"
else
    _bad "1. valid (line=[$_l] node=$(cat "$HSIN_SYSFS_CPU/cpufreq/policy0/scaling_max_freq"))"
fi

# 2. Di luar tabel OPP -> FALLBACK snap + alasan, node ikut snap.
_mk_tree FULL
_set cpu_policy_0_max_khz 1000000 >/dev/null 2>&1
_cycle
_l=$(_state_line cpu_policy_0_max_khz)
if [ "$_l" = "cpu_policy_0_max_khz=1000000|600000|FALLBACK|tidak ada di tabel OPP; snap ke 600000" ] \
    && [ "$(cat "$HSIN_SYSFS_CPU/cpufreq/policy0/scaling_max_freq")" = "600000" ]; then
    _ok "2. snap: FALLBACK 1000000->600000 + alasan, node beneran 600000"
else
    _bad "2. snap (line=[$_l] node=$(cat "$HSIN_SYSFS_CPU/cpufreq/policy0/scaling_max_freq"))"
fi

# 3. Governor tak tersedia -> FALLBACK pakai profil + alasan.
_mk_tree FULL
_set cpu_policy_0_gov ondemand >/dev/null 2>&1
_cycle
_l=$(_state_line cpu_policy_0_gov)
_prof_gov=$(hsin_cpu_governor_pick balanced "schedutil performance" 2>/dev/null)
if [ "$_l" = "cpu_policy_0_gov=ondemand|$_prof_gov|FALLBACK|ditolak: tidak ada di scaling_available_governors (pakai profil)" ] \
    && [ "$(cat "$HSIN_SYSFS_CPU/cpufreq/policy0/scaling_governor")" = "$_prof_gov" ]; then
    _ok "3. gov ditolak: FALLBACK pakai profil ($_prof_gov) + alasan"
else
    _bad "3. gov ditolak (line=[$_l] node=$(cat "$HSIN_SYSFS_CPU/cpufreq/policy0/scaling_governor") prof=$_prof_gov)"
fi

# 4. Tabel OPP kosong -> engine skip, TANPA klaim palsu di state.
_mk_tree EMPTY
_set cpu_policy_0_max_khz 1200000 >/dev/null 2>&1
_cycle
_l=$(_state_line cpu_policy_0_max_khz)
_out=$(hsin_uk_list 2>/dev/null | grep "^key=cpu_policy_0_max_khz ")
case "$_out" in
    *'reason="belum ada hasil apply"') _ok "4. OPP kosong: skip, tanpa klaim palsu" ;;
    *) _bad "4. OPP kosong (line=[$_l] list=[$_out])" ;;
esac

# 5. State file hilang -> "belum ada hasil apply", rc 0, no crash.
_mk_tree FULL
_set cpu_policy_0_max_khz 1200000 >/dev/null 2>&1
rm -f "$HSIN_DATA/knob_results.env"
_out=$(hsin_uk_list 2>/dev/null); _rc=$?
if [ "$_rc" -eq 0 ] && echo "$_out" | head -n 1 | grep -q "belum ada hasil apply"; then
    _ok "5. state hilang: pesan jujur + rc=0"
else
    _bad "5. state hilang (rc=$_rc out=[$_out])"
fi

# 6. Reset per siklus: hasil lama hilang, tidak basi.
_mk_tree FULL
_set cpu_policy_0_max_khz 1200000 >/dev/null 2>&1
_cycle
hsin_uk_results_reset
_resetenv
_cycle
if ! grep -q "^cpu_policy_0_max_khz=1200000|" "$HSIN_DATA/knob_results.env" 2>/dev/null \
    && grep -q "^cpu_policy_0_max_khz=(profil)|" "$HSIN_DATA/knob_results.env" 2>/dev/null; then
    _ok "6. reset: jejak override lama hilang, ganti nilai profil"
else
    _bad "6. reset (isi: $(cat "$HSIN_DATA/knob_results.env" 2>/dev/null | tr '\n' ';'))"
fi

# 7. Knob tanpa override -> tampil nilai profil.
_mk_tree FULL
_resetenv
_cycle
_l=$(_state_line cpu_policy_0_min_khz)
if printf '%s' "$_l" | grep -qF "cpu_policy_0_min_khz=(profil)|" \
    && printf '%s' "$_l" | grep -qF "|APPLIED|nilai profil (tanpa override)"; then
    _ok "7. tanpa override: nilai profil tampil ([$_l])"
else
    _bad "7. tanpa override (line=[$_l])"
fi

# 8. Format knob-list parseable + JSON terakhir utuh (kompatibel APK).
_mk_tree FULL
_set cpu_policy_0_max_khz 1200000 >/dev/null 2>&1
_cycle
_out=$(hsin_uk_list 2>/dev/null)
if echo "$_out" | grep -q '^key=cpu_policy_0_max_khz requested=1200000 applied=1200000 category=APPLIED reason="dipakai sesuai permintaan"$' \
    && echo "$_out" | tail -n 1 | python3 -c "import json,sys; d=json.load(sys.stdin); assert 'overrides' in d" 2>/dev/null; then
    _ok "8. knob-list: baris key=value + JSON terakhir valid"
else
    _bad "8. knob-list format ([$_out])"
fi

echo "=== SANDBOX RESULTS: PASS=$_PASS FAIL=$_FAIL ==="
[ "$_FAIL" -eq 0 ]
