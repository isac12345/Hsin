#!/system/bin/sh
# HSIN Log System

[ -z "$HSIN_MODULE_PATH" ] && HSIN_MODULE_PATH="/data/adb/modules/hsin"
HSIN_DATA="${HSIN_DATA:-/data/adb/hsin}"

# Log directory
HSIN_LOG_DIR="$HSIN_DATA/logs"

# Initialize log system
hsin_log_init() {
    mkdir -p "$HSIN_LOG_DIR" 2>/dev/null
    touch "$HSIN_LOG_DIR/boot.log" 2>/dev/null
    touch "$HSIN_LOG_DIR/apply.log" 2>/dev/null
    touch "$HSIN_LOG_DIR/rollback.log" 2>/dev/null
    touch "$HSIN_LOG_DIR/error.log" 2>/dev/null
}

# Write to log file
hsin_log() {
    _file="$1"
    _engine="$2"
    _msg="$3"

    [ -d "$HSIN_LOG_DIR" ] || hsin_log_init

    _ts=$(date '+%Y-%m-%d %H:%M:%S')
    echo "$_ts [$_engine] $_msg" >> "$HSIN_LOG_DIR/$_file" 2>/dev/null
}

# Log boot
hsin_log_boot() {
    hsin_log "boot.log" "BOOT" "$1"
}

# Log apply
hsin_log_apply() {
    hsin_log "apply.log" "$1" "$2"
}

# Log info / ok / warn - used throughout boot/detection/capability/backup
hsin_log_info() {
    hsin_log "boot.log" "$1" "$2"
}

hsin_log_ok() {
    hsin_log "boot.log" "$1" "OK: $2"
}

hsin_log_warn() {
    hsin_log "boot.log" "$1" "WARN: $2"
}

# Section divider - used to visually break up boot.log into phases
hsin_log_section() {
    hsin_log "boot.log" "SECTION" "===== $1 ====="
}

# Log rollback
hsin_log_rollback() {
    hsin_log "rollback.log" "ROLLBACK" "$1"
}

# Log error
hsin_log_error() {
    hsin_log "error.log" "ERROR" "$1"
}

# Print log
hsin_log_print() {
    _file="${1:-boot}"
    _lines="${2:-50}"

    _log="$HSIN_LOG_DIR/${_file}.log"
    [ -f "$_log" ] || { echo "No log file: $_file"; return 1; }

    echo ""
    echo "╔══════════════════════════════════════╗"
    echo "║   HSIN Log: $_file"
    echo "╚══════════════════════════════════════╝"
    echo ""

    tail -n "$_lines" "$_log" 2>/dev/null | while IFS= read -r _line; do
        printf "  %s\n" "$_line"
    done

    echo ""
}

# Print all logs
hsin_log_print_all() {
    hsin_log_print "boot" 20
    hsin_log_print "apply" 20
    hsin_log_print "rollback" 20
    hsin_log_print "error" 20
}

