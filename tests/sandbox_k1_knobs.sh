#!/system/bin/sh
# Sandbox test K1: knob manual untuk penulisan engine yang tadinya
# profil-only (readahead, vfs_cache_pressure, dirty_ratio,
# dirty_background_ratio, backlog).
#
# Yang dibuktikan di sini:
#   A. tiap knob di-set SATU-PER-SATU -> hanya node itu yang berubah
#      (snapshot md5 semua node sysfs/proc palsu sebelum vs sesudah)
#   B. manual tanpa override = NOL penulisan
#   C. profil non-manual tanpa override = IDENTIK nilai profil (regresi)
#   D. node hilang = UNAVAILABLE + alasan, tanpa crash
#   E. nilai di luar rentang/preset = ditolak, node tak berubah
#   F. dirty_background_ratio >= dirty_ratio = FALLBACK + alasan 2 angka
#   G. backup -> rollback PER KNOB (5 roundtrip)
#   H. knobs JSON memuat 5 field baru dengan cur dari node palsu
#   I. knob-list kategori benar per knob
#
# Cara pakai: sh tests/sandbox_k1_knobs.sh
# Keluar 0 = semua PASS, 1 = ada FAIL.
# Scratch HANYA di $HSIN_SANDBOX_DIR (default usr/tmp/opencode).

_HSIN_REPO=$(cd "${0%/*}/.." 2>/dev/null && pwd)
HSIN_SANDBOX_DIR="${HSIN_SANDBOX_DIR:-/usr/tmp/opencode/hsin-k1-test}"
SB_SYS="$HSIN_SANDBOX_DIR/sys"
SB_PROC="$HSIN_SANDBOX_DIR/proc"
export HSIN_MODULE_PATH="$_HSIN_REPO"
export HSIN_DATA="$HSIN_SANDBOX_DIR/data"
export HSIN_SANDBOX=1
export SYSFS_BLOCK_PREFIX="$SB_SYS/block"
export SYSFS_PROC_PREFIX="$SB_PROC"
export HSIN_SYSFS_BLOCK="$SB_SYS/block"
export HSIN_PROC="$SB_PROC"

_PASS=0
_FAIL=0

_ok() {
    _PASS=$((_PASS + 1))
    echo "PASS: $1"
}

_bad() {
    _FAIL=$((_FAIL + 1))
    echo "FAIL: $1"
}

# Pohon node palsu. $1 = 1 bila read_ahead_kb/node VM dihapus (uji UNAVAILABLE).
_mknodes() {
    rm -rf "$SB_SYS" "$SB_PROC"
    mkdir -p "$SB_SYS/block/sda/queue" "$SB_PROC/sys/vm" "$SB_PROC/sys/net/core" \
        "$SB_PROC/sys/net/ipv4" "$HSIN_DATA/logs"
    printf '128\n' > "$SB_SYS/block/sda/queue/read_ahead_kb"
    printf 'mq-deadline [none] kyber\n' > "$SB_SYS/block/sda/queue/scheduler"
    printf '100\n' > "$SB_PROC/sys/vm/vfs_cache_pressure"
    printf '20\n' > "$SB_PROC/sys/vm/dirty_ratio"
    printf '5\n' > "$SB_PROC/sys/vm/dirty_background_ratio"
    printf '60\n' > "$SB_PROC/sys/vm/swappiness"
    printf '1000\n' > "$SB_PROC/sys/net/core/netdev_max_backlog"
    printf '1\n' > "$SB_PROC/sys/net/ipv4/tcp_sack"
    printf '1\n' > "$SB_PROC/sys/net/ipv4/tcp_window_scaling"
    printf '2\n' > "$SB_PROC/sys/net/ipv4/tcp_ecn"
    return 0
}

