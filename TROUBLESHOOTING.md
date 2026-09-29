# TROUBLESHOOTING.md — Masalah Umum + Langkah Debug (Phase 4, PQ Step 15)

Setiap item memakai perintah/log yang benar-benar ada di kode — semua
bisa dicek sendiri sebagai root. Pola umum: `su -c '<perintah>'`.
Log utama: `/data/adb/hsin/logs/boot.log` (boot + engine),
`/data/adb/hsin/logs/error.log` (error),
`/data/adb/hsin/logs/rollback.log` (restore),
`/data/adb/hsin/logs/debug.log` (APPLY-TIME).

## 1. Boot lambat (slow boot)

**Gejala:** launcher lama muncul setelah pasang modul.

**Debug:**

1. `su -c 'grep APPLY-TIME /data/adb/hsin/logs/debug.log'` — tiap fase
   apply tercatat durasinya (`total …ms`); fase paling lama = tersangka
   (biasanya scan thermal zone atau snapshot backup pertama).
2. `service.sh` menunggu `sys.boot_completed` maksimal 120 detik
   (`HSIN_BOOT_WAIT_TIMEOUT`, default 120). Timeout = boot DINYATAKAN
   gagal → guard mencatat 1 kegagalan → tuning dilewati boot itu.
   Cek: `su -c 'grep -i "boot_completed timeout" /data/adb/hsin/logs/boot.log'`
3. Boot pertama setelah flash selalu paling lambat (scan cache +
   backup awal ditulis sekali). Bandingkan boot ke-2/ke-3 sebelum
   menyimpulkan modul yang memperlambat.

## 2. Guard aktif (tuning dilewati semua)

**Gejala:** HP nyala normal tapi tuning tidak diterapkan sama sekali.

**Cek status:**

```sh
su -c 'cat /data/adb/hsin/.boot_fail_count'
# Cara langsung (M2): subcommand read-only, rc selalu 0
su -c 'sh /data/adb/modules/hsin/action.sh guard-status'
# atau lewat log (untuk melihat alasan per kegagalan)
su -c 'grep "BOOT-GUARD AKTIF" /data/adb/hsin/logs/boot.log'
```

File counter berformat `timestamp:count`. Count ≥ 2 (threshold default
`HSIN_GUARD_THRESHOLD=2`) = guard aktif.

**Baca kenapa aktif** (dari `core/boot_guard.sh`, format log asli):

- `BOOT-GUARD AKTIF: boot gagal Nx berturut-turut (threshold 2) —
  semua tuning DILEWATI, modul tidak melakukan apapun`
- Baris sebelumnya selalu ada alasan per kegagalan:
  `boot gagal Nx (sys.boot_completed timeout 120s)` atau alasan lain
  — itu akar masalahnya (bukan guard-nya; guard hanya gejala).

**Reset manual** (kalau yakin masalah sudah beres — mis. timeout sesaat
karena update sistem, bukan modul):

```sh
su -c 'rm -f /data/adb/hsin/.boot_fail_count'
```

Lalu reboot 1x dan verifikasi tuning jalan lagi. Alternatif tanpa
hapus file: reboot sukses 1x mereset counter otomatis
(reset-on-success), atau tunggu state kedaluwarsa sendiri (cooldown
default `HSIN_GUARD_COOLDOWN=86400` detik = 24 jam, lalu counter
dianggap basi dan direset).

JANGAN reset berkali-kali tanpa membaca alasan kegagalannya — guard
yang aktif terus-menerus artinya ada masalah boot nyata.

## 3. Thermal unmanaged (UNKNOWN, bukan error fatal)

**Gejala:** log ada baris seperti:

```text
[thermal_check] UNKNOWN (no thermal data; zones=0)
```

**Artinya:** data sensor thermal tidak terbaca (node hilang di device
ini). Ini **bukan error fatal dan bukan bug**: state `UNKNOWN`
sengaja berarti "tidak ada guardrail tambahan, tapi tuning normal
tetap jalan" — modul tidak memblokir apa-apa dan tidak mengarang
status aman (`NORMAL` palsu).

**Bedanya dengan CRITICAL** (yang benar-benar trigger intervensi):

```text
[thermal_check] CRITICAL max=97000mC zones=1 basis=trip_point:95000 — emergency thermal intervention allowed
[thermal_check] CRITICAL intervention via safe_apply: node=…/scaling_max_freq value=… reason=max=…; safety priority over tuning
```

