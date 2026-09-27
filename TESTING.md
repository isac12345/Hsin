# TESTING.md — Prosedur QA HSIN (Phase 4, PQ Step 14)

Alur wajib: **baseline → install → functional → stability → cleanup**.
Setiap tahap punya gate: gagal di satu tahap = berhenti, perbaiki,
ulangi dari tahap itu (jangan loncat ke stability kalau functional
belum hijau).

Dua lapis verifikasi, peran berbeda:

- **Sandbox (Termux/CI):** logika benar tanpa hardware.
  `sh tests/sandbox_boot_guard.sh`, `sh tests/sandbox_safe_apply.sh`,
  `sh tests/thermal_sandbox/run.sh`, `sh tests/sandbox_degrade.sh`,
  `sh tests/sandbox_overrides.sh`, `sh tests/sandbox_service_guard.sh`,
  `sh tests/validate_build.sh` — semua harus exit 0.
- **L2 HP fisik:** perilaku nyata (sensor, reboot, timing). Sandbox
  hijau TIDAK BOLEH diklaim sebagai "tervalidasi di device".

Pola sandbox umum (detail di `tests/TESTING_FRAMEWORK.md`):
`HSIN_SANDBOX=1` + prefix palsu (`SYSFS_CPU_PREFIX`,
`SYSFS_THERMAL_PREFIX`, …) + `HSIN_DATA` terpisah.

## 1. Baseline (sebelum pasang modul)

Tujuan: tahu kondisi stock, supaya efek modul bisa dibandingkan jujur.

1. Catat: model HP, versi Android, kernel (`uname -r`), root
   (Magisk/KernelSU + versi).
2. Simpan `device.txt` acuan: `su -c 'cat /data/adb/hsin/device.txt'`
   (belum ada — catat manual dari `hsin detect` bila CLI tersedia,
   atau `getprop` + baca node langsung).
3. Catat suhu idle + governor aktif CPU dan `scaling_max_freq`
   tiap policy (baca langsung node `/sys`, tanpa modul).
4. Catat waktu boot stock (dari tekan reboot sampai launcher siap,
   stopwatch — kasar tapi jujur).

## 2. Install

1. Flash ZIP lewat aplikasi root manager, reboot.
2. Verifikasi modul termuat: direktori `/data/adb/modules/hsin` ada.
3. Verifikasi service selesai: `su -c 'cat /data/adb/hsin/service.state'`
   → `ready` (atau `degraded` + alasan di `error.log` — tetap lanjut,
   catat sebagai temuan).
4. Verifikasi tidak ada bootloop: HP mencapai launcher ≤ 2 menit
   (bandingkan dengan baseline).

## 3. Functional (wajib mencakup fitur yang dibangun)

Bukan cuma "modul jalan atau tidak" — tiap fitur diuji satu per satu.

### 3a. Boot guard nonaktif (kondisi normal)

- `su -c 'cat /data/adb/hsin/.boot_fail_count'` → file tidak ada
  (atau count 0) = tidak ada kegagalan tercatat.
- `su -c 'grep -i "guard" /data/adb/hsin/logs/boot.log'` → tidak ada
  baris `BOOT-GUARD AKTIF`.
- Tuning profil default diterapkan (cek satu node, mis. readahead
  atau governor, berubah dari baseline).

### 3b. Boot guard AKTIF (simulasi gagal, tetap di HP fisik)

Cara aman tanpa merusak boot: naikkan counter manual LALU reboot
(karena threshold 2 = butuh 2 gagal berturut-turut):

1. `su -c 'echo "$(date +%s):2" > /data/adb/hsin/.boot_fail_count'`
2. Reboot.
3. Verifikasi: `boot.log` ada baris `BOOT-GUARD AKTIF`, SEMUA tuning
   dilewati, HP tetap sampai launcher (modul tidak melakukan apa-apa).
4. Pulihkan: hapus file counter ATAU reboot sukses 1x
   (reset-on-success), verifikasi tuning jalan lagi.

### 3c. Safe apply — 5 kategori muncul di log

- `su -c 'grep -E "APPLIED|SKIPPED|FALLBACK|UNAVAILABLE|FAILED" /data/adb/hsin/logs/boot.log'`
- Wajib ada minimal 1 baris `APPLIED` (bukti tulis+verify jalan).
- Tiap `SKIPPED` wajib punya alasan (`node missing` / `read-only`).
- Klaim sukses tanpa baris `APPLIED` = temuan (indikasi tulis buta).

### 3d. Thermal 4 state

- `su -c 'grep "thermal_check" /data/adb/hsin/logs/boot.log'` →
  satu dari `NORMAL` / `HIGH` / `VERY HIGH` / `CRITICAL` / `UNKNOWN`
  + `basis=trip_point:…` (atau `fallback`, catat mana yang dipakai).
- `HIGH` / `VERY HIGH`: verifikasi TIDAK ada perubahan tuning karena
  thermal (bandingkan node sebelum/sesudah jeda beban).
- `CRITICAL` (hanya bila tercapai alami — JANGAN dipaksa dengan
  pemanas buatan): verifikasi intervensi via safe_apply terlog +
  beralasan, dan limit tidak pernah naik di atas profil.

