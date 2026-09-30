# APP_PLAN.md — Aplikasi Controller HSIN (Rakit dari Nol)

Rencana ini dijalankan step by step oleh Leader (dengan APK Agent sebagai
implementer). Aplikasi lama dihapus, aplikasi baru dirakit dari nol sesuai
desain yang sudah di-approve user.

Skill yang berlaku: `alpha-hsin-leader-agent` (proses), `alpha-hsin-controller-app`
(aturan APK), `alpha-hsin-engineering` (hanya untuk membaca kontrak modul),
`android-kotlin-core`, `android-coroutines-flow`, `android-gradle-build-logic`,
`android-static-verify`, `android-testing-unit`, `apk-pipeline` (alur build CI).

---

## 0. Aturan Eksekusi (WAJIB untuk Leader)

1. Kerjakan SATU step per instruksi user. Sebelum coding, tampilkan spec step
   itu PERSIS dari file ini, lalu tunggu user bilang lanjut.
2. Setelah step selesai: verifikasi dengan bukti (bukan klaim), push (commit
   baru), update tabel status di bawah, konfirmasi CI lewat `gh run list`,
   lalu STOP dan tunggu approve.
3. Build HANYA lewat GitHub Actions. Jangan kompilasi lokal di Termux.
4. GIT SAFETY: dilarang force-push atau `commit --amend` pada commit yang
   sudah di-push. Kesalahan diperbaiki dengan commit baru.
5. Jangan menyentuh file modul (core/, engine/, capability/, service.sh,
   module.prop, dst) kecuali step menyatakannya. Kalau APK butuh sesuatu yang
   belum ada di modul: STOP, laporkan ke user. Jangan bikin workaround logic
   engine di APK.
6. Setiap klaim di dokumen (nama command, format output, nama file) harus
   diverifikasi silang ke kode/sandbox, bukan dikarang.
7. Tidak ada klaim "stabil / production-ready". Versi aplikasi tetap beta
   sampai ada validasi di HP fisik bersama modul.
8. Kalau spec step ambigu atau bertabrakan dengan kondisi kode aktual,
   laporkan dulu, jangan menafsirkan sendiri.
9. Source of truth visual = screenshot di `/sdcard/hsin/docs/ui/`
   (`home_reference`, `home_detail_reference`, `knob_reference`,
   `knob_empty_reference`, `monitor_reference`, `log_reference`,
   `hsin_blank_reference` + `README.md`). Mockup terang = tampilan yang
   dimau; foto gelap = kondisi bug saat ini, BUKAN target. Bila mockup
   bertentangan dengan teks plan ini, mockup menang untuk visual,
   kontrak modul menang untuk data.
10. Setiap step yang menyentuh UI wajib bukti screenshot di HP fisik
    (L2 visual) sebelum dianggap selesai — compile hijau + unit test
    TIDAK bisa mendeteksi bug layout (pelajaran 30 Sep: BottomNav hilang
    sejak A5 tanpa terdeteksi).
11. Dilarang layar blank: tiap layar wajib punya 4 state eksplisit —
    Memuat, Gagal (pesan + tombol coba lagi), Kosong (pesan + aksi),
    Isi. Tidak ada kondisi yang merender layar kosong.

---

## 1. Keputusan Final (tidak boleh diubah tanpa persetujuan user)

- HSIN = manual penuh. TIDAK ADA pemilih profil (Battery/Balanced/Performance)
  di aplikasi. TIDAK ADA tombol "Otomatis" per knob.
- Hanya knob yang diubah user (dirty) yang dikirim ke modul saat Terapkan.
- Bahasa: Kotlin + Jetpack Compose. Tanpa Java. Tanpa C++/NDK kecuali ada bukti
  profiling yang membutuhkannya.
- Tanpa foreground service, tanpa wakelock, tanpa polling saat layar tidak
  terlihat. APK adalah controller, bukan daemon.
- Logic engine (mapping persen ke OPP, validasi governor, fallback) tetap di
  modul. APK mengirim nilai logis dan menampilkan hasil dari modul.
- Profil Extreme dan fitur bergate (`ALLOW_EXTREME`) tampil TERKUNCI. APK tidak
  menyediakan tombol untuk membuka gate itu.
- Dependency seminim mungkin. Prefer API platform daripada library pihak ketiga.
- Navigasi berbasis state (tanpa library navigasi) kecuali Leader bisa
  membuktikan manfaat nyata dan user setuju.
- Tema TERANG mengikuti mockup (`/sdcard/hsin/docs/ui/`), bukan tema gelap
  A5. Palet di bagian 2 diganti seluruhnya.
- Bottom nav = ikon + label (4 tab tetap: Beranda, Knob, Monitor, Log),
  ikon dari vector drawable XML di `res/` (tanpa dependency baru).
- Layar Knob dan Log memakai judul konten besar ("Knob", "Log");
  Beranda dan Monitor langsung kartu (sesuai mockup).
- Subtitle versi modul yang di-hardcode DILARANG. Versi modul hanya tampil
  bila kontrak menyediakannya (pending, lihat bagian 3) — TopBar hanya
  judul "HSIN" sampai saat itu.

---

## 2. Spesifikasi Desain (revisi 30 Sep 2026 — mengikuti mockup terang)

