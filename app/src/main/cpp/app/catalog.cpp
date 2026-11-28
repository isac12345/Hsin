#include "catalog.h"
#include <cstring>

namespace hs {

#define N nullptr
// tier, grp, id, kind, name(id,en), desc(id,en), tag, warn, def, rec, why(id,en), cmd, key, cap, capDef, opts, lo, hi, step, unit
const std::vector<Feat>& catalog() {
  static const std::vector<Feat> c = {
    // ---------------- basic
    {0, "layar", "refresh", FK_CHIPS, "Refresh rate layar", "Screen refresh rate",
     "Seberapa sering layar diperbarui. Tinggi = halus, tapi boros baterai.", "How often the screen redraws. High = smooth, but uses more battery.",
     N, N, false, "off", "off", "Otomatis mengikuti mode dan lebih hemat.", "Auto follows the mode and saves power.", N, N, "refresh", true,
     {{"off", "Otomatis", "Auto"}, {"60", N, N}, {"90", N, N}, {"120", N, N}, {"144", N, N}}, 0, 0, 0, " Hz"},
    {0, "layar", "night", FK_SW, "Mode malam", "Night mode",
     "Filter hangat di layar supaya nyaman di mata saat gelap.", "A warm filter that is easier on the eyes in the dark.",
     N, N, false, "0", "0", "Hidupkan hanya kalau perlu.", "Turn on only when needed.", N, N, "night", true, {}, 0, 0, 0, N},
    {0, "layar", "font", FK_CHIPS, "Ukuran teks sistem", "System text size",
     "Ukuran teks di seluruh HP.", "Text size across the whole phone.",
     N, N, false, "1.0", "1.0", "Normal paling pas untuk layar 720p.", "Normal fits a 720p screen best.", N, N, "font", true,
     {{"0.85", "Kecil", "Small"}, {"1.0", "Normal", "Normal"}, {"1.15", "Besar", "Large"}}, 0, 0, 0, N},
    {0, "memori", "memclean", FK_SW, "Bersihkan RAM otomatis", "Clean RAM automatically",
     "Saat game dibuka, app latar yang menumpuk ditutup. App penting tidak disentuh.", "When a game opens, piled-up background apps are closed. Important apps are left alone.",
     N, N, false, "1", "1", "Aman dan membantu game besar.", "Safe and helps big games.", N, N, N, true, {}, 0, 0, 0, N},
    // ---------------- Suhsin
    {1, "cpu", "bigidle", FK_SW, "Inti besar tetap siaga", "Keep big cores awake",
     "Inti besar (CPU 6 dan 7) tidak masuk tidur dalam. Respons lebih cepat, baterai lebih boros.", "Big cores (CPU 6 and 7) skip deep sleep. Faster response, more battery use.",
     N, N, false, "0", "1", "Cocok dipakai saat game saja.", "Good for gaming sessions only.", N, "perf_cpuidle", "bigidle", true, {}, 0, 0, 0, N},
    {1, "cpu", "turbo", FK_SW, "Turbo bawaan vendor", "Vendor turbo",
     "Membuka batas kecepatan CPU dan GPU dari pabrik HP.", "Unlocks the CPU and GPU speed limits set by the phone maker.",
     "Hati-hati", "Careful", true, "0", "1", "Cocok untuk tes performa.", "Good for performance tests.", N, "perf_turbo", "turbo", true, {}, 0, 0, 0, N},
    {1, "gpu", "mali", FK_INFO, "Dorongan GPU (Mali)", "GPU boost (Mali)",
     "Diatur otomatis mengikuti mode. Tidak bisa diubah manual.", "Set automatically with the mode. It cannot be changed by hand.",
     N, N, false, N, N, N, N, N, N, "mali", true, {}, 0, 0, 0, N},
    {1, "gpu", "framepace", FK_SW, "Perataan frame", "Frame pacing",
     "Jarak antar frame dibuat rata supaya terasa lebih halus.", "Frame spacing is evened out so it feels smoother.",
     N, N, false, "1", "1", "Aman dipakai.", "Safe to use.", N, N, "framepace", true, {}, 0, 0, 0, N},
    {1, "vm", "swap", FK_CHIPS, "Pemakaian swap (swappiness)", "Swap use (swappiness)",
     "Seberapa cepat HP memindahkan data RAM ke swap. Rendah = RAM dipakai dulu, game lebih jarang patah.", "How eagerly the phone moves RAM data to swap. Low = RAM first, fewer stutters.",
     N, N, false, "def", "40", "Nilai 40 dipakai profil game di modul.", "40 is what the module game profile uses.", N, N, "vm", false,
     {{"def", "Bawaan", "Default"}, {"30", N, N}, {"40", N, N}, {"60", N, N}, {"100", N, N}}, 0, 0, 0, N},
    {1, "vm", "vfs", FK_CHIPS, "Cache file (vfs cache)", "File cache (vfs cache)",
     "Seberapa lama daftar file disimpan di RAM. Tinggi = cache dibuang lebih cepat.", "How long the file list stays in RAM. High = cache is dropped sooner.",
     N, N, false, "def", "100", "Nilai 100 dipakai profil game di modul.", "100 is what the module game profile uses.", N, N, "vm", false,
     {{"def", "Bawaan", "Default"}, {"50", N, N}, {"100", N, N}, {"150", N, N}}, 0, 0, 0, N},
    {1, "vm", "dirty", FK_CHIPS, "Tulis ke penyimpanan (dirty ratio)", "Write to storage (dirty ratio)",
     "Batas data yang boleh menunggu sebelum ditulis. Rendah = lebih sering tulis, jarang macet.", "How much data may wait before it is written. Low = writes more often, fewer stalls.",
     N, N, false, "def", "10", "Nilai 10 dipakai profil game di modul.", "10 is what the module game profile uses.", N, N, "vm", false,
     {{"def", "Bawaan", "Default"}, {"10", N, N}, {"20", N, N}, {"30", N, N}}, 0, 0, 0, "%"},
    {1, "vm", "mglru", FK_SW, "MGLRU", "MGLRU",
     "Cara kernel memilih memori yang dibuang. Tidak semua HP mendukung.", "How the kernel picks memory to drop. Not every phone supports it.",
     "Eksperimen", "Experimental", false, "0", "0", "Biarkan mati kecuali ingin mencoba.", "Leave it off unless you want to try.", N, N, "mglru", false, {}, 0, 0, 0, N},
    {1, "io", "ra", FK_CHIPS, "Baca-depan penyimpanan (read-ahead)", "Storage read-ahead",
     "Berapa banyak data dibaca lebih dulu. Besar = loading game lebih cepat.", "How much data is read in advance. Large = faster game loading.",
     N, N, false, "def", "2048", "2048 KB dipakai profil game di modul.", "2048 KB is what the module game profile uses.", N, N, "ra", false,
     {{"def", "Bawaan", "Default"}, {"128", N, N}, {"512", N, N}, {"1024", N, N}, {"2048", N, N}}, 0, 0, 0, " KB"},
    {1, "suhu", "thermaloff", FK_SW, "Matikan thermal", "Disable thermal",
     "Melepas pembatas panas dari kernel. FPS bisa naik, HP bisa sangat panas.", "Removes the kernel heat limiter. FPS may rise, the phone may get very hot.",
     "Hati-hati", "Careful", true, "0", "0", "Hidupkan hanya untuk tes performa maksimal sambil dipantau.", "Use only for max performance tests while watching the temperature.", N, N, "thermaloff", false, {}, 0, 0, 0, N},
    {1, "suhu", "ttrip", FK_SW, "Naikkan batas suhu (+10\xC2\xB0)", "Raise temperature limit (+10\xC2\xB0)",
     "Memberi HP ruang lebih sebelum kecepatan diturunkan. Lebih aman dari mematikan thermal.", "Gives the phone more room before it slows down. Safer than disabling thermal.",
     "Hati-hati", "Careful", true, "0", "0", "Pilih ini dulu kalau butuh lebih kencang.", "Pick this first if you need more speed.", N, "perf_trip", "ttrip", true, {}, 0, 0, 0, N},
    {1, "daya", "bypass", FK_SW, "Bypass charging", "Bypass charging",
     "Saat main sambil mengisi, listrik langsung ke HP. Baterai tidak ikut panas.", "When gaming while charging, power goes straight to the phone. The battery stays cooler.",
     N, N, false, "0", "1", "Tersedia di HP-mu.", "Available on your phone.", N, "tools_bypass", "bypass", true, {}, 0, 0, 0, N},
    // ---------------- recording (page Rekaman)
    {2, "rekam", "rec_res", FK_CHIPS, "Resolusi video", "Video resolution",
     "Ukuran gambar rekaman. Besar = tajam, file lebih besar.", "Size of the recorded picture. Large = sharp, bigger files.",
     N, N, false, "720", "720", "720p cukup untuk layar HP-mu dan ringan.", "720p suits your screen and stays light.", "rec.set", "res", N, true,
     {{"0", "Layar", "Screen"}, {"1080", "1080p", "1080p"}, {"720", "720p", "720p"}, {"480", "480p", "480p"}}, 0, 0, 0, N},
    {2, "rekam", "rec_fps", FK_CHIPS, "Frame rate video", "Video frame rate",
     "Frame per detik rekaman. 120 hanya jika layar 120 Hz.", "Frames per second of the recording. 120 only on a 120 Hz screen.",
     N, N, false, "30", "30", "30 paling ringan dan stabil.", "30 is the lightest and most stable.", "rec.set", "fps", N, true,
     {{"24", N, N}, {"30", N, N}, {"60", N, N}, {"90", N, N}, {"120", N, N}}, 0, 0, 0, N},
    {2, "rekam", "rec_br", FK_CHIPS, "Kualitas (bitrate)", "Quality (bitrate)",
     "Data per detik. Besar = lebih bagus, file lebih besar.", "Data per second. Large = better, bigger files.",
     N, N, false, "0", "0", "Otomatis memilih yang pas.", "Auto picks a good value.", "rec.set", "br", N, true,
     {{"0", "Auto", "Auto"}, {"4", N, N}, {"8", N, N}, {"16", N, N}, {"24", N, N}}, 0, 0, 0, " Mbps"},
    {2, "rekam", "rec_codec", FK_CHIPS, "Codec", "Codec",
     "H.264 paling aman dan ringan. HEVC lebih kecil tapi lebih berat.", "H.264 is safest and lightest. HEVC is smaller but heavier.",
     N, N, false, "0", "0", "H.264 paling aman.", "H.264 is the safest.", "rec.set", "codec", N, true,
     {{"0", "H.264", "H.264"}, {"1", "HEVC", "HEVC"}}, 0, 0, 0, N},
    {2, "rekam", "rec_audio", FK_CHIPS, "Sumber suara", "Audio source",
     "Internal = suara dari dalam HP, butuh Android 10+. Game yang melarang tetap bisu.", "Internal = sound from inside the phone, needs Android 10+. Games that block it stay silent.",
     N, N, false, "0", "2", "Internal merekam suara game tanpa suara sekitar.", "Internal records game sound without room noise.", "rec.set", "audio", N, true,
     {{"0", "Mati", "Off"}, {"1", "Mic", "Mic"}, {"2", "Internal", "Internal"}, {"3", "Mic+Internal", "Mic+Internal"}}, 0, 0, 0, N},
    {2, "rekam", "rec_safe", FK_SW, "Batas aman otomatis", "Automatic safe limits",
     "Menyesuaikan fps, resolusi, dan bitrate dengan kemampuan HP supaya tidak gagal.", "Fits fps, resolution, and bitrate to the phone so recording does not fail.",
     N, N, false, "1", "1", "Disarankan tetap hidup.", "Recommended to keep on.", "rec.set", "safe", N, true, {}, 0, 0, 0, N},
    {2, "rekam", "rec_cd", FK_SW, "Hitung mundur 3 detik", "3-second countdown",
     "Memberi waktu pindah ke game sebelum rekaman mulai.", "Gives you time to switch to the game before recording starts.",
     N, N, false, "1", "1", "Berguna bila merekam dari floating.", "Useful when recording from the floating panel.", "rec.set", "cd", N, true, {}, 0, 0, 0, N},
    {2, "rekam", "fpsrec", FK_SW, "Rekam FPS otomatis saat main", "Record FPS automatically",
     "Menyimpan rata-rata, 1% terendah, dan jumlah patah tiap sesi.", "Saves the average, 1% low, and stutter count for each session.",
     N, N, false, "1", "1", "Dipakai untuk riwayat sesi.", "Used for the session history.", N, N, N, true, {}, 0, 0, 0, N},
    // ---------------- tools
    {2, "alat", "charge", FK_CHIPS, "Atur pengisian", "Charging limit",
     "Normal mengisi sampai penuh. 80% menjaga baterai awet.", "Normal charges to full. 80% keeps the battery healthy.",
     N, N, false, "100", "80", "80% baik untuk pemakaian harian.", "80% is good for daily use.", N, N, "charge", true,
     {{"100", "Normal", "Normal"}, {"80", "80%", "80%"}}, 0, 0, 0, N},
    {2, "alat", "dac", FK_SLIDER, "Penguat suara", "Audio gain",
     "Menaikkan volume keluaran audio internal. Terlalu tinggi bisa pecah.", "Raises internal audio output level. Too high may distort.",
     N, N, false, "0", N, N, N, "feat", "tools_dac", "dac", true, {}, 0, 127, 1, N},
    {2, "alat", "led", FK_CHIPS, "Lampu LED", "LED light",
     "Warna lampu LED di HP, bila ada.", "LED colour on the phone, if present.",
     N, N, false, "off", N, N, N, N, "tools_led", "led", true,
     {{"off", "Mati", "Off"}, {"red", "Merah", "Red"}, {"green", "Hijau", "Green"}, {"blue", "Biru", "Blue"}}, 0, 0, 0, N},
  };
  return c;
}
#undef N

const Feat* findFeat(const char* id) {
  for (auto& f : catalog()) if (std::strcmp(f.id, id) == 0) return &f;
  return nullptr;
}

}  // namespace hs