### 3e. Graceful degradation per-engine

- `su -c 'grep "\[engine\]" /data/adb/hsin/logs/boot.log'` (baris
  `SUMMARY`) → tiap engine tercatat `applied=X,failed=Y,skipped=Z,rc=R`.
- `service.state` = `degraded` + semua engine tercatat = PASS parsial
  (bukan gagal total).
- Engine yang `rc=1` wajib punya warning `lanjut engine berikut`
  dan engine sesudahnya tetap tercatat di summary.

### 3f. Profil + knob manual

- `hsin apply battery|balanced|performance` tiap profil → node
  berubah sesuai, `APPLY-TIME` tercatat di `debug.log`
  (`grep APPLY-TIME /data/adb/hsin/logs/debug.log`).
- `hsin knobs` valid JSON; `knob-set` satu key → node berubah;
  `knob-reset` → kembali ke profil.

## 4. Stability — reboot berulang minimal 3x (HP fisik)

Sandbox TIDAK BISA menggantikan tahap ini: boot guard hanya terbukti
di hardware nyata.

1. Reboot 1: catat `service.state` + ada/tidaknya `BOOT-GUARD AKTIF`
   + waktu sampai launcher.
2. Reboot 2 dan 3: ulangi yang sama.
3. Gate: 3/3 boot mencapai launcher; `service.state` konsisten
   (`ready`, atau `degraded` yang SAMA dengan alasan yang sama —
   degradasi baru di boot ke-2/3 = temuan).
4. Suhu: sentuh punggung HP tiap boot + catat `thermal_check` state
   (panas abnormal vs baseline = temuan).
5. Minimal 1 siklus: biarkan HP idle 30 menit pasca-boot ke-3,
   pastikan tidak ada reboot sendiri (tanda bootloop tertunda).

## 5. Cleanup

1. Hapus modul via aplikasi root manager (uninstall
   mengembalikan backup terakhir + menghapus `/data/adb/hsin` dan
   `/sdcard/Android/hsin`).
2. Reboot, verifikasi: direktori data hilang, node kembali ke stock
   (bandingkan dengan catatan baseline tahap 1).
3. Sisa file = temuan (laporkan path-nya).

## Report Template (berbasis capability, BUKAN nama chipset)

Form yang sama untuk semua device — pengisi tidak perlu tahu nama
chipset. Identitas device cukup sebaris; sisanya capability terdeteksi
+ hasil. (Lembar identitas per-device yang lama tetap ada di
`tests/TEMPLATE_DEVICE_REPORT.md` dan boleh dilampirkan.)

```text
HSIN TEST REPORT
Tanggal   : __________
Tester    : __________
Device    : __________ (model + root: Magisk/KSU + versi)
HSIN      : __________ (version dari module.prop) + ZIP: dev/release
Device ID : __________ (dari `hsin device`, bila ada)

CAPABILITY TERDETEKSI (dari device.txt / knobs):
- CPU policies          : __ (contoh: 2)   governors tersedia: __________
- GPU devfreq writable  : ya/tidak   node: __________
- Thermal zones         : __   trip basis: trip_point Caen / fallback
- Block devices         : __________
- Signature override    : cocok (entry ___) / default fallback

SANDBOX (Termux/CI):
- sandbox_boot_guard    : PASS / FAIL
- sandbox_safe_apply    : PASS / FAIL
- thermal_sandbox       : PASS / FAIL (__/6)
- sandbox_degrade       : PASS / FAIL (__/8)
- validate_build        : PASS / FAIL

L2 HP (tulis hasil, bukan klaim):
| Tahap                  | Hasil (PASS/FAIL/SKIP) | Bukti (baris log / nilai node) |
|------------------------|------------------------|--------------------------------|
| baseline tercatat      |                        |                                |
| install + service.state|                        |  ready / degraded: ___         |
| guard nonaktif         |                        |                                |
| guard AKTIF (simulasi) |                        |  BOOT-GUARD AKTIF: ya/tidak   |
| safe apply APPLIED     |                        |  jumlah APPLIED: ___           |
| skip beralasan         |                        |                                |
| thermal state          |                        |  state: ___ basis: ___         |
| engine summary lengkap |                        |                                |
| profil manual 3x       |                        |  APPLY-TIME: ___               |
| knob-set/reset         |                        |                                |
| reboot 1/2/3 stabil    |                        |  state: ___/___/___            |
| cleanup bersih         |                        |                                |

Temuan (wajib diisi, "-" bila nihil):
1. _______________________________________________
```

Aturan jujur (dari `ROADMAP_10_10.md`, berlaku semua laporan):

- **TERVALIDASI** = L2 HP nyata (boot log + apply log + APPLY-TIME +
  tes rasa). Saat ini: 1 device milik developer.
- **GRACEFUL DEGRADE** = sandbox capability-hilang PASS + fallback
  default terlog. Semua device lain.
- **DILARANG**: matriks nama-chipset sebagai janji support, dan klaim
  "tested" tanpa baris bukti di kolom Bukti.
