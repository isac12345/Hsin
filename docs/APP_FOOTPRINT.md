# APP_FOOTPRINT.md — Audit footprint dan kualitas (App A14)

Tanggal: 2026-09-30. Semua angka diverifikasi ke CI/kode (bukan karangan).
Versi tetap beta sampai validasi HP fisik (Larangan Keras APP_PLAN §6).

## 1. Manifest (file: `app/app/src/main/AndroidManifest.xml`)

- 1 activity (`com.hsin.MainActivity`, singleTop, launcher). Tanpa service,
  receiver, provider, wakelock. Tanpa permission (NOL permission, keputusan A4).
- Verifikasi: `grep -rn "permission\|WAKE_LOCK\|FOREGROUND\|RECEIVER\|<service" app/app/src/main/` → kosong.

## 2. Dependency + alasan tiap item

| Artifact | Alasan |
|---|---|
| compose BOM 2024.10.00 | versi tunggal semua artifact Compose |
| compose ui / foundation / ui-graphics / ui-tooling-preview | UI, layout, preview katalog (A5) |
| material3 | Text/Button/AlertDialog (dipakai HButton, dialog restore, kartu) |
| activity-compose 1.9.3 | `ComponentActivity.setContent` |
| lifecycle-viewmodel-compose / runtime-ktx / runtime-compose 2.8.7 | `viewModel()`, `collectAsStateWithLifecycle`, `repeatOnLifecycle` (monitor A11) |
| coroutines-android 1.8.1 | `viewModelScope`, `Dispatchers.IO` via RootClient |
| org.json (main, via `org.json:json` test? — main memakai `org.json.JSONObject` bawaan Android) | parser kontrak (A6) tanpa serialization lib |
| junit 4.13.2 / kotlinx-coroutines-test 1.8.1 (test only) | unit test JVM |

Tanpa NDK, tanpa Java, tanpa navigation lib, tanpa serialization lib,
tanpa database (cache = SharedPreferences).

## 3. Angka

- Ukuran APK debug terakhir yang tercatat: A4 `6.856.887 byte` (~6,5 MiB,
  dex tak terkompres 17,4 MB = runtime Compose debug tanpa R8); A5
  `8.758.734 byte` (~8,35 MiB, naik karena material3 masuk).
  Artefak CI saat ini sudah kedaluwarsa (retensi Actions) sehingga ukuran
  pasca-A10–A13 belum diukur ulang — dicatat jujur, bukan dikarang.
  Perkiraan: ~9 MiB (debug, tanpa R8). Ukur ulang saat rilis beta di HP.
- Waktu start: BELUM diukur di HP (tidak ada klaim). Jalur start dingin =
  1 activity + `collectAsStateWithLifecycle`, NOL root call saat launch
  (refresh hanya via tombol/efek layar) sehingga start tidak menunggu `su`.
- Thread permanen: TIDAK ADA. Thread transien: 1 reader-thread per panggilan
  `su` (mati setelah command selesai/timeout) + pool coroutines IO.
  Tanpa polling saat background (A11: `repeatOnLifecycle(STARTED)`).

## 4. Recomposition & main thread

- `grep RootClient|CommandRunner in ui/` → kosong: composable tidak memanggil
  root. Semua root call di `viewModelScope` (RootClient `Dispatchers.IO`).
- State dikumpulkan di SATU titik (`HsinApp.collectAsStateWithLifecycle`);
  kategori knob di-`remember(cap, dirty)`; flag loading terpisah per aksi
  (satu refresh tidak membuat semua layar berkedip).
- Polling hanya di Monitor (±2 dtk, berhenti saat pindah tab/background);
  Log refresh sekali saat buka + tombol. Tanpa polling global.

## 5. Verifikasi statis

- `lint-and-test` hijau di branch A14 (wajib sebelum merge).
- `build-apk` hijau (compile Kotlin termasuk layar baru).
- Temuan & tindak lanjut:
  1. `PlaceholderScreen.kt` tidak dipakai lagi (semua tab nyata sejak A12)
     → DIHAPUS di commit ini (anti dead-code).
  2. Artefak APK kedaluwarsa → ukur ulang saat beta (catat di A15 QA).
  3. Waktu start & RAM di HP → ukur di QA fisik (A15 checklist).