Gaya: neobrutalism TERANG (diukur dari mockup, dikunci setelah screenshot
L2). Palet tunggal:

| Token | Hex (sementara) | Pemakaian |
|---|---|---|
| bg | #F3EEE1 | latar layar (krem) |
| surface | #FCF9F1 | kartu (krem terang) |
| outline | #23211B | garis 1,5 dp (tinta, bukan abu) |
| text | #23211B | teks utama (tinta) |
| muted | #8B8471 | teks sekunder |
| accent | #C26A45 | SATU-SATUNYA aksen (terakota: tombol utama, tab aktif, toggle aktif, slider) |
| ok | #7E9A85 | APPLIED, status siap (sage) |
| warn | #B9954F | FALLBACK, WARN, DIUBAH (mustard) |
| error | #B5604F | FAILED |
| neutral | #6B6B70 | SKIPPED, DEFAULT, UNAVAILABLE |

Aturan visual: kartu = surface + outline tinta 1,5 dp + bayangan keras
hitam offset 3 dp tanpa blur. Badge status = fill pastel + teks tinta
(sesuai mockup, bukan outline-only). Tombol utama = fill accent + teks
tinta; tombol sekunder = outline tinta transparan. Tanpa gradient, tanpa
blur. Target sentuh minimal 44 dp. Nilai angka dan log monospace.

Struktur layar (bottom nav 4 tab, ikon + label):

- **Beranda** (tanpa judul konten, langsung kartu, sesuai mockup):
  kartu Status grid 2 kolom — Root (Tersedia/Tidak tersedia, dari
  `rootLine`), Modul (Terpasang/Belum diperiksa, dari `moduleLine`),
  Boot guard (Nonaktif / Aktif·tuning dilewati + alasan, dari
  `guard-status` kontrak §3.10), Termal (state modul bila ada, SEMENTARA
  suhu CPU saja tanpa badge — badge NORMAL menunggu field kontrak,
  pending bagian 3);
  kartu "Terakhir diterapkan · HH:MM" — maks 3 baris hasil knob-list
  (badge + `key requested→applied (alasan)`, kontrak §3.3/§3.4),
  jam dari baris terakhir `apply.log` (format `YYYY-MM-DD HH:MM:SS`,
  kontrak §3.6), fallback "waktu tak tercatat"; belum ada apply =
  state Kosong ("Belum ada apply", bukan kartu hilang);
  kartu "Kemampuan perangkat" — CPU policy N (`knobs.cpu.policies.size`),
  GPU devfreq Ada/Tidak (`gpu.nodes` tak kosong), zRAM Ada/Tidak
  (`memory.zram.supported`), I/O blok N; jumlah zona termal PENDING
  (tak ada di `knobs`, jangan karang); catatan kaki "Dibaca dari
  snapshot modul, tidak scan ulang tiap aplikasi dibuka." (cache APK);
  tombol "Buka knob" (primer) + "Pulihkan backup" (outline, wajib dialog
  konfirmasi, memanggil `rollback` kontrak §3.7) + "Periksa ulang"
  (outline, refresh 4 aksi).
- **Knob** (judul konten "Knob"): daftar kategori dari `knobs`
  (CPU per policy, GPU, I/O, Memori dan VM, Jaringan, Layar bila
  `supported`; daftar final dari kontrak A3) sebagai kartu "Nama + N
  knob + chevron"; halaman detail per kategori (label + kontrol pilihan
  atau slider + baris hasil); penanda DIUBAH per knob; bar bawah
  "Terapkan (N)" = jumlah dirty; bagian "Lanjutan (terkunci)" untuk
  fitur bergate (`features.*` false). Daftar `profiles` di JSON
  DIABAIKAN UI (tidak ada selector profil di mana pun).
- **Monitor** (tanpa judul konten, langsung kartu): kartu "Frekuensi" —
  baris CPU rata-rata (`cpu_freq`), Klaster besar (`cpu_freq_big`),
  Klaster kecil (`cpu_freq_little`, sembunyikan bila 0), GPU
  (`gpu_freq`); bar = nilai/maks (`cpu_max_khz`/`gpu_max_khz`,
  kontrak §3.1); baris per-policy mockup PENDING (status tak punya
  array per policy); kartu "Suhu dan memori" — Suhu CPU/GPU (°C),
  badge state PENDING (tampil tanpa badge sampai kontrak ada),
  RAM pakai/total GB + bar (`ram_used_kb`/`ram_total_kb`),
  Beban GPU = "N/A" + UNAVAILABLE (tak ada key-nya di kontrak — jujur,
  bukan 0). Polling on-demand ~2 detik, lifecycle-aware, tombol Jeda.
- **Log** (judul konten "Log"): toggle tersegmentasi boot.log/apply.log
  (aktif = fill accent) via `logs <type> <lines>` (kontrak §3.6, maks
  200 baris); entri = badge level + teks monospace; baris rusak tampil
  apa adanya; tombol "Salin ringkasan laporan bug" (guard + capability
  + ekor log); kosong = state Kosong ("Belum ada baris log"), bukan
  layar blank.

Per knob: label, kontrol (pilihan atau slider), dan baris hasil.
State baris hasil: `SAAT INI` (belum diubah), `DIUBAH`, lalu setelah apply
`APPLIED / FALLBACK / SKIPPED / UNAVAILABLE / FAILED` beserta teks
"diminta X → diterapkan Y (alasan)" yang berasal dari modul.

