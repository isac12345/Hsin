# APP_CONTRACT.md — Kontrak app ↔ modul HSIN (A3 facts + revisi M3, fakta terverifikasi)

Label bukti: [SANDBOX] = output eksekusi nyata di harness sandbox leader
(2026-09-29 untuk bagian M3; 2026-09-28 untuk bagian A3; `HSIN_SANDBOX=1`,
pohon sysfs/proc palsu, repo TIDAK diubah).
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
- **Perintah tak dikenal → teks `Usage:` dengan rc=0** ([SANDBOX] §3.8,
  verifikasi ulang 2026-09-29). APK WAJIB memvalidasi nama command dari
  allowlist; jangan menganggap rc=0 sebagai "berhasil".
- **`capabilities` TIDAK bisa di-sandbox** ([KODE] `action.sh:115-145`
  memakai path `/sys` + `/sys/class/*` literal tanpa prefix): di sandbox
  melaporkan `false` walau pohon palsu ada. Di HP nilai sebenarnya benar,
  tapi APK tidak boleh memakainya sebagai sumber kebenaran — sumber
  kebenaran tetap `knobs`.

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
| `guard-status` | `hsin_guard_status` (`core/guard_status.sh`) | — | 0, 5 baris key=value + 1 baris JSON terakhir | — (node hilang/rusak → `active=0`, bukan error) |
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

### 3.9 Batasan yang WAJIB diketahui APK [SANDBOX] (verifikasi ulang 2026-09-29)
Perintah tak dikenal (`frobnicate`) → rc=**0** + teks `Usage:`:
```
Usage: action.sh [info|device|capabilities|status|guard-status|logs|apply|backup|rollback|conflicts|export|renderer-apply|renderer-state|downscale-enable|downscale-disable|downscale-status|refresh-lock-enable|refresh-lock-disable|refresh-lock-status|export-debug|list-apps|game-list|game-add|game-remove]
```
Konsekuensi: rc=0 TIDAK berarti "dipahami". APK wajib (1) memakai nama
command dari allowlist tetap, (2) memeriksa baris pertama output — kalau
awalan `Usage:` perlakukan sebagai `COMMAND_FAILED`, bukan sukses.

`capabilities` → rc=0 tapi TIDAK bisa di-sandbox (path `/sys` literal,
[tidak ada `SYSFS_*_PREFIX` di baris 110–145 `action.sh`]):
```
{"cpu_tuning":true,"gpu_devfreq":false,"thermal_node":false,"fpsgo":false,"kgsl":false,"sched_lat":false}
```
Di sandbox Reporting hanya `cpu_tuning:true` padahal pohon devfreq palsu
ada → nilainya untuk harness, bukan bukti device nyata. Di HP nilai
sebenarnya benar, tapi APK tetap tidak boleh memakainya sebagai sumber
kebenaran (sumber pilihan valid = `knobs`, lihat D3).

### 3.10 `guard-status` [SANDBOX] (M2), rc=0 — output NYATA
Tidak aktif (state file `$HSIN_DATA/.boot_fail_count` tidak ada):
```
active=0
fail_count=0
threshold=2
cooldown_remaining_sec=0
last_reason="tidak ada state"
{"active":0,"fail_count":0,"threshold":2,"cooldown_remaining_sec":0,"last_reason":"tidak ada state"}
```
Aktif (state `1790688802:2` = 2 boot gagal berturut, threshold 2):
```
active=1
fail_count=2
threshold=2
cooldown_remaining_sec=86400
last_reason="boot gagal 2 x berturut-turut"
{"active":1,"fail_count":2,"threshold":2,"cooldown_remaining_sec":86400,"last_reason":"boot gagal 2 x berturut-turut"}
```
Kontrak ([KODE] `core/guard_status.sh`): 5 baris `key=value` (`active`,
`fail_count`, `threshold`, `cooldown_remaining_sec`, `last_reason`) lalu SATU
baris JSON dengan key yang sama, selalu rc=0. State hilang/rusak/expired →
`active=0` + `last_reason="tidak ada state"` ([SANDBOX] 4 kondisi: aktif,
tidak aktif, hilang, rusak — `tests/sandbox_guard_status.sh` 20/20). READ-ONLY:
nol file tercipta (terbukti: direktori data tetap kosong setelah dipanggil).

