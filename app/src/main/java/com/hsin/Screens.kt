package com.hsin

import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlin.math.roundToInt

// ======================= Banner =======================
@Composable
fun Banner(vm: HsinVm) {
    val p = LocalPal.current
    val shape = RoundedCornerShape(20.dp)
    Box(
        Modifier
            .fillMaxWidth()
            .height(124.dp)
            .clip(shape)
            .background(Color(0xFF2A2230))
            .border(0.5.dp, p.line, shape)
    ) {
        val bmp = vm.bannerBmp
        if (bmp != null) {
            Image(
                bitmap = bmp,
                contentDescription = null,
                contentScale = ContentScale.Crop,
                modifier = Modifier.fillMaxSize()
            )
        }
        Box(Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.35f)))
        Column(Modifier.align(Alignment.BottomStart).padding(16.dp)) {
            HText("HSIN CONTROL", size = 21.sp, color = Color(0xFFF4F1EC), spacing = 4.sp)
            HText("V5 · MANUAL", size = 11.sp, color = Color(0xFFF4F1EC).copy(alpha = 0.75f), spacing = 3.sp)
        }
        Box(
            Modifier
                .align(Alignment.TopEnd)
                .padding(10.dp)
                .size(36.dp)
                .clip(CircleShape)
                .background(Color.Black.copy(alpha = 0.4f))
                .clickable { vm.customOpen = true },
            contentAlignment = Alignment.Center
        ) {
            Icon(Icons.Filled.Settings, contentDescription = "Kustomisasi", tint = Color.White, modifier = Modifier.size(20.dp))
        }
    }
}

// ======================= Setup (root / modul) =======================
@Composable
fun SetupCard(vm: HsinVm) {
    val (title, body) = when (vm.setup) {
        Setup.Loading -> Pair("Memuat", "Menghubungi modul HSIN...")
        Setup.NoRoot -> Pair("Root tidak tersedia", "Beri izin root ke HSIN di Magisk / KernelSU / APatch, lalu coba lagi.")
        Setup.NoModule -> Pair("Modul belum aktif", "Pasang modul HSIN v5 dari Magisk lalu reboot. Setelah reboot, buka app ini lagi.")
        Setup.Ready -> Pair("", "")
    }
    HCard {
        Label(title)
        Spacer(Modifier.height(8.dp))
        HText(body, size = 12.sp, color = LocalPal.current.dim)
        if (vm.setup != Setup.Loading) {
            Spacer(Modifier.height(14.dp))
            HButton("Coba lagi", Modifier.fillMaxWidth(), primary = true) { vm.loadAll() }
        }
    }
}