# Clear logs
hsin_log_clear() {
    rm -f "$HSIN_LOG_DIR"/*.log 2>/dev/null
    hsin_log_init
    echo "[LOG] Logs cleared"
}

# Hidden dev-only debug line - appends to logs/debug.log (same file
hsin_debug() {
    _dbg_file="${HSIN_DATA:-/data/adb/hsin}/logs/debug.log"
    mkdir -p "$(dirname "$_dbg_file")" 2>/dev/null
    echo "[$(date '+%H:%M:%S')] [$1] $2" >> "$_dbg_file" 2>/dev/null
}

# Post a plain Android notification from a root shell (best-effort, never
# blocks - failures are silently ignored since a missing notification isn't
# worth breaking anything over). Re-uses the same tag every time so repeat
# notifications replace each other instead of stacking up.
hsin_notify() {
    _title="$1"
    _text="$2"
    command -v cmd >/dev/null 2>&1 || return 0

    _icon_path="/storage/emulated/0/Android/media/.hsin/notif_icon.png"
    _icon_args=""
    if [ -f "$_icon_path" ]; then
        _icon_uri="file://$_icon_path"
        _icon_args="--icon $_icon_uri"
    fi

    # Write notification commands to a temp script and launch via setsid
    # so the exec bridge (or monitor subshell) can exit without killing
    # the notification before it reaches the system server.
    _nscript="${HSIN_DATA:-/data/adb/hsin}/tmp/notif_$$.sh"
    mkdir -p "$(dirname "$_nscript")" 2>/dev/null
    cat > "$_nscript" << NEOF
#!/system/bin/sh
cmd package grant com.android.shell android.permission.POST_NOTIFICATIONS >/dev/null 2>&1
cmd notification post --user 0 $_icon_args -t "$_title" "hsin_notify" "$_text" >/dev/null 2>&1
cmd notification post -S messaging $_icon_args -t "$_title" "hsin_notify" "$_text" >/dev/null 2>&1
[ -n "$_icon_path" ] && [ -f "$_icon_path" ] && {
    _icon_legacy="-i file://$_icon_path -I file://$_icon_path"
    cmd notification post \$_icon_legacy -t "$_title" "hsin_notify" "$_text" >/dev/null 2>&1
}
cmd notification post -t "$_title" "hsin_notify" "$_text" >/dev/null 2>&1
su -lp 2000 -c "cmd notification post -t '$(printf '%s' "$_title" | sed "s/'/'\\\\''/g")' 'hsin_notify' '$(printf '%s' "$_text" | sed "s/'/'\\\\''/g")'" >/dev/null 2>&1
rm -f "$_nscript"
NEOF
    chmod 755 "$_nscript" 2>/dev/null

    if command -v setsid >/dev/null 2>&1; then
        setsid sh "$_nscript" </dev/null >/dev/null 2>&1 &
    elif [ -x /data/adb/ksu/bin/busybox ]; then
        /data/adb/ksu/bin/busybox setsid sh "$_nscript" </dev/null >/dev/null 2>&1 &
    else
        sh "$_nscript" </dev/null >/dev/null 2>&1 &
    fi
}

# PATCH v4.0.2: rotasi log berdasarkan ukuran - dipanggil PERIODIK oleh
# integrity guard loop di service.sh (tiap ~3 menit selama device nyala),
# BUKAN cuma pas boot. Log lama di-keep (.old).
#
# BUG FIX: fungsi ini sebelumnya ditulis SETELAH baris "return 0" di bawah
# - karena file ini di-source (". core/logger.sh"), "return 0" langsung
# menghentikan proses source di situ juga, jadi hsin_log_rotate() TIDAK
# PERNAH ke-define di shell manapun yang source file ini (selalu gagal
# "not found" kalau dipanggil). Dipindah ke atas "return 0" supaya benar-
# benar ke-load, dan sekarang benar-benar dipanggil dari service.sh -
# sebelumnya truncate-on-boot doang (service.sh baris ~28) yang jalan,
# jadi debug.log/monitor.log tetap bisa numpuk selama device nggak reboot
# lama (device gaming yang jarang di-restart).
hsin_log_rotate() {
    _max="${1:-262144}"
    _dir="$HSIN_DATA/logs"
    [ -d "$_dir" ] || return 0
    for _lf in "$_dir"/debug.log "$_dir"/boot.log "$_dir"/apply.log \
               "$_dir"/monitor.log "$_dir"/error.log; do
        [ -f "$_lf" ] || continue
        _sz=$(wc -c < "$_lf" 2>/dev/null)
        case "$_sz" in ''|*[!0-9]*) continue ;; esac
        if [ "$_sz" -gt "$_max" ]; then
            mv -f "$_lf" "$_lf.old" 2>/dev/null
            : > "$_lf" 2>/dev/null
        fi
    done
    return 0
}

return 0 2>/dev/null || true
