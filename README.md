# HSIN — Universal Manual Performance Module (v5.0.0-beta1)

HSIN adalah modul root untuk mengatur performa Android secara **manual**
(pengguna yang pegang kendali penuh lewat profil + knob), dirancang
**defensive by design**: tidak pernah menulis buta ke node yang tidak
ada, tidak pernah bootloop karena tuning, dan selalu degrade dengan
anggun di device yang belum dikenal.

Prinsip arsitektur: **capability-first** — semua keputusan diambil dari
hasil deteksi kapabilitas device saat itu (node writable, governor yang
tersedia, thermal zone), bukan dari nama chipset.

## Requirements

- Android dengan root: Magisk (minimal versi 20400, sesuai `module.prop`)
  atau KernelSU.
- Aplikasi pendamping HSIN (untuk UI), atau akses shell root untuk CLI.

## Quick Start

1. Pasang ZIP modul (`HSIN-v5.0.0-beta1.zip` atau dev build) lewat
   aplikasi root manager, lalu reboot.
2. Tunggu boot selesai — tuning profil default (`balanced`) diterapkan
   otomatis oleh `service.sh`.
3. Cek status:
   - CLI (sebagai root): `hsin status`
   - Log boot: `/data/adb/hsin/logs/boot.log`
4. Ganti profil manual: `hsin apply performance`
   (pilihan: `battery`, `balanced`, `performance`, `extreme`).
5. Fine-tuning per knob (contoh): `hsin knob-set cpu_policy_0_gov performance`
   Daftar knob yang tersedia di device ini: `hsin knobs`.

Profil `extreme` hanya aktif bila `ALLOW_EXTREME=true` ditulis eksplisit
di `/sdcard/Android/hsin/hsin.conf` (default `false`).

## Profiles

| Profil | Cocok untuk |
|---|---|
| `battery` | Hemat daya, limit paling agresif |
| `balanced` | Default harian |
| `performance` | Gaming / beban berat |
| `extreme` | Maksimal, risiko tinggi, butuh opt-in `ALLOW_EXTREME=true` |

Nilai tiap profil ada di `profiles/*.conf`. Pilihan pengguna (knob
override) selalu menang atas nilai profil; thermal guardrail tidak
pernah menaikkan limit di atas pilihan pengguna (hanya menahan).

## Safety Features (defensive by design)

- **Boot guard** (`core/boot_guard.sh`): boot yang gagal dicatat di
  `/data/adb/hsin/.boot_fail_count` (format `timestamp:count`). Gagal
  **2x berturut-turut** → semua tuning dilewati boot itu (modul tidak
  melakukan apa-apa, bukan bootloop). Boot yang sukses mereset counter.
- **Safe apply** (`core/safe_apply.sh`): setiap tulis sysfs dicek
  (node ada → writable → tulis → baca-balik → cocok) dan dikategorikan
  jujur: `APPLIED` / `SKIPPED` (node hilang atau read-only + alasan) /
  `UNAVAILABLE` / `FALLBACK` / `FAILED`. Tanpa verify = tanpa klaim sukses.
- **Thermal guardrail** (`core/thermal_check.sh`): klasifikasi suhu dari
  thermal zone yang **terdeteksi** (`NORMAL` / `HIGH` / `VERY HIGH` /
  `CRITICAL`), threshold dari `trip_point` kernel device itu sendiri
  (bukan angka universal). `HIGH` dan `VERY HIGH` hanya dimonitor —
  intervensi darurat hanya di `CRITICAL`. Tanpa data sensor → `UNKNOWN`
  (tidak memblokir tuning normal, tidak mengarang status aman).
- **Graceful degradation per-engine** (`core/engine_guard.sh`): satu
  engine gagal total (mis. semua node read-only) tidak menghentikan
  engine lain; sukses parsial (`applied > 0`) dihitung sukses; tiap
  skip mencantumkan alasan; laporan akhir merangkum status semua engine.
- **Backup/restore**: snapshot node sebelum apply (`/data/adb/hsin/backup/`);
  uninstall mengembalikan backup terakhir (best-effort).

## Supported Devices

**Tervalidasi di hardware fisik (1 device):**

| Device | Bukti |
|---|---|
| Perangkat developer (Unisoc T615 / GPU Mali) | Pengujian langsung di HP developer |

**Semua device lain: graceful degrade — BELUM divalidasi.**
Modul akan mendeteksi kapabilitas dan melewati (skip + log beralasan)
setiap tuning yang tidak cocok, bukan memaksakan angka. Klaim
"mendukung device X" hanya ditambahkan setelah validasi nyata di
hardware tersebut (lihat `DEVICE_COMPATIBILITY.md` setelah tersedia).

Daftar nama chipset lain sebagai matriks kompatibilitas sengaja TIDAK
dicantumkan — satu nama chipset di ROM/kernel berbeda bisa punya
governor, OPP table, dan thermal zone yang berbeda.

## Log Locations

Semua di `/data/adb/hsin/logs/`:

| File | Isi |
|---|---|
| `boot.log` | Alur boot, status engine, thermal check, guard |
| `apply.log` | Hasil apply manual per engine |
| `error.log` | Error (termasuk engine yang gagal) |
| `rollback.log` | Riwayat rollback/restore |
| `monitor.log` | Monitor berkala |
| `extreme.log` | Override + watchdog mode extreme |
| `debug.log` | Debug umum |

Status ringkas: `/data/adb/hsin/service.state`
(`ready` = semua engine jalan, `degraded` = ada engine yang gagal
tapi service selesai).

## Cara Lihat Status Boot Guard

```sh
# Counter kegagalan (tidak ada file = belum pernah gagal / sudah reset)
su -c 'cat /data/adb/hsin/.boot_fail_count'

# Status service boot terakhir
su -c 'cat /data/adb/hsin/service.state'

# Baris guard di log
su -c 'grep -i "guard" /data/adb/hsin/logs/boot.log'
```

Jika guard aktif (`BOOT-GUARD AKTIF` di log), modul sengaja tidak
menerapkan tuning apa pun boot itu. Untuk pulih: reboot normal yang
sukses akan mereset counter otomatis (atau tunggu cooldown kedaluwarsa).

## Uninstall

1. Hapus modul lewat aplikasi root manager (menjalankan
   `uninstall.sh`: backup terakhir dikembalikan, lalu
   `/data/adb/hsin` dan `/sdcard/Android/hsin` dihapus).
2. Reboot — kernel sudah mereset semua tuning sysfs saat reboot.

## Support

- Sertakan saat melapor: isi `/data/adb/hsin/service.state`,
  potongan relevan `boot.log`/`error.log`, dan file
  `/data/adb/hsin/device.txt` (hasil deteksi capability).
- Jangan mengirim file config berisi data pribadi selain yang diminta.