// ======================= DASH =======================
@Composable
fun DashScreen(vm: HsinVm) {
    val p = LocalPal.current
    var presetOpen by remember { mutableStateOf(false) }
    var nameDialog by remember { mutableStateOf(false) }
    var confirmRestore by remember { mutableStateOf(false) }
    var delTarget by remember { mutableStateOf<Preset?>(null) }

    Column(
        Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .statusBarsPadding()
            .padding(start = 14.dp, end = 14.dp, top = 10.dp, bottom = 112.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        Banner(vm)
        if (vm.setup != Setup.Ready) {
            SetupCard(vm)
            return@Column
        }
        val st = vm.live
        if (st != null && st.safeMode) {
            HCard {
                Label("Mode aman aktif")
                Spacer(Modifier.height(8.dp))
                HText("Boot tidak selesai 3 kali berturut-turut, jadi setelan tidak diterapkan saat boot.", size = 12.sp, color = p.warn)
                Spacer(Modifier.height(12.dp))
                HButton("Matikan mode aman", Modifier.fillMaxWidth()) { vm.disableSafeMode() }
            }
        }
        HCard {
            Label("Status")
            Spacer(Modifier.height(6.dp))
            val d = vm.device
            InfoRow("Perangkat", if (d != null) "${d.brand} ${d.model}".trim() else "-")
            InfoRow("Chipset", if (d != null && d.soc.isNotEmpty()) d.soc else "-")
            InfoRow("Root", "Aktif")
            InfoRow("Modul", d?.module ?: "-")
        }
        HCard(onClick = { vm.openCat = null; vm.tab = 1 }) {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
                Column {
                    Label("Knob diubah")
                    Spacer(Modifier.height(4.dp))
                    HText(vm.changedCount.toString(), size = 30.sp, spacing = 1.sp)
                }
                HText("dari ${vm.supportedCount} didukung  ›", size = 12.sp, color = p.dim)
            }
        }
        HCard(padV = 4.dp) {
            Row(
                Modifier.fillMaxWidth().clickable { presetOpen = !presetOpen }.padding(vertical = 12.dp),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Label("Preset · eksperimental")
                HText("${vm.presets.size} tersimpan  " + if (presetOpen) "⌃" else "⌄", size = 12.sp, color = p.dim)
            }
            if (presetOpen) {
                for (pr in vm.presets) {
                    Divider()
                    Row(
                        Modifier.fillMaxWidth().padding(vertical = 8.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Column(Modifier.weight(1f)) {
                            HText(pr.name, size = 13.sp)
                            HText("${pr.values.size} knob", size = 11.sp, color = p.faint)
                        }
                        HButton("Muat", Modifier.width(76.dp)) { vm.loadPreset(pr) }
                        Spacer(Modifier.width(6.dp))
                        HButton("Hapus", Modifier.width(76.dp)) { delTarget = pr }
                    }
                }
                Divider()
                Spacer(Modifier.height(10.dp))
                HButton("Simpan setelan sekarang", Modifier.fillMaxWidth()) { nameDialog = true }
                Spacer(Modifier.height(10.dp))
                HText("Angka yang cocok beda tiap HP. Preset hanya menyimpan knob yang kamu ubah dari bawaan.", size = 11.sp, color = p.faint)
                Spacer(Modifier.height(8.dp))
            }
        }
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            HButton("Pulihkan bawaan", Modifier.weight(1f), enabled = !vm.busy) { confirmRestore = true }
            HButton(if (vm.refreshing) "Memeriksa..." else "Periksa ulang", Modifier.weight(1f), enabled = !vm.refreshing) { vm.loadAll(silent = true) }
        }
        HText(vm.lastApply, size = 11.sp, color = p.faint, modifier = Modifier.fillMaxWidth().padding(top = 2.dp), spacing = 0.8.sp)
    }

    if (nameDialog) {
        var name by remember { mutableStateOf("") }
        AlertDialog(
            onDismissRequest = { nameDialog = false },
            title = { HText("Nama preset", size = 15.sp) },
            text = {
                Box(Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(p.ghost).padding(12.dp)) {
                    BasicTextField(
                        value = name,
                        onValueChange = { name = it.take(24) },
                        singleLine = true,
                        textStyle = TextStyle(color = p.text, fontSize = 14.sp, fontFamily = FontFamily.Monospace),
                        cursorBrush = SolidColor(p.text),
                        modifier = Modifier.fillMaxWidth()
                    )
                    if (name.isEmpty()) HText("Preset ${vm.presets.size + 1}", size = 14.sp, color = p.faint)
                }
            },
            confirmButton = { TextButton(onClick = { vm.savePreset(name); nameDialog = false }) { HText("SIMPAN", size = 12.sp) } },
            dismissButton = { TextButton(onClick = { nameDialog = false }) { HText("BATAL", size = 12.sp, color = p.dim) } }
        )
    }
    if (confirmRestore) {
        AlertDialog(
            onDismissRequest = { confirmRestore = false },
            title = { HText("Pulihkan bawaan?", size = 15.sp) },
            text = { HText("Semua knob dikembalikan ke nilai bawaan HP dan setelan tersimpan dihapus. Preset tidak ikut terhapus.", size = 12.sp, color = p.dim) },
            confirmButton = { TextButton(onClick = { confirmRestore = false; vm.restoreDefaults() }) { HText("PULIHKAN", size = 12.sp) } },
            dismissButton = { TextButton(onClick = { confirmRestore = false }) { HText("BATAL", size = 12.sp, color = p.dim) } }
        )
    }
    val dt = delTarget
    if (dt != null) {
        AlertDialog(
            onDismissRequest = { delTarget = null },
            title = { HText("Hapus \"${dt.name}\"?", size = 15.sp) },
            confirmButton = { TextButton(onClick = { vm.deletePreset(dt); delTarget = null }) { HText("HAPUS", size = 12.sp, color = p.bad) } },
            dismissButton = { TextButton(onClick = { delTarget = null }) { HText("BATAL", size = 12.sp, color = p.dim) } }
        )
    }
}

