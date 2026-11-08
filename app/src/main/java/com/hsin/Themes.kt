package com.hsin

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.remember
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.Density
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.graphics.Outline
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.graphics.Shape
import androidx.compose.foundation.shape.GenericShape
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlin.math.cos
import kotlin.math.sin

/** Bentuk jajar genjang miring (gaya tema 1). */
internal val SlantShape: Shape = GenericShape { s, _ ->
    val k = s.height * 0.28f
    moveTo(k, 0f); lineTo(s.width, 0f); lineTo(s.width - k, s.height); lineTo(0f, s.height); close()
}

/** Bentuk sudut terpotong (gaya gaming). */
internal val CutShape: Shape = GenericShape { s, _ ->
    val k = minOf(s.height * 0.3f, 24f)
    moveTo(k, 0f); lineTo(s.width, 0f); lineTo(s.width, s.height - k); lineTo(s.width - k, s.height); lineTo(0f, s.height); lineTo(0f, k); close()
}

/** Segi enam (gaya Nitro). */
internal val HexShape: Shape = GenericShape { s, _ ->
    moveTo(s.width * 0.5f, 0f); lineTo(s.width, s.height * 0.25f); lineTo(s.width, s.height * 0.75f)
    lineTo(s.width * 0.5f, s.height); lineTo(0f, s.height * 0.75f); lineTo(0f, s.height * 0.25f); close()
}

/** Segi delapan: keempat sudut dipotong (kartu gaya Nitro). */
internal val OctShape: Shape = GenericShape { s, _ ->
    val k = minOf(s.height * 0.2f, 20f)
    moveTo(k, 0f); lineTo(s.width - k, 0f); lineTo(s.width, k); lineTo(s.width, s.height - k)
    lineTo(s.width - k, s.height); lineTo(k, s.height); lineTo(0f, s.height - k); lineTo(0f, k); close()
}

/** Bentuk tombol/chip mengikuti tema: Apex miring, Turbo kapsul, Nitro segi delapan. */
internal fun btnShape(): Shape = when (UiState.theme) { 1 -> SlantShape; 3 -> OctShape; else -> androidx.compose.foundation.shape.RoundedCornerShape(50) }

/** Bentuk kartu besar mengikuti tema. */
internal fun cardShape(): Shape = when (UiState.theme) { 1 -> CutShape; 3 -> OctShape; else -> androidx.compose.foundation.shape.RoundedCornerShape(24.dp) }

/** Gambar bawaan tiap tema: latar, banner, logo. */
internal fun themeWall(t: Int): Int = when (t) { 1 -> R.drawable.art_blossom; 3 -> R.drawable.art_spark; else -> R.drawable.wallpaper_default }
internal fun themeBanner(t: Int): Int = when (t) { 1 -> R.drawable.banner_default; 3 -> R.drawable.art_cream; else -> R.drawable.art_fire }
internal fun themeLogo(t: Int): Int = when (t) { 1 -> R.drawable.art_gold; 3 -> R.drawable.art_cream; else -> R.drawable.icon_default }

/** Tombol navigasi bertema: bentuk mengikuti tema, aktif diisi warna aksen. */
@Composable
internal fun ThemedNavBtn(i: Int, shape: Shape, w: androidx.compose.ui.unit.Dp, h: androidx.compose.ui.unit.Dp, label: Boolean) {
    val sel = UiState.tab == i
    val a = ownAnim(if (sel) 1f else 0f, 200)
    val col = lerpColor(SP.dim, SP.ink, a)
    Column(Modifier.tap { UiState.tab = i }, horizontalAlignment = Alignment.CenterHorizontally) {
        Box(
            Modifier.size(w, h).clip(shape).background(lerpColor(Color(0xFF171B26), SP.gold, a))
                .border(1.dp, SP.gold.copy(alpha = 0.35f + 0.4f * a), shape),
            contentAlignment = Alignment.Center
        ) { NavIcon(i, col) }
        if (label) SText(navName(i), 9.sp, lerpColor(SP.dim, SP.gold, a), modifier = Modifier.padding(top = 2.dp))
    }
}

