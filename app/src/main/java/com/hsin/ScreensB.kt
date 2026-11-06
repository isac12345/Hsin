package com.hsin

import android.os.Build
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.key
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import android.os.SystemClock
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue

fun relTime(ms: Long?): String {
    if (ms == null) return "—"
    val d = (System.currentTimeMillis() - ms) / 60000
    return when {
        d < 1 -> "now"
        d < 60 -> "${d}m"
        d < 1440 -> "${d / 60}j"
        else -> "${d / 1440}h"
    }
}

@Composable
fun BgBannerScreen(vm: AppViewModel) {
    BackBtn { vm.back() }
    val pickBg = rememberLauncherForActivityResult(ActivityResultContracts.GetContent()) { uri -> if (uri != null) vm.setBackground(uri) }
    val pickBanner = rememberLauncherForActivityResult(ActivityResultContracts.GetContent()) { uri -> if (uri != null) vm.setBanner(uri) }
    HsinCard {
        Label("Background")
        Pill("PILIH GAMBAR BACKGROUND", { pickBg.launch("image/*") }, modifier = Modifier.padding(top = 0.dp))
        Pill("HAPUS BACKGROUND", { vm.clearBackground() })
        Label("Banner", Modifier.padding(top = 16.dp))
        Pill("PILIH GAMBAR BANNER", { pickBanner.launch("image/*") }, modifier = Modifier.padding(top = 0.dp))
        Pill("BANNER DEFAULT", { vm.resetBanner() })
    }
    HsinCard {
        val t = 1f - vm.cardAlpha
        SliderRow("Transparansi kartu", t, 0f..0.9f, "${(t * 100).toInt()}%", { vm.updateCardAlpha(1f - it) })
        Label("Penyesuaian gambar", Modifier.padding(top = 10.dp))
        Seg(listOf("CROP", "FIT", "FILL"), vm.fit, { vm.updateFit(it) })
    }
}

@Composable
fun BubbleScreen(vm: AppViewModel) {
    BackBtn { vm.back() }
    key(vm.flVer) { FloatingSettings(vm) }
}