// ======================= KNOB =======================
@Composable
fun KnobScreen(vm: HsinVm) {
    val p = LocalPal.current
    BackHandler(enabled = vm.openCat != null) { vm.openCat = null }
    val pc = vm.pendingList.size

    Column(
        Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .statusBarsPadding()
            .padding(start = 14.dp, end = 14.dp, top = 14.dp, bottom = 112.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        if (vm.setup != Setup.Ready) {
            Label("Knob")
            SetupCard(vm)
            return@Column
        }
        val cat = vm.cats.firstOrNull { it.id == vm.openCat }
        if (cat == null) {
            Label("Knob")
            HText("Ubah setelan sesukamu, lalu tekan Terapkan.", size = 12.sp, color = p.dim)
            Spacer(Modifier.height(2.dp))
            for (c in vm.cats) {
                val n = c.knobs.count { it.type != "locked" && ((vm.pending[it.key] ?: it.cur) != it.def) }
                val total = c.knobs.count { it.type != "locked" }
                HCard(onClick = { vm.openCat = c.id }, padV = 12.dp) {
                    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                        Column(Modifier.weight(1f)) {
                            HText(c.title.uppercase(), size = 14.sp, spacing = 1.6.sp)
                            HText("$total knob", size = 11.sp, color = p.faint)
                        }
                        if (n > 0) {
                            Box(Modifier.clip(CircleShape).background(p.pill).padding(horizontal = 9.dp, vertical = 2.dp)) {
                                HText("$n", size = 11.sp, color = p.onPill)
                            }
                            Spacer(Modifier.width(8.dp))
                        }
                        HText("›", size = 16.sp, color = p.dim)
                    }
                }
            }
        } else {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Box(
                    Modifier.size(36.dp).clip(CircleShape).clickable { vm.openCat = null },
                    contentAlignment = Alignment.Center
                ) {
                    Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Kembali", tint = p.text, modifier = Modifier.size(20.dp))
                }
                Spacer(Modifier.width(6.dp))
                Label(cat.title)
            }
            HCard(padV = 4.dp) {
                cat.knobs.forEachIndexed { i, k ->
                    if (i > 0) Divider()
                    KnobRow(vm, k)
                }
            }
        }
        Spacer(Modifier.height(6.dp))
        HButton(
            if (vm.busy) "Menerapkan..." else "Terapkan ($pc)",
            Modifier.fillMaxWidth(),
            primary = true,
            enabled = pc > 0 && !vm.busy
        ) { vm.applyPending() }
        if (pc > 0) {
            HButton("Batalkan perubahan", Modifier.fillMaxWidth(), enabled = !vm.busy) { vm.discardPending() }
        }
    }
}

@Composable
fun KnobRow(vm: HsinVm, k: Knob) {
    val p = LocalPal.current
    if (k.type == "locked") {
        Row(
            Modifier.fillMaxWidth().padding(vertical = 12.dp),
            horizontalArrangement = Arrangement.SpaceBetween
        ) {
            HText("🔒 ${k.label}", size = 12.sp, color = p.faint)
            HText(k.reason.ifEmpty { "Tidak didukung" }, size = 11.sp, color = p.faint)
        }
        return
    }
    val value = vm.valueOf(k)
    val changed = value != k.def
    Column(Modifier.fillMaxWidth().padding(vertical = 12.dp)) {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.Top) {
            HText((if (changed) "● " else "") + k.label, size = 12.sp, modifier = Modifier.weight(1f))
            HText("bawaan " + fmtFreq(k.unit, k.def), size = 11.sp, color = p.faint, modifier = Modifier.padding(start = 8.dp))
        }
        Spacer(Modifier.height(8.dp))
        if (k.type == "choice") {
            var open by remember { mutableStateOf(false) }
            Box {
                Row(
                    Modifier
                        .fillMaxWidth()
                        .clip(CircleShape)
                        .background(p.track)
                        .clickable { open = true }
                        .padding(horizontal = 14.dp, vertical = 10.dp),
                    horizontalArrangement = Arrangement.SpaceBetween
                ) {
                    HText(fmtFreq(k.unit, value), size = 12.sp)
                    HText("⌄", size = 12.sp, color = p.dim)
                }
                DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
                    for (o in k.options) {
                        DropdownMenuItem(
                            text = { HText(fmtFreq(k.unit, o), size = 13.sp) },
                            onClick = { vm.setPending(k, o); open = false }
                        )
                    }
                }
            }
        } else {
            val cur = value.toIntOrNull() ?: k.min
            Row(verticalAlignment = Alignment.CenterVertically) {
                Slider(
                    value = cur.toFloat(),
                    onValueChange = { f ->
                        val snapped = (k.min + ((f - k.min) / k.step).roundToInt() * k.step).coerceIn(k.min, k.max)
                        if (snapped.toString() != value) vm.setPending(k, snapped.toString())
                    },
                    valueRange = k.min.toFloat()..k.max.toFloat(),
                    colors = SliderDefaults.colors(
                        thumbColor = p.pill,
                        activeTrackColor = p.pill,
                        inactiveTrackColor = p.line
                    ),
                    modifier = Modifier.weight(1f)
                )
                HText(cur.toString(), size = 13.sp, modifier = Modifier.width(48.dp))
            }
        }
    }
}

