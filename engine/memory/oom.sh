#!/system/bin/sh
# HSIN Memory Engine - OOM Engine

[ -z "$HSIN_MODULE_PATH" ] && HSIN_MODULE_PATH="/data/adb/modules/hsin"
. "$HSIN_MODULE_PATH/core/logger.sh" 2>/dev/null
# Path proc dari core/scan_cache.sh (satu-satunya definisi), default sama
# dengan path yang sebelumnya ditulis langsung di file ini.
[ -n "$HSIN_PROC" ] || HSIN_PROC="${SYSFS_PROC_PREFIX:-/proc}"

# Protected processes (NEVER modify). Satu baris spasi — WAJIB cocok
# dengan cek `case " $HSIN_OOM_PROTECTED "` di bawah (multiline = mati).
HSIN_OOM_PROTECTED="system_server zygote surfaceflinger servicemanager vold installd logd lmkd healthd adbd shell init"

# Check if process is protected
hsin_oom_is_protected() {
    _pid="$1"
    _name=""

    if [ -r "$HSIN_PROC/$_pid/comm" ]; then
        IFS= read -r _name < "$HSIN_PROC/$_pid/comm" 2>/dev/null
    fi

    case " $HSIN_OOM_PROTECTED " in
        *" $_name "*) return 0 ;;
    esac
    return 1
}

# Set OOM score for a process
hsin_oom_set() {
    _pid="$1"
    _score="$2"

    # Check node exists
    [ -f "$HSIN_PROC/$_pid/oom_score_adj" ] || return 1

    # Check writable
    [ -w "$HSIN_PROC/$_pid/oom_score_adj" ] || return 1

    # Check if protected
    hsin_oom_is_protected "$_pid" && return 1

    # Validate range
    [ "$_score" -ge -1000 ] && [ "$_score" -le 1000 ] || return 1

    # Write
    echo "$_score" > "$HSIN_PROC/$_pid/oom_score_adj" 2>/dev/null || return 1

    # Verify (read builtin instead of forking cat)
    _verify=""
    IFS= read -r _verify < "$HSIN_PROC/$_pid/oom_score_adj" 2>/dev/null
    [ "$_verify" = "$_score" ] && return 0 || return 1
}

# Protect foreground app (set oom_score_adj = -500)
hsin_oom_protect_foreground() {
    _count=0

    # Find foreground activity
    _fg_pkg=""
    if command -v dumpsys >/dev/null 2>&1; then
        _line=$(dumpsys activity activities 2>/dev/null | grep -m1 "mResumedActivity")
        _fg_pkg=$(printf '%s' "$_line" | grep -oE '[A-Za-z0-9_.]+/[A-Za-z0-9_.]+' | head -1 | cut -d/ -f1)
    fi

    # Find foreground PID
    _fg_pid=""
    if [ -n "$_fg_pkg" ]; then
        _fg_pid=$(pidof "$_fg_pkg" 2>/dev/null | awk '{print $1}')
    fi

    # Fallback: find top-app via ps
    if [ -z "$_fg_pid" ]; then
        _fg_pid=$(ps -A -o PID,NAME 2>/dev/null | grep -E "(launcher|home)" | head -1 | awk '{print $1}')
    fi

    if [ -n "$_fg_pid" ]; then
        hsin_oom_set "$_fg_pid" -500 && _count=$((_count + 1))
        echo "    OOM: protected foreground (pid=$_fg_pid)"
    fi

    return 0
}

# Protect game process (set oom_score_adj = -500)
hsin_oom_protect_game() {
    _pkg="$1"
    [ -z "$_pkg" ] && return 0

    _pid=$(pidof "$_pkg" 2>/dev/null | awk '{print $1}')
    [ -z "$_pid" ] && return 0

    hsin_oom_set "$_pid" -500 && {
        echo "    OOM: protected game ($_pkg pid=$_pid)"
    }
}

# Release background apps (set oom_score_adj = 100)
hsin_oom_release_background() {
    _ok=0
    _skip=0

    for _pid_dir in "$HSIN_PROC"/[0-9]*; do
        [ -d "$_pid_dir" ] || continue
        [ -f "$_pid_dir/oom_score_adj" ] || continue

        _pid_num="${_pid_dir##*/}"

        # Skip protected system daemons
        hsin_oom_is_protected "$_pid_num" && continue

        # Extra safety margin: never touch Google Play Services or GSF,
        # even though they're not in the hardcoded system-daemon list
        # above. Banking apps and other sensitive apps often depend on
        # these staying alive/undisturbed, so this is deliberately more
        # cautious than strictly necessary.
        _cmdline=""
        if [ -r "$_pid_dir/cmdline" ]; then
            IFS= read -r _cmdline < "$_pid_dir/cmdline" 2>/dev/null
            _cmdline=$(printf '%s' "$_cmdline" | tr -d '\0')
        fi
        case "$_cmdline" in
            *com.google.android.gms*|*com.google.android.gsf*) continue ;;
        esac

        # Skip foreground / already released
        _adj=""
        IFS= read -r _adj < "$_pid_dir/oom_score_adj" 2>/dev/null
        [ "$_adj" -lt 0 ] 2>/dev/null && continue
        [ "$_adj" -ge 100 ] 2>/dev/null && continue

        # Set to allow kill
        #
        # BUG FIX: `echo 100 > ... && _ok++` menghitung redirect yang sukses,
        # bukan bukti oom_score_adj benar-benar berisi 100. Redirect ke node
        # oom_score_adj bisa gagal tanpa jejak (dihitung 0, tak dilaporkan)
        # dan redirect yang sukses belum tentu bisa dibaca balik - keduanya
        # dulu muncul sebagai "released N" padahal nilainya masih 000.
        # Sekarang lewat hsin_oom_set: [-f] + [-w] + cek proteksi + tulis +
        # readback verify; baru dihitung OK.
        #
        # hsin_oom_set juga gagal kalau proses/node oom_score_adj hilang di
        # tengah scan. Cek ulang node-nya: masih ada = tulis ditolak/
        # tidak terverifikasi (hitung SKIP + WARN), sudah hilang = prosesnya
        # memang sudah mati, bukan kegagalan (dilewati tanpa warning).
        if hsin_oom_set "$_pid_num" 100; then
            _ok=$((_ok + 1))
        elif [ -f "$_pid_dir/oom_score_adj" ]; then
            _skip=$((_skip + 1))
            hsin_log_warn "memory" \
                "OOM: pid $_pid_num (adj=${_adj:-?}) release 100 ditolak/tidak terverifikasi (skip)"
        fi
    done

    echo "    OOM: released $_ok background processes, skipped $_skip (GMS excluded)"
    return 0
}

# Get OOM state for top processes
hsin_oom_state() {
    echo "  OOM State:"
    ps -A -o PID,NAME 2>/dev/null | head -15 | while read _pid _name; do
        [ -f "$HSIN_PROC/$_pid/oom_score_adj" ] || continue
        _adj=$(cat "$HSIN_PROC/$_pid/oom_score_adj" 2>/dev/null)
        _protected="no"
        hsin_oom_is_protected "$_pid" && _protected="yes"
        printf "    PID %-8s %-25s adj=%-6s protected=%s\n" "$_pid" "$_name" "${_adj:-?}" "$_protected"
    done
}

return 0 2>/dev/null || true
