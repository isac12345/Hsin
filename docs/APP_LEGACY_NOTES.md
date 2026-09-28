# APP_LEGACY_NOTES.md — Inventaris app lama (App A1, fakta terverifikasi)

Tag backup: `app-legacy-backup` → `f60fcfa` (commit `docs: add app rebuild plan`).
Semua fakta di bawah diverifikasi ke kode pada commit tersebut. Tanpa klaim stabil.

## 1. Struktur direktori aplikasi lama

- `app/` = proyek Gradle terpisah di dalam repo (root: `app/build.gradle.kts`,
  `app/settings.gradle.kts`, `app/gradle.properties`, `app/gradle/wrapper/`).
- Modul aplikasi: `app/app/build.gradle.kts`, source di `app/app/src/main/`
  (`AndroidManifest.xml`, `cpp/`, `java/com/hsin/`, `res/`).
- `branding/` = aset gambar saja: `background.jpg`, `banner.jpg`, `logo.png`
  (tidak ada kode; satu-satunya rujukan kode = komentar warna di
  `app/app/src/main/res/values/colors.xml:2`).
- File Java yang masih ada: `app/app/src/main/java/com/hsin/HsinCompat.java`
  (satu file `.java`; sisanya Kotlin).
- Native: `app/app/src/main/cpp/CMakeLists.txt` + `hsin_native.cpp`
  (library `hsin_native`, `find_library(log-lib log)`).

## 2. applicationId / namespace / SDK / versi

- `app/app/build.gradle.kts:8` → `namespace = "com.hsin"`.
- `app/app/build.gradle.kts:12` → `applicationId = "com.hsin"`.
- `app/app/build.gradle.kts:9,13,14` → `compileSdk = 34`, `minSdk = 26`,
  `targetSdk = 34`.
- `app/app/build.gradle.kts:15,16` → `versionCode = 1`, `versionName = "1.0.0"`.
- `app/app/build.gradle.kts:17-19` → NDK `abiFilters` =
  `arm64-v8a, armeabi-v7a, x86_64`.
- `app/app/build.gradle.kts:43-48` → `externalNativeBuild.cmake`
  `path = file("src/main/cpp/CMakeLists.txt")`, `version = "3.22.1+"`.
- Java/Kotlin toolchain: `VERSION_17` (`:33-39`), AGP `8.6.0` + Kotlin `2.0.20`
  (`app/build.gradle.kts:3-5`), Gradle wrapper `8.7`
  (`app/gradle/wrapper/gradle-wrapper.properties`).
- Label: `HSIN Control` / `HSIN` (`app/app/src/main/res/values/strings.xml`).

## 3. Konfigurasi signing

- TIDAK ADA blok `signingConfigs` di `app/app/build.gradle.kts` (grep
  `signing|keystore|storeFile|storePassword|keyAlias|jks` di `app/` = kosong).
- `.gitignore:3-5` mengecualikan `*.jks`, `*.keystore`, `keystore.properties`
  → tidak ada keystore di tree. Signing release tidak terdefinisi di repo.

## 4. Dependency (inline di `app/app/build.gradle.kts:59-83`, tanpa version catalog)

- `androidx.core:core-ktx:1.13.1`
- `androidx.appcompat:appcompat:1.7.0`
- `androidx.activity:activity-ktx:1.9.3`
- `androidx.fragment:fragment-ktx:1.8.3`
- `androidx.lifecycle:lifecycle-viewmodel-ktx:2.8.7`
- `androidx.lifecycle:lifecycle-livedata-ktx:2.8.7`
- `androidx.lifecycle:lifecycle-runtime-ktx:2.8.7`
- `androidx.navigation:navigation-fragment-ktx:2.8.4`
- `androidx.navigation:navigation-ui-ktx:2.8.4`
- `com.google.android.material:material:1.12.0`
- `androidx.recyclerview:recyclerview:1.3.2`
- `androidx.constraintlayout:constraintlayout:2.1.4`
- `org.jetbrains.kotlinx:kotlinx-coroutines-android:1.8.1`
- `org.jetbrains.kotlinx:kotlinx-serialization-json:1.6.3`
- `androidx.swiperefreshlayout:swiperefreshlayout:1.1.0`
- `androidx.cardview:cardview:1.0.0`
- Variabel versi yang dideklarasikan tapi tidak dipakai langsung
  (`:60-65`: `lifecycle_version`, `activity_version`, `material_version`,
  `recyclerview_version`, `kotlinx_serialization_version`, `coroutines_version`).
- Tidak ada `libs.versions.toml` (tanpa version catalog).

## 5. Permission + komponen manifest (`app/app/src/main/AndroidManifest.xml`)

Permission (`:5-10`):
- `INTERNET`, `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`, `FOREGROUND_SERVICE`,
  `FOREGROUND_SERVICE_DATA_SYNC`, `POST_NOTIFICATIONS`, `RECEIVE_BOOT_COMPLETED`.