# md5 semua node (nilai isi) - urutan tetap supaya bisa dibandingkan.
_snapshot() {
    for _f in \
        "$SB_SYS/block/sda/queue/read_ahead_kb" \
        "$SB_SYS/block/sda/queue/scheduler" \
        "$SB_PROC/sys/vm/vfs_cache_pressure" \
        "$SB_PROC/sys/vm/dirty_ratio" \
        "$SB_PROC/sys/vm/dirty_background_ratio" \
        "$SB_PROC/sys/vm/swappiness" \
        "$SB_PROC/sys/net/core/netdev_max_backlog" \
        "$SB_PROC/sys/net/ipv4/tcp_sack" \
        "$SB_PROC/sys/net/ipv4/tcp_window_scaling" \
        "$SB_PROC/sys/net/ipv4/tcp_ecn"; do
        if [ -f "$_f" ]; then
            printf '%s=%s\n' "$_f" "$(cat "$_f" 2>/dev/null)"
        else
            printf '%s=<hilang>\n' "$_f"
        fi
    done
    return 0
}

# Node yang berubah antara 2 snapshot (hanya nama file, satu per node).
_diffnodes() {
    printf '%s\n' "$1" > "$HSIN_SANDBOX_DIR/.snap_before"
    printf '%s\n' "$2" > "$HSIN_SANDBOX_DIR/.snap_after"
    paste -d'|' "$HSIN_SANDBOX_DIR/.snap_before" "$HSIN_SANDBOX_DIR/.snap_after" | while IFS='|' read -r _l _r; do
        [ "$_l" = "$_r" ] || printf '%s\n' "${_l%%=*}"
    done
    return 0
}

# Bersihkan override + hasil, muat ulang file user_knobs (per proses).
_reset_state() {
    rm -f "$HSIN_DATA/user_knobs.env" "$HSIN_DATA/knob_results.env"
    _uk_inited=""
    _uk_cache=""
    _uk_cache_done=""
    _uk_used_n=0
    _uk_sum_done=""
    return 0
}

# Muat semua yang dibutuhkan apply (pola repo).
_load_all() {
    for _f in core/logger.sh core/sysfs.sh core/scan_cache.sh core/safe_apply.sh \
        core/user_knobs.sh core/knobs.sh engine/cpu/detect.sh engine/gpu/detector.sh \
        engine/memory/detect.sh engine/memory/vm.sh engine/io/scheduler.sh \
        engine/io/readahead.sh engine/network/tcp.sh engine/display/refresh_rate.sh \
        engine/render/renderer.sh; do
        . "$_HSIN_REPO/$_f" 2>/dev/null
    done
    return 0
}

# Set 1 knob lalu apply manual; $1 = key, $2 = nilai, $3 = path node yg
# harus berubah, $4 = nilai akhir yang diharapkan.
_apply_one() {
    _k="$1"
    _v="$2"
    _node="$3"
    _want="$4"
    _reset_state
    hsin_uk_set "$_k" "$_v" >/dev/null 2>&1
    _before=$(_snapshot)
    hsin_vm_apply manual >/dev/null 2>&1
    hsin_io_apply_readahead manual >/dev/null 2>&1
    hsin_network_apply_sysctl manual >/dev/null 2>&1
    _after=$(_snapshot)
    _changed=$(_diffnodes "$_before" "$_after")
    _cnt=$(printf '%s' "$_changed" | grep -c .)
    if [ "$_cnt" = "1" ] && [ "$_changed" = "$_node" ] && [ "$(cat "$_node" 2>/dev/null)" = "$_want" ]; then
        _ok "$_k=$_v: hanya node itu berubah -> $_want"
    else
        _bad "$_k=$_v: hanya node itu berubah (jumlah=$_cnt node=[$(printf '%s' "$_changed" | tr '\n' ' ')] isi=$(cat "$_node" 2>/dev/null))"
    fi
}

