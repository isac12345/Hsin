# Kontrak app ↔ modul HSIN v5

App memanggil: `su -c "sh /data/adb/modules/hsin/action.sh <perintah> [arg]"`.
Semua perintah mencetak SATU baris JSON (kecuali `ping`, `logs`). Data modul di `/data/adb/hsin5/`.

| Perintah | Hasil |
|---|---|
| `ping` | `pong v5.0.0` |
| `device` | `{"v":5,"module","model","brand","soc","kernel","android","ram_kb"}` |
| `status` | `{"cpu_khz","gpu_hz","cpu_temp","gpu_temp","bat_pct","bat_temp","ram_total_kb","ram_used_kb","load_x100","safe_mode","overrides"}` (nilai tak tersedia = -1 / 0) |
| `knobs` | `{"v":5,"categories":[{"id","title","knobs":[...]}]}` |
| `set-many k=v k=v ...` | tulis + verifikasi + simpan override. `{"ok","fail","results":[{"key","ok","value","msg"}]}` |
| `apply` | tulis ulang semua override tersimpan (dipakai boot) |
| `restore` | kembalikan ke baseline bawaan + hapus semua override |
| `snapshot` | simpan baseline (otomatis bila belum ada) |
| `guard` / `guard-reset` | status / matikan mode aman |
| `logs boot\|apply [n]` | n baris terakhir, format `YYYY-MM-DD HH:MM:SS LEVEL pesan` |

Knob: `type` = `choice` (`options`) | `range` (`min`,`max`,`step`) | `locked` (`reason`). `cur` = nilai sekarang, `def` = nilai bawaan boot.
Nilai kosong tidak pernah dikirim. Hanya `[A-Za-z0-9_.:+-]` yang lolos (app dan modul sama-sama menyaring).

Boot: `service.sh` menyimpan baseline → menerapkan override → reset counter setelah 60 dtk stabil.
Mode aman: bila counter ≥ 3 (boot tak pernah stabil), override TIDAK diterapkan sampai dimatikan lewat app.
Preset hidup di sisi app (SharedPreferences); modul tidak tahu soal preset.