// ======================= MONITOR =======================
@Composable
fun MonitorScreen(vm: HsinVm) {
    val p = LocalPal.current
    Column(
        Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .statusBarsPadding()
            .padding(start = 14.dp, end = 14.dp, top = 14.dp, bottom = 112.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        Label("Monitor")
        if (vm.setup != Setup.Ready) { SetupCard(vm); return@Column }
        Segmented(listOf("Live", "Log"), vm.monitorMode, {
            vm.monitorMode = it
            if (it == 1) vm.loadLogs()
        })
        if (vm.monitorMode == 0) {
            val st = vm.live
            HCard {
                MonRow("Suhu", vm.hCpuTemp, if (st != null && st.cpuTemp > 0) "${st.cpuTemp}°C" else "N/A")
                MonRow("CPU", vm.hCpuMhz, if (st != null && st.cpuKhz > 0) "${st.cpuKhz / 1000} MHz" else "N/A")
                MonRow("GPU", vm.hGpuMhz, if (st != null && st.gpuHz > 0) "${st.gpuHz / 1000000} MHz" else "N/A")
                MonRow("RAM", vm.hRamGb, if (st != null && st.ramUsedKb > 0) String.format(java.util.Locale.US, "%.1f GB", st.ramUsedKb / 1048576.0) else "N/A")
            }
            HCard(padV = 6.dp) {
                InfoRow("Suhu GPU", if (st != null && st.gpuTemp > 0) "${st.gpuTemp}°C" else "N/A")
                InfoRow("Beban CPU", if (st != null) String.format(java.util.Locale.US, "%.2f", st.loadX100 / 100.0) else "N/A")
                InfoRow("Baterai", if (st != null && st.batPct >= 0) "${st.batPct}%" + (if (st.batTemp > 0) " · ${st.batTemp}°C" else "") else "N/A")
            }
            HButton(if (vm.paused) "Lanjut" else "Jeda", Modifier.fillMaxWidth()) { vm.paused = !vm.paused }
            HText(if (vm.paused) "Dijeda" else "Diperbarui tiap 2 detik", size = 11.sp, color = p.faint, modifier = Modifier.fillMaxWidth())
        } else {
            Segmented(listOf("boot", "apply"), vm.logWhich, {
                vm.logWhich = it
                vm.loadLogs()
            })
            HCard(padV = 8.dp) {
                if (vm.logLines.isEmpty()) {
                    HText("Log kosong", size = 12.sp, color = p.faint, modifier = Modifier.padding(vertical = 8.dp))
                }
                for (line in vm.logLines) {
                    val parts = line.split(" ", limit = 4)
                    val lvl = if (parts.size >= 4) parts[2] else ""
                    val msg = if (parts.size >= 4) parts[3] else line
                    val col = when (lvl) {
                        "WARN" -> p.warn
                        "ERROR" -> p.bad
                        else -> p.dim
                    }
                    Row(Modifier.fillMaxWidth().padding(vertical = 4.dp)) {
                        HText(lvl.ifEmpty { "-" }, size = 11.sp, color = col, modifier = Modifier.width(46.dp))
                        HText(msg, size = 11.sp, modifier = Modifier.weight(1f))
                    }
                }
            }
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                HButton("Salin laporan", Modifier.weight(1f)) { vm.copyReport() }
                HButton("Muat ulang", Modifier.weight(1f)) { vm.loadLogs() }
            }
        }
    }
}

@Composable
fun MonRow(name: String, hist: List<Float>, value: String) {
    val p = LocalPal.current
    Row(Modifier.fillMaxWidth().padding(vertical = 9.dp), verticalAlignment = Alignment.CenterVertically) {
        HText(name, size = 12.sp, color = p.dim, modifier = Modifier.width(48.dp))
        Sparkline(hist, Modifier.weight(1f).height(26.dp))
        HText(value, size = 12.sp, modifier = Modifier.width(78.dp).padding(start = 8.dp))
    }
}

