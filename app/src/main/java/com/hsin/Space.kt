package com.hsin

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.FloatState
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.delay
import java.util.Locale
import kotlin.math.PI
import kotlin.math.sin

// ===================== warna & animasi sendiri =====================
// Semua animasi di file ini digerakkan jam frame (withFrameNanos), BUKAN ValueAnimator/animate*AsState,
// jadi tetap jalan walau "Skala animasi" di Opsi Pengembang diset 0.0.
object SP {
    val gold = Color(0xFFE8B95A)
    val goldHi = Color(0xFFF6D88F)
    val red = Color(0xFFE5484D)
    val glass = Color(0xB8141416)
    val glassLo = Color(0x99141416)
    val line = Color(0x26FFFFFF)
    val text = Color(0xFFF4F1EA)
    val dim = Color(0xB3F4F1EA)
    val faint = Color(0x66F4F1EA)
    val ink = Color(0xFF141416)
}

val LocalClock = staticCompositionLocalOf<FloatState> { mutableFloatStateOf(0f) }

@Composable
fun ownAnim(target: Float, ms: Int = 300): Float {
    val s = remember { mutableFloatStateOf(target) }
    LaunchedEffect(target) {
        val from = s.floatValue
        if (from != target) {
            val t0 = withFrameNanosCompat()
            while (true) {
                val now = withFrameNanosCompat()
                val k = ((now - t0) / 1_000_000f / ms).coerceIn(0f, 1f)
                val e = 1f - (1f - k) * (1f - k) * (1f - k)
                s.floatValue = from + (target - from) * e
                if (k >= 1f) break
            }
        }
    }
    return s.floatValue
}

/** Mulai dari 0 lalu naik ke 1 tiap `key` berubah (dipakai untuk judul mode, nama game, dll). */
@Composable
fun popKey(key: Any, ms: Int = 340): Float {
    val s = remember { mutableFloatStateOf(0f) }
    LaunchedEffect(key) {
        s.floatValue = 0f
        val t0 = withFrameNanosCompat()
        while (true) {
            val now = withFrameNanosCompat()
            val k = ((now - t0) / 1_000_000f / ms).coerceIn(0f, 1f)
            s.floatValue = 1f - (1f - k) * (1f - k) * (1f - k)
            if (k >= 1f) break
        }
    }
    return s.floatValue
}

private suspend fun withFrameNanosCompat(): Long = androidx.compose.runtime.withFrameNanos { it }

@Composable
fun Modifier.rise(delayMs: Int = 0, key: Any = Unit): Modifier {
    val a = remember(key) { mutableFloatStateOf(0f) }
    LaunchedEffect(key) {
        a.floatValue = 0f
        delay(delayMs.toLong())
        val t0 = withFrameNanosCompat()
        while (true) {
            val now = withFrameNanosCompat()
            val k = ((now - t0) / 1_000_000f / 440f).coerceIn(0f, 1f)
            a.floatValue = 1f - (1f - k) * (1f - k) * (1f - k)
            if (k >= 1f) break
        }
    }
    return this.graphicsLayer {
        alpha = a.floatValue
        translationY = (1f - a.floatValue) * 26.dp.toPx()
    }
}

@Composable
fun Modifier.tap(onClick: () -> Unit): Modifier {
    var down by remember { mutableStateOf(false) }
    val s = ownAnim(if (down) 0.95f else 1f, 110)
    val cb by rememberUpdatedState(onClick)
    return this
        .graphicsLayer { scaleX = s; scaleY = s }
        .pointerInput(Unit) {
            detectTapGestures(
                onPress = { down = true; tryAwaitRelease(); down = false },
                onTap = { cb() }
            )
        }
}

@Composable
fun SText(
    t: String,
    size: TextUnit = 13.sp,
    color: Color = SP.text,
    weight: FontWeight = FontWeight.Normal,
    spacing: TextUnit = 0.sp,
    modifier: Modifier = Modifier
) {
    Text(t, modifier, color = color, fontSize = size, fontWeight = weight, letterSpacing = spacing, maxLines = 1, overflow = TextOverflow.Ellipsis)
}

@Composable
fun Glass(modifier: Modifier = Modifier, radius: Int = 12, alt: Boolean = false, content: @Composable () -> Unit) {
    val sh = RoundedCornerShape(radius.dp)
    Box(
        modifier
            .clip(sh)
            .background(if (alt) SP.glassLo else SP.glass)
            .border(0.6.dp, SP.line, sh)
    ) { content() }
}

// ===================== info mode =====================
private class MInfo(val key: String, val name: String, val stars: Int, val tag: String, val detail: String)

