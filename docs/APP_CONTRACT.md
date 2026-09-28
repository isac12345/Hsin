# APP_CONTRACT.md — Kontrak app ↔ modul HSIN (App A3, fakta terverifikasi)

Label bukti: [SANDBOX] = output eksekusi nyata di harness sandbox leader
(2026-09-28, `HSIN_SANDBOX=1`, pohon sysfs/proc palsu, repo TIDAK diubah).
[KODE] = dibaca dari kode (dengan file:baris). Yang tidak ada ditulis
"TIDAK ADA". Tanpa klaim stabil; versi beta sampai validasi HP fisik.

Pohon sandbox: CPU `policy0`+`policy6` (gov `performance schedutil powersave`,
OPP `300000 600000 1200000 1800000`, cur `schedutil`/`1200000`), thermal
`zone0=45000`+`zone1=42000`, devfreq `23100000.gpu`
(`simple_ondemand performance`, `max_freq=850000000`), block `sda`
(`[mq-deadline] none`), zram `comp_algorithm=[zstd] lz4`, proc
(`MemTotal=8000000`, `loadavg=2.35`, `uptime=98765`,
`tcp_available_congestion_control="cubic reno bbr"`, `swappiness=60`),
`HSIN_CONF` berisi `ALLOW_EXTREME=false`.

Keterbatasan sandbox (jujur, memengaruhi contoh di bawah):
- `capabilities` membaca path `/sys` literal ([KODE] `action.sh:117-131`,
  tanpa guard prefix) sehingga di sandbox melaporkan `false` walau node
  palsu ada. Di HP (path asli) nilainya benar.
- `knobs` GPU `opp_khz=[]` di sandbox (sumber OPP devfreq tak resolve di
  harness ini); `zram.supported=false`; `device.soc="unknown"`;
  `battery_pct=-1`; `refresh_hz=0` (tanpa dumpsys). BUKAN 0 yang valid —
  APK harus memperlakukannya sebagai tidak tersedia (aturan A11).

## 1. Cara memanggil (transport, dari app lama — [KODE])

- `su -c "sh /data/adb/modules/hsin/action.sh <cmd> [args]"`
  ([KODE] `docs/APP_LEGACY_NOTES.md` §8; `action.sh:4-5` default
  `HSIN_MODULE_PATH=/data/adb/modules/hsin`, `HSIN_DATA=/data/adb/hsin`).
- Timeout 20 detik per command, di `Dispatchers.IO`, quoting token aman
  (`RootExec.kt`, `HsinRepository.kt` — app lama; app baru mendefinisikan
  ulang di A6).
- Output multi-baris + JSON di baris terakhir: ambil baris non-kosong
  TERAKHIR yang diawali `{` (`lastJsonLine`, [KODE]
  `docs/APP_LEGACY_NOTES.md` §8). Berlaku untuk `status`, `knobs`,
  `device`, `knob-list`, `config-get`, `conflicts`.
- Urutan kirim app lama: semua `knob-set` + `config-set` dulu, baru SATU
  `apply <profil>` ([KODE] `docs/APP_LEGACY_NOTES.md` §8).

## 2. Subcommand `action.sh` (dipakai APK)

Dispatcher [KODE] `action.sh:1212-1394` (`_main`, default `info`;
unknown command → teks Usage, rc=0):