// ======================= CUSTOM (gear) =======================
@Composable
fun CustomScreen(vm: HsinVm) {
    val p = LocalPal.current
    BackHandler { vm.customOpen = false }
    val pickBanner = rememberLauncherForActivityResult(ActivityResultContracts.GetContent()) { uri ->
        if (uri != null) vm.setImage(uri, true)
    }
    val pickWall = rememberLauncherForActivityResult(ActivityResultContracts.GetContent()) { uri ->
        if (uri != null) vm.setImage(uri, false)
    }
    Column(
        Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .statusBarsPadding()
            .padding(start = 14.dp, end = 14.dp, top = 14.dp, bottom = 40.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.size(36.dp).clip(CircleShape).clickable { vm.customOpen = false }, contentAlignment = Alignment.Center) {
                Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Kembali", tint = p.text, modifier = Modifier.size(20.dp))
            }
            Spacer(Modifier.width(6.dp))
            Label("Custom")
        }
        HCard {
            Label("Banner")
            Spacer(Modifier.height(10.dp))
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                HButton("Pilih gambar", Modifier.weight(1f)) { pickBanner.launch("image/*") }
                HButton("Reset", Modifier.weight(1f)) { vm.resetImage(true) }
            }
            Spacer(Modifier.height(8.dp))
            HText("Hanya tampil di Dash. Gambar dipotong otomatis agar pas, tidak gepeng.", size = 11.sp, color = p.faint)
        }
        HCard {
            Label("Wallpaper")
            Spacer(Modifier.height(10.dp))
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                HButton("Pilih gambar", Modifier.weight(1f)) { pickWall.launch("image/*") }
                HButton("Reset", Modifier.weight(1f)) { vm.resetImage(false) }
            }
            Spacer(Modifier.height(16.dp))
            Label("Transparansi kartu")
            Slider(
                value = vm.cardAlpha,
                onValueChange = { vm.cardAlpha = it },
                onValueChangeFinished = { vm.setCardAlpha(vm.cardAlpha) },
                valueRange = 0.15f..0.9f,
                colors = SliderDefaults.colors(thumbColor = p.pill, activeTrackColor = p.pill, inactiveTrackColor = p.line)
            )
        }
        HCard {
            Label("Tema")
            Spacer(Modifier.height(10.dp))
            Segmented(listOf("Gelap", "Terang", "Sistem"), vm.theme, { vm.setTheme(it) })
        }
    }
}

// ======================= Nav, Toast, Root =======================
@Composable
fun BottomNav(vm: HsinVm, modifier: Modifier) {
    val p = LocalPal.current
    Row(
        modifier
            .padding(horizontal = 12.dp, vertical = 12.dp)
            .fillMaxWidth()
            .clip(CircleShape)
            .background(p.navBg)
            .border(0.5.dp, p.line, CircleShape)
            .padding(5.dp)
    ) {
        listOf("Dash", "Knob", "Monitor").forEachIndexed { i, t ->
            val sel = vm.tab == i
            Box(
                Modifier
                    .weight(1f)
                    .clip(CircleShape)
                    .background(if (sel) p.pill else Color.Transparent)
                    .clickable {
                        if (vm.tab == i && i == 1) vm.openCat = null
                        vm.tab = i
                        if (i == 2 && vm.monitorMode == 1) vm.loadLogs()
                    }
                    .padding(vertical = 13.dp),
                contentAlignment = Alignment.Center
            ) {
                HText(t.uppercase(), size = 11.sp, color = if (sel) p.onPill else p.dim, spacing = 1.6.sp)
            }
        }
    }
}

@Composable
fun MessageBar(vm: HsinVm, modifier: Modifier) {
    val p = LocalPal.current
    val m = vm.message ?: return
    androidx.compose.runtime.LaunchedEffect(m) {
        kotlinx.coroutines.delay(3000)
        if (vm.message == m) vm.message = null
    }
    Box(
        modifier
            .padding(horizontal = 24.dp)
            .clip(RoundedCornerShape(16.dp))
            .background(p.pill)
            .padding(horizontal = 16.dp, vertical = 10.dp)
    ) {
        HText(m, size = 12.sp, color = p.onPill)
    }
}

@Composable
fun FailureDialog(vm: HsinVm) {
    val p = LocalPal.current
    if (vm.failures.isEmpty()) return
    AlertDialog(
        onDismissRequest = { vm.failures = emptyList() },
        title = { HText("Sebagian gagal diterapkan", size = 15.sp) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                for (f in vm.failures) {
                    HText(f.first + ": " + f.second.ifEmpty { "ditolak" }, size = 12.sp, color = p.dim)
                }
            }
        },
        confirmButton = { TextButton(onClick = { vm.failures = emptyList() }) { HText("OKE", size = 12.sp) } }
    )
}
