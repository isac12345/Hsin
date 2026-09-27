# AGENTS.md — HSIN manual (modul dulu, APK belakangan)

1. Tim: leader (primary, koordinasi + merge) + dev-modul (subagent,
   skrip modul) + dev-apk (nanti, saat APK). Skill: writing-plans,
   subagent-driven-development, requesting/receiving-code-review,
   systematic-debugging, verification-before-completion +
   shell-sandbox, shell-safety, magisk-module-debug,
   android-static-verify (saat APK).
2. Kepemilikan: dev-modul = core/, engine/, capability/, config/,
   profiles/, extreme/, bin/, assets/, skrip modul di root
   (action/customize/service/uninstall/post-fs-data). dev-apk =
   app/, branding/ (aset aplikasi). Kerja di cabang work/<id>.
   Master/main tidak disentuh langsung; merge hanya oleh leader.
3. DILARANG sentuh perangkat: tanpa pm install, menjalankan
   aplikasi, input, screenshot, su, tulis /sys|/proc, reboot,
   flash. Tanpa build/zip di Termux untuk sekarang (perintah user:
   fix isi + rakit dulu, JANGAN build). Hanya edit teks + git + gh.
4. Alur leader: brief (tujuan, file, kriteria, bukti) → Task ke
   dev → review diff + verifikasi statis → TERIMA / REVISI
   (maks 2) / KOREKSI ≤20 baris. Gagal 2x → catat di NOTES.md.
5. DILARANG mencetak/commit secret. Tanpa force push.
   Update STATE.md tiap tugas selesai.
6. Gagal model dev (429/tumbang): JANGAN ganti model (baru
   berlaku setelah restart). Hentikan item itu, commit WIP
   di work/<id>, tulis agent + error persis di STATE.md,
   lanjut item lain yg tak bergantung, lalu lapor; user
   yg ganti model + restart.
7. Pekerja Task berbagi working tree: DILARANG checkout/reset
   cabang di repo utama. Gunakan `git worktree` atau
   kerja di cabang tanpa pindah HEAD utama.
8. Arsip fix + verifikasi 2 langkah (aturan permanen, sama kayak Alpha).
   Status tiap perbaikan: TUNGGU -> L1 -> L2 -> ARSIP. Dilarang loncat.
   - L1 = verifikasi teknis oleh leader, WAJIB bukti konkret
     (grep/test/sandbox output). Tanpa bukti = belum selesai.
   - L2 = user tes di HP + bilang OK. Tanpa ini tetap "tunggu HP test".
   - Hanya item L2 yang masuk arsip. Tanpa force push ke mana pun.

## Khusus HSIN (project ini)
- Konsep (beda dari Alpha): HSIN = MANUAL / bebas setting sesuka hati
  user. Alpha = adaptif (tanpa setting manual). Jangan campur logika
  adaptif Alpha ke sini kecuali perintah eksplisit.
- Sumber: /sdcard/hsin/ (6 zip: v3.0-fixed, v4.0, v4_2_5-beta,
  v4.2.5-consolidated, v4.2.6-fixed, v4.2.7-fixed + folder hsin-dev
  v5.0.0-beta1). Tiap varian ada error (klaim user) → audit dulu,
  pilih basis rakit, jangan asal copy.
- Diketahui dari Alpha: core/extreme.sh v4.2.6 TERKONTAMINASI
  9router-sync (bukan HSIN asli). Waspadai kontaminasi serupa di
  varian lain — verifikasi isi sebelum pakai.
- Struktur hsin-dev (basis kandidat): core/ engine/ capability/
  config/ profiles/ extreme/ bin/ webroot/ META-INF/ + action.sh,
  customize.sh, service.sh, post-fs-data.sh, uninstall.sh, module.prop
  (id=hsin, v5.0.0-beta1, vCode 5001).
- Fokus: modul dulu. APK belakangan (belum mulai). Jangan build/zip
  sampai user perintahkan.
- Target device awal: Unisoc T615 (same as Alpha), tapi desain tetap
  universal (node absen = skip + log, bukan hardcode).