| Command | Handler | Argumen | rc sukses | rc gagal + pesan |
|---|---|---|---|---|
| `info` | `hsin_action_info` | — | 0, teks manusia | — |
| `device` | `hsin_action_device_info` (:61) | — | 0, 1 baris JSON | — |
| `capabilities` | `hsin_action_capabilities` (:106) | — | 0, 1 baris JSON boolean | — |
| `status` | `hsin_action_game_boost_check` + `hsin_action_live_status` (:1226-1229) | — | 0, baris non-JSON dulu lalu 1 baris JSON | — |
| `logs` | `hsin_action_logs` (:795) | `[type] [lines=20]` | 0, array JSON 1 baris; file hilang → `[]` | — |
| `apply` | `hsin_action_apply "$1" "manual"` (:1233) | `<profil>` | 0, `OK: Applying ... (running in background...)` | 1 `ERROR: Profile not found: X`; 1 `ERROR: Extreme mode requires ALLOW_EXTREME=true` (:877-887) |
| `backup` | `hsin_action_backup` | — | 0, `OK: Backup created` | — |
| `rollback` | `hsin_action_rollback` | — | 0, `OK: Rollback complete` (+ baris `Restore ... ok=N fail=M`) | — |
| `conflicts` | `hsin_action_conflicts` | — | 0, `{"count":N,"conflicts":[...]}` | — |
| `config-get` | `hsin_action_config_get` (:1032) | — | 0, 1 baris JSON | — |
| `config-set` | `hsin_action_config_set` (:1059) | `<key> <val>`, 7 key whitelist | 0, `OK: key=val` | 1 `ERROR: unknown setting: X`; 1 `ERROR: ... must be ...` (:1061-1083) |
| `knobs` | `hsin_knobs_json` (:1251) | — | 0, 1 baris JSON | — |
| `knob-set` | `hsin_uk_set` (:1254-1264) | `<key> <val>` (val kosong = hapus override) | 0, `OK key=val` | 1 `ERROR: usage...` (<2 arg); 1 `ERROR: key knob tidak dikenal (pola: ...)`; 1 `ERROR: <key>: nilai harus ...` |
| `knob-reset` | `hsin_uk_reset` (:1265-1270) | — | 0, `OK reset (N key dihapus)` | 1 bila file tak bisa dihapus |
| `knob-list` | `hsin_uk_list` (:1271) | — | 0, baris manusia + 1 baris JSON terakhir | — |
| `renderer-state` | `hsin_render_state` (:1282) | — | 0, teks multi-baris | — |
| `renderer-apply` | `hsin_render_apply_live` (:1274) | `<renderer>` | 0 (+ persist `RENDERER` via config-set) | gagal apply → tanpa OK |
| `downscale-status` | `hsin_downscale_status` (:1312) | — | 0, 1 baris JSON | — |
| `downscale-enable` | `hsin_downscale_apply` (:1286) | `[pct=30]`, 1-99 | 0, `OK: downscale applied ...` | 1 `ERROR: percent must be ...` |
| `downscale-disable` | `hsin_downscale_reset` (:1306) | — | 0, `OK: downscale disabled ...` | — |
| `refresh-lock-status` | `hsin_refresh_status` (:1368) | — | 0, 1 baris JSON | — |
| `refresh-lock-enable` | `hsin_refresh_lock` (:1346) | `[hz=120]` | 0, `OK: refresh rate locked at XHz` | 1 `ERROR: ...` |
| `refresh-lock-disable` | `hsin_refresh_unlock` (:1362) | — | 0, `OK: ...` | — |
| `list-apps`, `game-list\|game-add\|game-remove` | engine game (:1326-1345) | — | 0 | — |
| `export-debug` / `export` | `hsin_action_export_debug` (:1382-1387) | `[lines=100]` | 0, `OK: Debug report written to ...` | — |

`bin/hsin` ([KODE] `bin/hsin:78-243`): CLI diagnostik
(`detect|scan|apply|status|policy|backup|restore|cpu|memory|gpu|io|network|
thermal|thermal-test|game|refreshrate|dvfs|framelimit|surfaceflinger|render|
extreme|doctor|export|logs|version|help`). `apply`/`status`-nya mendelegasikan
ke `action.sh`. BUKAN jalur utama APK (APK memanggil `action.sh` langsung
via `su -c`, seperti app lama).

## 3. Contoh output NYATA [SANDBOX]