# --- A. snapshot byte per knob, satu per satu ---
_mknodes
_load_all
_apply_one "vfs_cache_pressure" "200" "$SB_PROC/sys/vm/vfs_cache_pressure" "200"
_apply_one "dirty_ratio" "30" "$SB_PROC/sys/vm/dirty_ratio" "30"
_apply_one "dirty_background_ratio" "10" "$SB_PROC/sys/vm/dirty_background_ratio" "10"
_apply_one "io_block_sda_readahead" "2048" "$SB_SYS/block/sda/queue/read_ahead_kb" "2048"
_apply_one "backlog" "5000" "$SB_PROC/sys/net/core/netdev_max_backlog" "5000"

# --- B. manual tanpa override = nol penulisan ---
_mknodes
_load_all
_reset_state
_before=$(_snapshot)
hsin_vm_apply manual >/dev/null 2>&1
hsin_io_apply_readahead manual >/dev/null 2>&1
hsin_network_apply_sysctl manual >/dev/null 2>&1
_after=$(_snapshot)
if [ "$_before" = "$_after" ]; then
    _ok "B. manual tanpa override: nol penulisan"
else
    _bad "B. manual tanpa override: nol penulisan (berubah: $(_diffnodes "$_before" "$_after" | tr '\n' ' '))"
fi

# --- C. profil non-manual tanpa override: nilai profil, tidak regresi ---
_mknodes
_load_all
_reset_state
hsin_vm_apply balanced >/dev/null 2>&1
hsin_io_apply_readahead balanced >/dev/null 2>&1
hsin_network_apply_sysctl balanced >/dev/null 2>&1
_c_vfs=$(cat "$SB_PROC/sys/vm/vfs_cache_pressure")
_c_dr=$(cat "$SB_PROC/sys/vm/dirty_ratio")
_c_dbr=$(cat "$SB_PROC/sys/vm/dirty_background_ratio")
_c_ra=$(cat "$SB_SYS/block/sda/queue/read_ahead_kb")
_c_bl=$(cat "$SB_PROC/sys/net/core/netdev_max_backlog")
if [ "$_c_vfs" = "100" ] && [ "$_c_dr" = "30" ] && [ "$_c_dbr" = "5" ] \
    && [ "$_c_ra" = "512" ] && [ "$_c_bl" = "1000" ]; then
    _ok "C. balanced tanpa override: nilai profil (vfs 100, ratio 30, bg 5, ra 512, backlog 1000)"
else
    _bad "C. balanced tanpa override (dapat vfs=$_c_vfs ratio=$_c_dr bg=$_c_dbr ra=$_c_ra backlog=$_c_bl)"
fi

# --- D. node hilang = UNAVAILABLE, tanpa crash ---
_mknodes
rm -f "$SB_PROC/sys/vm/vfs_cache_pressure" "$SB_PROC/sys/net/core/netdev_max_backlog"
_load_all
_reset_state
hsin_uk_set "vfs_cache_pressure" "300" >/dev/null 2>&1
hsin_uk_set "backlog" "8000" >/dev/null 2>&1
hsin_vm_apply manual >/dev/null 2>&1
hsin_io_apply_readahead manual >/dev/null 2>&1
hsin_network_apply_sysctl manual >/dev/null 2>&1
_rc=$?
if [ "$_rc" -eq 0 ] && [ "$(cat "$SB_PROC/sys/vm/dirty_ratio")" = "20" ] \
    && [ ! -f "$SB_PROC/sys/vm/vfs_cache_pressure" ] \
    && [ ! -f "$SB_PROC/sys/net/core/netdev_max_backlog" ]; then
    _ok "D. node hilang: tidak crash (rc=0), node lain tak ditulis"
else
    _bad "D. node hilang: tidak crash (rc=$_rc ratio=$(cat "$SB_PROC/sys/vm/dirty_ratio" 2>/dev/null))"
fi
if grep -q '^vfs_cache_pressure=.*UNAVAILABLE' "$HSIN_DATA/knob_results.env" 2>/dev/null \
    && grep -q '^backlog=.*UNAVAILABLE' "$HSIN_DATA/knob_results.env" 2>/dev/null; then
    _ok "D2. vfs + backlog UNAVAILABLE tercatat di hasil"