@Composable
internal fun LogoThemed(dp: Int) {
    val th = UiState.theme
    val sh: Shape = when (th) { 1 -> CutShape; 3 -> HexShape; else -> CircleShape }
    androidx.compose.foundation.Image(
        androidx.compose.ui.res.painterResource(themeLogo(th)), null,
        contentScale = androidx.compose.ui.layout.ContentScale.Crop,
        modifier = Modifier.size(dp.dp).clip(sh).border(1.5.dp, SP.gold, sh)
    )
}

/** Apex: rel kiri, tombol miring. */
@Composable
internal fun NavApex(compact: Boolean) {
    Column(
        Modifier.width(if (compact) 68.dp else 86.dp).fillMaxHeight().background(Color(0xB3080A10)).verticalScroll(rememberScrollState()).padding(vertical = if (compact) 6.dp else 12.dp),
        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(if (compact) 4.dp else 8.dp)
    ) {
        LogoThemed(if (compact) 34 else 46)
        for (i in 0 until 5) ThemedNavBtn(i, SlantShape, 56.dp, if (compact) 36.dp else 42.dp, !compact)
    }
}

/** Turbo: dock kapsul di bawah, tombol bulat. */
@Composable
internal fun NavTurbo(compact: Boolean) {
    Box(Modifier.fillMaxWidth().padding(bottom = 6.dp, top = 2.dp), contentAlignment = Alignment.Center) {
        Row(
            Modifier.clip(CircleShape).background(Color(0xE6080A10)).border(1.5.dp, SP.gold.copy(alpha = 0.7f), CircleShape).padding(horizontal = 14.dp, vertical = 5.dp),
            horizontalArrangement = Arrangement.spacedBy(14.dp), verticalAlignment = Alignment.CenterVertically
        ) {
            LogoThemed(34)
            for (i in 0 until 5) ThemedNavBtn(i, CircleShape, 42.dp, 42.dp, false)
        }
    }
}

/** Nitro: rel kanan, tombol segi enam. */
@Composable
internal fun NavNitro(compact: Boolean) {
    Column(
        Modifier.width(if (compact) 68.dp else 86.dp).fillMaxHeight().background(Color(0xB3080C14)).verticalScroll(rememberScrollState()).padding(vertical = if (compact) 6.dp else 12.dp),
        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(if (compact) 2.dp else 6.dp)
    ) {
        LogoThemed(if (compact) 34 else 46)
        for (i in 0 until 5) ThemedNavBtn(i, HexShape, if (compact) 44.dp else 52.dp, if (compact) 46.dp else 56.dp, !compact)
    }
}

/** Tombol Lanjut game terakhir (pengganti kartu sesi di Beranda; detail sesi ada di halaman Rekaman). */
@Composable
internal fun ResumeButton(vm: AppViewModel, col: Color) {
    val lastPkg = vm.prefs.lastGame
    if (lastPkg.isEmpty()) return
    HBtn(tx("▶  LANJUT: ", "▶  RESUME: ") + vm.label(lastPkg), Modifier.fillMaxWidth(), col, solid = true) { UiState.startRitual(lastPkg) }
}

@Composable
private fun SlantStat(name: String, v: String, col: Color, modifier: Modifier) {
    Box(modifier.clip(SlantShape).background(SP.glass).border(1.dp, col.copy(alpha = 0.55f), SlantShape).padding(horizontal = 18.dp, vertical = 7.dp)) {
        Column {
            SText(name, 10.sp, col, FontWeight.Bold, 1.5.sp)
            SText(v, 18.sp, SP.text, FontWeight.Bold)
        }
    }
}