### 3.11 `knob-list` di mode manual [SANDBOX] (M1) — output NYATA
Dua override (`io_block_sda_readahead=2048`, `vfs_cache_pressure=250`) +
`apply manual`:
```
key=io_block_sda_readahead requested=2048 applied=2048 category=APPLIED reason="dipakai sesuai permintaan"
key=vfs_cache_pressure requested=250 applied=250 category=APPLIED reason="dipakai sesuai permintaan"
key=cpu_policy_0_gov requested=(manual) applied=- category=SKIPPED reason="tidak diatur (mode manual)"
key=uclamp_min requested=(manual) applied=- category=SKIPPED reason="tidak diatur (mode manual)"
... (31 knob lain, semuanya SKIPPED "tidak diatur (mode manual)") ...
key=backlog requested=(manual) applied=- category=SKIPPED reason="tidak diatur (mode manual)"
{"count":2,"overrides":{"io_block_sda_readahead":"2048","vfs_cache_pressure":"250"}}
```
Snapshot node SEBELUM → SESUDAH pada siklus yang sama [SANDBOX]:
`read_ahead_kb 128→2048`, `vfs_cache_pressure 100→250`, sisanya TIDAK
berubah (`dirty_ratio=20`, `dirty_background_ratio=5`,
`scaling_governor=schedutil`, `scaling_max_freq=1800000`,
`netdev_max_backlog=1000`, `add_random=0`, `stat_interval=10`).
BUKTI mode manual murni: knob yang tidak di-set user tidak ditulis sama
sekali — bukan ditulis dengan nilai profil. [KODE] default profile =
`manual` ([KODE] `service.sh:80`, fallback `service.sh:180`, dan
`service.sh:239` TIDAK memuat `profiles/*.conf` saat mode manual);
apply dispatcher meneruskan `manual` ke semua engine
([KODE] `core/apply_engines.sh:25`).

## 4. Inventaris knob per engine (post K1/K2/K3, [KODE] pola + validasi)

Pola key ([KODE] `core/user_knobs.sh` `_uk_class`):
- per policy CPU: `cpu_policy_<id>_(gov|max_khz|min_khz|sched|rate_limit_us)`
- per node devfreq: `gpu_node_<nama>_(gov|max_khz|min_khz|sched|polling_interval|up_threshold|down_differential)`
- per block: `io_block_<nama>_(gov|max_khz|min_khz|sched|readahead|add_random|iostats|nomerges)`
- kunci tetap satu-node: `zram_algo|swappiness|tcp_cc|tfo|vfs_cache_pressure|dirty_ratio|dirty_background_ratio|backlog|stat_interval|page_cluster|sched_child_runs_first|sched_latency_pct|sched_min_granularity_pct|sched_wakeup_granularity_pct|uclamp_min|uclamp_max|mali_boost_level2|mali_pollingtime|mali_upthreshold`

Nama node disanitasi `[^A-Za-z0-9]`→`_` maks 40 (WAJIB identik dengan
sanitize di aplikasi; contoh `23100000.gpu` → `23100000_gpu`).

