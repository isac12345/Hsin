#!/usr/bin/env bash
# Cek sintaks semua script shell modul + konsistensi versi. Dipakai CI dan bisa dijalankan lokal.
set -e
cd "$(dirname "$0")/.."
fail=0
# Shell HP Android = mksh, dan mksh lebih ketat dari dash (mis. `${v#*Parcel(}` ditolak).
# Jadi tiap file dicek dua kali: dash (sh) dan mksh.
for f in $(find module -name '*.sh' -not -path '*/fasrs/*' -not -path '*/uperf/*'); do
  sh -n "$f" 2>/dev/null || { echo "SYNTAX ERROR (sh): $f"; fail=1; }
  command -v mksh >/dev/null 2>&1 && { mksh -n "$f" 2>/dev/null || { echo "SYNTAX ERROR (mksh): $f"; fail=1; }; }
done
# mksh membaca "|" tanpa kutip/backslash di dalam ${v%%|*} sebagai operator: hasilnya kosong
# tanpa error sintaks (bug thermal 20 Nov). Pola harus ditulis "|" atau \|.
bad=$(grep -rnE '\$\{[A-Za-z_0-9]+(%%?|##?)[^"\\}]*[^"\\}]\|[^}]*\}' module --include=*.sh | grep -vE '"\|"|\\\|' || true)
[ -z "$bad" ] || { echo "PIPE TANPA KUTIP di \${..} (mksh salah baca):"; echo "$bad"; fail=1; }
VER=$(tr -d '[:space:]' < version.txt)
MP=$(sed -n 's/^versionCode=//p' module/module.prop | head -n 1)
CV=$(sed -n 's/^HSIN_COMPANION_VER=//p' module/common/companion_install.sh | head -n 1)
[ "$VER" = "$MP" ] || { echo "version.txt ($VER) != module.prop versionCode ($MP)"; fail=1; }
[ "$VER" = "$CV" ] || { echo "version.txt ($VER) != HSIN_COMPANION_VER ($CV)"; fail=1; }
[ -f module/common/hsinctl.sh ] || { echo "hsinctl.sh hilang"; fail=1; }
[ -f module/common/autoctl.sh ] || { echo "autoctl.sh hilang"; fail=1; }
[ "$fail" = 0 ] && echo "check_module: OK (versionCode $VER)"
exit $fail
