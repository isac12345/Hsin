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
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
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
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
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

private val SCREEN_PAD = 14.dp
private val NAV_SPACE = 112.dp

@Composable
private fun ScreenColumn(content: @Composable androidx.compose.foundation.layout.ColumnScope.() -> Unit) {
    Column(
        Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .statusBarsPadding()
            .padding(start = SCREEN_PAD, end = SCREEN_PAD, top = 12.dp, bottom = NAV_SPACE),
        verticalArrangement = Arrangement.spacedBy(10.dp),
        content = content
    )
}

@Composable
private fun Title(text: String) {
    // Judul ditaruh di dalam kartu tipis supaya tetap terbaca di atas wallpaper terang.
    val p = LocalPal.current
    Box(
        Modifier
            .clip(CircleShape)
            .background(p.card)
            .border(0.5.dp, p.line, CircleShape)
            .padding(horizontal = 14.dp, vertical = 6.dp)
    ) { Label(text) }
}

@Composable
private fun BackRow(title: String, onBack: () -> Unit) {
    val p = LocalPal.current
    Row(verticalAlignment = Alignment.CenterVertically) {
        Box(
            Modifier.size(38.dp).clip(CircleShape).background(p.card).clickable { onBack() },
            contentAlignment = Alignment.Center
        ) {
            Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Kembali", tint = p.text, modifier = Modifier.size(20.dp))
        }
        Spacer(Modifier.width(8.dp))
        Title(title)
    }
}

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
            Image(bitmap = bmp, contentDescription = null, contentScale = ContentScale.Crop, modifier = Modifier.fillMaxSize())
        }
        Box(Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.40f)))
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
                .background(Color.Black.copy(alpha = 0.45f))
                .clickable { vm.customOpen = true },
            contentAlignment = Alignment.Center
        ) {
            Icon(Icons.Filled.Settings, contentDescription = "Pengaturan", tint = Color.White, modifier = Modifier.size(20.dp))
        }
    }
}