else
    _bad "D2. vfs/backlog UNAVAILABLE (hasil: $(tr '\n' '|' < "$HSIN_DATA/knob_results.env" 2>/dev/null))"
fi

# --- E. di luar rentang / bukan preset = ditolak, node tak berubah ---
_mknodes
_load_all
_reset_state
for _pair in "vfs_cache_pressure 1001" "dirty_ratio 0" "dirty_ratio 91" \
    "dirty_background_ratio 0" "dirty_background_ratio 51" \
    "io_block_sda_readahead 100" "backlog 100" "backlog 20000"; do
    _set_k=$(printf '%s' "$_pair" | cut -d' ' -f1)
    _set_v=$(printf '%s' "$_pair" | cut -d' ' -f2)
    if hsin_uk_set "$_set_k" "$_set_v" >/dev/null 2>&1; then
        _bad "E. $_set_k=$_set_v ditolak oleh knob-set (justru diterima)"
    else
        _ok "E. $_set_k=$_set_v: knob-set MENOLAK"
    fi
done
# Ditolak juga saat file override diisi tangan (cek ulang di engine).
_reset_state
printf 'backlog=20000\nio_block_sda_readahead=100\n' > "$HSIN_DATA/user_knobs.env"
chmod 600 "$HSIN_DATA/user_knobs.env"
_reset_state
_uk_inited=""
_uk_cache=""
_uk_cache_done=""
_uk_load
_before=$(_snapshot)
hsin_network_apply_sysctl manual >/dev/null 2>&1
hsin_io_apply_readahead manual >/dev/null 2>&1
_after=$(_snapshot)
if [ "$_before" = "$_after" ]; then
    _ok "E2. file override cacat: ditolak engine, nol penulisan"
else
    _bad "E2. file override cacat: ditolak engine (berubah: $(_diffnodes "$_before" "$_after" | tr '\n' ' '))"
fi

# --- F. dirty_background_ratio >= dirty_ratio = FALLBACK + alasan 2 angka ---
for _prof in manual balanced; do
    _mknodes
    _load_all
    _reset_state
    hsin_uk_set "dirty_ratio" "30" >/dev/null 2>&1
    hsin_uk_set "dirty_background_ratio" "40" >/dev/null 2>&1
    _before=$(_snapshot)
    if [ "$_prof" = "manual" ]; then
        hsin_vm_apply manual >/dev/null 2>&1
    else
        hsin_vm_apply balanced >/dev/null 2>&1
    fi
    _after=$(_snapshot)
    _f_line=$(grep '^dirty_background_ratio=' "$HSIN_DATA/knob_results.env" 2>/dev/null)
    if printf '%s' "$_f_line" | grep -q 'FALLBACK' \
        && printf '%s' "$_f_line" | grep -q 'dirty_background_ratio (40)' \
        && printf '%s' "$_f_line" | grep -q 'dirty_ratio (30)'; then
        _ok "F. bg>=ratio ($_prof): FALLBACK + dua angka di alasan"
    else
        _bad "F. bg>=ratio ($_prof): FALLBACK + dua angka (baris: $_f_line)"
    fi
    if [ "$_prof" = "manual" ]; then
        # Yang ditolak = knob dirty_background_ratio saja. dirty_ratio=30
        # sendiri override SAH di manual, jadi boleh ditulis.
        if [ "$(cat "$SB_PROC/sys/vm/dirty_background_ratio")" = "5" ] \
            && [ "$(cat "$SB_PROC/sys/vm/dirty_ratio")" = "30" ]; then
            _ok "F2. bg>=ratio (manual): bg tak ditulis (5), ratio sah tetap 30"
        else
            _bad "F2. bg>=ratio (manual): bg tak ditulis (dapat ratio=$(cat "$SB_PROC/sys/vm/dirty_ratio") bg=$(cat "$SB_PROC/sys/vm/dirty_background_ratio"))"
        fi
    fi
