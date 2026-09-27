# HSIN Testing Framework

## Sandbox Pattern

Uji tanpa menyentuh `/sys` atau `/proc` asli. Gunakan variabel prefix palsu:

- `SYSFS_CPU_PREFIX` — direktori palsu cpu/cpufreq
- `SYSFS_BLOCK_PREFIX` — direktori palsu block
- `SYSFS_GPU_PREFIX` — direktori palsu gpu/devfreq
- `SYSFS_DEVFREQ_PREFIX` — alternatif devfreq
- `GPU_SYSFS_PREFIX` — alternatif GPU
- `SYSFS_THERMAL_PREFIX` — thermal palsu
- `SYSFS_MODULE_PREFIX` — module palsu
- `SYSFS_PROC_PREFIX` — /proc palsu (default `/proc` bila kosong)

Contoh minimal Unisoc T615:
```bash
F=$(mktemp -d)
mkdir -p "$F/cpu/cpufreq/policy0"
echo "1800000" > "$F/cpu/cpufreq/policy0/scaling_max_freq"
mkdir -p "$F/class/devfreq/"
echo "500" > "$F/class/devfreq/dummy/max_freq"
mkdir -p "$F/class/thermal/thermal_zone0"
echo "42000" > "$F/class/thermal/thermal_zone0/temp"
export SYSFS_CPU_PREFIX="$F"
export SYSFS_THERMAL_PREFIX="$F"
export HSIN_SANDBOX=1
```

Uji via `HSIN_SANDBOX=1`. Skrip modul akan membaca prefix palsu, bukan node asli.

## Environment Variables

- `HSIN_SANDBOX=1` — aktifkan mode sandbox
- `SYSFS_*_PREFIX` — arahkan baca sysfs ke direktori palsu
- `HSIN_CONF` — file konfigurasi (default `/sdcard/Android/hsin/hsin.conf`)
- `ALLOW_EXTREME` — opt-in session-level untuk extreme
- `HSIN_MODULE_PATH` — path modul (default `/data/adb/modules/hsin`)
- `HSIN_DATA` — data path (default `/data/adb/hsin`)

## Actions and Expected Results

| Action | Args | Exit | Output / JSON |
|---|---|---|---|
| `status` | — | 0 | Status teks + info thermal/CPU/GPU |
| `device` | — | 0 | JSON: soc, gpu, kernel, ram_kb, device_id |
| `capabilities` | — | 0 | JSON: cpu_tuning, gpu_devfreq, thermal_node, fpsgo, kgsl, sched_lat |
| `knobs` | — | 0 | JSON daftar knob |
| `knob-set` | `<key>` `<val>` | 0 | `OK key=val` |
| `knob-reset` | — | 0 | `OK reset (N key)` |
| `knob-list` | — | 0 | Daftar knob tersimpan |
| `config-set` | `<key>` `<val>` | 0 | OK (persist ke HSIN_CONF) |
| `config-get` | — | 0 | Key-value dari HSIN_CONF |
| `apply` | `<profile>` | 0 | Apply profile (manual) |
| `backup` | — | 0 | Backup state saat ini |
| `rollback` | — | 0 | Rollback ke backup |
| `logs` | — | 0 | Tampilkan log |

Ekspektasi JSON: `python3 -m json.tool` lolos; semua field wajib ada bila aksi menghasilkan JSON.

## APPLY-TIME Reading

`APPLY-TIME` dicatat saat `action.sh apply <profile>` atau `service.sh` memuat profile saat boot. Baca dari:

- `/data/adb/hsin/logs/apply_time.log` (jika tersedia)
- Atau cek output `action.sh apply` yang menampilkan `Profile aktif:` dan waktu eksekusi (`date`).

Untuk verifikasi: jalankan `date +%s` sebelum dan sesudah apply; catat selisih sebagai durasi apply.