private val MODES = listOf(
    MInfo("hemat", "Hemat", 1, "Irit baterai dan adem", "CPU dibatasi ±70%, GPU ±55%, frekuensi terendah dibiarkan turun. Cocok untuk game ringan."),
    MInfo("bawaan", "Bawaan", 2, "Setelan asli HP, tanpa campur tangan", "Semua setelan kembali ke bawaan sistem. Tidak ada yang dibatasi atau dinaikkan."),
    MInfo("seimbang", "Seimbang", 3, "Lancar dan adem untuk sesi panjang", "CPU dan GPU boleh penuh, frekuensi minimum dinaikkan supaya tidak patah-patah."),
    MInfo("boost", "Boost", 4, "Tenaga penuh, tanpa batas", "CPU dan GPU dikunci di frekuensi tertinggi, governor performa, batas panas dilonggarkan. Paling kencang, HP lebih hangat.")
)

private fun info(k: String): MInfo = MODES.firstOrNull { it.key == k } ?: MODES[1]

private fun starText(n: Int): String = "★".repeat(n) + "☆".repeat(4 - n)

// ===================== akar =====================
@Composable
fun SpaceRoot(vm: HsinVm) {
    val clock = remember { mutableFloatStateOf(0f) }
    LaunchedEffect(Unit) {
        val t0 = withFrameNanosCompat()
        while (true) clock.floatValue = (withFrameNanosCompat() - t0) / 1_000_000_000f
    }
    CompositionLocalProvider(LocalClock provides clock) {
        BoxWithConstraints(Modifier.fillMaxSize().background(Color(0xFF0C0C0E))) {
            val land = maxWidth > maxHeight
            val wall = vm.wallBmp
            if (wall != null) Image(bitmap = wall, contentDescription = null, contentScale = ContentScale.Crop, modifier = Modifier.fillMaxSize())
            Box(
                Modifier.fillMaxSize().background(
                    if (land) Brush.horizontalGradient(listOf(Color(0xE60A0A0C), Color(0x990A0A0C), Color(0x330A0A0C)))
                    else Brush.verticalGradient(listOf(Color(0x990A0A0C), Color(0xE60A0A0C)))
                )
            )
            Embers()
            if (land) {
                Row(Modifier.fillMaxSize().systemBarsPadding()) {
                    NavRail(vm)
                    SpaceContent(vm, true, Modifier.weight(1f).fillMaxHeight())
                }
            } else {
                Column(Modifier.fillMaxSize().systemBarsPadding()) {
                    SpaceContent(vm, false, Modifier.weight(1f).fillMaxWidth())
                    NavBar(vm)
                }
            }
            MessageToast(vm, Modifier.align(Alignment.BottomCenter).navigationBarsPadding().padding(bottom = 88.dp))
            FailureDialog(vm)
        }
    }
}

@Composable
private fun SpaceContent(vm: HsinVm, land: Boolean, modifier: Modifier) {
    Box(modifier) {
        if (vm.setup != Setup.Ready) {
            Column(Modifier.fillMaxSize().padding(24.dp), verticalArrangement = Arrangement.Center) {
                Glass(Modifier.fillMaxWidth()) {
                    Column(Modifier.padding(4.dp)) { SetupCard(vm) }
                }
            }
        } else when (vm.spaceTab) {
            0 -> HomeTab(vm, land)
            1 -> GameTab(vm)
            2 -> RecTab(vm)
            else -> SettingsTab(vm)
        }
    }
}

@Composable
private fun MessageToast(vm: HsinVm, modifier: Modifier) {
    val m = vm.message ?: return
    LaunchedEffect(m) {
        delay(3000)
        if (vm.message == m) vm.message = null
    }
    Box(modifier.padding(horizontal = 24.dp).clip(RoundedCornerShape(16.dp)).background(SP.gold).padding(horizontal = 16.dp, vertical = 10.dp)) {
        SText(m, 13.sp, SP.ink, FontWeight.Medium)
    }
}

// ===================== hiasan =====================
@Composable
private fun Embers() {
    val clock = LocalClock.current
    Canvas(Modifier.fillMaxSize()) {
        val t = clock.floatValue
        for (i in 0 until 26) {
            val seed = i * 0.6180339f
            val x = ((seed * 7.31f) % 1f)
            val sp = 0.018f + (i % 5) * 0.007f
            val y = 1f - ((t * sp + seed) % 1f)
            val sway = sin(t * 0.7f + i) * 0.012f
            val a = (sin(((1f - y) * PI).toFloat()) * 0.55f).coerceIn(0f, 1f)
            drawCircle(SP.gold.copy(alpha = a * 0.7f), radius = (1.2f + (i % 3)) * density, center = Offset((x + sway) * size.width, y * size.height))
        }
    }
}

// ===================== navigasi =====================
private val NAV_NAMES = listOf("Beranda", "Game", "Rekaman", "Pengaturan")