### 3.1 `status` [SANDBOX], rc=0
Baris non-JSON (cek game boost) dulu, JSON TERAKHIR (dipotong di sini
hanya penanda — output asli 1 baris penuh):
`{"cpu_temp":45000,"gpu_temp":42000,"cpu_freq":1488500,"cpu_freq_big":1820000,"cpu_freq_little":1378000,"gpu_freq":400000,"cpu_max_khz":1820000,"gpu_max_khz":850000,"ram_used_kb":3000000,"ram_total_kb":8000000,"battery_pct":-1,"battery_status":"Unknown","battery_temp_c":0,"refresh_hz":0,"game_fps":0,"uptime_sec":98765,"profile":"none","apply_status":"unknown","cpu_load_x100":235,"zram_pct":0,"global_rr_enabled":"false","global_rr_reduced":"false","global_rr_peak_hz":0,"global_rr_min_hz":0,"dvfs_enabled":"false","dvfs_cpu_limit":100,"dvfs_gpu_limit":100,"frame_limit_disabled":"false","surfaceflinger_enabled":"false"}`
Sumber metrik ([KODE] `action.sh:353-792` `hsin_action_live_status`):
suhu = loop thermal zone; `cpu_freq` = `scaling_cur_freq` × jumlah core;
`cpu_freq_big/little` = max per policy; `gpu_freq` = devfreq `cur_freq`/1000;
RAM = meminfo; `battery_*` = `power_supply/*` (-1/Unknown bila absen);
`refresh_hz` = cache dumpsys (`action.sh:622-652`, 0 bila tak ada);
`profile`/`apply_status` = `state.lock`; `zram_pct` = node zram;
`cpu_load_x100` = `/proc/loadavg` (235 = 2.35 di sandbox).

### 3.2 `knobs` [SANDBOX], rc=0 (1 baris, disalin utuh)
`{"v":1,"profiles":["balanced","battery","extreme","performance"],"cpu":{"supported":true,"policies":[{"id":"0","hw_max_khz":1800000,"govs":["performance","schedutil","powersave"],"cur_gov":"schedutil","opp_khz":[300000,600000,1200000,1800000],"writable_min":true,"writable_max":true},{"id":"6","hw_max_khz":1800000,"govs":["performance","schedutil","powersave"],"cur_gov":"schedutil","opp_khz":[300000,600000,1200000,1800000],"writable_min":true,"writable_max":true}]},"gpu":{"supported":true,"nodes":[{"name":"23100000.gpu","govs":["simple_ondemand","performance"],"opp_khz":[],"cur_gov":"simple_ondemand","writable":true}]},"memory":{"supported":true,"swappiness":{"min":0,"max":100,"cur":60,"writable":true,"supported":true},"zram":{"algos":[],"cur":"","writable":false,"supported":false}},"io":{"supported":true,"blocks":[{"name":"sda","schedulers":["[mq-deadline]","none"],"cur":"mq-deadline","writable":true}]},"network":{"supported":true,"tcp_cc":["cubic","reno","bbr"],"tfo":{"min":0,"max":3,"cur":0,"supported":true}},"display":{"supported":false,"modes_hz":[],"cur_hz":0,"renderers":["skiagl","skiavk","system"],"cur_renderer":"skiavk","downscale":{"min":1,"max":99,"cur":30,"supported":false}},"features":{"dvfs":false,"global_rr":false,"frame_limit":false,"surfaceflinger":false,"gaming":false,"extreme_optin":false},"capabilities":{"available_frequencies_source":"cache"}}`
Catatan: `schedulers`/`zram.algos` apa adanya (kurung siku = aktif);
`cur` sudah bersih dari kurung.

### 3.3 `knob-list` [SANDBOX] — DUA format (baris + JSON terakhir)
Sebelum apply (override 1 key, belum ada hasil):
```
status=belum ada hasil apply
key=cpu_policy_0_gov requested=performance applied=- category=- reason="belum ada hasil apply"
{"count":1,"overrides":{"cpu_policy_0_gov":"performance"}}
```
rc=0. Format baris ([KODE] `core/user_knobs.sh:403,435,453`):
`key=<k> requested=<r> applied=<a> category=<c> reason="<alasan>"`.
Kosong: `status=belum ada hasil apply` + `{"count":0,"overrides":{}}`.