@Composable
fun SetupCard(vm: HsinVm) {
    val (title, body) = when (vm.setup) {
        Setup.Loading -> Pair("Memuat", "Menghubungi modul HSIN...")
        Setup.NoRoot -> Pair("Root tidak tersedia", "Beri izin root ke HSIN di Magisk / KernelSU / APatch, lalu coba lagi.")
        Setup.NoModule -> Pair("Modul belum aktif", "Pasang modul HSIN v5 lalu reboot. Setelah reboot, buka app ini lagi.")
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

    ScreenColumn {
        Banner(vm)
        if (vm.setup != Setup.Ready) {
            SetupCard(vm)
            return@ScreenColumn
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
        if (st != null && st.thermalTrip) {
            HCard {
                Label("Pengaman panas aktif")
                Spacer(Modifier.height(8.dp))
                HText("Suhu melewati ${vm.thermal.limit}°C. Setelan dikembalikan ke bawaan sementara.", size = 12.sp, color = p.warn)
                Spacer(Modifier.height(12.dp))
                HButton("Terapkan lagi", Modifier.fillMaxWidth(), enabled = !vm.busy) { vm.ackThermal() }
            }
        }
        if (vm.conflicts.isNotEmpty() && !vm.conflictHidden) {
            HCard {
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
                    HText("MODUL LAIN AKTIF", size = 11.sp, color = p.warn, spacing = 2.sp)
                    Box(Modifier.size(28.dp).clip(CircleShape).clickable { vm.conflictHidden = true }, contentAlignment = Alignment.Center) {
                        HText("×", size = 16.sp, color = p.dim)
                    }
                }
                Spacer(Modifier.height(6.dp))
                HText(vm.conflicts.joinToString(", ") + " terdeteksi. Node yang mereka pegang akan ditolak. Matikan modulnya, reboot, lalu terapkan lagi.", size = 12.sp)
            }
        }
        HCard {
            Label("Status")
            Spacer(Modifier.height(6.dp))
            val d = vm.device
            InfoRow("Perangkat", if (d != null) "${d.brand} ${d.model}".trim() else "-")
            InfoRow("Chipset", if (d != null && d.soc.isNotEmpty()) d.soc else "-")
            InfoRow("Root · Modul", "Aktif · ${d?.module ?: "-"}")
            InfoRow("Pengaman panas", if (vm.thermal.on) "${vm.thermal.limit}°C · aktif" else "nonaktif")
            InfoRow("Per game", if (st != null && st.gameMode) "aktif · ${vm.games.size} game" else "nonaktif")
        }
        HCard(onClick = { vm.goTab(1) }) {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
                Column {
                    Label("Knob global diubah")
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
                    Column(Modifier.fillMaxWidth().padding(vertical = 10.dp)) {
                        HText(pr.name, size = 13.sp)
                        HText("${pr.values.size} knob", size = 11.sp, color = p.faint)
                        Spacer(Modifier.height(8.dp))
                        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                            HButton("Muat", Modifier.weight(1f)) { vm.loadPreset(pr) }
                            HButton("Ekspor", Modifier.weight(1f)) { vm.exportPreset(pr) }
                            HButton("Hapus", Modifier.weight(1f)) { delTarget = pr }
                        }
                    }
                }
                Divider()
                Spacer(Modifier.height(10.dp))
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    HButton("Simpan setelan", Modifier.weight(1f)) { nameDialog = true }
                    HButton("Impor", Modifier.weight(1f)) { vm.importPreset() }
                }
                Spacer(Modifier.height(10.dp))
                HText("Angka yang cocok beda tiap HP. Impor membaca kode preset dari clipboard.", size = 11.sp, color = p.faint)
                Spacer(Modifier.height(8.dp))
            }
        }
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            HButton("Pulihkan bawaan", Modifier.weight(1f), enabled = !vm.busy) { confirmRestore = true }
            HButton(if (vm.refreshing) "Memeriksa..." else "Periksa ulang", Modifier.weight(1f), enabled = !vm.refreshing) {
                vm.conflictHidden = false
                vm.loadAll(silent = true)
            }
        }
        HText(vm.lastApply, size = 11.sp, color = p.dim, modifier = Modifier.fillMaxWidth().padding(top = 2.dp), spacing = 0.8.sp)
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
            text = { HText("Semua knob global dikembalikan ke nilai bawaan HP. Preset dan profil game tidak ikut terhapus.", size = 12.sp, color = p.dim) },
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

// ======================= Kontrol knob (dipakai Knob dan editor game) =======================
@Composable
fun KnobControl(k: Knob, value: String, onChange: (String) -> Unit) {
    val p = LocalPal.current
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
                        onClick = { onChange(o); open = false }
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
                    if (snapped.toString() != value) onChange(snapped.toString())
                },
                valueRange = k.min.toFloat()..k.max.toFloat(),
                colors = SliderDefaults.colors(thumbColor = p.pill, activeTrackColor = p.pill, inactiveTrackColor = p.track),
                modifier = Modifier.weight(1f)
            )
            HText(cur.toString(), size = 13.sp, modifier = Modifier.width(48.dp))
        }
    }
}

@Composable
fun KnobRow(vm: HsinVm, k: Knob) {
    val p = LocalPal.current
    if (k.type == "locked") {
        Row(Modifier.fillMaxWidth().padding(vertical = 12.dp), horizontalArrangement = Arrangement.SpaceBetween) {
            HText("🔒 ${k.label}", size = 12.sp, color = p.faint, modifier = Modifier.weight(1f))
            HText(k.reason.ifEmpty { "Tidak didukung" }, size = 11.sp, color = p.faint)
        }
        return
    }
    val value = vm.valueOf(k)
    val changed = value != k.def
    Column(Modifier.fillMaxWidth().padding(vertical = 12.dp)) {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
            HText((if (changed) "● " else "") + k.label, size = 12.sp, modifier = Modifier.weight(1f))
            if (changed) {
                Box(
                    Modifier.clip(CircleShape).border(0.5.dp, p.line, CircleShape).clickable { vm.resetKnob(k) }.padding(horizontal = 10.dp, vertical = 3.dp)
                ) { HText("↺ bawaan", size = 11.sp, color = p.dim) }
            } else {
                HText("bawaan " + fmtFreq(k.unit, k.def), size = 11.sp, color = p.faint)
            }
        }
        Spacer(Modifier.height(8.dp))
        KnobControl(k, value) { vm.setPending(k, it) }
    }
}