@Composable
private fun SlantModes(vm: AppViewModel) {
    val cm = curMode(vm)
    Row(Modifier.fillMaxWidth().rise(120), horizontalArrangement = Arrangement.spacedBy(4.dp)) {
        MODES.forEach { m ->
            val a = ownAnim(if (cm == m.key) 1f else 0f, 220)
            Box(
                Modifier.weight(1f).tap { vm.chooseMode(m.key) }.clip(SlantShape)
                    .background(lerpColor(SP.glass, m.color, a)).border(1.dp, m.color.copy(alpha = 0.6f), SlantShape).padding(vertical = 11.dp),
                contentAlignment = Alignment.Center
            ) { SText(mname(m), 12.sp, lerpColor(m.color, SP.ink, a), FontWeight.ExtraBold, 1.sp) }
        }
    }
}

private fun gpuText(l: Live) = if (l.gpuPct >= 0) "${l.gpuPct}%" else if (l.gpuMhz >= 0) "${l.gpuMhz} MHz" else "--"
private fun cpuText(l: Live) = if (l.cpu >= 0) "${l.cpu}%" else "--"
private fun tempText(l: Live) = if (l.tempC > 0) "${l.tempC}°" else "--"

/** Tema 1: Kartu Miring. */
@Composable
private fun HomeSlant(vm: AppViewModel, live: Live, col: Color, land: Boolean) {
    val side: @Composable (Modifier) -> Unit = { m ->
        Column(m, verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                SlantStat("CPU", cpuText(live), col, Modifier.weight(1f))
                SlantStat("GPU", gpuText(live), col, Modifier.weight(1f))
                SlantStat(tx("SUHU", "TEMP"), tempText(live), col, Modifier.weight(1f))
            }
            SlantModes(vm)
            GamePicker(vm)
            ActionRow(vm, col)
            ResumeButton(vm, col)
        }
    }
    if (land) {
        BoxWithConstraints(Modifier.fillMaxSize()) {
            val d = minOf(maxHeight - 20.dp, maxWidth * 0.40f, 310.dp)
            Row(Modifier.fillMaxSize().padding(14.dp, 10.dp), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                Box(Modifier.weight(0.9f).fillMaxHeight(), contentAlignment = Alignment.Center) { CoreDial(vm, d) }
                side(Modifier.weight(1.1f).fillMaxHeight().verticalScroll(rememberScrollState()))
            }
        }
    } else {
        BoxWithConstraints(Modifier.fillMaxSize()) {
            val dd = minOf(maxWidth - 28.dp, 300.dp)
            Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(14.dp), verticalArrangement = Arrangement.spacedBy(10.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                CoreDial(vm, dd)
                side(Modifier.fillMaxWidth())
            }
        }
    }
}

@Composable
private fun RoundGauge(name: String, v: String, frac: Float, col: Color, modifier: Modifier = Modifier) {
    val f = ownAnim(frac.coerceIn(0f, 1f), 500)
    Box(modifier.size(78.dp), contentAlignment = Alignment.Center) {
        Canvas(Modifier.fillMaxSize()) {
            val st = 6.dp.toPx(); val r = size.minDimension / 2f - st
            drawCircle(Color(0x22FFFFFF), r, style = Stroke(st))
            drawArc(col, -90f, 360f * f, false, Offset(st, st), androidx.compose.ui.geometry.Size(r * 2, r * 2), style = Stroke(st, cap = androidx.compose.ui.graphics.StrokeCap.Round))
        }
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            SText(v, 15.sp, SP.text, FontWeight.Bold)
            SText(name, 9.sp, col, FontWeight.SemiBold, 1.sp)
        }
    }
}