@Composable
private fun FloatingSettings(vm: AppViewModel) {
    val p = vm.prefs
    val setMetric: (Int, Boolean) -> Unit = { i, on ->
        when (i) {
            0 -> p.flMCpu = on
            1 -> p.flMGpu = on
            2 -> p.flMRam = on
            else -> p.flMTemp = on
        }
        if (!p.flMFps && !p.flMCpu && !p.flMGpu && !p.flMRam && !p.flMTemp) {
            when (i) {
                0 -> p.flMCpu = true
                1 -> p.flMGpu = true
                2 -> p.flMRam = true
                else -> p.flMTemp = true
            }
            vm.msg = "Minimal FPS atau satu metrik harus aktif"
        }
        vm.flChanged()
    }
    HsinCard {
        Label("Floating overlay")
        txt("Perubahan langsung terlihat di floating.", 11.sp, muted())
        // Nilai slider disimpan lokal supaya geseran mulus; ke pengaturan ditulis paling sering tiap 150 ms
        // dan pasti saat dilepas. Layar ini baru dibuat ulang (flChanged) sekali, setelah slider dilepas.
        var sz by remember { mutableStateOf(p.flScale.toFloat()) }
        var szT by remember { mutableStateOf(0L) }
        SliderRow("Ukuran", sz, 70f..160f, "${sz.toInt()}%",
            { sz = it; val n = SystemClock.uptimeMillis(); if (n - szT > 150) { szT = n; p.flScale = it.toInt() } },
            { p.flScale = sz.toInt(); vm.flChanged() })
        var al by remember { mutableStateOf(p.flAlpha.toFloat()) }
        var alT by remember { mutableStateOf(0L) }
        SliderRow("Transparansi", al, 40f..100f, "${al.toInt()}%",
            { al = it; val n = SystemClock.uptimeMillis(); if (n - alT > 150) { alT = n; p.flAlpha = it.toInt() } },
            { p.flAlpha = al.toInt(); vm.flChanged() })
        Label("Gaya floating", Modifier.padding(top = 10.dp))
        Seg(listOf("APEX", "TURBO", "NITRO"), p.flStyle - 3, { p.flStyle = it + 3; p.appTheme = it + 1; UiState.theme = it + 1; UiState.themeTick++; vm.flChanged() })
        Label("Posisi panel", Modifier.padding(top = 10.dp))
        Seg(listOf("OTOMATIS", "ATAS", "BAWAH", "KIRI", "KANAN"), p.flPanelPos, { p.flPanelPos = it; vm.flChanged() })
        var pw by remember { mutableStateOf(p.flPanelW.toFloat()) }
        SliderRow("Lebar panel", pw, 70f..130f, "${pw.toInt()}%",
            { pw = it },
            { p.flPanelW = pw.toInt(); vm.flChanged() })
        txt("Posisi dan lebar dipakai saat panel dibuka dari orb. Ukuran di atas berlaku untuk orb dan panel.", 11.sp, muted())
        Label("Tampilan awal", Modifier.padding(top = 10.dp))
        Seg(listOf("ORB", "KAPSUL"), if (p.flStartThin) 1 else 0, { p.flStartThin = it == 1; vm.flChanged() })
        ToggleRow("Kapsul tembus sentuh", "Kapsul hanya tampil, sentuhan diteruskan ke game. Matikan di sini untuk menggesernya lagi.", p.flBarThrough) { p.flBarThrough = it; vm.flChanged() }
    }
    HsinCard {
        Label("Metrik yang ditampilkan")
        ToggleRow("FPS", "mati = tampilan ringkas hanya logo yang berubah warna sesuai mode", p.flMFps) { p.flMFps = it; vm.flChanged() }
        ToggleRow("CPU", null, p.flMCpu) { setMetric(0, it) }
        ToggleRow("GPU", null, p.flMGpu) { setMetric(1, it) }
        ToggleRow("RAM", null, p.flMRam) { setMetric(2, it) }
        ToggleRow("Suhu", null, p.flMTemp) { setMetric(3, it) }
        run {
            val names = mapOf('C' to "CPU", 'G' to "GPU", 'R' to "RAM", 'T' to "Suhu", 'B' to "Baterai")
            Label("Urutan di kapsul", Modifier.padding(top = 8.dp))
            val ord = p.flOrder
            ord.forEachIndexed { i, ch ->
                Row(Modifier.fillMaxWidth().padding(top = 6.dp), verticalAlignment = Alignment.CenterVertically) {
                    txt("${i + 1}. ${names[ch]}", 13.sp, modifier = Modifier.weight(1f))
                    SmallPill("NAIK", { if (i > 0) { val c = ord.toCharArray(); val t = c[i]; c[i] = c[i - 1]; c[i - 1] = t; p.flOrder = String(c); vm.flChanged() } })
                    Spacer(Modifier.width(6.dp))
                    SmallPill("TURUN", { if (i < 4) { val c = ord.toCharArray(); val t = c[i]; c[i] = c[i + 1]; c[i + 1] = t; p.flOrder = String(c); vm.flChanged() } })
                }
            }
        }
        ToggleRow("Selalu tampil", "floating menyala terus (tidak hanya saat game) supaya kelihatan FPS-nya jalan atau tidak", p.flAlways) { p.flAlways = it; vm.flChanged() }
        ToggleRow("Baterai", "persen baterai di kapsul", p.flMBatt) { p.flMBatt = it; vm.flChanged() }
        ToggleRow("Rekam FPS otomatis", "mulai saat game dibuka, simpan ke file saat game ditutup", p.flAutoLog) { p.flAutoLog = it; vm.flChanged() }
        ToggleRow("Grafik FPS", null, p.flGraph) { p.flGraph = it; vm.flChanged() }
    }
    HsinCard {
        Label("Warna aksen")
        Seg(listOf("IKUT PROFIL", "TETAP"), if (p.flAccentFixed) 1 else 0, { p.flAccentFixed = it == 1; vm.flChanged() })
        if (p.flAccentFixed) {
            val swatches = listOf(0xFFF5A524.toInt(), 0xFF60A5FA.toInt(), 0xFF34D399.toInt(), 0xFFE5484D.toInt())
            Row(Modifier.fillMaxWidth().padding(top = 10.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                swatches.forEach { c ->
                    val on = p.flAccentColor == c
                    Box(
                        Modifier.size(36.dp).clip(CircleShape).background(Color(c))
                            .border(BorderStroke(2.dp, if (on) Color.White else Color.Transparent), CircleShape)
                            .clickable { p.flAccentColor = c; vm.flChanged() },
                    )
                }
            }
        }
        Pill("RESET POSISI", {
            p.flXp = 24; p.flYp = 20; p.flXl = 24; p.flYl = 20
            p.flPosVer = p.flPosVer + 1
            vm.flChanged()
        }, modifier = Modifier.padding(top = 12.dp))
    }
}

@Composable
fun LogRow(l: LogLine) {
    Row(Modifier.fillMaxWidth().padding(vertical = 3.dp), verticalAlignment = Alignment.CenterVertically) {
        txt(relTime(l.timeMs), 12.sp, muted(), modifier = Modifier.width(34.dp), maxLines = 1)
        txt(l.cat, 12.sp, weight = FontWeight.Medium, modifier = Modifier.width(86.dp), maxLines = 1)
        txt((l.status + " " + l.msg).trim(), 12.sp, muted(), modifier = Modifier.weight(1f), maxLines = 1)
    }
}

@Composable
fun FullLogScreen(vm: AppViewModel) {
    BackBtn { vm.back() }
    HsinCard {
        val filters = listOf("ALL" to "SEMUA", "ERROR" to "ERROR", "CPU" to "CPU", "GAME" to "GAME", "INPUT" to "INPUT")
        Row(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()).padding(bottom = 8.dp), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            filters.forEach { (k, t) -> Chip(t, vm.logFilter == k) { vm.logFilter = k } }
        }
        val shown = vm.logs.filter { Hsin.logMatches(it, vm.logFilter) }.takeLast(300).reversed()
        if (shown.isEmpty()) txt("Tidak ada baris yang cocok.", 12.sp, muted())
        shown.forEach { l ->
            txt(l.raw, 11.sp, muted(), modifier = Modifier.padding(vertical = 2.dp))
        }
        Pill("SALIN", { vm.copyLog() })
    }
}