@Composable
private fun NavIcon(i: Int, color: Color, modifier: Modifier = Modifier) {
    Canvas(modifier.size(24.dp)) {
        val w = size.width; val h = size.height
        val st = Stroke(width = 1.8.dp.toPx(), cap = StrokeCap.Round)
        when (i) {
            0 -> {
                val p = Path()
                p.moveTo(w * 0.12f, h * 0.48f); p.lineTo(w * 0.5f, h * 0.14f); p.lineTo(w * 0.88f, h * 0.48f)
                p.moveTo(w * 0.22f, h * 0.42f); p.lineTo(w * 0.22f, h * 0.86f); p.lineTo(w * 0.78f, h * 0.86f); p.lineTo(w * 0.78f, h * 0.42f)
                drawPath(p, color, style = st)
            }
            1 -> {
                drawRoundRect(color, Offset(w * 0.06f, h * 0.28f), Size(w * 0.88f, h * 0.48f), CornerRadius(w * 0.24f), style = st)
                drawLine(color, Offset(w * 0.28f, h * 0.43f), Offset(w * 0.28f, h * 0.61f), st.width, StrokeCap.Round)
                drawLine(color, Offset(w * 0.19f, h * 0.52f), Offset(w * 0.37f, h * 0.52f), st.width, StrokeCap.Round)
                drawCircle(color, w * 0.04f, Offset(w * 0.68f, h * 0.46f)); drawCircle(color, w * 0.04f, Offset(w * 0.78f, h * 0.58f))
            }
            2 -> {
                drawCircle(color, w * 0.40f, Offset(w / 2, h / 2), style = st)
                drawCircle(color, w * 0.16f, Offset(w / 2, h / 2))
            }
            else -> {
                for (k in 0 until 3) {
                    val y = h * (0.24f + 0.26f * k)
                    drawLine(color, Offset(w * 0.1f, y), Offset(w * 0.9f, y), st.width, StrokeCap.Round)
                    drawCircle(SP.ink, w * 0.09f, Offset(w * (0.30f + 0.2f * ((k * 2) % 3)), y))
                    drawCircle(color, w * 0.09f, Offset(w * (0.30f + 0.2f * ((k * 2) % 3)), y), style = st)
                }
            }
        }
    }
}

@Composable
private fun NavRail(vm: HsinVm) {
    Column(
        Modifier.width(84.dp).fillMaxHeight().background(Color(0x99000000)).padding(vertical = 14.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(6.dp)
    ) {
        Logo()
        Spacer(Modifier.height(6.dp))
        for (i in 0 until 4) NavItem(vm, i)
        Spacer(Modifier.weight(1f))
        ModeBadge(vm)
    }
}

@Composable
private fun NavBar(vm: HsinVm) {
    Row(
        Modifier.fillMaxWidth().background(Color(0xCC000000)).padding(vertical = 6.dp),
        horizontalArrangement = Arrangement.SpaceEvenly
    ) { for (i in 0 until 4) NavItem(vm, i) }
}

@Composable
private fun Logo() {
    Box(Modifier.size(44.dp).clip(RoundedCornerShape(12.dp)).background(Brush.linearGradient(listOf(SP.goldHi, SP.gold))), contentAlignment = Alignment.Center) {
        SText("H", 22.sp, SP.ink, FontWeight.Black)
    }
}

@Composable
private fun NavItem(vm: HsinVm, i: Int) {
    val sel = vm.spaceTab == i
    val a = ownAnim(if (sel) 1f else 0f, 220)
    val col = lerpColor(SP.dim, SP.gold, a)
    Column(
        Modifier.tap { vm.spaceTab = i; if (i == 2) vm.loadRecs(); if (i == 1) vm.loadApps() }.padding(horizontal = 8.dp, vertical = 4.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Box(
            Modifier.clip(RoundedCornerShape(14.dp)).background(SP.gold.copy(alpha = 0.16f * a)).padding(horizontal = 14.dp, vertical = 6.dp),
            contentAlignment = Alignment.Center
        ) { NavIcon(i, col) }
        SText(NAV_NAMES[i], 10.sp, col)
    }
}

private fun lerpColor(a: Color, b: Color, t: Float): Color = Color(
    red = a.red + (b.red - a.red) * t, green = a.green + (b.green - a.green) * t,
    blue = a.blue + (b.blue - a.blue) * t, alpha = a.alpha + (b.alpha - a.alpha) * t
)

@Composable
private fun ModeBadge(vm: HsinVm) {
    val clock = LocalClock.current
    Box(
        Modifier.size(44.dp).drawBehind {
            val a = 0.35f + 0.25f * sin(clock.floatValue * 2.4f)
            drawCircle(SP.gold.copy(alpha = a), radius = size.minDimension / 2f + 3.dp.toPx(), style = Stroke(2.dp.toPx()))
        }.clip(CircleShape).background(SP.glass),
        contentAlignment = Alignment.Center
    ) { SText(info(vm.mode).stars.toString() + "★", 12.sp, SP.gold, FontWeight.Bold) }
}

// ===================== BERANDA =====================
@Composable
private fun HomeTab(vm: HsinVm, land: Boolean) {
    if (land) {
        Row(Modifier.fillMaxSize().padding(16.dp), horizontalArrangement = Arrangement.spacedBy(14.dp)) {
            Column(Modifier.weight(1.15f).fillMaxHeight(), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                ModeHeader(vm)
                ModeTiles(vm)
                StatTiles(vm)
                SafeBanner(vm)
            }
            Column(Modifier.weight(0.85f).fillMaxHeight(), verticalArrangement = Arrangement.spacedBy(8.dp), horizontalAlignment = Alignment.End) {
                Chips(vm)
                Spacer(Modifier.weight(1f))
                QuickButtons(vm)
                GameCarousel(vm)
                StartButton(vm)
            }
        }
    } else {
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(14.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) { Chips(vm) }
            ModeHeader(vm)
            ModeTiles(vm)
            StatTiles(vm)
            SafeBanner(vm)
            QuickButtons(vm)
            GameCarousel(vm)
            StartButton(vm)
        }
    }
}

@Composable
private fun Chips(vm: HsinVm) {
    val l = vm.live
    val ram = if (l != null && l.ramTotalKb > 0) String.format(Locale.US, "%.1f/%.1fG", l.ramUsedKb / 1048576f, l.ramTotalKb / 1048576f) else "--"
    val tmp = if (l != null && maxOf(l.tempMax, l.cpuTemp) > 0) "${maxOf(l.tempMax, l.cpuTemp)}°" else "--"
    val bat = if (l != null && l.batPct >= 0) "${l.batPct}%" else "--"
    Row(Modifier.rise(0), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        Chip(SP.gold, ram); Chip(SP.red, tmp); Chip(Color(0xFF4FC3A1), bat)
    }
}

@Composable
private fun Chip(dot: Color, t: String) {
    Glass(radius = 8, alt = true) {
        Row(Modifier.padding(horizontal = 9.dp, vertical = 5.dp), verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.size(7.dp).background(dot))
            Spacer(Modifier.width(6.dp))
            SText(t, 12.sp, SP.text, FontWeight.Medium)
        }
    }
}

