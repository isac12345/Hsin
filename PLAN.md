# PLAN.md — HSIN manual (modul dulu, app)

## RENCANA BUAT USER (baca ini aja, bahasa simpel)
- Target: HSIN manual/bebas setting, apply CEPAT (dulu >15 dtk), scan
  SEKALI-simpan. Sekarang semua tweak/setting pindah ke APLICASI (webui
  sudah dihapus).
- Status: modul sudah dibetulkan TOTAL di sisi kode (14 temuan audit +
  3 bug bonus review), semua L1. Aplikasi sudah ada skeletonnya (3 tab).
  BELUM ada yang dijalankan di HP dan BELUM ada yang dikompilasi.
- Yang jalan otomatis (ga perlu kamu): perbaikan kode modul + app,
  kecil per commit, diverifikasi statis dulu (L1).
- TUGAS KAMU (urutan):
  1. [x] SELESAI (2026-09-26): `date +%s%3N` → 13 digit, marker ms
     DIPERCAYA. HP Android 14, T615.
  2. [x] SELESAI (2026-09-27): BUILD ZIP modul + APK lewat GitHub Actions
     berhasil (APK run #36296279179, Modul run #36296491773).
  3. [ ] L2: flash zip, apply manual 1x, kirim baris `APPLY-TIME` dari
     `/data/adb/hsin/logs/debug.log` (bukti cepat/lambat, bukan rasa).
  4. [ ] L2.app: pasang APK, cek tiap tweak bisa dipilih + Apply berhasil.
  5. [ ] PALING AKHIR: tes rasa (game adem/kenceng) = L2, bilang OK.

## Tahap 0 — Inventarisasi + basis rakit (SELESAI)
- [x] Repo GitHub isac12345/Hsin (private) + proyek lokal ~/Hsin.
- [x] Audit 6 varian: v4.2.5-consolidated & v4.2.6-fixed TERKONTAMINASI
  9Router, v4.2.7 bersih tapi Extreme no-op, v4_0 metadata salah.
- [x] Basis = hsin-dev v5.0.0-beta1 (c6e6957, 110 file, tanpa build/).

## Tahap 1 — Fix isi modul (KODE SELESAI, nunggu L2)
- [x] Audit timing apply: biang = scan ulang tiap apply (>15 dtk).
- [x] Cache scan `core/scan_cache.sh` (scan sekali, dipakai semua engine).
- [x] Backup/safety/IO/CPU/GPU/mem/IO/DVFS ke cache-first.
- [x] 14 temuan audit per tweak SELESAI (thermal-status, sched-log,
  dead-code, generic-msg, OOM proteksi, zram, dvfs-verify, oom-verify,
  zram-readback, precheck, kosmetik, /proc→HSIN_PROC 95→0).
- [x] 3 bug bonus dari review: cache kosong tidak lagi dianggap sah
  (dulu thermal+CPU safety bisa buta), scan_cache ikut runtime release
  (dulu cache-scan mati di ZIP release), refresh_hz baca `=`.
- [x] Kontrak untuk app: `action.sh knobs` (JSON inventaris semua tweak +
  nilai yang benar-benar ada di device).
- [x] Jalur tulis pilihan user: `knob-set` / `knob-reset` / `knob-list`
  (override tervalidasi di $HSIN_DATA/user_knobs.env).
- [ ] **Integrasi override ke jalur apply** (pilihan user benar-benar dipakai
  saat apply) — SEDANG DIKERJAKAN, butuh L2 karena mengubah perilaku.
- [x] Guard idempotent runtime P1 (source-ulang 456KB jadi no-op) + luruskan
  komentar integrity 2d — L1 DONE (b5cbf73, bbf27ee), nunggu L2.
- [ ] Audit blank P2f: error app terbukti tampil pesan (statis) → tersisa
  sisi shell/HP, pemisah = Task 2a manual oleh user (lihat NOTES).
- [ ] Bump versi: `module.prop` + `bin/hsin HSIN_VERSION` (wajib sebelum build).
- [ ] L2: flash + reboot (berat?) + `su -c 'sh .../action.sh status/knobs'`
  (blank?) + kirim APPLY-TIME.

## Tahap 2 — Rakit final modul (menunggu perintah build)
- [ ] Bump versi ke vCode baru + cek semua lokasi versi.
- [x] Build/zip HANYA lewat GitHub Actions (`.github/workflows/build-modul.yml`,
      manual). BERHASIL (run #36296491773, artifact `hsin-modul-dev`).
- [x] Verifikasi isi ZIP: `core/runtime.sh` punya cache-scan + override
      (otomatis dicek di workflow, lulus).

## Tahap 3 — Aplikasi (jalan, belum terverifikasi compile)
- Keputusan user: (a) Gradle+Kotlin sendiri, (b) webui DIHAPUS, (c) paket com.hsin.
- [x] Webroot dihapus; notif_icon → `assets/`; logo/banner/bg → `branding/`.
- [x] `app/`: Gradle 8.7 + Kotlin 2.0 + AGP 8.6, Material 3, ViewBinding,
      kotlinx.serialization, minSdk 26 / target 34.
- [x] `RootExec`: `su -c` + stdout capture + timeout 20s + quoting POSIX.
- [x] `HsinRepository`: knobs/status/device/knob-set/config-set/apply/logs/
      backup/rollback; ambil baris JSON terakhir.
- [x] 3 tab: Status (live + device), Knobs (dinamis dari `knobs`), Logs.
- [x] Apply: knob-set* + config-set* → satu `apply <profil>`.
- [x] Perbaikan scaffold yang tidak akan kompilasi: adapter baris datar,
      signature ArrayAdapter, import decodeFromString, akses private,
      manifest, layout, 0 TODO/placeholder, wrapper Gradle palsu dihapus.
- [x] **Compile verification** — lolos via CI (`.github/workflows/build-apk.yml`,
      run #36296279179, artifact `hsin-debug-apk`). 0 error compile.
- [ ] Extreme opt-in sudah ada sebagai switch ALLOW_EXTREME; perlu dipastikan
      apply extreme memakai profil extreme (bukan balanced).
- [ ] Game list (add/remove) — belum ada UI.
- [ ] Backup/Rollback button — method sudah ada, UI belum.
- [ ] Polish: mode gelap (values-night), ikon adaptive, animasi, ringkasan
      draft sebelum Apply.

## Aturan
- **Build hanya lewat GitHub Actions** (perintah user 2026-09-27). Termux
  tidak punya JDK/Android SDK → Termux = tulis source + verifikasi statis.
- Workflow build MANUAL (workflow_dispatch): tidak ada build otomatis saat push.
- Tanpa flash/sentuh perangkat tanpa izin.
- Satu tugas = satu tujuan. Verifikasi tiap langkah (L1 = bukti konkret).
- L2 wajib sebelum menyebut selesai; tanpa L2 status tetap "tunggu HP test".
- Tanpa secret di repo. Tanpa force push.