// ---------------------------------------------------------------- DEXOPT
@Composable
fun DexoptScreen(vm: AppViewModel) {
    BackBtn { if (!vm.dexRunning) vm.back() }
    val modes = listOf(
        Triple("speed-profile", "SEIMBANG", "pakai profil pemakaian · disarankan"),
        Triple("speed", "CEPAT", "compile penuh · storage lebih besar"),
        Triple("everything", "MAKSIMAL", "semua method · paling besar dan lama"),
        Triple("verify", "RINGAN", "verifikasi saja · hemat storage"),
        Triple("reset", "RESET", "kembalikan ke compile bawaan sistem"),
    )
    HsinCard {
        Label("Mode dexopt")
        modes.forEach { (k, t, d) ->
            val on = vm.dexMode == k
            Row(
                Modifier.fillMaxWidth().clickable(enabled = !vm.dexRunning) { vm.dexMode = k }.padding(vertical = 8.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Box(
                    Modifier.size(18.dp).clip(CircleShape).border(BorderStroke(1.2.dp, if (on) LocalUi.current.accent else muted()), CircleShape).padding(4.dp),
                ) { if (on) Box(Modifier.fillMaxWidth().height(10.dp).clip(CircleShape).background(LocalUi.current.accent)) }
                Column(Modifier.padding(start = 12.dp)) {
                    txt(t, 13.sp, weight = FontWeight.Medium, spacing = 1.sp)
                    txt(d, 12.sp, muted())
                }
            }
        }
    }

    HsinCard {
        Label("Jalankan")
        txt("${vm.dexSel.size} app dipilih · mode ${vm.dexMode}", 12.sp, muted())
        if (vm.dexRunning) {
            Box(Modifier.fillMaxWidth().padding(top = 10.dp).height(6.dp).clip(CircleShape).background(Color.White.copy(alpha = 0.15f))) {
                val f = if (vm.dexTotal == 0) 0f else vm.dexDone.toFloat() / vm.dexTotal
                Box(Modifier.fillMaxWidth(f.coerceIn(0.02f, 1f)).height(6.dp).clip(CircleShape).background(LocalUi.current.accent))
            }
            txt("${vm.dexDone}/${vm.dexTotal} · ${vm.dexCurrent}", 12.sp, modifier = Modifier.padding(top = 8.dp), maxLines = 1)
            txt("Berhasil ${vm.dexOk} · gagal ${vm.dexFail}", 12.sp, muted())
            Pill("BATALKAN", { vm.dexCancel() })
        } else {
            Pill("MULAI DEXOPT", { vm.dexStart() }, solid = true, enabled = vm.dexSel.isNotEmpty())
        }
    }

    HsinCard {
        val list = vm.thirdParty
        Label("App pihak ketiga · ${list.size}")
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Chip("PILIH SEMUA", false) { if (!vm.dexRunning) vm.dexSelectAll(list.map { it.pkg }) }
            Chip("KOSONGKAN", false) { if (!vm.dexRunning) vm.dexClear() }
        }
        if (list.isEmpty()) txt("Membaca daftar app...", 12.sp, muted(), modifier = Modifier.padding(top = 10.dp))
        list.forEach { a ->
            val on = a.pkg in vm.dexSel
            Row(
                Modifier.fillMaxWidth().clickable(enabled = !vm.dexRunning) { vm.dexToggle(a.pkg) }.padding(top = 10.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Box(
                    Modifier.size(22.dp).clip(RoundedCornerShape(6.dp)).background(if (on) Mint else Color.White.copy(alpha = 0.12f)),
                    contentAlignment = Alignment.Center,
                ) { if (on) txt("✓", 14.sp, Color(0xFF04342C)) }
                Box(Modifier.width(10.dp))
                AppIcon(a.pkg, 36.dp)
                Column(Modifier.weight(1f).padding(start = 10.dp)) {
                    txt(a.label, 13.sp, maxLines = 1)
                    txt(a.pkg, 11.sp, muted(), maxLines = 1)
                }
            }
        }
    }
}

// ---------------------------------------------------------------- MEMORI & ALAT (v55)
@Composable
fun MemFxScreen(vm: AppViewModel) {
    BackBtn { vm.back() }
    val m = vm.memInfo
    fun pct(k: String): String = m[k]?.toIntOrNull()?.let { "%d.%02d%%".format(it / 100, it % 100) } ?: "-"
    HsinCard {
        Label("Tekanan memori")
        if (m["psi"] != "1") {
            txt("Kernel ini tidak punya PSI memori, jadi angka tekanan tidak tersedia.", 12.sp, muted())
        } else {
            KV("Tertahan sebagian (10 dtk)", pct("psi_some10_x100"))
            Divider()
            KV("Tertahan penuh (10 dtk)", pct("psi_full10_x100"))
            Divider()
            KV("Ambang pembersih", pct("psi_threshold_x100"))
        }
        Divider()
        KV("RAM tersedia", m["mem_avail_mb"]?.let { "$it MB dari ${m["mem_total_mb"] ?: "?"} MB" } ?: "-")
        Divider()
        KV("Swap terpakai", m["swap_used_mb"]?.let { "$it MB" } ?: "-")
        Pill("SEGARKAN", { vm.loadMem() })
    }
    HsinCard {
        Label("MGLRU (eksperimental)")
        val sup = vm.mglru["supported"] == "1"
        if (!sup) {
            txt("Kernel ini tidak mendukung MGLRU.", 12.sp, muted())
        } else {
            ToggleRow(
                "Nyalakan MGLRU",
                "Bukan untuk game: manfaat terbukti hanya untuk multitasking, dan bisa membuat stutter. Nilai asli dikembalikan saat dimatikan.",
                vm.mglru["enabled"] == "1",
            ) { vm.setMglru(it) }
            txt("Status kernel: ${vm.mglru["enabled_raw"] ?: "-"}", 11.sp, muted())
        }
    }
    HsinCard {
        Label("Pembersih adaptif")
        ToggleRow(
            "Bersihkan saat tekanan tinggi",
            "Hanya saat game aktif: tutup proses latar bila tekanan memori tinggi berturut-turut. Jeda 3 menit antar aksi.",
            vm.confStr("MEMCLEAN", "0") == "1",
        ) { vm.setMemclean(it) }
        Divider()
        ToggleRow(
            "Bebaskan RAM saat game mulai",
            "Sekali tiap game dibuka.",
            vm.confStr("MEMCLEAN_ON_START", "0") == "1",
        ) { vm.setConfKey("MEMCLEAN_ON_START", if (it) "1" else "0") }
        txt("Memakai perintah am kill-all; bila ROM tidak punya, aksinya dilewati dan dicatat di log.", 11.sp, muted())
    }
    HsinCard {
        Label("Alat")
        Pill("TRIM PENYIMPANAN", { vm.runTrim() })
        txt("fstrim semua partisi. Tidak jalan saat game aktif atau baterai di bawah 15%.", 11.sp, muted())
        Pill("CARI GAME TERPASANG", { vm.scanGames() })
        val sl = vm.scanList
        if (sl != null && sl.isNotEmpty()) {
            sl.take(12).forEach { txt(vm.label(it), 12.sp, maxLines = 1, modifier = Modifier.padding(top = 4.dp)) }
            if (sl.size > 12) txt("+${sl.size - 12} lainnya", 11.sp, muted())
            Pill("DAFTARKAN ${sl.size} GAME", { vm.scanAdd() }, solid = true)
        }
        Pill("BUAT LAPORAN BUG", { vm.makeBugreport() })
        txt("Arsip log + konfigurasi ke folder Download, untuk dikirim saat ada masalah.", 11.sp, muted())
    }
}

// ---------------------------------------------------------------- APP DILINDUNGI (Bersihkan RAM)
@Composable
fun RamKeepScreen(vm: AppViewModel) {
    BackBtn { vm.back() }
    key(vm.ramKeepVer) {
        HsinCard {
            Label("Selalu dilindungi")
            txt("Termux, Magisk, KernelSU, APatch, HSIN, launcher, keyboard, dialer, dan layanan sistem tidak pernah ditutup. Pilih app lain yang juga ingin dilindungi dari Bersihkan RAM:", 12.sp, muted())
        }
        HsinCard {
            val list = vm.thirdParty
            val keep = vm.prefs.ramKeep
            Label("App pihak ketiga · ${list.size} · dilindungi ${keep.size}")
            if (list.isEmpty()) txt("Membaca daftar app...", 12.sp, muted(), modifier = Modifier.padding(top = 10.dp))
            list.forEach { a ->
                val on = a.pkg in keep
                Row(
                    Modifier.fillMaxWidth().clickable { vm.toggleRamKeep(a.pkg) }.padding(top = 10.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Box(
                        Modifier.size(22.dp).clip(RoundedCornerShape(6.dp)).background(if (on) Mint else Color.White.copy(alpha = 0.12f)),
                        contentAlignment = Alignment.Center,
                    ) { if (on) txt("✓", 14.sp, Color(0xFF04342C)) }
                    Box(Modifier.width(10.dp))
                    AppIcon(a.pkg, 36.dp)
                    Column(Modifier.weight(1f).padding(start = 10.dp)) {
                        txt(a.label, 13.sp, maxLines = 1)
                        txt(a.pkg, 11.sp, muted(), maxLines = 1)
                    }
                }
            }
        }
    }
}

// ---------------------------------------------------------------- BEKUKAN APP
@Composable
fun FreezeScreen(vm: AppViewModel) {
    BackBtn { vm.back() }
    HsinCard {
        Label("Bekukan app")
        txt("App yang dibekukan tidak jalan sama sekali di latar belakang dan ikonnya hilang, tapi datanya aman. Cairkan kapan saja dari sini. App sistem, launcher, keyboard, dan HSIN tidak bisa dibekukan.", 12.sp, muted())
        if (vm.frozen.isNotEmpty()) {
            Spacer(Modifier.height(10.dp))
            Label("Sedang dibekukan · ${vm.frozen.size}")
            vm.frozen.forEach { p ->
                Row(Modifier.fillMaxWidth().padding(top = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                    AppIcon(p, 32.dp)
                    Column(Modifier.weight(1f).padding(start = 10.dp)) {
                        txt(vm.label(p), 13.sp, maxLines = 1)
                        txt(p, 11.sp, muted(), maxLines = 1)
                    }
                    SmallPill("CAIRKAN", { vm.unfreezeApp(p) })
                }
            }
            Spacer(Modifier.height(10.dp))
            Pill("CAIRKAN SEMUA", { vm.unfreezeApp("") })
        }
    }
    HsinCard {
        val list = vm.thirdParty.filter { it.pkg !in vm.frozen }
        Label("Pilih app untuk dibekukan · ${list.size}")
        if (vm.thirdParty.isEmpty()) txt("Membaca daftar app...", 12.sp, muted(), modifier = Modifier.padding(top = 10.dp))
        list.forEach { a ->
            Row(Modifier.fillMaxWidth().clickable { vm.freezeApp(a.pkg) }.padding(top = 10.dp), verticalAlignment = Alignment.CenterVertically) {
                AppIcon(a.pkg, 36.dp)
                Column(Modifier.weight(1f).padding(start = 10.dp)) {
                    txt(a.label, 13.sp, maxLines = 1)
                    txt(a.pkg, 11.sp, muted(), maxLines = 1)
                }
                txt("BEKUKAN", 11.sp, Mint)
            }
        }
    }
}

// ---------------------------------------------------------------- RIWAYAT SESI + BANDINGKAN
@Composable
fun SessionsScreen(vm: AppViewModel) {
    BackBtn { vm.back() }
    val list = vm.prefs.fpsSessions
    HsinCard {
        Label("Riwayat sesi FPS")
        if (list.isEmpty()) txt("Belum ada sesi. Main game dengan floating aktif, sesi tersimpan otomatis (minimal ±10 detik).", 12.sp, muted())
        else txt("Ketuk dua sesi untuk dibandingkan (misal Hemat vs Puncak di game yang sama).", 12.sp, muted())
        list.forEachIndexed { i, s ->
            val sel = i == vm.cmpA || i == vm.cmpB
            val mode = if (s.ovdPct >= 50) "Puncak" else profileLabel(s.profile)
            Column(
                Modifier.fillMaxWidth().padding(top = 8.dp).clip(RoundedCornerShape(10.dp))
                    .background(if (sel) Mint.copy(alpha = 0.14f) else Color.White.copy(alpha = 0.05f))
                    .clickable {
                        if (vm.cmpA == i) vm.cmpA = -1
                        else if (vm.cmpB == i) vm.cmpB = -1
                        else if (vm.cmpA < 0) vm.cmpA = i
                        else vm.cmpB = i
                    }.padding(10.dp),
            ) {
                txt(vm.label(s.pkg) + " · " + mode, 13.sp)
                txt("${s.avg} FPS rata-rata · 1% low ${s.low1} · ${s.secs / 60}m ${s.secs % 60}s" + (if (s.jank > 0 || s.bigJank > 0) " · jank ${s.jank}/${s.bigJank}" else "") + (if (s.stab > 0) " · stabil ${s.stab}%" else "") + (if (s.watt10 > 0) " · ${s.watt10 / 10}.${s.watt10 % 10} W" else ""), 11.sp, muted())
            }
        }
    }
    val a = list.getOrNull(vm.cmpA)
    val b = list.getOrNull(vm.cmpB)
    if (a != null && b != null) {
        HsinCard {
            Label("Perbandingan")
            @Composable
            fun r(name: String, x: String, y: String) {
                Row(Modifier.fillMaxWidth().padding(top = 6.dp)) {
                    txt(name, 12.sp, muted(), modifier = Modifier.weight(1f))
                    txt(x, 12.sp, modifier = Modifier.weight(1f))
                    txt(y, 12.sp, modifier = Modifier.weight(1f))
                }
            }
            fun m(s: FpsSession) = if (s.ovdPct >= 50) "Puncak" else profileLabel(s.profile)
            r("", "A: " + m(a), "B: " + m(b))
            r("FPS rata-rata", "${a.avg}", "${b.avg}")
            r("1% low", "${a.low1}", "${b.low1}")
            r("Jank / besar", "${a.jank} / ${a.bigJank}", "${b.jank} / ${b.bigJank}")
            r("Kestabilan", "${a.stab}%", "${b.stab}%")
            r("Frame maks", "${a.maxFt} ms", "${b.maxFt} ms")
            r("Daya", if (a.watt10 > 0) "${a.watt10 / 10}.${a.watt10 % 10} W" else "--", if (b.watt10 > 0) "${b.watt10 / 10}.${b.watt10 % 10} W" else "--")
            val dFps = b.avg - a.avg
            txt("B " + (if (dFps >= 0) "lebih tinggi " else "lebih rendah ") + Math.abs(dFps) + " FPS dari A." + (if (a.watt10 > 0 && b.watt10 > 0) " Daya B " + (if (b.watt10 >= a.watt10) "lebih boros " else "lebih hemat ") + Math.abs(b.watt10 - a.watt10) / 10.0 + " W." else ""), 12.sp, Mint, modifier = Modifier.padding(top = 10.dp))
        }
    }
    if (list.isNotEmpty()) {
        val ctx = androidx.compose.ui.platform.LocalContext.current
        Pill("SALIN RINGKASAN", {
            val t = list.joinToString("\n") { s -> "${vm.label(s.pkg)} | ${if (s.ovdPct >= 50) "Puncak" else profileLabel(s.profile)} | ${s.avg} FPS | 1% low ${s.low1} | jank ${s.jank}/${s.bigJank} | stabil ${s.stab}% | ${s.secs}s" + if (s.watt10 > 0) " | ${s.watt10 / 10.0} W" else "" }
            (ctx.getSystemService(android.content.Context.CLIPBOARD_SERVICE) as android.content.ClipboardManager).setPrimaryClip(android.content.ClipData.newPlainText("HSIN", t))
            vm.msg = "Ringkasan disalin"
        })
    }
}

// ---------------------------------------------------------------- UJI PERFORMA
@Composable
fun BenchScreen(vm: AppViewModel) {
    BackBtn { vm.back() }
    key(vm.benchVer) {
        HsinCard {
            Label("Uji performa CPU")
            txt("Menjalankan hitungan berat 3 detik pada satu inti, lalu 3 detik pada semua inti. Biarkan HP tidak dipakai selama uji. Uji semua mode berjalan sendiri sekitar 1 menit (ada jeda dingin) lalu mengembalikan mode awalmu.", 12.sp, muted())
            if (vm.benchBusy && vm.benchStep.isNotEmpty()) txt(vm.benchStep, 13.sp, Mint, FontWeight.Medium, modifier = Modifier.padding(top = 6.dp))
            Pill(if (vm.benchBusy) "Menguji..." else "UJI SEMUA MODE (otomatis)", { vm.runBenchAll() }, solid = !vm.benchBusy, enabled = !vm.benchBusy)
            Pill(if (vm.benchBusy) "Menguji..." else "UJI MODE SAAT INI (${profileLabel(vm.status.profile)})", { vm.runBench() }, enabled = !vm.benchBusy)
        }
        val h = vm.prefs.benchHist
        if (h.isNotEmpty()) HsinCard {
            Label("Hasil (juta iterasi, makin tinggi makin kencang)")
            val mx = (h.maxOfOrNull { it[3].toLongOrNull() ?: 0L } ?: 1L).coerceAtLeast(1L)
            h.take(8).forEach { r ->
                val all = r[3].toLongOrNull() ?: 0L
                Column(Modifier.fillMaxWidth().padding(top = 8.dp)) {
                    Row(Modifier.fillMaxWidth()) {
                        txt(r[1], 13.sp, modifier = Modifier.weight(1f))
                        txt("1 inti ${r[2]}", 12.sp, muted(), modifier = Modifier.weight(1f))
                        txt("semua ${r[3]}", 12.sp, modifier = Modifier.weight(1f))
                    }
                    Box(Modifier.fillMaxWidth().padding(top = 4.dp).height(6.dp).clip(RoundedCornerShape(3.dp)).background(Color.White.copy(alpha = 0.08f))) {
                        Box(Modifier.fillMaxWidth(all.toFloat() / mx).height(6.dp).clip(RoundedCornerShape(3.dp)).background(Mint))
                    }
                }
            }
        }
    }
}

// ---------------------------------------------------------------- BATAS PENGISIAN
@Composable
fun ChargeScreen(vm: AppViewModel) {
    BackBtn { vm.back() }
    val ci = vm.chargeInfo
    val kind = ci["kind"].orEmpty()
    val lim = ci["limit"]?.toIntOrNull() ?: 100
    val steps = listOf(100, 95, 90, 85, 80, 70)
    HsinCard {
        Label("Batas pengisian")
        txt("Menghentikan pengisian di persen tertentu supaya baterai lebih awet. Berhasil atau tidaknya tergantung kernel HP: HSIN mencari node pengisian yang bisa dipakai.", 12.sp, muted())
        Spacer(Modifier.height(10.dp))
        when (kind) {
            "", "none" -> txt(if (ci.isEmpty()) "Memeriksa HP..." else "HP ini tidak punya kontrol pengisian yang bisa diatur. Fitur ini tidak tersedia di perangkatmu.", 13.sp)
            else -> {
                txt("Jenis kontrol: " + (if (kind == "thr") "batas persen kernel" else if (kind == "stop") "saklar stop_chg (eksperimen) + penjaga HSIN" else "saklar pengisian + penjaga HSIN"), 12.sp, muted())
                txt("Baterai ${ci["level"].orEmpty()}% · ${ci["status"].orEmpty()}", 13.sp)
                Spacer(Modifier.height(8.dp))
                Label("Batas isi")
                Seg(steps.map { if (it == 100) "OFF" else "$it%" }, steps.indexOf(lim).coerceAtLeast(0), { vm.setChargeLimit(steps[it]) })
                txt("OFF = isi sampai penuh seperti biasa. Batas dipulihkan otomatis saat HP restart dan dimatikan saat modul dihapus.", 11.sp, muted(), modifier = Modifier.padding(top = 6.dp))
            }
        }
    }
}

// ---------------------------------------------------------------- BATTERY LAB
@Composable
fun BatLabScreen(vm: AppViewModel) {
    BackBtn { vm.back() }
    val b = vm.battery
    HsinCard {
        Label("Battery Lab")
        txt(if (b.level >= 0) "${b.level}%" else "—", 28.sp, weight = FontWeight.Medium, modifier = Modifier.padding(bottom = 6.dp))
        KV("Status", b.status.ifEmpty { "—" })
        Divider()
        KV("Kondisi", b.health.ifEmpty { "—" })
        Divider()
        KV("Suhu baterai", "%.1f°C".format(b.tempC))
        Divider()
        KV("Tegangan", if (b.voltageMv > 0) "${b.voltageMv} mV" else "—")
        Divider()
        KV("Arus", if (b.currentMa != 0) "${kotlin.math.abs(b.currentMa)} mA" else "—")
        Divider()
        val w = kotlin.math.abs(b.voltageMv.toLong() * b.currentMa.toLong()) / 1_000_000f
        KV("Daya", if (b.currentMa != 0) "%.2f W".format(w) else "—")
        Divider()
        KV("Siklus", if (b.cycles >= 0) b.cycles.toString() else "—")
        Divider()
        KV("Kapasitas vs desain", if (b.healthPct >= 0) "${b.healthPct}%" else "—")
        Divider()
        KV("Teknologi", b.tech.ifEmpty { "—" })
    }
}