### 3.4 `knob_results.env` (hasil apply per knob) [SANDBOX]
Setelah `apply balanced` dengan SATU override (`cpu_policy_0_gov`), isi
`$HSIN_DATA/knob_results.env`:
```
cpu_policy_0_gov=performance|performance|APPLIED|dipakai sesuai permintaan
cpu_policy_6_gov=(profil)|schedutil|APPLIED|nilai profil (tanpa override)
cpu_policy_0_max_khz=(profil)|1800000|APPLIED|nilai profil (tanpa override)
cpu_policy_0_min_khz=(profil)|300000|APPLIED|nilai profil (tanpa override)
cpu_policy_6_max_khz=(profil)|1800000|APPLIED|nilai profil (tanpa override)
cpu_policy_6_min_khz=(profil)|300000|APPLIED|nilai profil (tanpa override)
```
Format ([KODE] `core/user_knobs.sh:608-633` `hsin_uk_result`):
`key=requested|applied|KATEGORI|alasan`, kategori ∈
`APPLIED|SKIPPED|FALLBACK|UNAVAILABLE|FAILED`. Sumber override vs profil
ditandai di kolom requested (`performance` vs `(profil)`).

### 3.5 `config-get` [SANDBOX], rc=0
`{"gam_boost_enabled":"false","allow_extreme":"false","renderer":"system","downscale_enabled":"false","downscale_percent":"30","refresh_lock_enabled":"false","refresh_lock_hz":"120"}`

### 3.6 `logs` [SANDBOX]
- `logs boot` rc=0: `["2026-09-28 12:38:36 [scan] gpu detect source=scan ...","... [scan] cache tidak valid/tak ada -> rescan (versi=1)",...,"2026-09-28 12:38:37 [memory] zram tidak ada (num_devices tak terbaca / 0)"]`
- `logs apply` rc=0: `["2026-09-28 12:38:37 [ENGINE] Profile applied (queued): balanced"]`
- Sintaks ([KODE] `action.sh:795-821`): `logs [type] [lines=20]` → array JSON
  1 baris berisi N baris terakhir; file hilang → `[]`. `type` = nama file di
  `$HSIN_DATA/logs/` (`boot.log`, `apply.log`, `rollback.log`, `error.log`,
  `debug.log`; [KODE] `core/logger.sh:10-17`, `action.sh:10-11`).
- `export-debug [lines=100]` → `OK: Debug report written to
  $HSIN_DATA/HSIN_DEBUG_REPORT.txt` (menggabungkan semua log).

### 3.7 `backup` / `rollback` [SANDBOX], rc=0
- `backup`: `Creating backup...` + `OK: Backup created`
- `rollback`: `Rolling back...` + `Restore 20260928_123838 done. ok=18 fail=0` + `OK: Rollback complete`

### 3.8 Lainnya [SANDBOX], rc=0
- `device`: `{"soc":"unknown","gpu":".../sys/devfreq/23100000.gpu","kernel":"5.15.211-...","ram_kb":"8000000","device_id":"HSIN-DEV-..."}` (`soc`/`gpu` apa adanya dari node).
- `capabilities`: `{"cpu_tuning":true,"gpu_devfreq":false,"thermal_node":false,"fpsgo":false,"kgsl":false,"sched_lat":false}` (`false` di sandbox karena path literal — lihat keterbatasan di atas).
- `conflicts`: `{"count":0,"conflicts":[]}`
- `renderer-state` (teks): `Renderer State: debug.hwui.renderer: skiavk ...`
- `downscale-status`: `{"enabled":"false","native":"unknown",...,"percent":"30",...}`
- `refresh-lock-status`: `{"enabled":"false","saved_hz":"120","peak":"auto","min":"auto","supported":"unknown"}`
- `info` (teks): `HSIN Universal Engine / Profile aktif: none / CPU: ... / GPU: ...`
- Error ([SANDBOX]): `knob-set bogus_key value` → `ERROR: key knob tidak dikenal (pola: ...)` rc=1; `knob-set cpu_policy_0_gov "bad;gov"` → `ERROR: cpu_policy_0_gov: nilai harus token ...` rc=1; command tak dikenal → teks Usage rc=0.

## 4. Inventaris knob per engine ([KODE] pola + validasi)

Pola key ([KODE] `core/user_knobs.sh:93-96,134-147`):
`cpu_policy_<id>_(gov|max_khz|min_khz|sched)`,
`gpu_node_<nama>_(gov|max_khz|min_khz|sched)` (nama disanitasi
`[^A-Za-z0-9]`→`_`, maks 40),
`io_block_<nama>_(gov|max_khz|min_khz|sched)` (hanya `sched` dipakai engine),
`zram_algo|swappiness|tcp_cc|tfo`.
Numerik: kHz `100000-5000000`, `swappiness` 0-200, `tfo` 0-3
(`user_knobs.sh:162-187,298`); token `1-32` karakter `[A-Za-z0-9_.-]`.