CATATAN PENTING: prototipe chat menghitung pemetaan OPP secara lokal hanya
untuk demo. Di aplikasi asli, APK TIDAK boleh menghitung pemetaan OPP.
Sebelum apply tampilkan nilai yang diminta saja. Nilai "diterapkan" hanya
dari modul.

---

## 3. Batas Tanggung Jawab

| Tugas | Pemilik |
|---|---|
| Deteksi hardware, capability, OPP, governor tersedia | Modul |
| Pemetaan nilai logis ke nilai hardware, verifikasi, fallback | Modul |
| Klasifikasi termal | Modul |
| Tampilan, input user, dirty tracking, kirim perintah, tampilkan hasil | APK |
| Cache capability untuk render cepat | APK (turunan dari modul, ada aturan invalidasi) |

### Pending kontrak modul (DILARANG dikerjakan sekarang — dicatat saja)

Mockup butuh data yang BELUM disediakan kontrak (verifikasi 30 Sep 2026).
APK dilarang mengarangnya (lihat aturan interim di bagian 2). Bila user
menyetujui penambahan kontrak di masa depan, kandidatnya:

| Kebutuhan mockup | Status kontrak sekarang | Kandidat penambahan |
|---|---|---|
| Badge state termal (NORMAL/dst) | `status` tak punya state; APK dilarang threshold sendiri | field `thermal_state` di JSON `status`, atau command `thermal-state` |
| Baris frekuensi per policy | `status` hanya rata-rata + big/little | array per policy di `status` |
| Jumlah zona termal | tak ada di `knobs` | field di `knobs` atau `capabilities` |
| Versi modul di header | tak ada command yang mengembalikannya | field `module_version` (sumber: `module.prop`) |
| Jam "Terakhir diterapkan" | interim: parse baris terakhir `apply.log` | field waktu eksplisit bila diinginkan |

---

## 4. Status

| Step | Judul | Status |
|---|---|---|
| A1 | Backup dan inventaris app lama | [x] |
| A2 | Hapus app lama, bersihkan referensi | [x] |
| A3 | Kontrak app-modul dan laporan gap | [x] |
| M1 | Mode manual murni di modul | [x] |
| M1b | Kemurnian mode manual | [x] |
| M2 | Command guard-status | [x] |
| K1 | Knob engine yang sudah ada | [x] |
| K2 | Knob tier-1 dari Alpha | [x] |
| K3 | Knob tier-2 berbasis capability | [x] |
| M3 | Perbarui kontrak app-modul | [x] |
| A4 | Scaffold proyek dan CI | [x] |
| A5 | Tema dan komponen | [x] |
| A6 | RootClient dan Repository | [x] |
| A7 | State, ViewModel, cache | [x] |
| A8 | Shell navigasi dan Beranda | [x] |
| A9 | Layar Knob | [x] |
| A10 | Alur Terapkan | [x] |
| A11 | Monitor | [x] |
| A12 | Log | [x] |
| A13 | State error dan kasus tepi | [x] |
| A14 | Audit footprint dan kualitas | [x] |
| A15 | Dokumen dan QA | [x] |
| A16 | Status final | [x] |
| R1 | Tema terang + komponen ulang | [x] |
| R2 | Navigasi ikon + judul konten + state anti-blank | [x] |
| R3 | Beranda + Monitor sesuai mockup (mapping interim) | [x] |
| R4 | Bukti screenshot L2 semua tab + penanda selesai | [ ] |

---

## 5. Langkah-langkah

### A1 — Backup dan inventaris app lama (JANGAN hapus apa pun)

Requirements:
- Buat git tag `app-legacy-backup` pada commit main saat ini dan push tag-nya.
- Inventaris: struktur direktori aplikasi lama, applicationId, lokasi konfigurasi
  signing, minSdk/targetSdk, daftar dependency, permission di manifest,
  workflow CI yang menyentuh aplikasi, dan referensi ke direktori aplikasi dari
  luar (build_release.sh, customize.sh, skrip modul, dokumen).
- Catat cara app lama memanggil modul: command, parsing output (mis.
  `lastJsonLine`), timeout, di `docs/APP_LEGACY_NOTES.md`. Fakta saja.

Acceptance: tag ada di remote; semua isi catatan diverifikasi ke kode; tidak
ada file dihapus atau diubah selain dokumen baru.

Commit: `docs: legacy app inventory and backup tag (App A1)`

### A2 — Hapus app lama, bersihkan referensi

Requirements:
- Hapus HANYA direktori proyek aplikasi lama (bisa dipulihkan lewat tag).
- Perbaiki referensi hasil inventaris A1 seminimal mungkin. Workflow build
  aplikasi jangan dihapus: nonaktifkan job aplikasi dengan komentar jelas,
  karena A4 memakainya lagi.
- Kalau build_release.sh atau skrip install modul membundel APK, JANGAN diubah
  diam-diam: laporkan ke user dan minta keputusan.

Acceptance: `git status` hanya berisi penghapusan aplikasi dan perbaikan
referensi; CI modul (lint-and-test) tetap hijau; file modul dan module.prop
tidak tersentuh.

Commit: `chore: remove legacy app project, recoverable via tag app-legacy-backup (App A2)`