/** Tema 2: Dasbor Bundar — dial tengah, CPU kiri, GPU kanan. */
@Composable
private fun HomeRound(vm: AppViewModel, live: Live, col: Color, land: Boolean) {
    BoxWithConstraints(Modifier.fillMaxSize()) {
        val d = if (land) minOf(maxHeight - 20.dp, maxWidth * 0.36f, 300.dp) else minOf(maxWidth - 150.dp, 260.dp).coerceAtLeast(180.dp)
        val mid: @Composable () -> Unit = {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Column(verticalArrangement = Arrangement.spacedBy(10.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                    RoundGauge("CPU", cpuText(live), live.cpu / 100f, col)
                    RoundGauge(tx("SUHU", "TEMP"), tempText(live), live.tempC / 60f, col)
                }
                CoreDial(vm, d)
                Column(verticalArrangement = Arrangement.spacedBy(10.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                    RoundGauge("GPU", gpuText(live), if (live.gpuPct >= 0) live.gpuPct / 100f else live.gpuMhz / 1000f, col)
                    RoundGauge("BATT", if (vm.status.batt >= 0) "${vm.status.batt}%" else "--", vm.status.batt / 100f, col)
                }
            }
        }
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(14.dp), verticalArrangement = Arrangement.spacedBy(10.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            mid()
            ModePills(vm)
            GamePicker(vm)
            ActionRow(vm, col)
            ResumeButton(vm, col)
        }
    }
}

/** Tema 3: Kubus Energi — kubus heksagon di tengah, batang miring CPU/GPU di sisi. */
@Composable
private fun HomeCube(vm: AppViewModel, live: Live, col: Color, land: Boolean) {
    val clock = LocalClock.current
    val cm = curMode(vm)
    val m = if (cm.isEmpty()) MODES[1] else info(cm)
    BoxWithConstraints(Modifier.fillMaxSize()) {
        val d = if (land) minOf(maxHeight - 120.dp, 180.dp).coerceAtLeast(110.dp) else 190.dp
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(14.dp), verticalArrangement = Arrangement.spacedBy(10.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.SpaceBetween) {
                Column(Modifier.weight(1f)) {
                    SText(cpuText(live), 26.sp, col, FontWeight.Bold)
                    SText("CPU", 10.sp, SP.dim, spacing = 2.sp)
                    SlantBar(if (live.cpu >= 0) live.cpu / 100f else 0f, col, false)
                }
                Box(Modifier.size(d), contentAlignment = Alignment.Center) {
                    Canvas(Modifier.fillMaxSize()) {
                        val c = center; val r = size.minDimension / 2f - 6.dp.toPx()
                        val pts = (0..5).map { i -> val a = Math.toRadians(-90.0 + 60.0 * i); Offset(c.x + r * cos(a).toFloat(), c.y + r * sin(a).toFloat()) }
                        val path = Path().apply { moveTo(pts[0].x, pts[0].y); for (i in 1..5) lineTo(pts[i].x, pts[i].y); close() }
                        drawPath(path, Color(0xFF0A1424))
                        drawPath(path, col, style = Stroke(2.5.dp.toPx()))
                        drawLine(col.copy(alpha = .6f), c, pts[1], 1.5.dp.toPx()); drawLine(col.copy(alpha = .6f), c, pts[3], 1.5.dp.toPx()); drawLine(col.copy(alpha = .6f), c, pts[5], 1.5.dp.toPx())
                        rotate(clock.floatValue * 12f, c) {
                            drawCircle(col.copy(alpha = .55f), r * 0.8f, c, style = Stroke(1.dp.toPx(), pathEffect = PathEffect.dashPathEffect(floatArrayOf(4.dp.toPx(), 8.dp.toPx()))))
                        }
                    }
                    SText(mname(m), 15.sp, SP.text, FontWeight.ExtraBold, 2.sp)
                }
                Column(Modifier.weight(1f), horizontalAlignment = Alignment.End) {
                    SText(gpuText(live), 26.sp, col, FontWeight.Bold)
                    SText("GPU", 10.sp, SP.dim, spacing = 2.sp)
                    SlantBar(if (live.gpuPct >= 0) live.gpuPct / 100f else live.gpuMhz / 1000f, col, true)
                }
            }
            SText("${tempText(live)} · ${if (vm.status.batt >= 0) vm.status.batt.toString() + "%" else "--"} · " + (if (LocalEn.current) m.tagEn else m.tagId), 11.sp, SP.dim)
            SlantModes(vm)
            GamePicker(vm)
            ActionRow(vm, col)
            ResumeButton(vm, col)
        }
    }
}

