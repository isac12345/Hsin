#!/system/bin/sh
# HSIN GPU Engine - Devfreq Tunables (K3, capability-gated)
#
# MENGAPA file ini terpisah dari generic.sh: generic.sh menulis governor +
# min/max_freq (nilai absolut frekuensi). Tiga tunable di sini BUKAN
# frekuensi - mereka parameter perilaku governor:
#   polling_interval   - jeda antar evaluasi governor (ms) (devfreq ABI)
#   up_threshold       - persen busy sebelum governor menaikkan (%)
#   down_differential  - persen selisih sebelum menurunkan (%)
#
# Kenapa file terpisah: node-node ini hanya ADA kalau governor yang
# sedang aktif memang mengexpos-nya. Jadi keberadaan node = gate
# capability, bukan nama governor. Driver yang
# tidak punya node ini hanya laporan UNAVAILABLE, tidak pernah error.
#
# Deteksi ketat (sesuai requirement K3): node ADA + WRITABLE + nilai
# override lolos validasi ulang di engine. Tidak ada tebakan vendor/SoC.
# Tidak ada nilai default profil: tanpa override, tidak ada yang ditulis.

[ -z "$HSIN_MODULE_PATH" ] && HSIN_MODULE_PATH="/data/adb/modules/hsin"
# shellcheck disable=SC1091
. "$HSIN_MODULE_PATH/core/sysfs.sh" 2>/dev/null
# shellcheck disable=SC1091
. "$HSIN_MODULE_PATH/core/safe_apply.sh" 2>/dev/null
. "$HSIN_MODULE_PATH/core/logger.sh" 2>/dev/null
. "$HSIN_MODULE_PATH/core/user_knobs.sh" 2>/dev/null
# Daftar node devfreq GPU + sanitasi nama node.
command -v hsin_gpu_devfreq_candidates >/dev/null 2>&1 || \
    . "$HSIN_MODULE_PATH/engine/gpu/detector.sh" 2>/dev/null
[ -n "$HSIN_SYSFS_DEVFREQ" ] || HSIN_SYSFS_DEVFREQ="${SYSFS_DEVFREQ_PREFIX:-/sys/class/devfreq}"

# field|min|max (batas = devfreq ABI + batas UI, lihat NOTES K3)
_HSIN_GPU_TUNE_SPEC="polling_interval|1|1000 up_threshold|1|100 down_differential|0|100"

