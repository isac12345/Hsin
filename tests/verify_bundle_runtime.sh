#!/system/bin/sh
# HSIN — verifikasi runtime.sh hasil MERGE bundle (gate CI).
#
# KENAPA ADA: insiden 2026-09-30. build_release.sh menggabungkan seluruh
# core/engine/extreme/*.sh ke satu core/runtime.sh. Statement top-level
# `return`/`exit` dari salah satu file (thermal_check.sh) tidak ikut
# dibuang, jadi saat runtime.sh di-source, `return` menghentikan sourcing
# di tengah file. Semua yang di-merge SESUDAHNYA (core/apply_engines.sh
# -> hsin_apply_all_engines) tidak pernah terdefinisi, jadi apply di ZIP
# mati total: rc=0 "queued", tidak ada error, knob tidak pernah berubah.
# Semua sandbox test lama tetap hijau karena menyource file SATU per satu
# dari source tree, bukan runtime.sh hasil merge.
#
# TES INI MENJAGA 2 HAL:
#   (A) SETIAP fungsi yang ada di file yang di-merge WAJIB terdefinisi
#       setelah runtime.sh di-source (menangkap "runtime terpotong").
#   (B) SETIAP fungsi hsin_* yang dipanggil entrypoint (action.sh,
#       service.sh, post-fs-data.sh) WAJIB terdefinisi (menangkap file
#       baru yang memanggil engine tapi tidak didaftarkan di merge).
# Plus dua guard merge: tidak boleh ada `return `/`exit ` top-level yang
# bocor ke runtime.sh, dan runtime.sh harus lolos `sh -n`.
#
# CARA PAKAI:
#   sh tests/verify_bundle_runtime.sh --merge-only     # merge tanpa zip
#   sh tests/verify_bundle_runtime.sh build/*.zip      # dari ZIP asli
#
# Keluar 0 = semua PASS. Keluar 1 = ada yang FAIL (CI jadi merah).

_PASS=0
_FAIL=0
_ok() { _PASS=$((_PASS + 1)); echo "PASS: $1"; }
_bad() { _FAIL=$((_FAIL + 1)); echo "FAIL: $1"; }

# Fungsi inti yang WAJIB ada (dipanggil entrypoint / jalur apply).
# Ditambah daftar lengkap di bawah: daftar ini sengaja TIDAK di-hardcode
# per-file, tapi dihitung dari daftar merge build_release.sh (lihat
# bagian A), sehingga file baru otomatis ikut teruji.
CORE_REQUIRED="hsin_apply_all_engines hsin_boot_guard_check hsin_safe_apply hsin_thermal_apply hsin_engine_run hsin_knobs_json hsin_uk_set hsin_guard_status hsin_scan_cache_load"

# Daftar file yang di-merge, diambil PERSIS dari build_release.sh agar
# tidak bisa drift dari builder.
_MERGED_FILES() {
    sed -n '/^    for _src in \\/,/; do$/p' "$1/build_release.sh" \
        | grep -o 'core/[a-z_]*\.sh\|engine/[a-z_/]*\.sh\|extreme/[a-z_]*\.sh' \
        | sort -u
}

# A) Semua fungsi yang didefinisikan di file yang di-merge.
_EXPECTED_FUNCS() {
    _repo="$1"
    for _f in $(_MERGED_FILES "$_repo"); do
        [ -f "$_repo/$_f" ] || continue
        sed -n 's/^\([a-zA-Z_][a-zA-Z0-9_]*\)[[:space:]]*()[[:space:]]*{.*/\1/p' "$_repo/$_f"
    done | sort -u
}

# B) Semua hsin_* yang DIPANGGIL sebagai perintah oleh entrypoint.
# PENTING: hanya token di POSISI PERINTAH yang dihitung. Token yang
# sebenarnya variabel (`for _hsin_boot_log in ...`, `_hsin_mpid=`,
# `"$_hsin_mpid"`) akan salah dianggap fungsi kalau hanya di-grep
# teksnya — itulah 4 false positive pertama di versi test ini.
_CALLED_ENTRYPOINTS() {
    for _e in action.sh service.sh post-fs-data.sh; do
        [ -f "$1/$_e" ] || continue
        grep -v '^[[:space:]]*#' "$1/$_e" | awk '
            {
                line = $0
                # Pisah di batas perintah; sisanya jadi segmen-segmen
                # yang kata pertamanya adalah kata perintah.
                gsub(/;|&&|\|\||\||\(|\)/, "\n", line)
                n = split(line, seg, "\n")
                for (i = 1; i <= n; i++) {
                    s = seg[i]
                    sub(/^[ \t]+/, "", s)
                    if (s !~ /^_?hsin_[A-Za-z0-9_]+$/) continue
                    print s
                }
            }
        '
    done | sort -u
}

