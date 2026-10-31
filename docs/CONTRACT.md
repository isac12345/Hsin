# Kontrak app ↔ modul HSIN v6.0.0

App memanggil: `su -c "sh /data/adb/modules/hsin/action.sh <perintah> [arg]"`.
Hampir semua perintah mencetak SATU baris JSON. Data modul di `/data/adb/hsin5/`.

| Perintah | Hasil |
|---|---|
| `ping` | `pong v6.0.0` |
| `device` | `{"v":5,"module","model","brand","soc","kernel","android"}` |
| `status` | CPU (`cpu_khz`,`cores`,`policies[{id,cur,min,max,hw,gov}]`,`cpu_total`,`cpu_idle`), GPU (`gpu_hz`,`gpu_max_hz`,`gpu_gov`), suhu (`cpu_temp`,`gpu_temp`,`temp_max`,`bat_temp`), baterai (`bat_pct`,`bat_charging`), memori (`ram_*_kb`,`swap_*_kb`), `load_x100`, status (`safe_mode`,`thermal_trip`,`game_mode`,`game_active`,`overrides`). Tidak tersedia = -1 / 0. Pemakaian CPU dihitung app dari selisih `cpu_total`/`cpu_idle` antar panggilan. |
| `knobs` | `{"v":5,"categories":[{"id","title","knobs":[...]}]}`; knob `choice`(`options`) / `range`(`min`,`max`,`step`) / `locked`(`reason`); `cur` sekarang, `def` bawaan boot |
| `set-many k=v ...` | tulis + verifikasi + simpan override global. `{"ok","fail","results":[{"key","ok","value","msg"}]}` |
| `apply` | tulis ulang override global (dipakai saat boot) |
| `restore` | kembalikan semua ke baseline + hapus override global |
| `conflicts` | `{"list":["Alpha Fusion",...]}` modul aktif lain yang kemungkinan ikut mengatur performa |
| `thermal-get` / `thermal-set <0\|1> <60..110>` / `thermal-ack` | pengaman panas; `thermal-ack` menerapkan lagi override global setelah trip |
| `game-set <pkg> [k=v ...]` / `game-del <pkg>` / `game-list` / `game-mode <0\|1>` / `detect` | profil per game |
| `guard-reset` | matikan mode aman |
| `mode <hemat\|bawaan\|seimbang\|boost>` / `mode-get` | mode global (Boost: batas panas 100, CPU/GPU min=max=tertinggi) |
| `game-cfg <pkg> <mode\|global> [res 50-100]` / `game-get <pkg>` | mode + resolusi per game (Game Mode API) |
| `launch <pkg>` | terapkan profil game lalu buka game (monkey) |
| `dnd-cfg <0\|1>` / `dnd-now <0\|1>` | Jangan ganggu otomatis saat game / sekarang |
| `ram-clean` | matikan app pihak ketiga latar (kecuali IME, launcher, game aktif, root manager) → `freed_kb` |
| HUD | `core/hud.sh --loop <pkg>` stream metrik (lat/cpu/gpu/suhu), dibaca app untuk floating FPS |
| `logs boot\|apply\|game\|thermal [n]` | n baris terakhir: `YYYY-MM-DD HH:MM:SS LEVEL pesan` |

Alasan penolakan knob: `node read-only`, `node ditimpa mount modul lain`, `ditolak: kemungkinan dipegang modul lain <nama>`, `ditolak kernel`, atau `nilai kembali ke X karena ada yang menahan`.

## Boot dan daemon
`service.sh`: baseline → override global → jalankan `daemon.sh` → counter boot direset setelah 60 dtk stabil.
Mode aman: boot tidak pernah stabil 3 kali berturut-turut → override TIDAK diterapkan sampai `guard-reset`.

`daemon.sh` (satu proses): tiap 3 dtk (mode per game aktif) atau 10 dtk.
- Pengaman panas: suhu CPU ≥ batas → tulis baseline ke semua knob (override tersimpan TIDAK dihapus), buat `thermal_trip`; berhenti memproses game sampai `thermal-ack`.
- Per game: baca `/dev/cpuset/top-app/cgroup.procs` → `/proc/<pid>/cmdline`; bila paket punya `games/<pkg>.env`: tulis nilainya (tidak disimpan sebagai global). Game ditutup: tiap knob profil kembali ke nilai Global (override user, kalau tidak ada baseline). Deteksi tidak tersedia → `detect` mengembalikan `ok:0`.
- Mode aman menghentikan semua tindakan daemon.

Preset hidup di sisi app (SharedPreferences, ekspor/impor lewat clipboard). Profil game disimpan di app dan disalin ke modul lewat `game-set` (disinkronkan ulang tiap sesi app).
