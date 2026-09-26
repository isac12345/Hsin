#!/system/bin/sh
# HSIN Build Script - produces DEV and RELEASE zips from this source tree.
#
# DEV zip   : integrity check disabled (.devmode present). Edit anything,
#             it always runs. This is what YOU flash on your own device.
# RELEASE   : integrity check enabled, hashes generated fresh from the
#             exact files being packaged, no way to turn it off. This is
#             what you give out.
#
# Usage:
#   sh build_release.sh dev
#   sh build_release.sh release
#   sh build_release.sh          (builds both)

set -e
SRC_DIR="$(cd "$(dirname "$0")" && pwd)"
OUT_DIR="$SRC_DIR/build"
VERSION=$(grep '^version=' "$SRC_DIR/module.prop" 2>/dev/null | cut -d= -f2)
[ -z "$VERSION" ] && VERSION="unknown"

# Files whose content must never change without you noticing.
# Add more paths here any time you add a new script that matters.
PROTECTED_FILES_LIGHT="
action.sh
service.sh
post-fs-data.sh
bin/hsin
core/runtime.sh
profiles/balanced.conf
profiles/battery.conf
profiles/performance.conf
profiles/extreme.conf
config/hsin.conf
webroot/index.html
webroot/script.js
webroot/style.css
"

PROTECTED_FILES_EXTRA="
core/runtime.sh
customize.sh
uninstall.sh
META-INF/com/google/android/update-binary
"
# config/hsin.conf is intentionally excluded from both sets - customize.sh
# copies it out to the user's own /sdcard config on first install, and that
# copy is meant to be user-editable afterwards.

PROTECTED_FILES_FULL="$PROTECTED_FILES_LIGHT $PROTECTED_FILES_EXTRA"
# LIGHT = checked synchronously on every action.sh call (WebUI click/poll) -
#         must stay fast, so keep this list small.
# FULL  = checked at boot (post-fs-data.sh) and periodically by a background
#         loop in service.sh, NEVER on the WebUI's hot path - can be as
#         thorough as we want since nothing is waiting on it.