# Fungsi yang didefinisikan entrypoint itu sendiri (mis. hsin_action_* di
# action.sh) — tidak boleh diminta dari runtime.sh.
_ENTRYPOINT_DEFS() {
    for _e in action.sh service.sh post-fs-data.sh; do
        [ -f "$1/$_e" ] || continue
        sed -n 's/^\([a-zA-Z_][a-zA-Z0-9_]*\)[[:space:]]*()[[:space:]]*{.*/\1/p' "$1/$_e"
    done | sort -u
}

# Cek satu runtime.sh (yang sudah diekstrak/staged).
_check_runtime() {
    _label="$1"
    _root="$2"
    _runtime="$_root/core/runtime.sh"

    if [ ! -f "$_runtime" ]; then
        _bad "$_label: core/runtime.sh tidak ada"
        return 1
    fi
    _ok "$_label: core/runtime.sh ada ($(wc -l < "$_runtime" | tr -d ' ') baris)"

    # Guard 1: tidak boleh ada statement top-level yang menghentikan source.
    _leak=$(grep -c '^return[[:space:]]\|^exit[[:space:]]' "$_runtime" || true)
    if [ "$_leak" = "0" ]; then
        _ok "$_label: tidak ada return/exit top-level bocor ke runtime"
    else
        _bad "$_label: $_leak baris return/exit TOP-LEVEL bocor ke runtime.sh (sourcing akan terpotong!)"
        grep -n '^return[[:space:]]\|^exit[[:space:]]' "$_runtime" | head -5 | sed 's/^/      /'
    fi

    # Guard 2: parse harus sehat.
    if sh -n "$_runtime" 2>/dev/null; then
        _ok "$_label: sh -n runtime.sh lolos"
    else
        _bad "$_label: sh -n runtime.sh GAGAL"
    fi

    # Siapkan sandbox kosong (tanpa /sys, tanpa /proc asli).
    _sb="$_root/.verify-sandbox"
    rm -rf "$_sb"
    mkdir -p "$_sb/data/logs" "$_sb/sys" "$_sb/proc" "$_sb/cpu" \
             "$_sb/thermal" "$_sb/devfreq" "$_sb/kgsl" "$_sb/block" 2>/dev/null
    printf 'Profile=manual\nALLOW_EXTREME=false\n' > "$_sb/data/hsin.conf"

    # Probe dijalankan di subshell yang meng-source runtime.sh dengan
    # sandbox kosong: memastikan definisi benar-benar terjadi, bukan hanya
    # teks yang ada di file.
    _list="$_sb/required.txt"
    { _EXPECTED_FUNCS "$_REPO"
      for _c in $CORE_REQUIRED; do echo "$_c"; done
      _CALLED_ENTRYPOINTS "$_root" | while IFS= read -r _fn; do
          _ENTRYPOINT_DEFS "$_root" | grep -qx "$_fn" || echo "$_fn"
      done
    } | sort -u > "$_list"

    _out="$_sb/probe.out"
    (
        # Semua variabel di-export (bukan prefix per-perintah): prefix
        # hanya berlaku untuk SATU perintah, jadi probe.sh akan jalan
        # tanpa HSIN_PROBE_LIST dan diam-diam memeriksa 0 fungsi.
        export HSIN_SANDBOX=1
        export HSIN_MODULE_PATH="$_root"
        export HSIN_DATA="$_sb/data"
        export HSIN_CONF="$_sb/data/hsin.conf"
        export HSIN_SYSFS_CPU="$_sb/cpu" SYSFS_CPU_PREFIX="$_sb/cpu"
        export HSIN_SYSFS_THERMAL="$_sb/thermal" SYSFS_THERMAL_PREFIX="$_sb/thermal"
        export HSIN_SYSFS_DEVFREQ="$_sb/devfreq" SYSFS_DEVFREQ_PREFIX="$_sb/devfreq"
        export HSIN_SYSFS_GPU="$_sb/kgsl" SYSFS_GPU_PREFIX="$_sb/kgsl"
        export HSIN_SYSFS_BLOCK="$_sb/block" SYSFS_BLOCK_PREFIX="$_sb/block"
        export HSIN_PROC="$_sb/proc" SYSFS_PROC_PREFIX="$_sb/proc"
        export HSIN_PROBE_LIST="$_list"
        . "$_runtime" >/dev/null 2>&1
        echo "SOURCE_RC:$?" >&2
        # PENTING: probe dijalankan INLINE di subshell yang sama, bukan
        # lewat `sh probe.sh` — fungsi shell tidak diwarisi ke proses
        # anak, jadi child process selalu melaporkan semua fungsi hilang.
        _pn=0
        while IFS= read -r _pf; do
            [ -n "$_pf" ] || continue
            if command -v "$_pf" >/dev/null 2>&1; then
                echo "DEFINED:$_pf"
            else
                echo "MISSING:$_pf"
                _pn=$((_pn + 1))
            fi
        done < "$_list"
        echo "MISSING_COUNT:$_pn"
    ) > "$_out" 2>&1

    if grep -q '^SOURCE_RC:0$' "$_out"; then
        _ok "$_label: runtime.sh selesai di-source tanpa terpotong (rc=0)"
    else
        _bad "$_label: sourcing runtime.sh tidak rc=0 ($(grep '^SOURCE_RC:' "$_out" | tail -1))"
    fi

    _nmiss=$(sed -n 's/^MISSING_COUNT://p' "$_out" | tail -1)
    [ -n "$_nmiss" ] || _nmiss=0
    _ntotal=$(grep -c '^\(DEFINED\|MISSING\):' "$_out" 2>/dev/null || true)
    [ -n "$_ntotal" ] || _ntotal=0

    if [ "$_nmiss" = "0" ]; then
        _ok "$_label: $_ntotal fungsi terdefinisi setelah runtime.sh di-source"
    else
        _bad "$_label: $_nmiss fungsi HILANG setelah runtime.sh di-source"
        grep '^MISSING:' "$_out" | head -20 | sed 's/^/      /'
    fi

    # Daftar fungsi inti, satu per satu, supaya kegagalan menyebut nama.
    for _c in $CORE_REQUIRED; do
        if grep -qx "DEFINED:$_c" "$_out"; then
            _ok "$_label: fungsi inti $_c terdefinisi"
        else
            _bad "$_label: fungsi inti $_c HILANG"
        fi
    done

    rm -rf "$_sb"
}