@Composable
private fun SlantBar(frac: Float, col: Color, right: Boolean) {
    val f = ownAnim(frac.coerceIn(0f, 1f), 500)
    Column(Modifier.padding(top = 6.dp), verticalArrangement = Arrangement.spacedBy(3.dp), horizontalAlignment = if (right) Alignment.End else Alignment.Start) {
        for (i in 0 until 5) {
            val on = f >= (i + 1) / 5f - 0.1f
            Box(Modifier.width((50 + i * 10).dp).height(8.dp).clip(SlantShape).background(if (on) col else col.copy(alpha = 0.18f)))
        }
    }
}

private val lastProg = floatArrayOf(1f)
private fun lerpColorHold(a: Color, b: Color, t: Float) = lerpColor(a, b, t)

@Composable
internal fun ThemedHome(vm: AppViewModel, land: Boolean) {
    val live = rememberLive(vm, true)
    val cm = curMode(vm)
    val target = if (cm.isEmpty()) SP.gold else info(cm).color
    // warna aksen pindah halus ke mode baru (jam sendiri, tidak ikut skala animasi sistem)
    val hold = remember { arrayOf(target, target) }   // [0] asal, [1] tujuan sebelumnya
    if (hold[1] != target) { hold[0] = lerpColorHold(hold[0], hold[1], lastProg[0]); hold[1] = target }
    val prog = popKey(target, 420)
    lastProg[0] = prog
    val col = lerpColor(hold[0], target, prog)
    Box(Modifier.fillMaxSize()) {
        ThemeDeco(vm.prefs.appTheme, col)
        when (vm.prefs.appTheme) {
            1 -> HomeSlant(vm, live, col, land)
            2 -> HomeRound(vm, live, col, land)
            else -> HomeCube(vm, live, col, land)
        }
    }
}

/** Dekorasi latar tiap tema (di belakang konten, tidak menangkap sentuhan). */
@Composable
private fun ThemeDeco(theme: Int, col: Color) {
    val clock = LocalClock.current
    Canvas(Modifier.fillMaxSize()) {
        val t = clock.floatValue
        val w = size.width; val h = size.height
        when (theme) {
            1 -> {   // batang miring bercahaya di kiri dan kanan
                val bh = 16.dp.toPx(); val gap = 8.dp.toPx(); val sk = bh * 0.9f
                for (side in 0..1) for (i in 0 until 6) {
                    val y = h * 0.12f + i * (bh + gap)
                    val len = (60 + (i * 17 + (t * 20f).toInt() * (if (side == 0) 1 else 2)) % 70).dp.toPx()
                    val x0 = if (side == 0) 6.dp.toPx() else w - 6.dp.toPx() - len
                    val path = Path().apply { moveTo(x0 + sk, y); lineTo(x0 + len, y); lineTo(x0 + len - sk, y + bh); lineTo(x0, y + bh); close() }
                    drawPath(path, col.copy(alpha = 0.05f + 0.025f * ((i + (t * 2f).toInt()) % 4)))
                }
                drawLine(col.copy(alpha = 0.5f), Offset(0f, 1.dp.toPx()), Offset(w * 0.35f, 1.dp.toPx()), 2.dp.toPx())
                drawLine(col.copy(alpha = 0.5f), Offset(w, h - 1.dp.toPx()), Offset(w * 0.65f, h - 1.dp.toPx()), 2.dp.toPx())
            }
            2 -> {   // lingkar skala besar berputar pelan di tengah
                val c = Offset(w / 2f, h / 2f); val r = minOf(w, h) * 0.52f
                rotate(t * 4f, c) {
                    for (k in 0 until 72) {
                        val a = Math.toRadians(k * 5.0)
                        val r2 = r - (if (k % 6 == 0) 10.dp.toPx() else 5.dp.toPx())
                        drawLine(col.copy(alpha = if (k % 6 == 0) 0.28f else 0.12f), Offset(c.x + r * cos(a).toFloat(), c.y + r * sin(a).toFloat()), Offset(c.x + r2 * cos(a).toFloat(), c.y + r2 * sin(a).toFloat()), 1.dp.toPx())
                    }
                }
                drawCircle(col.copy(alpha = 0.08f), r * 0.78f, c, style = Stroke(1.dp.toPx()))
            }
            else -> { // kisi heksagon samar + garis energi naik
                val s = 34.dp.toPx(); val hh = s * 0.866f
                var row = 0; var y = 0f
                while (y < h + hh) {
                    var x = if (row % 2 == 0) 0f else s * 0.75f
                    while (x < w + s) {
                        val p = Path()
                        for (i in 0 until 6) { val a = Math.toRadians(60.0 * i); val px = x + s * 0.5f * cos(a).toFloat(); val py = y + s * 0.5f * sin(a).toFloat(); if (i == 0) p.moveTo(px, py) else p.lineTo(px, py) }
                        p.close(); drawPath(p, col.copy(alpha = 0.045f), style = Stroke(1.dp.toPx()))
                        x += s * 1.5f
                    }
                    y += hh * 0.5f; row++
                }
                for (i in 0 until 5) {
                    val x = w * (0.1f + 0.2f * i); val yy = h - ((t * 40f + i * 90f) % h)
                    drawLine(col.copy(alpha = 0.22f), Offset(x, yy), Offset(x, yy - 38.dp.toPx()), 2.dp.toPx())
                }
            }
        }
    }
}