// ======================= KNOB =======================
@Composable
fun KnobScreen(vm: HsinVm) {
    val p = LocalPal.current
    BackHandler(enabled = vm.openCat != null) { vm.openCat = null }
    val pc = vm.pendingList.size

    ScreenColumn {
        if (vm.setup != Setup.Ready) {
            Title("Knob")
            SetupCard(vm)
            return@ScreenColumn
        }
        val cat = vm.cats.firstOrNull { it.id == vm.openCat }
        if (cat == null) {
            Title("Knob · Global")
            HText("Ubah setelan sesukamu, lalu tekan Terapkan.", size = 12.sp, color = p.dim)
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
            BackRow(cat.title) { vm.openCat = null }
            HCard(padV = 4.dp) {
                cat.knobs.forEachIndexed { i, k ->
                    if (i > 0) Divider()
                    KnobRow(vm, k)
                }
            }
        }
        Spacer(Modifier.height(4.dp))
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

// ======================= GAMES =======================
@Composable
fun GamesScreen(vm: HsinVm) {
    val p = LocalPal.current
    var picker by remember { mutableStateOf(false) }
    BackHandler(enabled = vm.openGame != null) { vm.openGame = null }
    val og = vm.openGame
    if (og != null && vm.games.any { it.pkg == og }) {
        GameEditor(vm, og)
        return
    }
    ScreenColumn {
        Title("Games")
        if (vm.setup != Setup.Ready) { SetupCard(vm); return@ScreenColumn }
        val st = vm.live
        val on = st?.gameMode ?: false
        HCard {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
                HText("Otomatis per game", size = 13.sp)
                Switch(
                    checked = on,
                    onCheckedChange = { vm.toggleGameMode(it) },
                    colors = SwitchDefaults.colors(
                        checkedThumbColor = p.onPill, checkedTrackColor = p.accent,
                        uncheckedThumbColor = p.dim, uncheckedTrackColor = p.track, uncheckedBorderColor = p.line
                    )
                )
            }
            Spacer(Modifier.height(4.dp))
            HText("Eksperimental. Game dibuka: pakai setelan game itu. Game ditutup: balik ke Global.", size = 11.sp, color = p.dim)
        }
        HCard {
            Label("Aktif sekarang")
            Spacer(Modifier.height(4.dp))
            val act = st?.gameActive.orEmpty()
            HText(if (act.isEmpty()) "Global" else vm.gameLabel(act), size = 14.sp)
        }
        for (g in vm.games) {
            HCard(onClick = { vm.openGame = g.pkg }, padV = 12.dp) {
                Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                    Column(Modifier.weight(1f)) {
                        HText(g.label, size = 14.sp)
                        HText(g.pkg, size = 11.sp, color = p.faint)
                    }
                    if (g.values.isEmpty()) HText("ikut Global", size = 11.sp, color = p.dim)
                    else Box(Modifier.clip(CircleShape).background(p.pill).padding(horizontal = 9.dp, vertical = 2.dp)) {
                        HText("${g.values.size} knob", size = 11.sp, color = p.onPill)
                    }
                    Spacer(Modifier.width(8.dp))
                    HText("›", size = 16.sp, color = p.dim)
                }
            }
        }
        HButton("+ Tambah game", Modifier.fillMaxWidth()) { vm.loadApps(); picker = true }
    }
    if (picker) AppPicker(vm, onDismiss = { picker = false }) { vm.addGame(it); picker = false }
}