# Terapkan tunable untuk satu node devfreq. $1=path node, $2=profile.
_hsin_gpu_tune_one() {
    _gt_d="$1"
    _gt_profile="$2"
    _gt_manual=0
    [ "$_gt_profile" = "manual" ] && _gt_manual=1
    _gt_applied=0
    _gt_skipped=0

    _uk_sanitize "${_gt_d##*/}"

    for _gt_spec in $_HSIN_GPU_TUNE_SPEC; do
        _gt_f="${_gt_spec%%|*}"
        _gt_rest="${_gt_spec#*|}"
        _gt_min="${_gt_rest%%|*}"
        _gt_max="${_gt_rest#*|}"
        _gt_key="gpu_node_${_uk_sn}_${_gt_f}"
        _gt_node="$_gt_d/$_gt_f"

        _gt_uk=$(hsin_uk_get "$_gt_key" 2>/dev/null)
        if [ -z "$_gt_uk" ]; then
            # Tanpa override: di manual dicatat SKIPPED; di profil tidak ada
            # nilai profil untuk ketiga tunable ini (tidak ada di profiles/),
            # jadi tidak ada yang ditulis.
            if [ "$_gt_manual" = "1" ]; then
                hsin_uk_result "$_gt_key" "(manual)" "-" "SKIPPED" "tidak diatur (mode manual)" 2>/dev/null || true
            fi
            continue
        fi

        # Validasi ulang di engine (pola tfo): file bisa diisi manual.
        _gt_bad=0
        case "$_gt_uk" in
            ''|*[!0-9]*) _gt_bad=1 ;;
            *)
                [ "$_gt_uk" -lt "$_gt_min" ] 2>/dev/null && _gt_bad=1
                [ "$_gt_uk" -gt "$_gt_max" ] 2>/dev/null && _gt_bad=1
                ;;
        esac
        if [ "$_gt_bad" = "1" ]; then
            hsin_log_warn "gpu" "override $_gt_key=$_gt_uk ditolak: harus $_gt_min-$_gt_max"
            if [ "$_gt_manual" = "1" ]; then
                hsin_uk_result "$_gt_key" "$_gt_uk" "-" "SKIPPED" "ditolak: di luar $_gt_min-$_gt_max (mode manual, tidak ditulis)" 2>/dev/null || true
            else
                hsin_uk_result "$_gt_key" "$_gt_uk" "-" "FALLBACK" "ditolak: di luar $_gt_min-$_gt_max, tidak ada nilai profil" 2>/dev/null || true
            fi
            continue
        fi

        # Gate capability: node harus ADA. Tidak writable / tidak ada =
        # UNAVAILABLE, bukan error.
        if [ ! -f "$_gt_node" ]; then
            hsin_uk_result "$_gt_key" "$_gt_uk" "-" "UNAVAILABLE" "node $_gt_f tidak ada di devfreq node ini" 2>/dev/null || true
            _gt_skipped=$((_gt_skipped + 1))
            continue
        fi

        # rc: 0 APPLIED, 2 SKIPPED (read-only), 1 FAILED.
        hsin_safe_apply "$_gt_node" "$_gt_uk" "GPU_TUNE"
        _gt_rc=$?
        case "$_gt_rc" in
            0)
                _gt_applied=$((_gt_applied + 1))
                hsin_uk_used "gpu" "$_gt_key" "$_gt_uk"
                ;;
            2)
                _gt_skipped=$((_gt_skipped + 1))
                hsin_uk_result "$_gt_key" "$_gt_uk" "-" "UNAVAILABLE" "node read-only" 2>/dev/null || true
                ;;
            *)
                _gt_skipped=$((_gt_skipped + 1))
                hsin_uk_result "$_gt_key" "$_gt_uk" "-" "FAILED" "tulis/readback gagal" 2>/dev/null || true
                ;;
        esac
    done
    _HSIN_GT_APPLIED=$_gt_applied
    _HSIN_GT_SKIP=$_gt_skipped
    return 0
}

# Entry point: $1 = profile.
hsin_gpu_devfreq_tunables_apply() {
    _gd_profile="$1"
    _gd_ok=0
    _gd_skip=0
    hsin_gpu_devfreq_candidates
    for _gd_d in $HSIN_GPU_DEVFRES; do
        [ -d "$_gd_d" ] || continue
        _hsin_gpu_tune_one "$_gd_d" "$_gd_profile"
        _gd_ok=$((_gd_ok + _HSIN_GT_APPLIED))
        _gd_skip=$((_gd_skip + _HSIN_GT_SKIP))
    done
    echo "    GPU devfreq tunables: applied=$_gd_ok skip=$_gd_skip"
    return 0
}

# Cur per node/field untuk knobs JSON. Baris: "<node> <field> <cur> <w> <sup>"
hsin_gpu_devfreq_tunables_state() {
    hsin_gpu_devfreq_candidates
    for _gs_d in $HSIN_GPU_DEVFRES; do
        [ -d "$_gs_d" ] || continue
        for _gs_spec in $_HSIN_GPU_TUNE_SPEC; do
            _gs_f="${_gs_spec%%|*}"
            _gs_n="$_gs_d/$_gs_f"
            if [ -r "$_gs_n" ]; then
                _gs_v=$(hsin_node_read "$_gs_n")
                [ -w "$_gs_n" ] && _gs_w=true || _gs_w=false
                printf '%s %s %s %s true\n' "${_gs_d##*/}" "$_gs_f" "${_gs_v:-0}" "$_gs_w"
            else
                printf '%s %s 0 false false\n' "${_gs_d##*/}" "$_gs_f"
            fi
        done
    done
    return 0
}

return 0 2>/dev/null || true
