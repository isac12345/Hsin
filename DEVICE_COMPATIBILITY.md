# DEVICE_COMPATIBILITY.md — Matriks Kompatibilitas Jujur (Phase 4, PQ Step 16)

Aturan: **TERVALIDASI** hanya dengan bukti L2 HP nyata. Semua yang
lain = **GRACEFUL DEGRADE**, tanpa kecuali, tanpa matriks nama chipset
sebagai janji support (satu nama chipset di ROM/kernel berbeda bisa
beda governor, OPP table, dan thermal zone).

## TERVALIDASI (L2 HP nyata + bukti)

| Device | Bukti (log / tanggal / tester) | Profil dites | Hasil singkat |
|---|---|---|---|
| Perangkat developer (Unisoc T615 / GPU Mali) | Sandbox L1 hijau (boot_guard, safe_apply, thermal 6/6, degrade 8/8) + pemakaian langsung developer; 2026-09-27; tester: developer | `battery`, `balanced`, `performance` (sandbox A/B); `extreme` gated opt-in, belum tes rasa | Modul jalan; degradasi terbukti di sandbox. Tes rasa HP + report L2 (`tests/device_reports/`) MENYUSUL — saat ini direktori report masih kosong (hanya `.gitkeep`) |

Template report L2: `TESTING.md` (prosedur + template capability) dan
`tests/TEMPLATE_DEVICE_REPORT.md` (lembar identitas). Device baru masuk
tabel ini HANYA setelah report L2 terisi lengkap (boot log + apply log
+ APPLY-TIME + tes rasa).

## GRACEFUL DEGRADE (semua device lain — mekanisme, bukan daftar)

Tidak ada daftar nama chipset di sini — sengaja. Yang ada adalah
mekanisme yang berlaku untuk **device apa pun** yang capability-nya
tidak cocok signature mana pun di
`capability/capability_overrides.json` (rujukan: `README.md`, PQ Step 9):

1. `core/load_overrides.sh` menghitung signature dari `detected.conf`
   + cek `[ -w ]` live, tidak menemukan entry cocok →
   `default_fallback` + log wajib `no signature match, using
   default fallback` (bisa dicek: `grep "no signature match"
   /data/adb/hsin/logs/boot.log`).
2. Tiap engine yang node-nya tidak ada / read-only → `SKIPPED` +
   alasan di log (bukan crash, bukan tulis buta).
3. Engine yang nol applied → `rc=1` + warning + lanjut engine berikut
   (`core/engine_guard.sh`, PQ Step 12); `service.state` menjadi
   `degraded` bila ada yang gagal, service tetap selesai.
4. Thermal tanpa data sensor → `UNKNOWN` (tidak block tuning, tidak
   mengarang `NORMAL`).

Klaim yang bisa ditelusuri ke kode (bukan optimisme): device yang
tidak cocok **tidak akan bootloop karena tuning** — boot guard
melewati semua tuning setelah 2 gagal berturut-turut, dan tiap tulis
sysfs lewat `safe_apply` (cek exist + writable + read-back). Klaim
yang TIDAK dibuat: persentase device yang "seharusnya jalan",
performa, atau suhu — itu hanya boleh ditulis setelah L2 per device.