| Key | Tipe | Engine (file) | Sumber nilai valid |
|---|---|---|---|
| `cpu_policy_<id>_gov` | pilihan | `engine/cpu/governor.sh` | `scaling_available_governors` per policy (:79-82); ditolak → FALLBACK profil (:98-99) |
| `cpu_policy_<id>_max_khz` | rentang (kHz) | `engine/cpu/frequency.sh` | `scaling_available_frequencies` (snap ke OPP ≤ bila tak ada di tabel) |
| `cpu_policy_<id>_min_khz` | rentang (kHz) | `engine/cpu/frequency.sh` | sama dengan max |
| `gpu_node_<n>_gov` | pilihan | `engine/gpu/generic.sh` | `available_governors` node (:93) |
| `gpu_node_<n>_max_khz` | rentang (kHz) | `engine/gpu/generic.sh` | OPP node |
| `io_block_<n>_sched` | pilihan | `engine/io/scheduler.sh` | `queue/scheduler` (`[x]` = aktif, :108-134) |
| `tcp_cc` | pilihan | `engine/network/tcp.sh` | `tcp_available_congestion_control` (:51) |
| `tfo` | rentang 0-3 | `engine/network/tcp.sh` | node `tcp_fastopen` (:95) |
| `swappiness` | rentang 0-200 | `engine/memory/vm.sh` | `vm/swappiness` (:347); UI jujur 0-100 (clamp kernel) |
| `zram_algo` | pilihan | `engine/memory/zram.sh` | `comp_algorithm` node (:37) |

DISPLAY: TIDAK ADA knob user (hanya state di `knobs.display` +
command `renderer-apply`/`downscale-enable`/`refresh-lock-enable`).
`config-set` (bukan knob): 7 key
`GAM_BOOST_ENABLED|ALLOW_EXTREME|DOWNSCALE_ENABLED|REFRESH_LOCK_ENABLED|
RENDERER|DOWNSCALE_PERCENT|REFRESH_LOCK_HZ` ([KODE] `action.sh:1061-1064`).

## 5. Jawaban 5 gap (dengan bukti)

1. **Pilihan valid per knob**: dari command `knobs` (§3.2) — tiap node
   membawa `govs`/`opp_khz`/`schedulers`/`algos` + flag writable.
   `knobs` ADALAH command capability per-knob. `capabilities` hanya boolean
   kasar per subsistem ([SANDBOX] §3.8; [KODE] `action.sh:106-131`) dan TIDAK
   bisa di-sandbox (path `/sys` literal). Command capability terpisah di luar
   `knobs`/`capabilities`: TIDAK ADA.
2. **Kirim + apply, atomik?**: app mengirim N× `knob-set`/`config-set`
   (satu `su` per key) lalu 1× `apply <profil>` ([KODE] urutan app lama
   §1; `action.sh:1233-1235,1248-1270`). TIDAK atomik antar command:
   tidak ada transaksi/lock yang mengikat rangkaian `knob-set`
   (`hsin_uk_set` = tulis file + readback per key). Lock `mkdir`
   hanya melindungi update `state.lock` ([KODE]
   `core/state_manager.sh:37-39`), bukan rangkaian knob. Di dalam SATU
   proses apply, override dibaca sekali (cache per-proses), jadi apply
   konsisten terhadap file saat ia mulai. `apply` berjalan background
   (`OK: Applying ... (running in background...)` [SANDBOX] §3.4) —
   APK harus polling `knob-list`/`knob_results` untuk hasil, bukan
   menganggap selesai saat rc=0.