| Key | Tipe / rentang | Engine (file) | Sumber nilai valid |
|---|---|---|---|
| `cpu_policy_<id>_gov` | pilihan | `engine/cpu/governor.sh` | `scaling_available_governors` per policy |
| `cpu_policy_<id>_max_khz` / `_min_khz` | kHz 100000-5000000 | `engine/cpu/frequency.sh` | `scaling_available_frequencies` (snap ke OPP terdekat) |
| `cpu_policy_<id>_sched` | pilihan | `engine/cpu/scheduler.sh` | `sched_*_cs_flags` |
| `cpu_policy_<id>_rate_limit_us` | 0-100000 (µs) | `engine/cpu/governor.sh` | node `policy<id>/schedutil/rate_limit_us`; **hanya ada bila governor aktif = `schedutil`** (0 = tanpa rate limit). Batas = batas UI; kernel (`cpufreq_schedutil.c`) hanya `kstrtouint` tanpa clamp |
| `gpu_node_<n>_gov` | pilihan | `engine/gpu/generic.sh` | `available_governors` node |
| `gpu_node_<n>_max_khz` | kHz | `engine/gpu/generic.sh` | OPP node |
| `gpu_node_<n>_polling_interval` | 1-1000 (ms) | `engine/gpu/devfreq_tuning.sh` | ABI devfreq (ms; <1 jiffy = 0 = no polling) |
| `gpu_node_<n>_up_threshold` | 1-100 (%) | `engine/gpu/devfreq_tuning.sh` | ABI devfreq ondemand |
| `gpu_node_<n>_down_differential` | 0-100 (%) | `engine/gpu/devfreq_tuning.sh` | ABI devfreq |
| `io_block_<n>_sched` | pilihan | `engine/io/scheduler.sh` | `queue/scheduler` |
| `io_block_<n>_readahead` | PRESET 128/256/512/1024/2048/4096/8192 (KB) | `engine/io/readahead.sh` | preset (bukan rentang) |
| `io_block_<n>_add_random`, `_iostats` | 0/1 | `engine/io/queue_tuning.sh` | boolean queue |
| `io_block_<n>_nomerges` | 0/1/**2** | `engine/io/queue_tuning.sh` | 0 = semua merge, 1 = simple one-hit saja, 2 = tanpa merge |
| `swappiness` | 0-200 (UI jujur 0-100) | `engine/memory/vm.sh` | `vm/swappiness` |
| `vfs_cache_pressure` | 0-1000 | `engine/memory/vm.sh` | `vm/vfs_cache_pressure` |
| `dirty_ratio` | 1-90 | `engine/memory/vm.sh` | `vm/dirty_ratio` |
| `dirty_background_ratio` | 1-50 | `engine/memory/vm.sh` | WAJIB < `dirty_ratio` (strict) sebelum apply; langgar → `FALLBACK` + alasan dua angka; di manual tanpa tulis |
| `page_cluster` | 0-9 | `engine/memory/vm.sh` | `vm/page-cluster` (nama sysctl ber-hypen → kunci knob underscore) |
| `stat_interval` | 1-60 (detik) | `engine/memory/vm.sh` | `vm/stat_interval` |
| `backlog` | 128-16384 | `engine/network/tcp.sh` | `net/core/netdev_max_backlog` (satu-satunya sysctl backlog per profil) |
| `tcp_cc` | pilihan | `engine/network/tcp.sh` | `tcp_available_congestion_control` |
| `tfo` | 0-3 | `engine/network/tcp.sh` | `tcp_fastopen` |
| `zram_algo` | pilihan | `engine/memory/zram.sh` | `comp_algorithm` node |
| `sched_child_runs_first` | 0/1 | `engine/cpu/governor.sh` | sysctl bool |
| `sched_latency_pct`, `sched_min_granularity_pct`, `sched_wakeup_granularity_pct` | 10-200 (**persen** dari native) | `engine/cpu/scheduler.sh` | persent dari nilai native + lantai keras 500000 ns; node TIDAK ADA di sebagian kernel → UNAVAILABLE |
| `uclamp_min`, `uclamp_max` | 0-1024 | `engine/cpu/scheduler.sh` | cgroup v1 vendor `/dev/cpuctl/foreground/cpu.uclamp.*` (format nilai bisa "0.00"/"max") |
| `mali_boost_level2` | 0/1 | `engine/gpu/mali.sh` | `/sys/module/mali_kbase/parameters/gpu_boost_level2` |
| `mali_pollingtime` | 1-10 | `engine/gpu/mali.sh` | `gpu_pollingtime` |
| `mali_upthreshold` | 10-100 | `engine/gpu/mali.sh` | `gpu_upthreshold` |

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
3. **Semantik manual murni: SUDAH MURNI (M1 + M1b, 2026-09-28)**. Profil
   default = `manual`; apply hanya menulis knob yang punya override user.
   Bukti nyata [SANDBOX] §3.11: 2 override → hanya 2 node berubah
   (`read_ahead_kb 128→2048`, `vfs_cache_pressure 100→250`), 31 knob lain
   `SKIPPED "tidak diatur (mode manual)"`, node lain byte-identik.
   Semua jalur apply menghormati aturan yang sama (cpu/gpu/io/vm/network).
   Override tidak valid → di manual tidak ditulis sama sekali (nilai
   sistem tetap), di profil non-manual jatuh ke nilai profil.

4. **Gate `ALLOW_EXTREME` + boot guard**: `ALLOW_EXTREME` dibaca via
   `config-get` (`allow_extreme`, [SANDBOX] §3.5) dan ditulis via
   `config-set` (whitelist, [KODE] `action.sh:1062`); sesi env
   `ALLOW_EXTREME=true` juga dihormati per-invocation ([KODE]
   `action.sh:38-57`); `apply extreme` tanpa opt-in → rc=1 ([KODE]
   `action.sh:884-887`). **Boot guard SUDAH punya subcommand `guard-status`
   (M2)** — read-only, 5 baris key=value + JSON terakhir, rc=0, node
   hilang/rusak → `active=0` (§3.10). APK TIDAK lagi perlu parse
   `logs boot` mencari marker `BOOT-GUARD AKTIF` (rapuh bila teks berubah).

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

- **D1 (GATE A10) — semantik apply: SUDAH PUTUS (user, 2026-09-28)** →
  opsi (b) mode manual murni, dikerjakan di M1 + M1b. Konsekuensi untuk A10:
  "Terapkan (N)" = N knob dirty; modul tidak menulis apa pun yang tidak
  dirty. Tidak ada lagi ambiguity profil-vs-override.
- **D2 — baca boot guard: SUDAH PUTUS (user) → opsi (a)** → `guard-status`
  diimplementasikan di M2 (§3.10). Konsekuensi untuk A8/A13: banner
  "tuning dilewati" dibaca dari `active=1`, bukan dari parsing `logs boot`.
- **D3 — `capabilities` vs `knobs`**: APK memakai `knobs` sebagai sumber
  pilihan valid (sudah sandboxable); `capabilities` hanya pelengkap
  boolean di HP dan TIDAK bisa disandbox. Dicatat agar A9 tidak
  bergantung pada `capabilities` untuk daftar governor/OPP.
- **D4 — SUDAH PUTUS (user, 2026-09-29)**: `applicationId=com.hsin`,
  minSdk 26 / targetSdk 34 / compileSdk 34, keystore debug sementara
  (signing release ditunda), NOL permission, Compose BOM 2024.10.00
  (selesai di A4).