_clean_stage() {
    _stage="$1"
    rm -rf "$_stage"
    mkdir -p "$_stage"
    # Copy named top-level entries only - NOT a dot-copy of $SRC_DIR, because
    # $SRC_DIR/build is where we're staging into and a dot-copy would try to
    # copy that directory into itself.
    for _entry in "$SRC_DIR"/*; do
        _name=$(basename "$_entry")
        case "$_name" in
            build|.git) continue ;;
        esac
        cp -r "$_entry" "$_stage/$_name"
    done
    rm -f "$_stage/.devmode" 2>/dev/null
    rm -f "$_stage/core/.integrity.manifest" 2>/dev/null
    rm -f "$_stage/core/.integrity.manifest.full" 2>/dev/null
    # Never carry a verifier binary from another architecture into a release.
    # Verifiers are rebuilt below when an ARM compiler is available.
    rm -f "$_stage/bin/hsin-verify" "$_stage/bin/hsin-verify-full" 2>/dev/null

    # Compact v5 runtime: one maintained library, dynamic feature detection.
    # Keep WebUI untouched; remove duplicated source trees from the shipped ZIP.
    _runtime="$_stage/core/runtime.sh"
    : > "$_runtime"
    for _src in \
        core/sysfs.sh core/logger.sh core/validator.sh core/profile_loader.sh \
        core/state_manager.sh core/protect.sh core/backup.sh core/policy_engine.sh \
        core/detector.sh core/hardware.sh core/capability.sh core/capability_scan.sh \
        core/root_check.sh core/rollback.sh core/doctor.sh core/export.sh \
        engine/cpu/detect.sh engine/cpu/governor.sh engine/cpu/frequency.sh \
        engine/cpu/scheduler.sh engine/cpu/safety.sh engine/cpu/apply.sh \
        engine/gpu/detector.sh engine/gpu/generic.sh engine/gpu/devfreq.sh \
        engine/gpu/adreno.sh engine/gpu/mali.sh engine/gpu/imgtec.sh \
        engine/gpu/validator.sh engine/gpu/dvfs.sh engine/gpu/apply.sh \
        engine/thermal/detect.sh engine/thermal/monitor.sh engine/thermal/policy.sh \
        engine/thermal/backup.sh engine/thermal/apply.sh engine/thermal/thermal_manager.sh \
        engine/memory/detect.sh engine/memory/zram.sh engine/memory/vm.sh \
        engine/memory/oom.sh engine/memory/apply.sh \
        engine/io/scheduler.sh engine/io/readahead.sh engine/io/io_manager.sh \
        engine/network/tcp.sh engine/network/network_manager.sh \
        engine/game/detector.sh engine/game/game_manager.sh \
        engine/display/downscale.sh engine/display/refresh_rate.sh engine/display/frame_limit.sh \
        engine/render/renderer.sh engine/render/surfaceflinger.sh \
        extreme/frequency_unlock.sh extreme/gpu_override.sh extreme/thermal_override.sh \
        extreme/restore_extreme.sh extreme/safety_monitor.sh \
        core/apply_engines.sh core/monitor.sh; do
        [ -f "$_stage/$_src" ] || continue
        printf '\n# --- %s ---\n' "$_src" >> "$_runtime"
        awk '!/^#!\/system\/bin\/sh$/ && !/^return 0 2>\/dev\/null \|\| true$/' "$_stage/$_src" >> "$_runtime"
    done
    [ -f "$_stage/engine/game/games.conf" ] && cp "$_stage/engine/game/games.conf" "$_stage/config/games.conf"
    # All functions are now present in runtime.sh; split-file source calls
    # would otherwise fail after the source tree is removed.
    sed -i '/^[[:space:]]*\. .*\(core\|engine\|extreme\)\//d' "$_runtime"
    sed -i 's#\$HSIN_MODULE_PATH/engine/game/games.conf#\$HSIN_MODULE_PATH/config/games.conf#g' "$_runtime"
    sed -i 's#\$HSIN_MODULE_PATH/extreme/safety_monitor\.sh#\$HSIN_MODULE_PATH/core/runtime.sh#g; s#\$HSIN_MODULE_PATH}/extreme/safety_monitor\.sh#\$HSIN_MODULE_PATH}/core/runtime.sh#g; s#\$HSIN_MODULE_PATH}/core/monitor\.sh#\$HSIN_MODULE_PATH}/core/runtime.sh#g' "$_runtime"
    sed -i 's#core/monitor\.sh#core/runtime.sh#g; s#extreme/safety_monitor\.sh#core/runtime.sh#g; s#core/protect\.sh#core/runtime.sh#g' "$_runtime" "$_stage/service.sh" "$_stage/action.sh" "$_stage/post-fs-data.sh"
    for _entry in engine extreme capability; do
        rm -rf "$_stage/$_entry"
    done
    for _old in "$_stage/core"/*.sh; do
        [ "${_old##*/}" = "runtime.sh" ] || rm -f "$_old"
    done
    rm -f "$_stage/bin/hsin-cli" "$_stage/build_release.sh"
    # Entrypoints load the compact runtime once. Existing optional source lines
    # remain harmless when the removed split files are absent.
    for _entry in action.sh service.sh post-fs-data.sh bin/hsin; do
        [ -f "$_stage/$_entry" ] || continue
        _tmp="$_stage/$_entry.tmp"
        {
            printf '%s\n' '#!/system/bin/sh'
            printf '%s\n' 'HSIN_MODULE_PATH="${HSIN_MODULE_PATH:-/data/adb/modules/hsin}"'
            printf '%s\n' 'HSIN_DATA="${HSIN_DATA:-/data/adb/hsin}"'
            printf '%s\n' '. "$HSIN_MODULE_PATH/core/runtime.sh" 2>/dev/null'
            tail -n +2 "$_stage/$_entry"
        } > "$_tmp"
        mv "$_tmp" "$_stage/$_entry"
        sed -i 's#\(\$MODPATH\|\$HSIN_MODULE_PATH\)/\(core\|engine\|extreme\)/[^" ]*#\1/core/runtime.sh#g' "$_stage/$_entry"
    done
    sed -i 's/set_perm "\$MODPATH\/core\/protect\.sh".*$/set_perm "\$MODPATH\/core\/runtime.sh" 0 0 0755/' "$_stage/customize.sh"
}

_zip_stage() {
    _stage="$1"
    _zipname="$2"
    ( cd "$_stage" && zip -r -X -q "$OUT_DIR/$_zipname" . )
    echo "  -> $OUT_DIR/$_zipname"
}

mkdir -p "$OUT_DIR"

build_dev() {
    echo "[dev] staging..."
    _stage="$OUT_DIR/stage-dev"
    _clean_stage "$_stage"
    touch "$_stage/.devmode"
    echo "[dev] zipping..."
    _zip_stage "$_stage" "HSIN-dev-${VERSION}.zip"
    rm -rf "$_stage"
}