done

# --- G. backup -> rollback PER KNOB (5 roundtrip) ---
. "$_HSIN_REPO/core/backup.sh" 2>/dev/null
for _knob in vfs_cache_pressure dirty_ratio dirty_background_ratio backlog readahead; do
    _mknodes
    _load_all
    . "$_HSIN_REPO/core/backup.sh" 2>/dev/null
    _orig_vfs=$(cat "$SB_PROC/sys/vm/vfs_cache_pressure")
    _orig_dr=$(cat "$SB_PROC/sys/vm/dirty_ratio")
    _orig_dbr=$(cat "$SB_PROC/sys/vm/dirty_background_ratio")
    _orig_bl=$(cat "$SB_PROC/sys/net/core/netdev_max_backlog")
    _orig_ra=$(cat "$SB_SYS/block/sda/queue/read_ahead_kb")
    HSIN_BACKUP_ROOT="$HSIN_DATA/backup"
    hsin_backup_init "k1test"
    hsin_backup_io
    hsin_backup_memory
    hsin_backup_network
    # Ubah semua node ke nilai lain.
    case "$_knob" in
        vfs_cache_pressure) printf '600\n' > "$SB_PROC/sys/vm/vfs_cache_pressure" ;;
        dirty_ratio)        printf '70\n' > "$SB_PROC/sys/vm/dirty_ratio" ;;
        dirty_background_ratio) printf '40\n' > "$SB_PROC/sys/vm/dirty_background_ratio" ;;
        backlog)            printf '9000\n' > "$SB_PROC/sys/net/core/netdev_max_backlog" ;;
        readahead)          printf '8192\n' > "$SB_SYS/block/sda/queue/read_ahead_kb" ;;
    esac
    hsin_restore_session "k1test" >/dev/null 2>&1
    _got_vfs=$(cat "$SB_PROC/sys/vm/vfs_cache_pressure")
    _got_dr=$(cat "$SB_PROC/sys/vm/dirty_ratio")
    _got_dbr=$(cat "$SB_PROC/sys/vm/dirty_background_ratio")
    _got_bl=$(cat "$SB_PROC/sys/net/core/netdev_max_backlog")
    _got_ra=$(cat "$SB_SYS/block/sda/queue/read_ahead_kb")
    if [ "$_got_vfs" = "$_orig_vfs" ] && [ "$_got_dr" = "$_orig_dr" ] \
        && [ "$_got_dbr" = "$_orig_dbr" ] && [ "$_got_bl" = "$_orig_bl" ] \
        && [ "$_got_ra" = "$_orig_ra" ]; then
        _ok "G. rollback $_knob: nilai kembali ($_got_vfs/$_got_dr/$_got_dbr/$_got_bl/$_got_ra)"
    else
        _bad "G. rollback $_knob (dapat $_got_vfs/$_got_dr/$_got_dbr/$_got_bl/$_got_ra, asli $_orig_vfs/$_orig_dr/$_orig_dbr/$_orig_bl/$_orig_ra)"
    fi
    rm -rf "$HSIN_DATA/backup"
done

# --- H. knobs JSON: 5 field baru dengan cur dari node palsu ---
_mknodes
_load_all
_kn_json=$(hsin_knobs_json 2>/dev/null)
if printf '%s' "$_kn_json" | python3 -c "import sys,json; json.load(sys.stdin)" 2>/dev/null; then
    _ok "H. knobs JSON valid"
else
    _bad "H. knobs JSON valid (output: $(printf '%s' "$_kn_json" | head -c 200))"
fi
if printf '%s' "$_kn_json" | grep -q '"vfs_cache_pressure":{"min":0,"max":1000,"cur":100,"writable":true,"supported":true}'; then
    _ok "H2. JSON vfs_cache_pressure min0/max1000/cur100"