@Composable
private fun ModeHeader(vm: HsinVm) {
    val m = info(vm.mode)
    val pop = popKey(vm.mode)
    var showDetail by remember { mutableStateOf(false) }
    val playing = (vm.live?.gameActive ?: "").isNotEmpty()
    Glass(Modifier.fillMaxWidth().rise(60)) {
        Row {
            Box(Modifier.width(3.dp).height(if (showDetail) 148.dp else 104.dp).background(SP.gold))
            Column(Modifier.padding(horizontal = 14.dp, vertical = 10.dp)) {
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                    SText("MODE SAAT INI", 11.sp, SP.dim, spacing = 1.6.sp)
                    SText(if (playing) "SEDANG MAIN" else "DIPILIH", 11.sp, SP.gold, spacing = 1.6.sp)
                }
                Row(
                    Modifier.graphicsLayer { alpha = pop; translationX = (1f - pop) * 18.dp.toPx() },
                    verticalAlignment = Alignment.Bottom
                ) {
                    SText(m.name, 30.sp, SP.goldHi, FontWeight.Bold)
                    Spacer(Modifier.width(10.dp))
                    SText(starText(m.stars), 15.sp, SP.gold, modifier = Modifier.padding(bottom = 5.dp))
                }
                SText(m.tag, 13.sp, SP.dim)
                Box(Modifier.tap { showDetail = !showDetail }.padding(vertical = 6.dp)) {
                    SText(if (showDetail) "Tutup ▴" else "Detail ▾", 13.sp, SP.gold)
                }
                if (showDetail) Text(m.detail, color = SP.dim, fontSize = 12.sp, lineHeight = 16.sp)
            }
        }
    }
}