@Composable
fun AppPicker(vm: HsinVm, onDismiss: () -> Unit, onPick: (AppItem) -> Unit) {
    val p = LocalPal.current
    var q by remember { mutableStateOf("") }
    val shown = vm.apps.filter { a ->
        vm.games.none { it.pkg == a.pkg } && (q.isBlank() || a.label.contains(q, true) || a.pkg.contains(q, true))
    }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { HText("Pilih game", size = 15.sp) },
        text = {
            Column {
                Box(Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(p.ghost).padding(12.dp)) {
                    BasicTextField(
                        value = q,
                        onValueChange = { q = it.take(40) },
                        singleLine = true,
                        textStyle = TextStyle(color = p.text, fontSize = 14.sp, fontFamily = FontFamily.Monospace),
                        cursorBrush = SolidColor(p.text),
                        modifier = Modifier.fillMaxWidth()
                    )
                    if (q.isEmpty()) HText("Cari aplikasi", size = 14.sp, color = p.faint)
                }
                Spacer(Modifier.height(8.dp))
                if (vm.appsLoading && vm.apps.isEmpty()) {
                    HText("Memuat daftar aplikasi...", size = 12.sp, color = p.dim)
                } else {
                    LazyColumn(Modifier.heightIn(max = 340.dp)) {
                        items(shown, key = { it.pkg }) { a ->
                            Column(Modifier.fillMaxWidth().clickable { onPick(a) }.padding(vertical = 8.dp)) {
                                HText(a.label, size = 13.sp)
                                HText(a.pkg, size = 11.sp, color = p.faint)
                            }
                        }
                    }
                }
            }
        },
        confirmButton = {},
        dismissButton = { TextButton(onClick = onDismiss) { HText("TUTUP", size = 12.sp, color = p.dim) } }
    )
}

@Composable
fun GameEditor(vm: HsinVm, pkg: String) {
    val p = LocalPal.current
    val g = vm.games.firstOrNull { it.pkg == pkg } ?: return
    var addKnob by remember { mutableStateOf(false) }
    var copyPreset by remember { mutableStateOf(false) }
    var confirmDel by remember { mutableStateOf(false) }

    ScreenColumn {
        BackRow(g.label) { vm.openGame = null }
        HCard {
            HText("Atur sesukamu. Knob yang tidak ada di sini ikut Global. Tersimpan otomatis.", size = 12.sp, color = p.dim)
            Spacer(Modifier.height(4.dp))
            HText("${g.values.size} knob diatur untuk game ini", size = 12.sp)
        }
        if (g.values.isNotEmpty()) {
            HCard(padV = 4.dp) {
                var first = true
                for ((key, value) in g.values) {
                    val k = vm.knobByKey(key)
                    if (!first) Divider()
                    first = false
                    if (k == null) {
                        Row(Modifier.fillMaxWidth().padding(vertical = 12.dp), horizontalArrangement = Arrangement.SpaceBetween) {
                            HText(key, size = 12.sp, color = p.faint, modifier = Modifier.weight(1f))
                            HText("tidak ada di HP ini", size = 11.sp, color = p.faint)
                        }
                        continue
                    }
                    Column(Modifier.fillMaxWidth().padding(vertical = 12.dp)) {
                        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
                            HText("● " + k.label, size = 12.sp, modifier = Modifier.weight(1f))
                            Box(
                                Modifier.clip(CircleShape).border(0.5.dp, p.line, CircleShape)
                                    .clickable { vm.removeGameKnob(pkg, key) }.padding(horizontal = 10.dp, vertical = 3.dp)
                            ) { HText("↺ Global", size = 11.sp, color = p.dim) }
                        }
                        Spacer(Modifier.height(8.dp))
                        KnobControl(k, value) { vm.setGameValue(pkg, key, it) }
                    }
                }
            }
        }
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            HButton("+ Tambah knob", Modifier.weight(1f)) { addKnob = true }
            HButton("Salin preset", Modifier.weight(1f), enabled = vm.presets.isNotEmpty()) { copyPreset = true }
        }
        HButton("Hapus game", Modifier.fillMaxWidth()) { confirmDel = true }
    }

    if (addKnob) {
        val free = vm.cats.map { c -> Pair(c, c.knobs.filter { it.type != "locked" && !g.values.containsKey(it.key) }) }.filter { it.second.isNotEmpty() }
        AlertDialog(
            onDismissRequest = { addKnob = false },
            title = { HText("Tambah knob", size = 15.sp) },
            text = {
                LazyColumn(Modifier.heightIn(max = 380.dp)) {
                    for ((c, ks) in free) {
                        item(key = "h_" + c.id) { Label(c.title) }
                        items(ks, key = { it.key }) { k ->
                            Column(Modifier.fillMaxWidth().clickable { vm.addKnobToGame(pkg, k); addKnob = false }.padding(vertical = 8.dp)) {
                                HText(k.label, size = 12.sp)
                            }
                        }
                    }
                }
            },
            confirmButton = {},
            dismissButton = { TextButton(onClick = { addKnob = false }) { HText("TUTUP", size = 12.sp, color = p.dim) } }
        )
    }
    if (copyPreset) {
        AlertDialog(
            onDismissRequest = { copyPreset = false },
            title = { HText("Salin dari preset", size = 15.sp) },
            text = {
                Column {
                    for (pr in vm.presets) {
                        Column(Modifier.fillMaxWidth().clickable { vm.copyPresetToGame(pkg, pr); copyPreset = false }.padding(vertical = 8.dp)) {
                            HText(pr.name, size = 13.sp)
                            HText("${pr.values.size} knob", size = 11.sp, color = p.faint)
                        }
                    }
                }
            },
            confirmButton = {},
            dismissButton = { TextButton(onClick = { copyPreset = false }) { HText("TUTUP", size = 12.sp, color = p.dim) } }
        )
    }
    if (confirmDel) {
        AlertDialog(
            onDismissRequest = { confirmDel = false },
            title = { HText("Hapus ${g.label}?", size = 15.sp) },
            text = { HText("Profil game ini dihapus. Game kembali memakai Global.", size = 12.sp, color = p.dim) },
            confirmButton = { TextButton(onClick = { confirmDel = false; vm.removeGame(pkg) }) { HText("HAPUS", size = 12.sp, color = p.bad) } },
            dismissButton = { TextButton(onClick = { confirmDel = false }) { HText("BATAL", size = 12.sp, color = p.dim) } }
        )
    }
}