build_release() {
    echo "[release] staging..."
    _stage="$OUT_DIR/stage-release"
    _clean_stage "$_stage"

    # OBFUSCATION disabled for v5 compact: stable names simplify maintenance.
    # filenames and gzip+base64-encodes engine/extreme *.sh content. This
    # MUST run before hashing/compiling below - hashing the plain names
    # would produce a manifest/binary that no longer matches the files
    # actually shipped once they get renamed.
    _map_file="$OUT_DIR/rename_map.tsv"
    rm -f "$_map_file"
    _py=""
    for _p in python3 python; do
        command -v "$_p" >/dev/null 2>&1 && { _py="$_p"; break; }
    done
    if false && [ -n "$_py" ]; then
        echo "[release] obfuscating..."
        if ! "$_py" "$SRC_DIR/tools/hsin_obfuscate.py" "$_stage" "$_map_file"; then
            echo "  [!] WARNING: obfuscation failed - shipping plain-text release"
            rm -f "$_map_file"
        fi
    else
        echo "  [!] WARNING: no python3/python found - skipping obfuscation."
        echo "      Release will ship with readable core/engine/extreme source."
        echo "      Install python3 (e.g. 'pkg install python' in Termux) and rebuild."
    fi

    # Translate the protected-file lists through the rename map so we hash
    # (and later compile the verifier against) the files under the names
    # they'll ACTUALLY have in the shipped zip, not their pre-obfuscation
    # names.
    _translate_list() {
        _list="$1"
        _map="$2"
        [ -f "$_map" ] || { printf '%s' "$_list"; return 0; }
        for _rel in $_list; do
            [ -z "$_rel" ] && continue
            _new=$(awk -F'\t' -v k="$_rel" '$1==k{print $2; exit}' "$_map")
            printf '%s\n' "${_new:-$_rel}"
        done
    }

    if [ -f "$_map_file" ]; then
        PROTECTED_FILES_LIGHT=$(_translate_list "$PROTECTED_FILES_LIGHT" "$_map_file")
        PROTECTED_FILES_FULL=$(_translate_list "$PROTECTED_FILES_FULL" "$_map_file")
        # The loader helper the obfuscator writes (core/_hsin_loader.sh's
        # real random name) is critical glue for every encoded file to work
        # at all - protect it in the FULL set even though it never existed
        # under that name pre-obfuscation.
        _helper_new=$(awk -F'\t' '$1=="core/_hsin_loader.sh"{print $2; exit}' "$_map_file")
        [ -n "$_helper_new" ] && PROTECTED_FILES_FULL="$PROTECTED_FILES_FULL
$_helper_new"
    fi
    _write_manifest_and_entries() {
        # $1 = file list (space/newline separated), $2 = manifest output path
        # Prints C struct entries to stdout for the caller to capture.
        _list="$1"
        _out_manifest="$2"
        : > "$_out_manifest"
        for _rel in $_list; do
            [ -z "$_rel" ] && continue
            _f="$_stage/$_rel"
            if [ -f "$_f" ]; then
                _h=$(md5sum "$_f" | awk '{print $1}')
                echo "${_rel}:${_h}" >> "$_out_manifest"
                printf '    {"%s", "%s"},\n' "$_rel" "$_h"
            else
                echo "  [!] WARNING: $_rel listed but not found, skipping" >&2
            fi
        done
    }

    _compile_verifier() {
        # $1 = entries text, $2 = output binary name
        _entries="$1"
        _binname="$2"
        _gen_c="$OUT_DIR/${_binname}_gen.c"
        awk -v entries="$_entries" '
            /\/\*__ENTRIES__\*\// { printf "%s", entries; next }
            { print }
        ' "$SRC_DIR/tools/hsin_verify_template.c" > "$_gen_c"

        mkdir -p "$_stage/bin"
        if "$_cc" -O2 -o "$_stage/bin/$_binname" "$_gen_c" 2>"$OUT_DIR/${_binname}-build.log"; then
            chmod 0755 "$_stage/bin/$_binname"
            echo "  -> bin/$_binname compiled OK (using $_cc)"
        else
            echo "  [!] WARNING: $_binname compile failed, see $OUT_DIR/${_binname}-build.log"
            rm -f "$_stage/bin/$_binname"
        fi
    }

    echo "[release] hashing LIGHT set (checked on every WebUI call)..."
    _entries_light=$(_write_manifest_and_entries "$PROTECTED_FILES_LIGHT" "$_stage/core/.integrity.manifest")
    echo "[release] LIGHT manifest has $(wc -l < "$_stage/core/.integrity.manifest") entries"

    echo "[release] hashing FULL set (checked at boot + background loop only)..."
    _entries_full=$(_write_manifest_and_entries "$PROTECTED_FILES_FULL" "$_stage/core/.integrity.manifest.full")
    echo "[release] FULL manifest has $(wc -l < "$_stage/core/.integrity.manifest.full") entries"

    # ARCH GUARD: cc/clang/gcc here compiles for whatever machine THIS
    # script happens to be running on, with no cross-compile target. Run
    # this from a PC/laptop/CI (x86-64) by mistake and it "succeeds" -
    # compile exits 0, log says "compiled OK" - but the resulting binary
    # is an x86-64 ELF that a real Android/ARM phone can't execute at
    # all. hsin_protect_integrity treats that failed exec as "tampered"
    # and action.sh/service.sh refuse to run - the WHOLE module goes
    # dead, not just a feature. This must always be built from an ARM
    # environment (Termux on-device is the normal case).
    _host_arch=$(uname -m 2>/dev/null)
    case "$_host_arch" in
        aarch64|arm64|armv7*|armv8*) _arch_ok=1 ;;
        *) _arch_ok=0 ;;
    esac

    _cc=""
    if [ "$_arch_ok" -eq 1 ]; then
        for _c in cc clang gcc; do
            command -v "$_c" >/dev/null 2>&1 && { _cc="$_c"; break; }
        done
    fi

    if [ "$_arch_ok" -ne 1 ]; then
        echo "  [!] WARNING: this machine reports arch '$_host_arch', not ARM."
        echo "      Compiling here would produce a verifier binary that CANNOT"
        echo "      run on an Android/ARM phone - action.sh and service.sh"
        echo "      would refuse to start entirely if this shipped (not a"
        echo "      minor bug, the module goes fully dead)."
        echo "      Run build_release.sh from Termux ON THE DEVICE (or an"
        echo "      aarch64 NDK cross-compiler) to get a working binary."
        echo "      Skipping binary compile - falling back to the safe"
        echo "      shell/manifest check for both LIGHT and FULL sets."
        rm -f "$_stage/bin/hsin-verify" "$_stage/bin/hsin-verify-full" 2>/dev/null
    fi

    if [ -n "$_cc" ]; then
        echo "[release] compiling verifiers..."
        _compile_verifier "$_entries_light" "hsin-verify"
        _compile_verifier "$_entries_full" "hsin-verify-full"
        # Post-compile sanity check: catch a cross-compiler that silently
        # targets the wrong arch even though we're technically on ARM
        # (e.g. a misconfigured clang toolchain) before it ships.
        if command -v file >/dev/null 2>&1 || command -v readelf >/dev/null 2>&1; then
            for _binname in hsin-verify hsin-verify-full; do
                _bp="$_stage/bin/$_binname"
                [ -f "$_bp" ] || continue
                if command -v file >/dev/null 2>&1; then
                    _finfo=$(file "$_bp" 2>/dev/null)
                else
                    _finfo=$(readelf -h "$_bp" 2>/dev/null | awk -F: '/Machine:/{gsub(/^ +/, "", $2); print $2}')
                fi
                case "$_finfo" in
                    *aarch64*|*AArch64*|*ARM*|*arm64*) : ;;
                    *)
                        echo "  [!] WARNING: $_binname arch check failed ($_finfo)"
                        echo "      Removing it - falling back to shell/manifest check"
                        echo "      for this binary instead of shipping a broken one."
            rm -f "$_bp"
                        ;;
                esac
            done
        fi
    elif [ "$_arch_ok" -eq 1 ]; then
        echo "  [!] WARNING: no C compiler found (cc/clang/gcc)."
        echo "      Release will fall back to the shell/manifest check for both sets."
        echo "      Install a compiler (e.g. 'pkg install clang' in Termux) and rebuild"
        echo "      to get the hardened binary check."
    fi
    # Build tooling never ships inside the release - only in dev.
    rm -f "$OUT_DIR/hsin-verify_gen.c" "$OUT_DIR/hsin-verify-full_gen.c"
    rm -rf "$_stage/tools"
    rm -f "$_stage/build_release.sh"

    echo "[release] zipping..."
    _zip_stage "$_stage" "HSIN-${VERSION}.zip"
    rm -rf "$_stage"
}

case "$1" in
    dev) build_dev ;;
    release) build_release ;;
    *)
        build_dev
        build_release
        ;;
esac

echo "Done."