@Composable
private fun ModeTiles(vm: HsinVm) {
    val clock = LocalClock.current
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        MODES.forEachIndexed { i, m ->
            val sel = vm.mode == m.key
            val a = ownAnim(if (sel) 1f else 0f, 240)
            Box(
                Modifier
                    .weight(1f)
                    .rise(120 + i * 60)
                    .tap { vm.setMode(m.key) }
                    .drawBehind {
                        if (sel) {
                            val g = 0.22f + 0.16f * sin(clock.floatValue * 2.6f)
                            drawRoundRect(SP.gold.copy(alpha = g), Offset(-3.dp.toPx(), -3.dp.toPx()), Size(size.width + 6.dp.toPx(), size.height + 6.dp.toPx()), CornerRadius(14.dp.toPx()), style = Stroke(5.dp.toPx()))
                        }
                    }
                    .clip(RoundedCornerShape(11.dp))
                    .background(lerpColor(SP.glass, Color(0xCC2A2214), a))
                    .border(1.dp, lerpColor(SP.line, SP.gold, a), RoundedCornerShape(11.dp))
                    .padding(vertical = 10.dp),
                contentAlignment = Alignment.Center
            ) {
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    SText(m.name, 14.sp, lerpColor(SP.text, SP.goldHi, a), FontWeight.SemiBold)
                    Spacer(Modifier.height(3.dp))
                    SText("★".repeat(m.stars), 10.sp, SP.gold)
                }
            }
        }
    }
}

@Composable
private fun StatTiles(vm: HsinVm) {
    val l = vm.live
    val cpu = vm.cpuUsage
    val gpu = if (l != null && l.gpuMaxHz > 0) (l.gpuHz * 100 / l.gpuMaxHz).toInt().coerceIn(0, 100) else -1
    val t = if (l != null) maxOf(l.tempMax, l.cpuTemp) else -1
    val ram = if (l != null && l.ramTotalKb > 0) l.ramUsedKb / 1048576f else -1f
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        Stat("CPU", cpu.toFloat(), "%", 0, Modifier.weight(1f).rise(380))
        Stat("GPU", gpu.toFloat(), "%", 0, Modifier.weight(1f).rise(430))
        Stat("Suhu", t.toFloat(), "°C", 0, Modifier.weight(1f).rise(480))
        Stat("RAM", ram, " GB", 1, Modifier.weight(1f).rise(530))
    }
}

@Composable
private fun Stat(name: String, v: Float, unit: String, dec: Int, modifier: Modifier) {
    val shown = ownAnim(if (v < 0f) 0f else v, 500)
    Glass(modifier, radius = 10, alt = true) {
        Column(Modifier.padding(horizontal = 10.dp, vertical = 7.dp)) {
            SText(name, 11.sp, SP.dim)
            SText(if (v < 0f) "--" else (if (dec == 0) shown.toInt().toString() else String.format(Locale.US, "%.${dec}f", shown)) + unit, 17.sp, SP.text, FontWeight.SemiBold)
        }
    }
}

@Composable
private fun SafeBanner(vm: HsinVm) {
    val l = vm.live ?: return
    if (!l.safeMode && !l.thermalTrip) return
    Glass(Modifier.fillMaxWidth()) {
        Row(Modifier.padding(horizontal = 12.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                SText(if (l.safeMode) "Mode aman aktif" else "HP terlalu panas", 13.sp, SP.gold, FontWeight.SemiBold)
                SText(if (l.safeMode) "Boot sebelumnya gagal, tuning ditahan." else "Setelan diturunkan otomatis.", 11.sp, SP.dim)
            }
            Box(Modifier.clip(CircleShape).background(SP.gold).tap { if (l.safeMode) vm.disableSafeMode() else vm.ackThermal() }.padding(horizontal = 12.dp, vertical = 6.dp)) {
                SText(if (l.safeMode) "MATIKAN" else "OKE", 11.sp, SP.ink, FontWeight.Bold)
            }
        }
    }
}

@Composable
private fun QuickButtons(vm: HsinVm) {
    Row(Modifier.fillMaxWidth().rise(300), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        QBtn(if (vm.cleaning) "Membersihkan..." else "Bersihkan RAM", false, Modifier.weight(1f)) { vm.cleanRam() }
        QBtn("Jangan ganggu", vm.dndNow, Modifier.weight(1f)) { vm.toggleDndNow() }
    }
}

@Composable
private fun QBtn(t: String, on: Boolean, modifier: Modifier, onClick: () -> Unit) {
    val a = ownAnim(if (on) 1f else 0f, 220)
    Box(
        modifier.tap(onClick).clip(RoundedCornerShape(10.dp)).background(lerpColor(SP.glass, SP.gold, a * 0.9f))
            .border(0.6.dp, lerpColor(SP.line, SP.gold, a), RoundedCornerShape(10.dp)).padding(vertical = 13.dp),
        contentAlignment = Alignment.Center
    ) { SText(t, 13.sp, lerpColor(SP.text, SP.ink, a), FontWeight.Medium) }
}

