# Device Report Template

## Device Identity

- Model: __________
- Chipset / SoC: __________
- Kernel: __________
- Root status: __________ (Magisk / KernelSU / None)
- HSIN version: __________ (module.prop `version`)
- Build ZIP: __________

## Test Results

| Aksi | Hasil | Catatan |
|---|---|---|
| install | ✅ / ❌ | |
| boot | ✅ / ❌ | |
| status | ✅ / ❌ | |
| apply (battery) | ✅ / ❌ | |
| apply (balanced) | ✅ / ❌ | |
| apply (performance) | ✅ / ❌ | |
| apply (extreme) | ✅ / ❌ | |
| knob-set | ✅ / ❌ | |
| knob-reset | ✅ / ❌ | |
| backup | ✅ / ❌ | |
| rollback | ✅ / ❌ | |
| logs | ✅ / ❌ | |

## APPLY-TIME

- Waktu mulai apply: __________
- Waktu selesai apply: __________
- Durasi (detik): __________

## Weight / Blank Check

- File `tests/device_reports/.gitkeep` ada: ✅ / ❌
- File ini tidak kosong: ✅ / ❌
