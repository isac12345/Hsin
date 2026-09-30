# API.md — Panduan Modder (Phase 4, PQ Step 17)

Untuk modder teknis: cara menambah signature entry, memperluas
deteksi, dan menambah tweak — dengan nama fungsi + env var asli dari
repo ini. Semua contoh mengikuti pola yang sudah ada; contoh yang
tidak match fungsi asli = bug dokumentasi, laporkan.

Konvensi umum semua skrip: guard di awal
`[ -z "$HSIN_MODULE_PATH" ] && HSIN_MODULE_PATH="/data/adb/modules/hsin"`,
source dengan `2>/dev/null || true`, akhir file library
`return 0 2>/dev/null || true`. Panggil fungsi LANGSUNG, jangan dalam
`$( )` (subshell menghilangkan assignment global — pelajaran fix #7).

## Env var yang dipakai lintas file

| Var | Arti | Default |
|---|---|---|
| `HSIN_MODULE_PATH` | Root modul terinstal | `/data/adb/modules/hsin` |
| `HSIN_DATA` | Data persistent | `/data/adb/hsin` |
| `HSIN_PROFILE` | Profil aktif (`battery`/`balanced`/`performance`/`extreme`) | `balanced` |
| `HSIN_SYSFS_THERMAL` / `SYSFS_THERMAL_PREFIX` | Override baca thermal (sandbox) | `/sys/class/thermal` |
| `HSIN_SYSFS_CPU` / `SYSFS_CPU_PREFIX` | Override baca CPU (sandbox) | `/sys/devices/system/cpu` |
| `HSIN_SANDBOX`=`1` | Matikan efek samping device (`cmd`, `su`) di uji | unset |
| `HSIN_CONF` | Config user | `/sdcard/Android/hsin/hsin.conf` |
| `ALLOW_EXTREME` / `HSIN_ALLOW_EXTREME` | Opt-in profil extreme | `false` |

## 1. Tambah tweak (pola safe_apply — WAJIB)

JANGAN `echo "$val" > "$node` langsung. Setiap tulis sysfs lewat
gateway `core/safe_apply.sh` (butuh `core/sysfs.sh` di-source dulu
untuk `hsin_node_write_verify`):

```sh
[ -z "$HSIN_MODULE_PATH" ] && HSIN_MODULE_PATH="/data/adb/modules/hsin"
# shellcheck disable=SC1091
. "$HSIN_MODULE_PATH/core/sysfs.sh" 2>/dev/null || true
# shellcheck disable=SC1091
. "$HSIN_MODULE_PATH/core/safe_apply.sh" 2>/dev/null || true
. "$HSIN_MODULE_PATH/core/logger.sh" 2>/dev/null || true

# hsin_safe_apply <node> <value> [kategori]
# rc: 0 APPLIED / 2 SKIPPED (hilang|read-only+alasan) /
#     3 UNAVAILABLE / 4 FALLBACK / 1 FAILED
hsin_safe_apply "$_node" "$_value" "MYTWEAK"
case "$?" in
    0) _ok=$((_ok + 1)) ;;
    *) _skip=$((_skip + 1)) ;;
esac
```

Pola lengkap (diambil dari `engine/io/readahead.sh`,
`hsin_io_apply_readahead`): pilih nilai per profil via `case
"$_profile"`, daftar node dari helper detect, node hilang sejak
scan → `hsin_report_skip "alasan jelas"` + `continue` (bukan crash),
akhiri dengan `hsin_log_info "<engine>" "… ok=$_ok skip=$_skip"` dan
`return 0`.

Bila nilai harus dari daftar yang didukung node (governor, scheduler,
algo zram): pakai `hsin_safe_apply_validated <node> <requested>
"<allowed…>" [kategori]` — requested tak ada di allowed + allowed
kosong → `UNAVAILABLE` (rc 3); ada alternatif → tulis alternatif
pertama → `FALLBACK` (rc 4). Daftar allowed dibaca dari node
(`scaling_available_governors`, `comp_algorithm`, …), bukan
dihardcode. Helper baca: `hsin_node_read <node>`; helper OPP:
`hsin_opp_min` / `hsin_opp_max` / `hsin_opp_cap_pick` /
`hsin_opp_floor_pick` (semua di `core/sysfs.sh`).

Entry point engine dipanggil `service.sh` section 7 via wrapper
`hsin_engine_run "<Nama>" <fungsi_apply> "$HSIN_PROFILE"` — fungsi
tweak baru didaftarkan dengan pola yang sama agar dapat isolasi
gagal + summary per-engine gratis (`core/engine_guard.sh`).

## 2. Tambah signature entry (capability-based — TIDAK AKTIF)

> **STATUS 2026-09-30: fitur ini TIDAK AKTIF.** `hsin_override_load` =
> 0 pemanggil di seluruh runtime, dan `capability/*.json` tidak ikut
> ter-bundle ke ZIP (folder `capability/` dibuang saat build). Entrinya
> tidak memengaruhi tuning apa pun. Tuning device ini berasal dari
> `user_knobs.env` (mode manual, lewat `knob-set`) + capability `knobs`.
> Loader tidak diubah dan tidak dipanggil; isi file hanya dokumentasi
> untuk modder. Kalau nanti diaktifkan, harus Decision terpisah
> (aktifkan pemanggil + bundel JSON + uji), bukan disisipkan diam-diam.

File: `capability/capability_overrides.json`, array `signatures`
(match pertama menang) + `default_fallback`. Loader:
`hsin_override_load` (`core/load_overrides.sh`) → export
`HSIN_OV_MATCHED` (1/0), `HSIN_OV_SOURCE`
(`signature:<nama>`/`default_fallback`), dan hints
(`HSIN_OV_CPU_GOV_PREF`, `HSIN_OV_GPU_PCT_BALANCED`, …,
`HSIN_OV_THERMAL_CLASS`).

Parser loader HANYA membaca 4 kunci `match` ini (lainnya diabaikan):

- `cpu_policy_count_min` (angka), `governor_list_contains` (string),
  `devfreq_writable` (true/false, cek `[ -w ]` live),
  `thermal_zone_count_min` (angka).

Contoh entry valid (struktur sama seperti `managed-performance`):

```json
{
  "name": "contoh-deskriptif",
  "description": "Syarat capability dalam bahasa manusia.",
  "match": {
    "cpu_policy_count_min": 4,
    "governor_list_contains": "schedutil",
    "devfreq_writable": false,
    "thermal_zone_count_min": 2
  },
  "profile_hints": {
    "cpu_gov_preference": ["schedutil", "powersave"],
    "thermal_class": "managed"
  }
}
```

DILARANG: keyed by nama chipset/vendor (`"snapdragon_…"`,
`"unisoc_…"` tidak dibaca loader — entry seperti itu mati dan akan
direvert, pelajaran Step 5 lama). Validasi JSON:
`python3 -m json.tool capability/capability_overrides.json`.

## 3. Extend detection

Fungsi detect ada di `core/detector.sh`: `detect_soc`,
`detect_gpu_vendor`, `detect_cpu_clusters`, `detect_core_online`,
`detect_governor_list`, `detect_ram`, `detect_zram`,
`detect_thermal_zones` (+ varian vendor di bawahnya). Hasil ditulis
ke `$HSIN_DATA/detected.conf` (`THERMAL`, `THERMAL_W`,
`THERMAL_PATH`, `GOVS`, …) dan `device.txt`.

Aturan extend:

1. Baca sysfs HANYA lewat var prefix (`HSIN_SYSFS_THERMAL`,
   `HSIN_SYSFS_CPU`, …) agar bisa di-sandbox — literal `/sys`
   / `/proc` baru = temuan (lihat pelajaran audit `/proc` → `$HSIN_PROC`).
2. Node hilang = skip + log, bukan crash, bukan nilai karangan.
3. Output capability (count/daftar/writable), BUKAN nama marketing —
   loader signature hanya makan capability.
4. WAJIB dites di sandbox dulu: `sh tests/sandbox_overrides.sh`
   untuk signature baru (match → dipakai, asing → fallback + log,
   data cacat → aman), plus sandbox area yang disentuh. Sandbox
   hijau ≠ validasi HP (lihat `TESTING.md` tahap L2).

## Safety Warning for Modders

- **Jangan menaikkan limit di atas profil/cap user.** Aturan
  `core/thermal_check.sh`: thermal hanya boleh MENAHAN (turunkan
  `scaling_max_freq` saat `CRITICAL`), tidak pernah menaikkan —
  menaikkan = membatalkan cap profil/override user (pelajaran bug
  `policy.sh`). Tweak pendingin/throttle yang menaikkan max saat
  "adem" = bug, bukan fitur.
- **Jangan bypass `core/boot_guard.sh`.** Alur `service.sh` section 1
  (tunggu `sys.boot_completed` ≤120 dtk → gagal = catat + skip semua)
  dan reset `on_boot_ok` di akhir adalah rantai anti-bootloop.
  Mod yang mematikan guard = modul berisiko brick-boot; bila guard
  mengganggu eksperimen, naikkan `HSIN_GUARD_THRESHOLD` di env uji,
  jangan hapus pemanggilannya.
- **Jangan tulis sysfs di luar `safe_apply`.** Tulis tanpa
  write+read-back+verify = klaim sukses palsu (pelajaran bug
  `dvfs.sh` "OK applied" padahal nilai tetap).
- **Jangan tambah file ke ZIP tanpa daftar runtime.** Setiap
  `core/*.sh` baru WAJIB masuk daftar bundle `build_release.sh`
  (pelajaran bug `thermal_check.sh` hilang dari rilis: source
  di-rewrite jadi `runtime.sh`, fitur mati diam-diam).