@Composable
private fun GameCarousel(vm: HsinVm) {
    val gs = vm.games
    Glass(Modifier.fillMaxWidth().rise(340)) {
        if (gs.isEmpty()) {
            Box(Modifier.fillMaxWidth().tap { vm.spaceTab = 1; vm.loadApps() }.padding(vertical = 14.dp), contentAlignment = Alignment.Center) {
                SText("+ Tambah game dulu", 14.sp, SP.gold, FontWeight.Medium)
            }
        } else {
            val idx = vm.gameIdx.coerceIn(0, gs.size - 1)
            val g = gs[idx]
            val pop = popKey(g.pkg)
            Row(Modifier.fillMaxWidth().padding(vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                Box(Modifier.tap { vm.gameIdx = (idx - 1 + gs.size) % gs.size }.padding(horizontal = 14.dp, vertical = 8.dp)) { SText("‹", 22.sp, SP.dim) }
                Column(
                    Modifier.weight(1f).graphicsLayer { alpha = pop; translationX = (1f - pop) * 20.dp.toPx() },
                    horizontalAlignment = Alignment.CenterHorizontally
                ) {
                    SText(g.label, 17.sp, SP.text, FontWeight.SemiBold)
                    SText(vm.gameModeText(g.pkg), 12.sp, SP.dim)
                    Spacer(Modifier.height(4.dp))
                    Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                        for (k in gs.indices) Box(Modifier.size(width = if (k == idx) 16.dp else 6.dp, height = 3.dp).clip(CircleShape).background(if (k == idx) SP.gold else SP.faint))
                    }
                }
                Box(Modifier.tap { vm.gameIdx = (idx + 1) % gs.size }.padding(horizontal = 14.dp, vertical = 8.dp)) { SText("›", 22.sp, SP.dim) }
            }
        }
    }
}

@Composable
private fun StartButton(vm: HsinVm) {
    val clock = LocalClock.current
    val gs = vm.games
    val sh = RoundedCornerShape(10.dp)
    Box(
        Modifier
            .fillMaxWidth()
            .rise(400)
            .tap { if (gs.isNotEmpty()) vm.launchGame(gs[vm.gameIdx.coerceIn(0, gs.size - 1)].pkg) else vm.message = "Tambah game dulu di tab Game" }
            .clip(sh)
            .background(Brush.horizontalGradient(listOf(SP.red, Color(0xFFE08A4E), SP.gold)))
            .drawBehind {
                val x = (((clock.floatValue % 2.6f) / 2.6f) * 1.7f - 0.3f) * size.width
                drawRect(Brush.horizontalGradient(listOf(Color.Transparent, Color(0x55FFFFFF), Color.Transparent), startX = x, endX = x + size.width * 0.3f))
            }
            .padding(vertical = 15.dp),
        contentAlignment = Alignment.Center
    ) { SText("▶  MULAI GAME", 16.sp, Color.White, FontWeight.Bold, 2.sp) }
}

// ===================== GAME =====================
@Composable
private fun GameTab(vm: HsinVm) {
    var picker by remember { mutableStateOf(false) }
    LazyColumn(
        Modifier.fillMaxSize(),
        contentPadding = androidx.compose.foundation.layout.PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        item { SText("GAME", 12.sp, SP.gold, spacing = 2.sp, modifier = Modifier.rise(0)) }
        item {
            Glass(Modifier.fillMaxWidth().rise(40)) {
                Column(Modifier.padding(12.dp)) {
                    SText("Tiap game punya mode dan resolusi sendiri. \"Ikut\" = pakai mode yang dipilih di Beranda.", 12.sp, SP.dim)
                }
            }
        }
        items(vm.games, key = { it.pkg }) { g -> GameCard(vm, g) }
        item {
            Box(
                Modifier.fillMaxWidth().tap { vm.loadApps(); picker = true }.clip(RoundedCornerShape(10.dp))
                    .border(1.dp, SP.gold, RoundedCornerShape(10.dp)).padding(vertical = 13.dp),
                contentAlignment = Alignment.Center
            ) { SText("+ Tambah game", 14.sp, SP.gold, FontWeight.Medium) }
        }
    }
    if (picker) AppPicker(vm, onDismiss = { picker = false }) { vm.addGame(it); vm.openGame = null; picker = false }
}

private val CHIPS = listOf("global" to "Ikut", "hemat" to "Hemat", "bawaan" to "Bawaan", "seimbang" to "Seimbang", "boost" to "Boost")