// ======================= MONITOR =======================
private fun gb(kb: Long): String = String.format(java.util.Locale.US, "%.1f", kb / 1048576.0)

@Composable
private fun MetricRow(name: String, value: String, fraction: Float, hot: Boolean = false, sub: String = "") {
    val p = LocalPal.current
    Column(Modifier.fillMaxWidth().padding(vertical = 7.dp)) {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            HText(name, size = 12.sp, color = p.dim)
            HText(value, size = 13.sp)
        }
        Spacer(Modifier.height(6.dp))
        Bar(fraction, hot = hot)
        if (sub.isNotEmpty()) {
            Spacer(Modifier.height(4.dp))
            HText(sub, size = 11.sp, color = p.faint)
        }
    }
}

@Composable
fun MonitorScreen(vm: HsinVm) {
    val p = LocalPal.current
    ScreenColumn {
        Title("Monitor")
        if (vm.setup != Setup.Ready) { SetupCard(vm); return@ScreenColumn }
        Segmented(listOf("Live", "Log"), vm.monitorMode, {
            vm.monitorMode = it
            if (it == 1) vm.loadLogs()
        })
        if (vm.monitorMode == 0) {
            val st = vm.live
            if (st == null) {
                HCard { HText("Belum ada data", size = 12.sp, color = p.dim) }
            } else {
                val lim = vm.thermal.limit
                HCard {
                    Label("CPU")
                    MetricRow(
                        "Pemakaian", if (vm.cpuUsage >= 0) "${vm.cpuUsage}%" else "mengukur...",
                        if (vm.cpuUsage >= 0) vm.cpuUsage / 100f else 0f,
                        sub = "load rata-rata ${String.format(java.util.Locale.US, "%.2f", st.loadX100 / 100.0)} · ${st.cores} core"
                    )
                    for (pl in st.policies) {
                        MetricRow(
                            "policy${pl.id} · ${pl.gov}",
                            fmtFreq("khz", pl.cur.toString()),
                            if (pl.hw > 0) pl.cur.toFloat() / pl.hw.toFloat() else 0f,
                            sub = "batas ${fmtFreq("khz", pl.min.toString())} sampai ${fmtFreq("khz", pl.max.toString())}"
                        )
                    }
                }
                HCard {
                    Label("GPU")
                    MetricRow(
                        if (st.gpuGov.isEmpty()) "Frekuensi" else "Frekuensi · ${st.gpuGov}",
                        if (st.gpuHz > 0) fmtFreq("hz", st.gpuHz.toString()) else "N/A",
                        if (st.gpuMaxHz > 0) st.gpuHz.toFloat() / st.gpuMaxHz.toFloat() else 0f,
                        sub = if (st.gpuMaxHz > 0) "batas atas ${fmtFreq("hz", st.gpuMaxHz.toString())}" else ""
                    )
                }
                HCard {
                    Label("Suhu")
                    val temps = listOf(
                        Pair("CPU", st.cpuTemp), Pair("GPU", st.gpuTemp),
                        Pair("Baterai", st.batTemp), Pair("Tertinggi", st.tempMax)
                    )
                    for ((nm, t) in temps) {
                        MetricRow(nm, if (t > 0) "$t°C" else "N/A", if (t > 0) (t - 20f) / 80f else 0f, hot = t >= lim - 5 && t > 0)
                    }
                    HText("Skala 20 sampai 100°C. Batas pengaman panas $lim°C.", size = 11.sp, color = p.faint)
                }
                HCard {
                    Label("Memori")
                    MetricRow(
                        "RAM", "${gb(st.ramUsedKb)} / ${gb(st.ramTotalKb)} GB",
                        if (st.ramTotalKb > 0) st.ramUsedKb.toFloat() / st.ramTotalKb.toFloat() else 0f
                    )
                    if (st.swapTotalKb > 0) {
                        MetricRow(
                            "Swap", "${gb(st.swapUsedKb)} / ${gb(st.swapTotalKb)} GB",
                            st.swapUsedKb.toFloat() / st.swapTotalKb.toFloat()
                        )
                    }
                }
                HCard {
                    Label("Baterai")
                    MetricRow(
                        if (st.charging) "Mengisi daya" else "Menggunakan baterai",
                        if (st.batPct >= 0) "${st.batPct}%" else "N/A",
                        if (st.batPct >= 0) st.batPct / 100f else 0f
                    )
                }
            }
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                HButton(if (vm.paused) "Lanjut" else "Jeda", Modifier.weight(1f)) { vm.paused = !vm.paused }
            }
            Segmented(listOf("1 dtk", "2 dtk", "5 dtk"), when (vm.monitorMs) { 1000 -> 0; 5000 -> 2; else -> 1 }, {
                vm.applyMonitorMs(when (it) { 0 -> 1000; 2 -> 5000; else -> 2000 })
            })
        } else {
            Segmented(listOf("boot", "apply", "game"), vm.logWhich, {
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

// ======================= PENGATURAN (gear di banner) =======================
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
    var limit by remember { mutableStateOf(vm.thermal.limit.toFloat()) }
    LaunchedEffect(vm.thermal.limit) { limit = vm.thermal.limit.toFloat() }

    Column(
        Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .statusBarsPadding()
            .padding(start = SCREEN_PAD, end = SCREEN_PAD, top = 12.dp, bottom = 40.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        BackRow("Pengaturan") { vm.customOpen = false }
        HCard {
            Label("Tema")
            Spacer(Modifier.height(10.dp))
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                HButton(THEME_NAMES[0], Modifier.weight(1f), primary = vm.theme == 0) { vm.applyTheme(0) }
                HButton(THEME_NAMES[1], Modifier.weight(1f), primary = vm.theme == 1) { vm.applyTheme(1) }
            }
            Spacer(Modifier.height(8.dp))
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                HButton(THEME_NAMES[2], Modifier.weight(1f), primary = vm.theme == 2) { vm.applyTheme(2) }
                HButton(THEME_NAMES[3], Modifier.weight(1f), primary = vm.theme == 3) { vm.applyTheme(3) }
            }
        }
        HCard {
            Label("Banner")
            Spacer(Modifier.height(10.dp))
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                HButton("Pilih gambar", Modifier.weight(1f)) { pickBanner.launch("image/*") }
                HButton("Reset", Modifier.weight(1f)) { vm.resetImage(true) }
            }
            Spacer(Modifier.height(8.dp))
            HText("Hanya tampil di Dash. Gambar dipotong otomatis agar pas, tidak gepeng.", size = 11.sp, color = p.dim)
        }
        HCard {
            Label("Wallpaper")
            Spacer(Modifier.height(10.dp))
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                HButton("Pilih gambar", Modifier.weight(1f)) { pickWall.launch("image/*") }
                HButton("Reset", Modifier.weight(1f)) { vm.resetImage(false) }
            }
            Spacer(Modifier.height(8.dp))
            HText("Wallpaper bawaan hanya tampil di tema Carbon. Gambar pilihanmu tampil di semua tema.", size = 11.sp, color = p.dim)
            Spacer(Modifier.height(14.dp))
            Label("Kepekatan kartu")
            Slider(
                value = vm.cardAlpha,
                onValueChange = { vm.cardAlpha = it },
                onValueChangeFinished = { vm.applyCardAlpha(vm.cardAlpha) },
                valueRange = 0.30f..0.95f,
                colors = SliderDefaults.colors(thumbColor = p.pill, activeTrackColor = p.pill, inactiveTrackColor = p.track)
            )
        }
        HCard {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
                Label("Pengaman panas")
                Switch(
                    checked = vm.thermal.on,
                    onCheckedChange = { vm.updateThermal(it, vm.thermal.limit) },
                    colors = SwitchDefaults.colors(
                        checkedThumbColor = p.onPill, checkedTrackColor = p.accent,
                        uncheckedThumbColor = p.dim, uncheckedTrackColor = p.track, uncheckedBorderColor = p.line
                    )
                )
            }
            Spacer(Modifier.height(6.dp))
            HText("Jika suhu CPU melewati batas, semua setelan dikembalikan ke bawaan sampai kamu menerapkannya lagi.", size = 11.sp, color = p.dim)
            Row(verticalAlignment = Alignment.CenterVertically) {
                Slider(
                    value = limit,
                    onValueChange = { limit = it.roundToInt().toFloat() },
                    onValueChangeFinished = { vm.updateThermal(vm.thermal.on, limit.roundToInt()) },
                    valueRange = 70f..100f,
                    colors = SliderDefaults.colors(thumbColor = p.pill, activeTrackColor = p.pill, inactiveTrackColor = p.track),
                    modifier = Modifier.weight(1f)
                )
                HText("${limit.roundToInt()}°C", size = 13.sp, modifier = Modifier.width(52.dp))
            }
        }
    }
}

// ======================= Nav, pesan, dialog =======================
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
        listOf("Dash", "Knob", "Games", "Monitor").forEachIndexed { i, t ->
            val sel = vm.tab == i
            Box(
                Modifier
                    .weight(1f)
                    .clip(CircleShape)
                    .background(if (sel) p.pill else Color.Transparent)
                    .clickable {
                        if (vm.tab == i) { vm.openCat = null; vm.openGame = null }
                        vm.goTab(i)
                    }
                    .padding(vertical = 13.dp),
                contentAlignment = Alignment.Center
            ) {
                HText(t.uppercase(), size = 10.sp, color = if (sel) p.onPill else p.dim, spacing = 1.2.sp)
            }
        }
    }
}

@Composable
fun MessageBar(vm: HsinVm, modifier: Modifier) {
    val p = LocalPal.current
    val m = vm.message ?: return
    LaunchedEffect(m) {
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
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                for (f in vm.failures) {
                    Column {
                        HText(f.first, size = 12.sp)
                        HText(f.second.ifEmpty { "ditolak" }, size = 11.sp, color = p.dim)
                    }
                }
            }
        },
        confirmButton = { TextButton(onClick = { vm.failures = emptyList() }) { HText("OKE", size = 12.sp) } }
    )
}