`CRITICAL` = suhu melewati basis trip_point device → satu parameter
(`scaling_max_freq` → minimum) diturunkan via `safe_apply`, dengan
alasan lengkap di log. `HIGH` / `VERY HIGH` = hanya monitor, tidak
mengubah apa-apa. Jadi urutannya: `UNKNOWN` (tidak tahu, tidak
bertindak) < `HIGH`/`VERY HIGH` (tahu, memantau) < `CRITICAL`
(bertindak, tercatat).

**Debug:** `su -c 'grep "thermal_check" /data/adb/hsin/logs/boot.log'`
— lihat `basis=`-nya: `trip_point:<angka>` (dari kernel device) atau
`fallback:95000` (tanpa data trip). `zones=0` + `UNKNOWN` di device
tanpa sensor = perilaku yang benar, laporkan sebagai temuan
graceful-degrade (lihat TESTING.md), bukan sebagai crash.

## 4. GPU skip (graceful degradation yang disengaja, bukan bug)

**Gejala:** log GPU penuh `SKIP`, tidak ada `APPLIED` untuk GPU.

**Artinya:** capability GPU device tidak cocok signature mana pun di
`capability/capability_overrides.json`, sehingga dipakai
`default_fallback` yang aman. Baris buktinya (dari
`core/load_overrides.sh`):

```text
no signature match, using default fallback (cpu_policies=… govs='…' devfreq_writable=… thermal=…)
```

Tiap skip GPU juga beralasan di level node (dari `safe_apply`):
`SKIPPED … (node missing)` atau `(read-only)`. Cek:

```sh
su -c 'grep -i "gpu" /data/adb/hsin/logs/boot.log | grep -i "skip"'
su -c 'grep "no signature match" /data/adb/hsin/logs/boot.log'
```

Ini **bukan bug yang perlu difix di device tersebut** — modul sengaja
tidak memaksakan angka GPU yang belum tervalidasi. Yang benar:
laporkan capability device (lihat template di TESTING.md) agar bisa
jadi entry tervalidasi di masa depan, bukan memaksa nilai manual ke
node yang tidak cocok.

## 5. Rollback / kembalikan keadaan semula

**Kapan:** tuning terasa salah, atau sebelum uninstall untuk memastikan
node kembali stock.

**Langkah:**

1. Manual: `hsin restore` (atau `hsin backup` dulu sebelum
   eksperimen knob, untuk titik pulih yang segar).
2. Verifikasi: `su -c 'cat /data/adb/hsin/logs/rollback.log'` —
   tiap node yang dikembalikan tercatat (`ROLLBACK`).
3. Uninstall total via aplikasi root manager (menjalankan
   `uninstall.sh`): backup terakhir dikembalikan (best-effort),
   lalu `/data/adb/hsin` dan `/sdcard/Android/hsin` dihapus.
   Reboot — kernel mereset tuning sysfs yang tersisa.
4. Verifikasi pasca-uninstall: direktori data hilang + 1-2 node
   (mis. governor) kembali seperti catatan baseline TESTING.md.

## 6. Engine tercatat gagal di summary tapi service selesai

**Gejala:** `service.state` = `degraded`, atau summary seperti:

```text
[engine] GPU:applied=0,failed=0,skipped=2,rc=1
```

**Artinya:** kontrak graceful degradation bekerja — engine itu gagal
total tapi engine lain tetap jalan dan service selesai (bukan abort).
Lihat `failed=` vs `skipped=`: `skipped` = node tidak cocok (normal di
device lain), `failed` = tulis ditolak kernel (perlu perhatian).

**Debug:** `su -c 'grep "WARN.*lanjut engine berikut" /data/adb/hsin/logs/boot.log'`
dan `su -c 'cat /data/adb/hsin/logs/error.log'` untuk baris error
per engine.

Untuk pertanyaan "knob saya diminta X, diterapkan Y, kenapa" — jangan
ubek `boot.log` dulu: `hsin knob-list` merangkumnya per knob
(`requested` → `applied` + kategori + alasan, dari
`/data/adb/hsin/knob_results.env` siklus apply terakhir). Detail
per tulis node tetap di `boot.log` (kategori safe_apply).