@Composable
private fun GameCard(vm: HsinVm, g: GameProfile) {
    val c = vm.cfgOf(g.pkg)
    var res by remember(g.pkg) { mutableFloatStateOf(c.second.toFloat()) }
    Glass(Modifier.fillMaxWidth().rise(80, g.pkg)) {
        Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f)) {
                    SText(g.label, 16.sp, SP.text, FontWeight.SemiBold)
                    SText(g.pkg, 10.sp, SP.faint)
                }
            }
            Row(horizontalArrangement = Arrangement.spacedBy(5.dp)) {
                for ((k, n) in CHIPS) {
                    val sel = c.first == k
                    val a = ownAnim(if (sel) 1f else 0f, 200)
                    Box(
                        Modifier.weight(1f).tap { vm.setGameCfg(g.pkg, k, res.toInt()) }.clip(RoundedCornerShape(8.dp))
                            .background(lerpColor(Color(0x22FFFFFF), SP.gold, a)).padding(vertical = 8.dp),
                        contentAlignment = Alignment.Center
                    ) { SText(n, 11.sp, lerpColor(SP.text, SP.ink, a), FontWeight.Medium) }
                }
            }
            Row(verticalAlignment = Alignment.CenterVertically) {
                SText("Resolusi", 12.sp, SP.dim, modifier = Modifier.width(66.dp))
                Slider(
                    value = res,
                    onValueChange = { res = it },
                    onValueChangeFinished = { vm.setGameCfg(g.pkg, c.first, res.toInt()) },
                    valueRange = 50f..100f,
                    steps = 9,
                    colors = SliderDefaults.colors(thumbColor = SP.gold, activeTrackColor = SP.gold, inactiveTrackColor = Color(0x33FFFFFF), activeTickColor = Color.Transparent, inactiveTickColor = Color.Transparent),
                    modifier = Modifier.weight(1f)
                )
                SText("${res.toInt()}%", 13.sp, SP.text, modifier = Modifier.width(46.dp))
            }
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Box(
                    Modifier.weight(1f).tap { vm.launchGame(g.pkg) }.clip(RoundedCornerShape(8.dp))
                        .background(Brush.horizontalGradient(listOf(SP.red, SP.gold))).padding(vertical = 10.dp),
                    contentAlignment = Alignment.Center
                ) { SText("▶ LUNCURKAN", 12.sp, Color.White, FontWeight.Bold, 1.sp) }
                Box(
                    Modifier.tap { vm.removeGame(g.pkg) }.clip(RoundedCornerShape(8.dp)).border(0.6.dp, SP.line, RoundedCornerShape(8.dp)).padding(horizontal = 16.dp, vertical = 10.dp),
                    contentAlignment = Alignment.Center
                ) { SText("HAPUS", 12.sp, SP.dim) }
            }
        }
    }
}

// ===================== REKAMAN =====================
@Composable
private fun RecTab(vm: HsinVm) {
    LaunchedEffect(Unit) { vm.loadRecs() }
    LazyColumn(
        Modifier.fillMaxSize(),
        contentPadding = androidx.compose.foundation.layout.PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        item { SText("REKAMAN FPS", 12.sp, SP.gold, spacing = 2.sp, modifier = Modifier.rise(0)) }
        item {
            Glass(Modifier.fillMaxWidth().rise(40)) {
                Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    SText("Cara merekam", 13.sp, SP.text, FontWeight.SemiBold)
                    Text("Mulai game dari HSIN, ketuk logo FPS yang melayang, lalu pilih REKAM FPS. Berhenti merekam untuk menyimpan ke folder Download.", color = SP.dim, fontSize = 12.sp, lineHeight = 16.sp)
                }
            }
        }
        if (vm.recs.isEmpty()) item { SText("Belum ada rekaman.", 13.sp, SP.faint) }
        items(vm.recs, key = { it.name }) { r -> RecCard(vm, r) }
        item {
            Box(Modifier.fillMaxWidth().tap { vm.loadRecs() }.clip(RoundedCornerShape(10.dp)).border(1.dp, SP.gold, RoundedCornerShape(10.dp)).padding(vertical = 12.dp), contentAlignment = Alignment.Center) {
                SText("Muat ulang", 13.sp, SP.gold, FontWeight.Medium)
            }
        }
    }
}

@Composable
private fun RecCard(vm: HsinVm, r: RecItem) {
    Glass(Modifier.fillMaxWidth().rise(60, r.name)) {
        Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f)) {
                    SText(vm.gameLabel(r.pkg.replace('_', '.')), 14.sp, SP.text, FontWeight.SemiBold)
                    SText("${r.secs / 60} mnt ${r.secs % 60} dtk", 11.sp, SP.faint)
                }
                Box(Modifier.tap { vm.deleteRec(r.name) }.padding(8.dp)) { SText("HAPUS", 11.sp, SP.dim) }
            }
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                RStat("Rata-rata", String.format(Locale.US, "%.0f", r.avg))
                RStat("1% low", String.format(Locale.US, "%.0f", r.low1))
                RStat("Maks", String.format(Locale.US, "%.0f", r.max))
                RStat("Suhu maks", if (r.tMax > 0) "${r.tMax}°" else "--")
            }
            Canvas(Modifier.fillMaxWidth().height(44.dp)) {
                val s = r.series
                if (s.size < 2) return@Canvas
                val mx = maxOf(60f, s.maxOrNull() ?: 60f)
                val path = Path()
                val step = size.width / (s.size - 1)
                for (i in s.indices) {
                    val x = i * step; val y = size.height - (s[i].coerceAtLeast(0f) / mx) * size.height
                    if (i == 0) path.moveTo(x, y) else path.lineTo(x, y)
                }
                drawPath(path, SP.gold, style = Stroke(1.6.dp.toPx(), cap = StrokeCap.Round))
            }
        }
    }
}

