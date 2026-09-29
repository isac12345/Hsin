# Fixture A7 — disalin VERBATIM dari keluaran sandbox nyata (HSIN_SANDBOX=1)
# Jangan mengarang angka: parser dan mapping diuji terhadap nilai sebenarnya.
# Sumber perintah + tanggal: `sh action.sh <cmd>` di repo, 2026-09-29.
- knobs_sandbox.txt → `action.sh knobs` (satu baris JSON, kontrak §3.2)
- config_get.txt → `action.sh config-get` (kontrak §3.5)
- guard-status.txt → `action.sh guard-status` (kontrak §3.10, tidak aktif)
- guard-status_active.txt → `action.sh guard-status` setelah state file `1790688802:2` (kontrak §3.10, aktif)
- knob-list_manual.txt → `action.sh knob-list` setelah 2 override (kontrak §3.11)
- status.txt → `action.sh status`, baris JSON terakhir (kontrak §3.1)
- status_ok.txt → sama dengan status.txt (dipakai A6)
- usage_rc0.txt → `action.sh frobnicate` (kontrak §3.9, rc=0)