Komponen (`:12-33`): satu `<activity>` saja
(`com.hsin.MainActivity`, `exported=true`, `singleTop`, launcher intent).
TIDAK ADA `<service>`, `<receiver>`, `<provider>` di manifest.

## 6. Workflow CI yang menyentuh aplikasi

- `.github/workflows/build-apk.yml` (satu-satunya workflow app):
  job `apk` (`:20`), `runs-on: ubuntu-latest`, trigger HANYA
  `workflow_dispatch` (`:6-14`, manual, tanpa auto-build saat push).
- Build: `working-directory: app`,
  `gradle :app:assembleDebug|Release` (`:72-74`); prasyarat JDK 17
  (`:26-30`), Android SDK platform `android-34` + build-tools `34.0.0`
  (`:55`), NDK `26.3.11579264` + CMake `3.22.1` (`:65`), Gradle `8.7`
  (`:67-70`).
- Artifact: `hsin-<variant>-apk`, path `app/app/build/outputs/apk/*/*.apk`
  (`:76-81`).
- `.github/workflows/build-modul.yml` dan `lint-and-test.yml` TIDAK menyentuh
  `app/` (grep `app|apk|kt|java` di `lint-and-test.yml` = kosong).

## 7. Referensi ke direktori aplikasi dari luar

- `AGENTS.md:12` → `dev-apk = app/, branding/ (aset aplikasi)`.
- `STATE.md:139`, `NOTES.md:607,617` → catatan historis path
  `app/app/build/outputs/apk/*/*.apk` dan reposisi `app/src` → `app/app/src/`.
- `build_release.sh:63` → `build|.git|app|branding) continue`:
  direktori `app/` + `branding/` DIKECUALIKAN dari ZIP modul
  (APK tidak dibundel ke modul).
- `customize.sh`, `service.sh`, `action.sh`, `module.prop`:
  grep `app/|apk|APK` tidak menemukan bundling APK
  (hit yang ada hanya komentar umum seperti `action.sh:13` soal refresh UI
  dan `top-app` cpuset yang bukan direktori aplikasi).
- `core/user_knobs.sh:531` → komentar sanitasi nama node merujuk
  `app/.../ui/knobs/KnobsRowBuilder.kt` (kontrak sanitasi, bukan bundling).

## 8. Cara app lama memanggil modul (fakta kode)

- Transport: `RootExec.exec(arrayOf("su", "-c", command))`
  (`app/app/src/main/java/com/hsin/RootExec.kt:40`).
- Timeout: `DEFAULT_TIMEOUT_MS = 20_000L` (`RootExec.kt:16`);
  duplikat `TIMEOUT_MS = 20_000L` di `HsinRepository.kt:21`.
  Timeout → `destroy()` + `destroyForcibly()` → `Result(false)`
  (`RootExec.kt:49-56`), bukan silent.
- Threading: `withContext(Dispatchers.IO)` di `HsinRepository.action`
  (`HsinRepository.kt:25-31`); stdout+stderr dibaca dua thread terpisah
  (`RootExec.kt:44-47`).
- Quoting: `SAFE_TOKEN = ^[A-Za-z0-9._/@:=+-]+$`, selain itu dibungkus `'...'`
  (`RootExec.kt:25-34`); pengiriman via `execTokens(*tokens)`
  (`RootExec.kt:73-74`).
- Command yang dikirim: `sh /data/adb/modules/hsin/action.sh <nama> [args]`
  (`HsinRepository.kt:27`, `MODULE_PATH = "/data/adb/modules/hsin"` di `:20`).
  Aksi yang dipakai: `knobs`, `status`, `device`, `knob-list`, `knob-set`,
  `knob-reset`, `config-set` (7 key whitelist modul), `apply <profile>`,
  `logs <type>`, `backup`, `rollback` (`HsinRepository.kt:41-75`).
- Urutan Apply: `knob-set*` + `config-set*` dulu semua, baru SATU `apply`
  (`ui/knobs/ApplyController.kt:27-50`, komentar `:18-20`).
  Normalisasi nilai di `normalizeValue` (`:53-57`).
- Parsing output (`lastJsonLine`): `HsinRepository.lastJsonLine`
  (`HsinRepository.kt:37-39`) → `HsinNative.lastJsonLineOrNull`
  (`HsinNative.kt:28-29`): ambil baris non-kosong TERAKHIR yang diawali `{`
  (fallback Kotlin `:47-50`; native bila `.so` ter-load, `:15-20`).
  Gagal → `throw HsinException` (`:29`, `:39`).
- JSON: `Json { ignoreUnknownKeys = true }` (`HsinRepository.kt:22`).
- Contoh command lengkap: `su -c "sh /data/adb/modules/hsin/action.sh knobs"`.