@Composable
private fun RStat(k: String, v: String) {
    Column { SText(k, 10.sp, SP.dim); SText(v, 15.sp, SP.text, FontWeight.SemiBold) }
}

// ===================== PENGATURAN =====================
@Composable
private fun SettingsTab(vm: HsinVm) {
    val ctx = LocalContext.current
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        SText("PENGATURAN", 12.sp, SP.gold, spacing = 2.sp, modifier = Modifier.rise(0))
        SwitchRow("Jangan ganggu otomatis saat game", "Notifikasi dibisukan selama game jalan, balik normal saat game ditutup.", vm.dndGame, 40) { vm.setDndGame(it) }
        SwitchRow("Floating FPS saat game", "Logo FPS melayang; ketuk untuk panel, ganti mode, dan rekam.", vm.hudOn, 80) { vm.setHudOn(it) }
        if (!Hud.canDraw(ctx)) {
            Glass(Modifier.fillMaxWidth().tap { ctx.startActivity(Hud.permissionIntent(ctx)) }.rise(120)) {
                Column(Modifier.padding(12.dp)) {
                    SText("Beri izin tampil di atas aplikasi lain", 14.sp, SP.gold, FontWeight.SemiBold)
                    SText("Dibutuhkan supaya floating FPS bisa muncul di dalam game. Ketuk di sini.", 12.sp, SP.dim)
                }
            }
        }
        val d = vm.device
        Glass(Modifier.fillMaxWidth().rise(160)) {
            Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                SText("Perangkat", 12.sp, SP.dim)
                SText(if (d != null) "${d.brand} ${d.model}" else "-", 14.sp, SP.text, FontWeight.Medium)
                SText(if (d != null) "${d.soc} · Android ${d.android}" else "", 12.sp, SP.dim)
                SText(if (vm.conflicts.isEmpty()) "Tidak ada modul tuning lain terdeteksi" else "Modul lain: " + vm.conflicts.joinToString(", "), 11.sp, if (vm.conflicts.isEmpty()) SP.faint else SP.gold)
            }
        }
        Row(Modifier.fillMaxWidth().rise(200), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            QBtn("Salin laporan", false, Modifier.weight(1f)) { vm.copyReport() }
            QBtn("Pulihkan bawaan", false, Modifier.weight(1f)) { vm.restoreDefaults(); vm.setModeLocal("bawaan") }
        }
        Box(
            Modifier.fillMaxWidth().rise(240).tap { vm.advanced = true }.clip(RoundedCornerShape(10.dp)).border(1.dp, SP.gold, RoundedCornerShape(10.dp)).padding(vertical = 14.dp),
            contentAlignment = Alignment.Center
        ) { SText("Lanjutan: tuning manual (CPU, GPU, RAM, I/O)", 13.sp, SP.gold, FontWeight.Medium) }
        Spacer(Modifier.height(12.dp))
    }
}

@Composable
private fun SwitchRow(title: String, sub: String, on: Boolean, delayMs: Int, onChange: (Boolean) -> Unit) {
    Glass(Modifier.fillMaxWidth().rise(delayMs)) {
        Row(Modifier.padding(12.dp), verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                SText(title, 14.sp, SP.text, FontWeight.Medium)
                Text(sub, color = SP.dim, fontSize = 11.sp, lineHeight = 14.sp)
            }
            Spacer(Modifier.width(8.dp))
            Switch(
                checked = on, onCheckedChange = onChange,
                colors = SwitchDefaults.colors(checkedThumbColor = SP.ink, checkedTrackColor = SP.gold, uncheckedThumbColor = SP.dim, uncheckedTrackColor = Color(0x33FFFFFF), uncheckedBorderColor = SP.line)
            )
        }
    }
}

/** Tombol kecil di layar Lanjutan untuk kembali ke Game Space. */
@Composable
fun BackToSpace(vm: HsinVm, modifier: Modifier) {
    BackHandler(enabled = vm.advanced && vm.openCat == null && vm.openGame == null && !vm.customOpen) { vm.advanced = false }
    Box(
        modifier.padding(12.dp).clip(CircleShape).background(SP.gold).tap { vm.advanced = false }.padding(horizontal = 14.dp, vertical = 8.dp)
    ) { SText("← GAME SPACE", 11.sp, SP.ink, FontWeight.Bold, 1.sp) }
}