### A3 — Kontrak app-modul dan laporan gap

Requirements:
- Baca bin/hsin, action.sh, API.md, README, TROUBLESHOOTING. Tulis
  `docs/APP_CONTRACT.md` berisi setiap command yang akan dipakai app dengan
  contoh output NYATA yang diambil dari sandbox test (bukan karangan): status,
  knob-list (format baris dan JSON terakhir), apply, restore, backup, lokasi
  log, dan sumber metrik monitor.
- Inventaris knob dari kode (user_knobs.sh dan engine/*): key, tipe nilai
  (pilihan atau rentang), engine asal, dan dari mana nilai valid didapat
  (governor tersedia, tabel OPP, dst).
- Analisis gap dan jawab dengan bukti file:baris:
  1. Bagaimana APK mendapat pilihan valid per knob? Apakah ada command
     capability yang mengeluarkan daftar governor, scheduler, OPP?
  2. Bagaimana APK mengirim perubahan knob dan memicu apply? Apakah atomik?
  3. Semantik manual murni: knob yang TIDAK diatur user, apakah modul menulis
     nilai profil dasar, atau membiarkan nilai sistem? (HSIN harus tidak
     menyentuh knob yang tidak diubah.)
  4. Bagaimana status gate `ALLOW_EXTREME` dan boot guard dibaca APK?
  5. Kode exit dan format error yang bisa dipetakan ke error APK.
- STOP dan laporkan gap ke user. JANGAN mengubah modul dan JANGAN merancang
  workaround di APK pada step ini.

Acceptance: kontrak lengkap dan terverifikasi; setiap gap punya bukti;
keputusan yang dibutuhkan dari user tercantum.

Commit: `docs: app-module contract and gap report (App A3)`

### M1 — Mode manual murni di modul (IZIN: boleh mengubah kode modul)
Objective: HSIN hanya menulis knob yang di-set user. Knob lain tidak
disentuh sama sekali.
Requirements:
- Tambah profil `manual`. Profil lama (battery/balanced/performance/
  extreme) tetap ada dan perilakunya TIDAK berubah.
- Default profil untuk instalasi BARU = manual. Instalasi yang sudah
  punya config tidak diubah diam-diam.
- Di mode manual, SEMUA jalur apply (service.sh saat boot,
  hsin_apply_all_engines, apply via action.sh) hanya menerapkan
  override dari user_knobs.env. Knob tanpa override tidak ditulis,
  dicatat SKIPPED dengan alasan "tidak diatur (mode manual)".
- Inventaris SEMUA penulisan di jalur apply (termasuk nilai tetap di
  profiles/*.conf dan engine yang menulis tanpa knob: jaringan, zram,
  VM, display, renderer). Untuk tiap penulisan tunjukkan perilakunya di
  mode manual: dilewati atau hanya jalan bila ada override. Tabel ini
  masuk laporan.
- Boot guard, thermal guard, safe_apply, engine_guard, backup/rollback,
  dan gate ALLOW_EXTREME tetap berlaku tanpa perubahan.
- knob-list di mode manual mempertahankan format baris dan JSON
  terakhir yang sudah ada. Knob tanpa override tampil SKIPPED dengan
  alasan di atas.
- Ganti profil ke manual lewat config-set kalau key profil sudah masuk
  whitelist. Kalau belum, tambahkan seminimal mungkin dan laporkan.
Acceptance (sandbox dengan file asli, snapshot byte sebelum/sesudah):
(1) manual + 1 override: hanya node itu berubah, semua node lain
byte-identik; (2) manual tanpa override: nol penulisan; (3) semua
sandbox test yang ada lulus (regresi profil lama); (4) jalur boot
manual hanya menerapkan override tersimpan; (5) backup lalu rollback
mengembalikan nilai; (6) override valid, invalid, dan snap OPP tetap
benar; ShellCheck -S error 0, sh -n lulus. File runtime baru wajib
terdaftar di build_release.sh dan dibuktikan lewat isi ZIP.
Commit: feat: manual mode applies only user overrides (M1)

### M1b — Kemurnian mode manual (IZIN: boleh mengubah kode modul, seminimal mungkin)
Objective: di mode manual tidak ada penulisan dari profil dan tidak ada
nilai yang tertinggal.
Requirements:
1. Safety remap (engine/cpu/safety.sh): di mode manual, remap
   low-battery dan remap critical ke profil battery TIDAK boleh
   menulis profil. Intervensi termal kritis di manual hanya lewat jalur
   thermal cap yang sudah ada (thermal/policy.sh dan thermal_check),
   bukan profil penuh. Profil lain perilakunya tidak berubah.
2. Thermal cap: buktikan dulu di sandbox apa yang terjadi setelah suhu
   turun (apakah nilai sebelum cap dipulihkan). Kalau tidak dipulihkan,
   pulihkan ke nilai yang tercatat sebelum cap saat suhu turun di bawah
   ambang (dengan histeresis), bukan permanen sampai reboot.
3. Game boost di mode manual: buktikan dulu dengan sandbox base MANUAL
   (snapshot byte sebelum, saat, dan sesudah boost). Kalau boost menulis
   nilai profil dan nilainya tertinggal, nonaktifkan game boost di mode
   manual (skip + log "game boost tidak aktif di mode manual"). Profil
   non-manual tidak berubah.
4. Koreksi NOTES.md dan STATE.md: restore memverifikasi readback dengan
   benar, catatan "restore hitung ok walau tulis ditolak" keliru.
Acceptance (sandbox file asli, snapshot byte): (a) manual + suhu 96C
tanpa override: hanya node thermal cap yang berubah (sebutkan node),
node lain byte-identik; (b) manual + baterai 10% tidak mengisi: nol
penulisan; (c) suhu turun: node cap kembali ke nilai sebelum cap;
(d) manual + game boost aktif: nol penulisan profil; (e) semua sandbox
test lama dan sandbox M1 lulus, profil lama identik; ShellCheck
-S error 0, sh -n lulus; file runtime baru (jika ada) terdaftar di
build_release.sh dan dibuktikan lewat isi ZIP.
Commit: fix: manual mode purity for safety remap, thermal cap restore
and game boost (M1b)

### M2 — Command guard-status (IZIN: boleh mengubah kode modul)
Objective: APK membaca status boot guard tanpa parsing log.
Requirements:
- Subcommand read-only `guard-status` di dispatch action.sh yang sama.
  Output key=value per baris plus satu baris JSON terakhir (ikuti pola
  knob-list): active (0/1), fail_count, threshold,
  cooldown_remaining_sec, last_reason. Tidak boleh menulis file apa pun.
  Data dibaca dari state boot_guard.sh yang sudah ada, tanpa logic
  guard baru.
- State hilang atau rusak: active=0, reason "tidak ada state", rc 0,
  tanpa crash.
Acceptance: sandbox untuk guard aktif, tidak aktif, state hilang, state
rusak; snapshot membuktikan nol penulisan; ShellCheck -S error 0,
sh -n lulus; daftarkan ke bundle bila ada file baru.
Commit: feat: guard-status read-only command (M2)

### K1 — Beri knob pada engine HSIN yang sudah ada (IZIN: boleh mengubah kode modul)
GATE: investigasi pasca-M1 dan M2 selesai dan disetujui user. Kalau investigasi menemukan pelanggaran mode manual murni, perbaikannya (M1b) dikerjakan lebih dulu.
Objective: penulisan yang selama ini hanya jalan dari profil (dan mati di mode manual) mendapat knob manual.
Requirements:
- Cakupan: readahead (I/O), vfs_cache_pressure, dirty_ratio, dirty_background_ratio (VM), sysctl backlog (jaringan), sesuai inventaris M1 baris 10, 13, 15. Baris 16-19 (DVFS, refresh-rate range, frame limit, SurfaceFlinger) TIDAK dikerjakan di sini. Laporkan saja apakah aman dijadikan knob.
- Ikuti pola knob yang ada persis (pola key, kategori hasil, knob-list, knobs). Rentang atau daftar nilai valid dibaca dari perangkat (node live), bukan hardcode. Kalau tidak bisa dibaca, ajukan batas ke user sebelum mengunci.
- Node tidak ada atau tidak writable: knob tampil UNAVAILABLE dengan alasan, lewat safe_apply dan engine_guard, tanpa crash.
- Setiap node baru masuk backup dan rollback. Uji backup lalu rollback per knob.
- Mode manual tanpa override tetap nol penulisan. Profil lama tidak berubah perilakunya.
- Perintah knobs mengeluarkan knob baru beserta engine dan kategori supaya app menampilkannya otomatis.
Acceptance (sandbox file asli, snapshot byte): hanya node yang di-set yang berubah; node hilang jadi UNAVAILABLE; nilai di luar rentang ditolak atau di-snap sesuai pola; backup lalu rollback mengembalikan nilai per knob; semua sandbox test lama lulus; ShellCheck -S error 0 dan sh -n lulus; file runtime baru terdaftar di build_release.sh dan dibuktikan lewat isi ZIP.
Commit: feat: knobs for existing engine writes (K1)

### K2 — Knob baru tingkat 1 dari Alpha (IZIN: boleh mengubah kode modul)
GATE: K1 disetujui user.
Objective: tambah knob yang aman dan universal.
Requirements:
- Cakupan: I/O add_random, iostats, nomerges (mengikuti pola engine I/O yang ada, RPMB dan boot dikecualikan seperti di Alpha); VM stat_interval dan page-cluster; schedutil rate_limit_us per policy (hanya bila governor schedutil aktif dan node ada).
- Semua persyaratan K1 berlaku.
- Tulis ulang sebagai knob sendiri, jangan salin kode Alpha mentah. Catat asal tiap tweak di dokumen.
- Untuk rate_limit_us: laporkan default dan rentang nyata di sandbox, ajukan batas ke user sebelum mengunci.
Acceptance: sama seperti K1.
Commit: feat: tier-1 knobs from Alpha (K2)

### K3 — Knob tingkat 2 berbasis capability (IZIN: boleh mengubah kode modul)
GATE: K2 disetujui user.
Cakupan: sched sysctl (sched_latency_ns, sched_min_granularity_ns, sched_wakeup_granularity_ns, sched_child_runs_first); uclamp cpuctl (cpu.uclamp.min dan max grup foreground); tunables GPU (devfreq polling_interval, up_threshold, down_differential bila governor cocok; mali_kbase boost, polling, upthreshold).
TIDAK termasuk: sched_migration_cost_ns, cpuset, stune, bus/DRAM, dan semua tweak tingkat 3 (ditunda sampai L2 di HP fisik).
Requirements:
- Semua persyaratan K1 berlaku.
- Deteksi ketat: node ada, writable, dan nilai valid. Kernel tanpa sysctl tertentu jadi UNAVAILABLE, bukan error. Jangan bergantung pada nama SoC atau vendor GPU, deteksi lewat node.
- Batas rentang tiap knob dijustifikasi (dokumentasi kernel atau nilai relatif Alpha terhadap nilai asli) dan dilaporkan ke user sebelum dikunci. Tidak ada nilai default: knob tidak disentuh sampai user mengubahnya.
- Uji sandbox dua varian: node lengkap dan node hilang sebagian.
Acceptance: sama seperti K1.
Commit: feat: tier-2 capability-gated knobs (K3)

### M3 — Perbarui kontrak app-modul (dokumen saja)
Objective: kontrak mencerminkan M1 dan M2.
Requirements:
- Perbarui docs/APP_CONTRACT.md: mode manual, guard-status (output
  [SANDBOX] nyata), perilaku knob-list di mode manual, dan jawaban ulang
  gap D1 dan D2 dengan bukti. Cantumkan keterbatasan: perintah tak
  dikenal mengembalikan Usage dengan rc 0, dan capabilities tidak bisa
  disandbox.
- Perbarui README, TROUBLESHOOTING, API.md, TESTING.md HANYA bagian
  yang jadi salah (verifikasi silang ke kode). Tidak ada perubahan kode.
Acceptance: semua contoh output di kontrak diambil dari sandbox setelah
M1 dan M2; CI hijau.
Commit: docs: update app contract for manual mode and guard-status (M3)

### A4 — Scaffold proyek dan CI

Requirements:
- Proyek baru di direktori aplikasi: Kotlin + Compose, satu modul, version
  catalog, dependency minimal (Compose BOM, activity-compose, lifecycle
  runtime/viewmodel untuk Compose). Tanpa Java, tanpa NDK.
- Pakai applicationId dan konfigurasi signing yang sama dengan app lama
  (dari A1). minSdk/targetSdk: usulkan dari konfigurasi lama, konfirmasi ke
  user sebelum mengunci.
- Aktifkan kembali workflow build aplikasi (via GitHub Actions saja), unggah
  artifact APK. Manifest bersih: tanpa service, receiver, atau permission
  yang tidak diperlukan.

Acceptance: CI membangun APK dan artifact tersedia (`gh run list` sukses);
tidak ada file .java dan tidak ada NDK; ukuran APK dilaporkan.

Commit: `feat: app scaffold kotlin+compose (App A4)`

### A5 — Tema dan komponen

Requirements:
- Token warna, tipografi, dan bentuk dari bagian 2 di satu tempat (single
  source). Komponen: HCard (outline + bayangan keras), HBadge (outline-only
  per status), HButton (utama dan sekunder), HSlider, HSelectRow, TopBar,
   BottomNav, ScreenScaffold.
- Katalog komponen hanya lewat `@Preview` (bukan layar yang dikirim).
- Tanpa gradient dan blur. Target sentuh minimal 44 dp. Kontras teks dicek.
- CATATAN 30 Sep: spec ini disupersede R1 (tema jadi terang, badge jadi
  fill pastel + teks tinta, nav berikon). Riwayat tidak diubah.

Acceptance: semua komponen punya preview, lint bersih, CI hijau.

Commit: `feat: theme and components (App A5)`

### A6 — RootClient dan Repository

Requirements:
- RootClient: eksekusi `su` di `Dispatchers.IO` dengan timeout, hasil berupa
  sealed class. Tipe error: ROOT_UNAVAILABLE, MODULE_NOT_FOUND,
  FEATURE_UNSUPPORTED, COMMAND_FAILED, TIMEOUT, INVALID_RESPONSE.
- Hanya command dari allowlist kontrak A3. Argumen divalidasi dan di-escape.
  Tidak ada input teks bebas yang menjadi command root.
- HsinRepository: parser output sesuai kontrak, abaikan key tak dikenal,
  parser baris knob-list (key, requested, applied, category, reason),
  kategori divalidasi ke set yang diketahui.
- Unit test JVM memakai fixture dari A3, termasuk output rusak dan log
  bercampur JSON.

Acceptance: unit test jalan di CI dan lulus; tidak ada eksekusi di main
thread; setiap error terpetakan.

Commit: `feat: root client and repository with parsers (App A6)`

### A7 — State, ViewModel, cache

Requirements:
- ViewModel dan UiState immutable per layar (Home, Knob, Monitor, Log).
  Bedakan data STATIC, CAPABILITY, CURRENT STATE, REALTIME.
- Cache capability lokal (SharedPreferences, tanpa database). Invalidasi saat
  versi modul berubah, cache hilang, atau user minta refresh. Empat aksi
  refresh terpisah: UI state, status modul, capability, metrik.
- State edit knob: base, current, dirty per key. Bertahan saat rotasi dan
  pindah tab.
- Tidak ada panggilan root saat komposisi.

Acceptance: unit test untuk dirty tracking dan invalidasi cache; tinjauan
membuktikan tidak ada root call di composable.

Commit: `feat: state holders and capability cache (App A7)`

### A8 — Shell navigasi dan Beranda

Requirements:
- Bottom nav 4 tab, top bar, navigasi berbasis state, sesuai desain.
- Beranda sesuai bagian 2. "Pulihkan backup" wajib dialog konfirmasi.
- status boot guard dibaca lewat guard-status (M2).
- Semua error tampil sebagai pesan ramah (tanpa exception mentah).

Acceptance: sesuai token desain; state root tidak ada dan modul tidak ada
tampil benar; CI hijau.

Commit: `feat: navigation shell and home screen (App A8)`

### A9 — Layar Knob

Requirements:
- Daftar kategori dari capability (kategori final dari A3). Kategori atau knob
  yang tidak tersedia disembunyikan atau dinonaktifkan dengan alasan jelas.
- Halaman detail per kategori dengan kontrol sesuai tipe knob. Penanda
  DIUBAH per knob, badge hitung per kategori.
- APK tidak menghitung mapping OPP atau validasi governor sendiri.
- Baris terkunci untuk fitur bergate.

Acceptance: dirty tracking benar; capability hilang tidak membuat crash;
tidak ada engine logic di APK.

Commit: `feat: knob screens (App A9)`

### A10 — Alur Terapkan

GATE: kerjakan hanya setelah user memutuskan gap A3 (terutama semantik
manual murni).
GATE: M1 harus selesai dan disetujui user.

Requirements:
- "Terapkan (N)" hanya mengirim knob dirty lewat kontrak. State "menerapkan"
  tidak memblokir UI.
- Setelah apply, baca hasil dari modul dan tampilkan per knob: kategori
  (APPLIED/FALLBACK/SKIPPED/UNAVAILABLE/FAILED) dan "diminta X → diterapkan Y
  (alasan)". Sukses parsial ditangani dengan benar.
- Pemulihan lewat backup tetap tersedia.

Acceptance: tes dengan RootClient palsu untuk sukses, parsial, gagal, dan
timeout; UI tidak pernah freeze.

Commit: `feat: apply flow with per-knob results (App A10)`

### A11 — Monitor

Requirements:
- Polling on-demand tiap sekitar 2 detik, hanya saat layar terlihat dan app
  foreground (lifecycle-aware). Ada tombol Jeda.
- Sumber metrik dari kontrak A3 (APK tidak membaca sysfs langsung kecuali
  kontrak menyatakannya). Klasifikasi termal dari modul.
- Metrik tidak tersedia = "N/A" dengan badge UNAVAILABLE, bukan 0.

Acceptance: bukti polling berhenti saat pindah layar dan saat app ke
background; kasus metrik hilang teruji.

Commit: `feat: on-demand monitor (App A11)`

### A12 — Log

Requirements:
- Tab boot.log dan apply.log, hanya N baris terakhir (mis. 200) lewat
  kontrak. Badge level per baris.
- Tombol "Salin ringkasan laporan bug": status boot guard, ringkasan
  capability, dan baris log terakhir.
- Baris rusak tidak boleh membuat crash. Penggunaan memori dibatasi.

Acceptance: tail terbatas; salin bekerja; unit test untuk baris rusak.

Commit: `feat: log screen with bug report summary (App A12)`

### A13 — State error dan kasus tepi

Requirements:
- UI dan fixture uji untuk: tanpa root, modul dinonaktifkan atau tidak ada,
  versi modul tidak cocok, timeout, respons tidak valid, boot guard aktif
  (banner "tuning dilewati"), state degraded, node read-only yang dilaporkan
  modul.
- status boot guard dibaca lewat guard-status (M2).

Acceptance: setiap state punya tampilan dan unit test.

Commit: `feat: error and edge states (App A13)`

### A14 — Audit footprint dan kualitas

Requirements:
- Manifest tanpa service/receiver/wakelock; permission minimal; daftar
  dependency beserta alasan tiap item.
- Ukur dan laporkan ukuran APK, waktu start, jumlah thread. Periksa
  recomposition berlebihan dan operasi di main thread.
- Jalankan verifikasi statis sesuai skill `android-static-verify` dan lint.

Acceptance: laporan berisi angka; temuan diperbaiki atau dicatat.

Commit: `chore: footprint and quality audit (App A14)`

### A15 — Dokumen dan QA

Requirements:
- `README_APP.md`: cara build (via Actions), cara pasang, permission, state
  yang didukung.
- `APP_QA_CHECKLIST.md`: tes manual di HP (tanpa root, modul nonaktif, run
  pertama, apply knob, monitor berhenti saat keluar layar, salin laporan bug,
  uninstall). Semua perintah dan nama diverifikasi ke kode.
- Tidak ada klaim stabil atau production-ready.

Acceptance: verifikasi silang dokumen ke kode; CI hijau.

Commit: `docs: app readme and QA checklist (App A15)`

### A16 — Status final

Requirements:
- Ringkasan semua step dengan hash commit dari git log, daftar item terbuka,
  dan langkah berikutnya: pasang APK dan modul bersama di HP fisik lalu isi
  laporan tes.
- Versi aplikasi tetap beta. STOP.

Commit: `docs: app final status (App A16)`

---

## 7. Realignment ke screenshot reference (R1–R4, setelah A16)

GATE tiap step R: user bilang lanjut (satu step per instruksi, aturan §0.1).
Dilarang menyentuh modul/core/engine/capability di semua step R.

### R1 — Tema terang + komponen ulang

Requirements:
- Ganti token bagian 2 (gelap → terang) di satu tempat; komponen HCard
  (outline tinta + bayangan keras), HBadge (fill pastel + teks tinta),
  HButton (primer accent / sekunder outline), HSlider, HSelectRow,
  TopBar (judul "HSIN" saja, tanpa subtitle hardcode), BottomNav
  (slot ikon + label), ScreenScaffold mengikuti.
- Katalog komponen hanya lewat `@Preview`.
- Tanpa gradient dan blur. Target sentuh minimal 44 dp.

Acceptance: semua komponen punya preview; lint bersih; CI hijau
(compile + unit test). Belum perlu screenshot (belum layar).

Commit: `feat: light neobrutalist theme and components (App R1)`

### R2 — Navigasi ikon + judul konten + state anti-blank

Requirements:
- Bottom nav 4 tab = ikon (4 vector drawable XML di `res/`, tanpa
  dependency baru) + label; tab aktif accent.
- Judul konten besar di Knob ("Knob") dan Log ("Log"); Beranda dan
  Monitor langsung kartu.
- Tiap layar (Beranda, Knob, Monitor, Log) punya 4 state eksplisit:
  Memuat (progress + teks), Gagal (pesan ramah + tombol coba lagi),
  Kosong (pesan + aksi), Isi. Tidak ada jalur yang merender blank
  (foto bug `knob_reference`, `knob_empty_reference`,
  `hsin_blank_reference` tidak boleh terulang).
- Perbaikan bug isi yang blank di HP (kartu status tak muncul) termasuk
  di sini bila akar masalahnya di APK; bila akarnya di kontrak/modul:
  STOP dan laporkan (jangan workaround engine di APK).

Acceptance: tiap state tiap layar punya preview atau unit test presenter;
CI hijau; screenshot HP 4 tab dilampirkan sebagai L2 (aturan §0.10).

Commit: `feat: icon nav, content titles, explicit states (App R2)`

### R3 — Beranda + Monitor sesuai mockup (mapping interim)

Requirements:
- Beranda persis bagian 2 revisi: grid status 2 kolom (kata mockup:
  Tersedia/Terpasang/Nonaktif), kartu "Terakhir diterapkan · HH:MM"
  (maks 3 baris + jam dari `apply.log`), kartu kemampuan + catatan
  snapshot, 3 tombol (Buka knob / Pulihkan backup + konfirmasi +
  Periksa ulang). Tanpa badge termal dan tanpa jumlah zona termal
  sampai kontrak menyediakannya (pending bagian 3).
- Monitor persis bagian 2 revisi: kartu Frekuensi (rata-rata + big/
  little + GPU + bar), kartu Suhu dan memori (tanpa badge state sampai
  kontrak ada), Beban GPU N/A + UNAVAILABLE. Tanpa baris per policy
  sampai kontrak menyediakannya.
- Knob dan Log: selaraskan detail kecil ke mockup (hitungan "N knob" +
  chevron; toggle tersegmentasi log) tanpa mengubah logic.
- Daftar `profiles` di JSON tetap diabaikan UI.

Acceptance: screenshot HP Beranda + Monitor + Knob + Log cocok dengan
mockup (isi boleh beda karena data nyata); tiap nilai di screenshot
bisa ditelusur ke kontrak §3; CI hijau.

Commit: `feat: home and monitor per reference mockups (App R3)`

### R4 — Bukti screenshot L2 semua tab + penanda selesai

Requirements:
- Kumpulkan screenshot HP fisik 4 tab (isi nyata dari modul) +
  1 screenshot tiap state Gagal/Kosong (simulasi: tanpa root / modul
  nonaktif bila memungkinkan tanpa merusak HP).
- Perbarui `docs/APP_FINAL_STATUS.md` dan tabel status bagian 4
  (R1–R4 [x]) dengan hash commit + tanggal screenshot. Versi tetap beta.
- STOP. Langkah berikutnya perlu keputusan user (kontrak pending
  bagian 3: tambah field modul atau tetap interim).

Commit: `docs: reference realignment complete with device proof (App R4)`

---

## 6. Larangan Keras

- Logic engine di APK (mapping OPP, validasi governor, klasifikasi termal
  dengan threshold sendiri).
- Pemilih profil atau tombol "Otomatis" di UI HSIN.
- Service permanen, wakelock, polling saat layar tidak terlihat.
- Command root dari input teks bebas.
- Menampilkan 0 untuk metrik yang tidak tersedia.
- Membuka gate Extreme dari aplikasi.
- Force-push atau amend pada commit yang sudah di-push.
- Build lokal di Termux.
- Klaim stabil, siap rilis, atau production-ready.
- Tema gelap A5 (digantikan tema terang bagian 2).
- Subtitle versi modul yang di-hardcode di APK.
- Klasifikasi termal dengan threshold buatan APK.
- Layar blank dalam kondisi apa pun (wajib 4 state eksplisit).
- Bottom nav teks saja (wajib ikon + label).
- Menampilkan jumlah zona termal, state termal, frekuensi per policy,
  atau versi modul yang dikarang tanpa sumber kontrak.