3. **Semantik manual murni**: TIDAK MURNI saat ini — knob yang tidak
   diatur user DITULIS dari nilai profil dasar. Bukti [SANDBOX] §3.4:
   hanya `cpu_policy_0_gov=performance` di-set, hasil apply mencatat
   `cpu_policy_6_gov=(profil)|schedutil`,
   `cpu_policy_0_max_khz=(profil)|1800000`,
   `cpu_policy_0_min_khz=(profil)|300000`,
   `cpu_policy_6_max_khz=(profil)|1800000`,
   `cpu_policy_6_min_khz=(profil)|300000` — semua `APPLIED` dari profil
   `balanced` ([KODE] `profiles/balanced.conf`: `governor=schedutil`,
   `freq_max_percent=100`). Override hanya mengganti per key yang cocok;
   yang ditolak engine jatuh ke FALLBACK profil ([KODE]
   `engine/cpu/governor.sh:98-99`). Keputusan user dibutuhkan (lihat §6 D1)
   — GATE A10.
4. **Gate `ALLOW_EXTREME` + boot guard**: `ALLOW_EXTREME` dibaca via
   `config-get` (`allow_extreme`, [SANDBOX] §3.5) dan ditulis via
   `config-set` (whitelist, [KODE] `action.sh:1062`); sesi env
   `ALLOW_EXTREME=true` juga dihormati per-invocation ([KODE]
   `action.sh:38-57`); `apply extreme` tanpa opt-in → rc=1 ([KODE]
   `action.sh:884-887`). Boot guard: TIDAK ADA subcommand yang
   mengeksposnya (grep `guard` di `action.sh` hanya komentar `:775`).
   APK hanya bisa membaca via `logs boot` dengan marker
   `BOOT-GUARD AKTIF: ... semua tuning DILEWATI`
   ([KODE] `core/boot_guard.sh:99-101`; state file
   `$HSIN_DATA/.boot_fail_count`, `:19`; threshold 2, cooldown 86400).
   Command `guard-status`: TIDAK ADA — keputusan user (§6 D2).
5. **Exit code + error untuk APK**: rc=0 = sukses (termasuk command tak
   dikenal → Usage, dan `logs` file hilang → `[]`); rc=1 + baris
   `ERROR: ...` = gagal (key tak dikenal, nilai invalid, profil hilang,
   extreme terkunci, `config-set` invalid). Format sukses `OK ...`,
   format error `ERROR: ...` (stdout; bukan JSON). Pemetaan:
   `COMMAND_FAILED` ← rc=1/`ERROR:`; `INVALID_RESPONSE` ← output tanpa
   JSON (sisi parser APK); `FEATURE_UNSUPPORTED` ← sebagian via
   `writable:false`/`supported:false` di `knobs` + kategori
   `SKIPPED/UNAVAILABLE` di hasil (BUKAN rc); `TIMEOUT` /
   `ROOT_UNAVAILABLE` / `MODULE_NOT_FOUND` = sisi transport APK
   (TIDAK ADA dari modul).

## 6. Keputusan yang dibutuhkan user (STOP, tanpa workaround)

- **D1 (GATE A10) — semantik apply**: (a) TERIMA perilaku sekarang (apply
  menulis profil dasar + override per key; "Terapkan (N)" berarti
  N override di atas profil dasar), atau (b) MINTA mode manual murni di
  modul (apply hanya menyentuh key dirty — perubahan perilaku modul,
  di luar scope APK). Tanpa keputusan ini A10 tidak boleh dikerjakan.
- **D2 — baca boot guard**: (a) tambah command `guard-status` di modul
  (perubahan kecil, di luar A3), atau (b) APK parse `logs boot` mencari
  marker `BOOT-GUARD AKTIF` (rapuh bila teks berubah). Rekomendasi
  leader: (a) saat modul disentuh berikutnya.
- **D3 — `capabilities` vs `knobs`**: APK memakai `knobs` sebagai sumber
  pilihan valid (sudah sandboxable); `capabilities` hanya pelengkap
  boolean di HP. Tanpa perubahan; dicatat agar A9 tidak bergantung pada
  `capabilities` untuk daftar governor/OPP.
- **D4 — A4**: `applicationId=com.hsin`, signing release belum terdefinisi
  (lihat LAPORAN A2 poin 7), minSdk 26/targetSdk 34 menunggu konfirmasi —
  dibawa ke A4, bukan diputuskan di sini.