_REPO=$(cd "${0%/*}/.." 2>/dev/null && pwd)
_WORK=$(mktemp -d 2>/dev/null || echo /tmp/hsin-verify-$$)
mkdir -p "$_WORK"
trap 'rm -rf "$_WORK"' EXIT INT TERM

MODE="${1:-}"
case "$MODE" in
    --merge-only)
        echo "=== merge-only: merge runtime.sh tanpa zip ==="
        STAGE_OUT=$(sh "$_REPO/build_release.sh" merge-only 2>&1)
        _mrc=$?
        _stage=$(echo "$STAGE_OUT" | sed -n 's/^MERGE_STAGE=//p' | tail -1)
        if [ "$_mrc" != "0" ] || [ -z "$_stage" ] || [ ! -f "$_stage/core/runtime.sh" ]; then
            _bad "merge-only: build_release.sh gagal (rc=$_mrc)"
            echo "$STAGE_OUT" | tail -15 | sed 's/^/      /'
        else
            _ok "merge-only: runtime.sh terbentuk ($_stage/core/runtime.sh)"
            _check_runtime "merge-only" "$_stage"
        fi
        ;;
    "")
        echo "ERROR: pakai --merge-only atau berikan path ZIP" >&2
        exit 2
        ;;
    *)
        for _zip in "$@"; do
            if [ ! -f "$_zip" ]; then
                _bad "ZIP tidak ditemukan: $_zip"
                continue
            fi
            _dir="$_WORK/$(basename "$_zip" .zip)"
            rm -rf "$_dir"
            mkdir -p "$_dir"
            if ! unzip -q -o "$_zip" -d "$_dir" 2>/dev/null; then
                _bad "gagal ekstrak: $_zip"
                continue
            fi
            echo "=== $(basename "$_zip") ==="
            _check_runtime "$(basename "$_zip")" "$_dir"
        done
        ;;
esac

echo
echo "PASS: $_PASS  FAIL: $_FAIL"
[ "$_FAIL" = "0" ] || exit 1
exit 0