else
    _bad "H2. JSON vfs_cache_pressure (dapat: $(printf '%s' "$_kn_json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('vm'))" 2>/dev/null))"
fi
if printf '%s' "$_kn_json" | grep -q '"dirty_ratio":{"min":1,"max":90,"cur":20,"writable":true,"supported":true}'; then
    _ok "H3. JSON dirty_ratio min1/max90/cur20"
else
    _bad "H3. JSON dirty_ratio (dapat: $(printf '%s' "$_kn_json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('vm',{}).get('dirty_ratio'))" 2>/dev/null))"
fi
if printf '%s' "$_kn_json" | grep -q '"dirty_background_ratio":{"min":1,"max":50,"cur":5,"writable":true,"supported":true}'; then
    _ok "H4. JSON dirty_background_ratio min1/max50/cur5"
else
    _bad "H4. JSON dirty_background_ratio (dapat: $(printf '%s' "$_kn_json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('vm',{}).get('dirty_background_ratio'))" 2>/dev/null))"
fi
if printf '%s' "$_kn_json" | grep -q '"readahead":{"options":\[128,256,512,1024,2048,4096,8192\],"cur":128,"writable":true,"supported":true}'; then
    _ok "H5. JSON io.blocks readahead preset + cur 128"
else
    _bad "H5. JSON io.blocks readahead (dapat: $(printf '%s' "$_kn_json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('io'))" 2>/dev/null))"
fi
if printf '%s' "$_kn_json" | grep -q '"backlog":{"min":128,"max":16384,"cur":1000,"writable":true,"supported":true}'; then
    _ok "H6. JSON backlog min128/max16384/cur1000"
else
    _bad "H6. JSON backlog (dapat: $(printf '%s' "$_kn_json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('backlog'))" 2>/dev/null))"
fi

# --- I. knob-list kategori benar per knob ---
_mknodes
_load_all
_reset_state
hsin_uk_set "vfs_cache_pressure" "250" >/dev/null 2>&1
hsin_uk_set "backlog" "4000" >/dev/null 2>&1
hsin_uk_set "io_block_sda_readahead" "1024" >/dev/null 2>&1
hsin_vm_apply manual >/dev/null 2>&1
hsin_io_apply_readahead manual >/dev/null 2>&1
hsin_network_apply_sysctl manual >/dev/null 2>&1
_i_out=$(hsin_uk_list 2>/dev/null)
if printf '%s' "$_i_out" | grep -q '^key=vfs_cache_pressure requested=250 applied=250 category=APPLIED'; then
    _ok "I. knob-list vfs APPLIED"
else
    _bad "I. knob-list vfs APPLIED (baris: $(printf '%s' "$_i_out" | grep vfs_cache_pressure))"
fi
if printf '%s' "$_i_out" | grep -q '^key=backlog requested=4000 applied=4000 category=APPLIED'; then
    _ok "I2. knob-list backlog APPLIED"
else
    _bad "I2. knob-list backlog APPLIED (baris: $(printf '%s' "$_i_out" | grep '^key=backlog'))"
fi
if printf '%s' "$_i_out" | grep -q '^key=io_block_sda_readahead requested=1024 applied=1024 category=APPLIED'; then
    _ok "I3. knob-list readahead APPLIED"
else
    _bad "I3. knob-list readahead APPLIED (baris: $(printf '%s' "$_i_out" | grep readahead))"
fi
if printf '%s' "$_i_out" | tail -n 1 | python3 -c "import sys,json; d=json.load(sys.stdin); assert d['count']==3" 2>/dev/null; then
    _ok "I4. knob-list JSON terakhir valid count=3"
else
    _bad "I4. knob-list JSON terakhir count=3 (baris: $(printf '%s' "$_i_out" | tail -n 1))"
fi

echo "---"
echo "sandbox_k1_knobs: PASS=$_PASS FAIL=$_FAIL"
rm -rf "$HSIN_SANDBOX_DIR"
[ "$_FAIL" -eq 0 ]