/** Bukaan lingkaran dari tengah (tema Nitro). p = 0..1. */
class IrisShape(private val p: Float) : Shape {
    override fun createOutline(size: Size, layoutDirection: LayoutDirection, density: Density): Outline {
        val r = Math.hypot(size.width.toDouble(), size.height.toDouble()).toFloat() / 2f * (0.08f + 0.92f * p)
        val c = Offset(size.width / 2f, size.height / 2f)
        return Outline.Generic(Path().apply { addOval(Rect(c.x - r, c.y - r, c.x + r, c.y + r)) })
    }
}

/** Efek singkat saat mode berganti, beda per tema. Digambar di draw phase, nol biaya saat tidak jalan. */
@Composable
internal fun ModeFx(vm: AppViewModel) {
    val cm = curMode(vm)
    val col = if (cm.isEmpty()) SP.gold else info(cm).color
    val tick = remember { mutableIntStateOf(0) }
    val first = remember { booleanArrayOf(true) }
    LaunchedEffect(cm) { if (first[0]) first[0] = false else tick.intValue++ }
    val key = tick.intValue
    if (key == 0 || UiState.reduceAnim) return
    val p = popKeyS(key, 640)
    val th = UiState.theme
    Canvas(Modifier.fillMaxSize()) {
        val t = p.floatValue
        if (t >= 1f) return@Canvas
        val fade = 1f - t
        val big = maxOf(size.width, size.height)
        when (th) {
            2 -> drawCircle(col.copy(alpha = fade * 0.8f), radius = t * big * 0.6f, center = center, style = Stroke(6f))
            3 -> {
                val r = t * big * 0.6f
                val hex = Path()
                for (i in 0 until 6) {
                    val a = Math.toRadians(60.0 * i - 90.0)
                    val x = center.x + r * Math.cos(a).toFloat(); val y = center.y + r * Math.sin(a).toFloat()
                    if (i == 0) hex.moveTo(x, y) else hex.lineTo(x, y)
                }
                hex.close()
                drawPath(hex, col.copy(alpha = fade * 0.7f), style = Stroke(6f))
            }
            else -> {
                val w = size.width * 0.3f; val skew = size.height * 0.2f
                val x = -w + (size.width + 2f * w) * t
                val band = Path().apply { moveTo(x, 0f); lineTo(x + w, 0f); lineTo(x + w - skew, size.height); lineTo(x - skew, size.height); close() }
                drawPath(band, Brush.horizontalGradient(listOf(Color.Transparent, col.copy(alpha = 0.38f), Color.Transparent), startX = x - skew, endX = x + w))
            }
        }
    }
}
