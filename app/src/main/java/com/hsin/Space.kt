package com.hsin

import android.app.ActivityManager
import android.content.Context
import androidx.activity.compose.BackHandler
import androidx.compose.runtime.produceState
import androidx.compose.runtime.mutableIntStateOf
import kotlinx.coroutines.launch
import androidx.lifecycle.viewModelScope
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
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.platform.LocalContext
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.TextButton
import androidx.compose.foundation.clickable
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.text.TextStyle
import androidx.compose.foundation.layout.heightIn
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

val LocalEn = staticCompositionLocalOf { false }

@Composable
fun tx(id: String, en: String): String = if (LocalEn.current) en else id

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

// ===================== state UI =====================
object UiState {
    var en by mutableStateOf(false)
    var portrait by mutableStateOf(false)
    var tab by mutableIntStateOf(0)
    var gameIdx by mutableIntStateOf(0)
    private var inited = false
    fun init(p: Prefs) {
        if (inited) return
        inited = true
        en = p.sp.getBoolean("hsin_en", false)
        portrait = p.sp.getBoolean("hsin_portrait", false)
    }
    fun setEn(p: Prefs, v: Boolean) { en = v; p.sp.edit().putBoolean("hsin_en", v).apply() }
    fun setPortrait(p: Prefs, v: Boolean) { portrait = v; p.sp.edit().putBoolean("hsin_portrait", v).apply() }
}

// ===================== mode =====================
private class MInfo(val key: String, val nameId: String, val nameEn: String, val stars: Int, val tagId: String, val tagEn: String, val detId: String, val detEn: String)

private val MODES = listOf(
    MInfo("hemat", "Hemat", "Saver", 1, "Irit baterai, tetap lancar", "Saves battery, still smooth",
        "Profil harian Alpha: hemat tapi tidak ngelag. Cocok untuk game ringan dan pemakaian harian.",
        "Alpha daily profile: efficient without lag. Good for light games and everyday use."),
    MInfo("seimbang", "Seimbang", "Balanced", 2, "Lancar dan adem untuk sesi panjang", "Smooth and cool for long sessions",
        "Profil balanced: performa cukup untuk kebanyakan game, suhu dan baterai tetap terjaga.",
        "Balanced profile: enough power for most games while keeping heat and battery in check."),
    MInfo("performa", "Performa", "Performance", 3, "Tenaga tinggi untuk game berat", "High power for heavy games",
        "Profil performa Alpha: CPU/GPU agresif, tetap dijaga pengaman panas.",
        "Alpha performance profile: aggressive CPU/GPU, still protected by the thermal guard."),
    MInfo("gacor", "Gacor", "Gacor", 4, "Tanpa batas, CPU/GPU dikunci penuh", "No limits, CPU/GPU locked at full speed",
        "Overdrive Alpha: CPU dan GPU dikunci frekuensi tertinggi, batas panas dilonggarkan. Paling kencang, HP lebih hangat.",
        "Alpha Overdrive: CPU and GPU locked at top frequency, thermal limit relaxed. Fastest, phone runs warmer.")
)

private fun info(k: String): MInfo = MODES.firstOrNull { it.key == k } ?: MODES[1]

@Composable
private fun mname(m: MInfo): String = if (LocalEn.current) m.nameEn else m.nameId

private fun starText(n: Int): String = "★".repeat(n) + "☆".repeat(4 - n)

private fun curMode(vm: AppViewModel): String {
    if (vm.status.ovd) return "gacor"
    return when (vm.status.profile) { "battery" -> "hemat"; "performance" -> "performa"; "balanced" -> "seimbang"; else -> "" }
}

private fun profMode(profile: String, ovd: Boolean): String =
    if (ovd) "gacor" else when (profile) { "battery" -> "hemat"; "performance" -> "performa"; else -> "seimbang" }

fun AppViewModel.chooseMode(key: String) {
    val prof = when (key) { "hemat" -> "battery"; "seimbang" -> "balanced"; else -> "performance" }
    status = status.copy(profile = prof, active = prof, ovd = key == "gacor")
    viewModelScope.launch {
        if (key != "gacor") Alpha.ovdStop()
        val r = Alpha.setProfile(prof)
        if (key == "gacor") {
            val o = Alpha.ovdStart()
            toast(if (o.ok) (if (UiState.en) "Gacor on" else "Gacor aktif") else o.out.lines().firstOrNull { it.isNotBlank() } ?: "Gagal")
        } else {
            toast(if (r.ok) (if (UiState.en) "Mode applied" else "Mode diterapkan") else r.out.take(60))
        }
        refreshStatus()
    }
}

// ===================== akar =====================
@Composable
fun SpaceRoot(vm: AppViewModel) {
    val clock = LocalClock.current
    var splashDone by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) {
        delay(1500)
        var n = 0
        while (!vm.loaded && n < 100) { delay(100); n++ }
        splashDone = true
    }
    BoxWithConstraints(Modifier.fillMaxSize().background(Color(0xFF0C0C0E))) {
        val land = maxWidth > maxHeight
        val compact = maxHeight < 300.dp
        Image(painterResource(R.drawable.wallpaper_default), null, contentScale = ContentScale.Crop, modifier = Modifier.fillMaxSize())
        Box(
            Modifier.fillMaxSize().background(
                if (land) Brush.horizontalGradient(listOf(Color(0xE60A0A0C), Color(0x990A0A0C), Color(0x330A0A0C)))
                else Brush.verticalGradient(listOf(Color(0x990A0A0C), Color(0xE60A0A0C)))
            )
        )
        Embers()
        if (land) {
            Row(Modifier.fillMaxSize().systemBarsPadding()) {
                NavRail(compact)
                SpaceContent(vm, true, Modifier.weight(1f).fillMaxHeight())
            }
        } else {
            Column(Modifier.fillMaxSize().systemBarsPadding()) {
                SpaceContent(vm, false, Modifier.weight(1f).fillMaxWidth())
                NavBar()
            }
        }
        Splash(splashDone)
    }
}

@Composable
private fun SpaceContent(vm: AppViewModel, land: Boolean, modifier: Modifier) {
    Box(modifier) {
        if (vm.loaded && !vm.rootOk) {
            NoticeCard(tx("Akses root belum diberikan", "Root access not granted"), tx("Buka manager root (KernelSU/Magisk/APatch) dan izinkan HSIN, lalu coba lagi.", "Open your root manager and allow HSIN, then retry."), vm)
        } else if (vm.loaded && vm.modPath.isEmpty()) {
            NoticeCard(tx("Modul HSIN belum aktif", "HSIN module is not active"), tx("Flash modul HSIN lewat manager root, reboot, lalu buka app ini lagi.", "Flash the HSIN module in your root manager, reboot, then open this app again."), vm)
        } else when (UiState.tab) {
            0 -> HomeTab(vm, land)
            1 -> GameTab(vm)
            2 -> RecTab(vm)
            else -> SettingsTab(vm)
        }
    }
}

@Composable
private fun NoticeCard(title: String, body: String, vm: AppViewModel) {
    Column(Modifier.fillMaxSize().padding(24.dp), verticalArrangement = Arrangement.Center) {
        Glass(Modifier.fillMaxWidth()) {
            Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                SText(title, 16.sp, SP.gold, FontWeight.SemiBold)
                Text(body, color = SP.dim, fontSize = 13.sp, lineHeight = 17.sp)
                Box(Modifier.tap { vm.refreshButton() }.clip(CircleShape).background(SP.gold).padding(horizontal = 16.dp, vertical = 8.dp)) {
                    SText(tx("COBA LAGI", "RETRY"), 12.sp, SP.ink, FontWeight.Bold, 1.sp)
                }
            }
        }
    }
}

@Composable
private fun Splash(done: Boolean) {
    val clock = LocalClock.current
    val off = ownAnim(if (done) 1f else 0f, 600)
    if (off >= 1f) return
    Box(
        Modifier.fillMaxSize().graphicsLayer { alpha = 1f - off }.background(Color(0xFF0C0C0E)).pointerInput(Unit) { detectTapGestures { } },
        contentAlignment = Alignment.Center
    ) {
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Box(Modifier.graphicsLayer { val k = 1f + 0.05f * sin(clock.floatValue * 3f); scaleX = k; scaleY = k }) { Logo(84) }
            Spacer(Modifier.height(14.dp))
            SText("HSIN", 26.sp, SP.goldHi, FontWeight.Bold, 8.sp)
            Spacer(Modifier.height(14.dp))
            Box(Modifier.width(180.dp).height(3.dp).clip(CircleShape).background(Color(0x22FFFFFF)).drawBehind {
                val w = size.width * 0.35f
                val x = (((clock.floatValue * 0.9f) % 1f) * (size.width + w)) - w
                val l = x.coerceAtLeast(0f)
                drawRoundRect(SP.gold, Offset(l, 0f), Size(((x + w).coerceAtMost(size.width) - l).coerceAtLeast(0f), size.height), CornerRadius(4f))
            })
            Spacer(Modifier.height(10.dp))
            SText(tx("Memuat...", "Loading..."), 12.sp, SP.dim)
        }
    }
}

// ===================== hiasan =====================
@Composable
private fun Embers() {
    val clock = LocalClock.current
    Canvas(Modifier.fillMaxSize()) {
        val t = clock.floatValue
        for (i in 0 until 18) {
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
@Composable
private fun navName(i: Int): String = when (i) {
    0 -> tx("Beranda", "Home"); 1 -> tx("Game", "Games"); 2 -> tx("Rekaman", "Records"); else -> tx("Pengaturan", "Settings")
}

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
                    val kx = w * (0.30f + 0.2f * ((k * 2) % 3))
                    drawLine(color, Offset(w * 0.1f, y), Offset(w * 0.9f, y), st.width, StrokeCap.Round)
                    drawCircle(SP.ink, w * 0.09f, Offset(kx, y))
                    drawCircle(color, w * 0.09f, Offset(kx, y), style = st)
                }
            }
        }
    }
}

@Composable
private fun NavRail(compact: Boolean) {
    Column(
        Modifier.width(if (compact) 64.dp else 84.dp).fillMaxHeight().background(Color(0x99000000)).verticalScroll(rememberScrollState()).padding(vertical = if (compact) 6.dp else 12.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(if (compact) 2.dp else 6.dp)
    ) {
        Logo(if (compact) 36 else 44)
        for (i in 0 until 4) NavItem(i, compact)
    }
}

@Composable
private fun NavBar() {
    Row(Modifier.fillMaxWidth().background(Color(0xCC000000)).padding(vertical = 6.dp), horizontalArrangement = Arrangement.SpaceEvenly) {
        for (i in 0 until 4) NavItem(i, false)
    }
}

@Composable
private fun Logo(dp: Int) {
    Box(Modifier.size(dp.dp).clip(RoundedCornerShape((dp / 4).dp)).background(Color(0xFF15121A)).border(1.dp, SP.gold.copy(alpha = 0.6f), RoundedCornerShape((dp / 4).dp))) {
        Image(
            painterResource(R.drawable.ic_launcher_foreground), null, contentScale = ContentScale.Crop,
            modifier = Modifier.fillMaxSize().graphicsLayer { scaleX = 1.45f; scaleY = 1.45f }
        )
    }
}

@Composable
private fun NavItem(i: Int, compact: Boolean) {
    val sel = UiState.tab == i
    val a = ownAnim(if (sel) 1f else 0f, 220)
    val col = lerpColor(SP.dim, SP.gold, a)
    Column(Modifier.tap { UiState.tab = i }.padding(horizontal = 8.dp, vertical = 4.dp), horizontalAlignment = Alignment.CenterHorizontally) {
        Box(
            Modifier.clip(RoundedCornerShape(14.dp)).background(SP.gold.copy(alpha = 0.16f * a)).padding(horizontal = 14.dp, vertical = if (compact) 4.dp else 6.dp),
            contentAlignment = Alignment.Center
        ) { NavIcon(i, col) }
        if (!compact) SText(navName(i), 10.sp, col)
    }
}

private fun lerpColor(a: Color, b: Color, t: Float): Color = Color(
    red = a.red + (b.red - a.red) * t, green = a.green + (b.green - a.green) * t,
    blue = a.blue + (b.blue - a.blue) * t, alpha = a.alpha + (b.alpha - a.alpha) * t
)

// ===================== data live (CPU/GPU/suhu) =====================
private class Live(val cpu: Int, val gpuMhz: Int, val gpuPct: Int, val tempC: Int)

@Composable
private fun rememberLive(vm: AppViewModel, active: Boolean): Live {
    var live by remember { mutableStateOf(Live(-1, -1, -1, -1)) }
    LaunchedEffect(active, vm.modPath) {
        if (!active || vm.modPath.isEmpty()) return@LaunchedEffect
        var pt = 0L; var pi = 0L
        while (true) {
            val r = Root.exec("sh '${vm.modPath}/common/hud_sample.sh' --once x", 10_000L)
            val m = HashMap<String, String>()
            for (l in r.out.lines()) { val i = l.indexOf('='); if (i > 0) m[l.substring(0, i)] = l.substring(i + 1).trim() }
            var cpu = -1
            val p = m["cpu"].orEmpty().split(Regex("\\s+")).filter { it.isNotEmpty() }
            if (p.size >= 9 && p[0] == "cpu") {
                val v = p.drop(1).take(8).map { it.toLongOrNull() ?: 0L }
                val tot = v.sum(); val idle = v[3] + v[4]
                if (pt > 0L && tot > pt) cpu = (((tot - pt) - (idle - pi)) * 100 / (tot - pt)).toInt().coerceIn(0, 100)
                pt = tot; pi = idle
            }
            val gp = m["gpu"]?.toIntOrNull() ?: -1
            val gm = m["gpu_freq"]?.toIntOrNull() ?: -1
            val soc = (m["soc_mc"]?.toIntOrNull() ?: 0) / 1000
            val bat = (m["temp_mc"]?.toIntOrNull() ?: 0) / 1000
            live = Live(cpu, gm, gp, if (soc in 1..105) soc else if (bat in 1..105) bat else -1)
            delay(2500)
        }
    }
    return live
}

private fun ramInfo(ctx: Context): Pair<Float, Float> {
    val mi = ActivityManager.MemoryInfo()
    (ctx.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager).getMemoryInfo(mi)
    val tot = mi.totalMem / 1073741824f
    return Pair(tot - mi.availMem / 1073741824f, tot)
}

// ===================== BERANDA =====================
@Composable
private fun HomeTab(vm: AppViewModel, land: Boolean) {
    val live = rememberLive(vm, true)
    if (land) {
        Row(Modifier.fillMaxSize().padding(16.dp), horizontalArrangement = Arrangement.spacedBy(14.dp)) {
            Column(Modifier.weight(1.15f).fillMaxHeight(), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                ModeHeader(vm)
                ModeTiles(vm)
                StatTiles(vm, live)
            }
            Column(Modifier.weight(0.85f).fillMaxHeight(), verticalArrangement = Arrangement.spacedBy(8.dp), horizontalAlignment = Alignment.End) {
                Chips(vm, live)
                Spacer(Modifier.weight(1f))
                QuickButtons(vm)
                GameCarousel(vm)
                StartButton(vm)
            }
        }
    } else {
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(14.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) { Chips(vm, live) }
            ModeHeader(vm)
            ModeTiles(vm)
            StatTiles(vm, live)
            QuickButtons(vm)
            GameCarousel(vm)
            StartButton(vm)
        }
    }
}

@Composable
private fun Chips(vm: AppViewModel, live: Live) {
    val ctx = LocalContext.current
    val (u, t) = ramInfo(ctx)
    val tmp = if (live.tempC > 0) "${live.tempC}°" else "--"
    val bat = if (vm.status.batt >= 0) "${vm.status.batt}%" else "--"
    Row(Modifier.rise(0), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        Chip(SP.gold, String.format(Locale.US, "%.1f/%.1fG", u, t)); Chip(SP.red, tmp); Chip(Color(0xFF4FC3A1), bat)
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
private fun ModeHeader(vm: AppViewModel) {
    val cm = curMode(vm)
    val m = info(cm)
    val pop = popKey(cm)
    var showDetail by remember { mutableStateOf(false) }
    val playing = vm.status.gamePkg.isNotEmpty()
    Glass(Modifier.fillMaxWidth().rise(60)) {
        Row {
            Box(Modifier.width(3.dp).height(if (showDetail) 150.dp else 104.dp).background(SP.gold))
            Column(Modifier.padding(horizontal = 14.dp, vertical = 10.dp)) {
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                    SText(tx("MODE SAAT INI", "CURRENT MODE"), 11.sp, SP.dim, spacing = 1.6.sp)
                    SText(if (playing) tx("SEDANG MAIN", "PLAYING") else tx("DIPILIH", "SELECTED"), 11.sp, SP.gold, spacing = 1.6.sp)
                }
                Row(Modifier.graphicsLayer { alpha = pop; translationX = (1f - pop) * 18.dp.toPx() }, verticalAlignment = Alignment.Bottom) {
                    SText(if (cm.isEmpty()) "—" else mname(m), 30.sp, SP.goldHi, FontWeight.Bold)
                    Spacer(Modifier.width(10.dp))
                    SText(starText(if (cm.isEmpty()) 0 else m.stars), 15.sp, SP.gold, modifier = Modifier.padding(bottom = 5.dp))
                }
                SText(if (LocalEn.current) m.tagEn else m.tagId, 13.sp, SP.dim)
                Box(Modifier.tap { showDetail = !showDetail }.padding(vertical = 6.dp)) {
                    SText(if (showDetail) tx("Tutup ▴", "Close ▴") else tx("Detail ▾", "Details ▾"), 13.sp, SP.gold)
                }
                if (showDetail) Text(if (LocalEn.current) m.detEn else m.detId, color = SP.dim, fontSize = 12.sp, lineHeight = 16.sp)
            }
        }
    }
}

@Composable
private fun ModeTiles(vm: AppViewModel) {
    val clock = LocalClock.current
    val cm = curMode(vm)
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        MODES.forEachIndexed { i, m ->
            val sel = cm == m.key
            val a = ownAnim(if (sel) 1f else 0f, 240)
            Box(
                Modifier
                    .weight(1f)
                    .rise(120 + i * 60)
                    .tap { vm.chooseMode(m.key) }
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
                    SText(mname(m), 14.sp, lerpColor(SP.text, SP.goldHi, a), FontWeight.SemiBold)
                    Spacer(Modifier.height(3.dp))
                    SText("★".repeat(m.stars), 10.sp, SP.gold)
                }
            }
        }
    }
}

@Composable
private fun StatTiles(vm: AppViewModel, live: Live) {
    val ctx = LocalContext.current
    val (u, _) = ramInfo(ctx)
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        Stat("CPU", live.cpu.toFloat(), "%", 0, Modifier.weight(1f).rise(380))
        if (live.gpuPct >= 0) Stat("GPU", live.gpuPct.toFloat(), "%", 0, Modifier.weight(1f).rise(430))
        else Stat("GPU", live.gpuMhz.toFloat(), " MHz", 0, Modifier.weight(1f).rise(430))
        Stat(tx("Suhu", "Temp"), live.tempC.toFloat(), "°C", 0, Modifier.weight(1f).rise(480))
        Stat("RAM", u, " GB", 1, Modifier.weight(1f).rise(530))
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
private fun QuickButtons(vm: AppViewModel) {
    val dnd = vm.flag("GAME_DND_ON")
    Row(Modifier.fillMaxWidth().rise(300), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        QBtn(tx("Bersihkan RAM", "Clean RAM"), false, Modifier.weight(1f)) { vm.cleanRam() }
        QBtn(tx("Jangan ganggu", "Do not disturb"), dnd, Modifier.weight(1f)) { vm.setFlag("GAME_DND_ON", !dnd) }
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
private fun gameModeText(vm: AppViewModel, g: GameEntry): String {
    val opts by produceState<Map<String, String>>(emptyMap(), g.pkg, vm.games) { value = Alpha.gameOpts(g.pkg) }
    val fx by produceState<Map<String, String>>(emptyMap(), g.pkg, vm.games) { value = Alpha.gamefx(g.pkg) }
    val m = info(profMode(g.profile, opts["OVD"] == "on"))
    val ds = fx["downscale"].orEmpty()
    val res = ds.toDoubleOrNull()?.let { "${Math.round(it * 100)}%" } ?: "100%"
    return if (LocalEn.current) "${m.nameEn} mode · Resolution $res" else "Mode ${m.nameId} · Resolusi $res"
}

@Composable
private fun GameCarousel(vm: AppViewModel) {
    val gs = vm.games
    Glass(Modifier.fillMaxWidth().rise(340)) {
        if (gs.isEmpty()) {
            Box(Modifier.fillMaxWidth().tap { vm.go("addgame") }.padding(vertical = 14.dp), contentAlignment = Alignment.Center) {
                SText(tx("+ Tambah game dulu", "+ Add a game first"), 14.sp, SP.gold, FontWeight.Medium)
            }
        } else {
            val idx = UiState.gameIdx.coerceIn(0, gs.size - 1)
            val g = gs[idx]
            val pop = popKey(g.pkg)
            Row(Modifier.fillMaxWidth().padding(vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                Box(Modifier.tap { UiState.gameIdx = (idx - 1 + gs.size) % gs.size }.padding(horizontal = 14.dp, vertical = 8.dp)) { SText("‹", 22.sp, SP.dim) }
                Column(Modifier.weight(1f).graphicsLayer { alpha = pop; translationX = (1f - pop) * 20.dp.toPx() }, horizontalAlignment = Alignment.CenterHorizontally) {
                    SText(vm.label(g.pkg), 17.sp, SP.text, FontWeight.SemiBold)
                    SText(gameModeText(vm, g), 12.sp, SP.dim)
                    Spacer(Modifier.height(4.dp))
                    Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                        for (k in gs.indices) Box(Modifier.size(width = if (k == idx) 16.dp else 6.dp, height = 3.dp).clip(CircleShape).background(if (k == idx) SP.gold else SP.faint))
                    }
                }
                Box(Modifier.tap { UiState.gameIdx = (idx + 1) % gs.size }.padding(horizontal = 14.dp, vertical = 8.dp)) { SText("›", 22.sp, SP.dim) }
            }
        }
    }
}

@Composable
private fun StartButton(vm: AppViewModel) {
    val clock = LocalClock.current
    val gs = vm.games
    val sh = RoundedCornerShape(10.dp)
    Box(
        Modifier
            .fillMaxWidth()
            .rise(400)
            .tap { if (gs.isNotEmpty()) vm.launchGame(gs[UiState.gameIdx.coerceIn(0, gs.size - 1)].pkg) else vm.go("addgame") }
            .clip(sh)
            .background(Brush.horizontalGradient(listOf(SP.red, Color(0xFFE08A4E), SP.gold)))
            .drawBehind {
                val x = (((clock.floatValue % 2.6f) / 2.6f) * 1.7f - 0.3f) * size.width
                drawRect(Brush.horizontalGradient(listOf(Color.Transparent, Color(0x55FFFFFF), Color.Transparent), startX = x, endX = x + size.width * 0.3f))
            }
            .padding(vertical = 15.dp),
        contentAlignment = Alignment.Center
    ) { SText(tx("▶  MULAI GAME", "▶  START GAME"), 16.sp, Color.White, FontWeight.Bold, 2.sp) }
}

// ===================== GAME =====================
private val GCHIPS = listOf("hemat", "seimbang", "performa", "gacor")

@Composable
private fun GameTab(vm: AppViewModel) {
    LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        item { SText(tx("GAME", "GAMES"), 12.sp, SP.gold, spacing = 2.sp, modifier = Modifier.rise(0)) }
        items(vm.games, key = { it.pkg }) { g -> GameCard(vm, g) }
        item {
            Box(
                Modifier.fillMaxWidth().tap { vm.go("addgame") }.clip(RoundedCornerShape(10.dp)).border(1.dp, SP.gold, RoundedCornerShape(10.dp)).padding(vertical = 13.dp),
                contentAlignment = Alignment.Center
            ) { SText(tx("+ Tambah game", "+ Add game"), 14.sp, SP.gold, FontWeight.Medium) }
        }
    }
}

@Composable
private fun GameCard(vm: AppViewModel, g: GameEntry) {
    var ver by remember { mutableIntStateOf(0) }
    val opts by produceState<Map<String, String>>(emptyMap(), g.pkg, ver, vm.games) { value = Alpha.gameOpts(g.pkg) }
    val fx by produceState<Map<String, String>>(emptyMap(), g.pkg, ver) { value = Alpha.gamefx(g.pkg) }
    val cur = profMode(g.profile, opts["OVD"] == "on")
    var res by remember(g.pkg, fx["downscale"]) { mutableFloatStateOf(((fx["downscale"]?.toDoubleOrNull() ?: 1.0) * 100).toFloat().coerceIn(50f, 100f)) }
    Glass(Modifier.fillMaxWidth().rise(80, g.pkg)) {
        Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            SText(vm.label(g.pkg), 16.sp, SP.text, FontWeight.SemiBold)
            Row(horizontalArrangement = Arrangement.spacedBy(5.dp)) {
                for (k in GCHIPS) {
                    val m = info(k)
                    val sel = cur == k
                    val a = ownAnim(if (sel) 1f else 0f, 200)
                    Box(
                        Modifier.weight(1f).tap {
                            val prof = when (k) { "hemat" -> "battery"; "seimbang" -> "balanced"; else -> "performance" }
                            vm.addGame(g.pkg, g.fps, prof) { ver++ }
                            vm.setGameOpt(g.pkg, "OVD", if (k == "gacor") "on" else "off")
                            ver++
                        }.clip(RoundedCornerShape(8.dp)).background(lerpColor(Color(0x22FFFFFF), SP.gold, a)).padding(vertical = 8.dp),
                        contentAlignment = Alignment.Center
                    ) { SText(mname(m), 11.sp, lerpColor(SP.text, SP.ink, a), FontWeight.Medium) }
                }
            }
            Row(verticalAlignment = Alignment.CenterVertically) {
                SText(tx("Resolusi", "Resolution"), 12.sp, SP.dim, modifier = Modifier.width(66.dp))
                Slider(
                    value = res, onValueChange = { res = it },
                    onValueChangeFinished = {
                        val v = if (res >= 99.5f) "off" else String.format(Locale.US, "%.2f", res / 100f)
                        vm.setGameFx(g.pkg, "downscale", v)
                    },
                    valueRange = 50f..100f, steps = 9,
                    colors = SliderDefaults.colors(thumbColor = SP.gold, activeTrackColor = SP.gold, inactiveTrackColor = Color(0x33FFFFFF), activeTickColor = Color.Transparent, inactiveTickColor = Color.Transparent),
                    modifier = Modifier.weight(1f)
                )
                SText("${res.toInt()}%", 13.sp, SP.text, modifier = Modifier.width(46.dp))
            }
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Box(
                    Modifier.weight(1f).tap { vm.launchGame(g.pkg) }.clip(RoundedCornerShape(8.dp)).background(Brush.horizontalGradient(listOf(SP.red, SP.gold))).padding(vertical = 10.dp),
                    contentAlignment = Alignment.Center
                ) { SText(tx("▶ LUNCURKAN", "▶ LAUNCH"), 12.sp, Color.White, FontWeight.Bold, 1.sp) }
                Box(Modifier.tap { vm.editPkg = g.pkg; vm.go("edit") }.clip(RoundedCornerShape(8.dp)).border(0.6.dp, SP.line, RoundedCornerShape(8.dp)).padding(horizontal = 12.dp, vertical = 10.dp), contentAlignment = Alignment.Center) {
                    SText(tx("DETAIL", "MORE"), 12.sp, SP.text)
                }
                Box(Modifier.tap { vm.removeGame(g.pkg) }.clip(RoundedCornerShape(8.dp)).border(0.6.dp, SP.line, RoundedCornerShape(8.dp)).padding(horizontal = 12.dp, vertical = 10.dp), contentAlignment = Alignment.Center) {
                    SText(tx("HAPUS", "DELETE"), 12.sp, SP.dim)
                }
            }
        }
    }
}

// ===================== REKAMAN =====================
@Composable
private fun RecTab(vm: AppViewModel) {
    var files by remember { mutableStateOf<List<String>>(emptyList()) }
    LaunchedEffect(vm.recOn, vm.modPath) {
        vm.loadFpsFiles()
        if (vm.modPath.isNotEmpty()) {
            val r = Root.exec("sh '${vm.modPath}/common/screenrec.sh' list 10", 10_000L)
            files = r.out.lines().map { it.trim() }.filter { it.endsWith(".mp4") }
        }
    }
    LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        item { SText(tx("REKAMAN", "RECORDS"), 12.sp, SP.gold, spacing = 2.sp, modifier = Modifier.rise(0)) }
        item {
            Glass(Modifier.fillMaxWidth().rise(40)) {
                Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    SText(tx("Rekam layar", "Screen recording"), 14.sp, SP.text, FontWeight.SemiBold)
                    Text(tx("Hasil disimpan di Movies/Alpha (tanpa suara sistem).", "Saved to Movies/Alpha (no system audio)."), color = SP.dim, fontSize = 12.sp)
                    Box(
                        Modifier.fillMaxWidth().tap { vm.toggleRec() }.clip(RoundedCornerShape(10.dp)).background(if (vm.recOn) SP.red else SP.gold).padding(vertical = 12.dp),
                        contentAlignment = Alignment.Center
                    ) { SText(if (vm.recOn) tx("■ HENTIKAN REKAM", "■ STOP") else tx("● MULAI REKAM LAYAR", "● START RECORDING"), 13.sp, SP.ink, FontWeight.Bold, 1.sp) }
                    for (f in files.take(5)) SText(f, 11.sp, SP.faint)
                }
            }
        }
        item {
            Glass(Modifier.fillMaxWidth().rise(80)) {
                Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    SText(tx("Rekam FPS", "FPS recording"), 14.sp, SP.text, FontWeight.SemiBold)
                    Text(tx("Mulai game dari HSIN, ketuk logo floating, lalu REKAM FPS. Atau tombol di bawah. Hasil CSV di folder Download.", "Start a game from HSIN, tap the floating logo, then record FPS. Or use the button below. CSV goes to Downloads."), color = SP.dim, fontSize = 12.sp, lineHeight = 16.sp)
                    Box(
                        Modifier.fillMaxWidth().tap { vm.toggleFpsLog() }.clip(RoundedCornerShape(10.dp)).border(1.dp, SP.gold, RoundedCornerShape(10.dp)).padding(vertical = 11.dp),
                        contentAlignment = Alignment.Center
                    ) { SText(if (FpsLog.on) tx("■ HENTIKAN REKAM FPS", "■ STOP FPS LOG") else tx("● MULAI REKAM FPS", "● START FPS LOG"), 12.sp, SP.gold, FontWeight.Bold, 1.sp) }
                }
            }
        }
        if (vm.fpsFiles.isEmpty()) item { SText(tx("Belum ada rekaman FPS.", "No FPS records yet."), 13.sp, SP.faint) }
        items(vm.fpsFiles, key = { it.name }) { r -> RecCard(vm, r) }
    }
}

@Composable
private fun RecCard(vm: AppViewModel, r: FpsFile) {
    Glass(Modifier.fillMaxWidth().rise(60, r.name)) {
        Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            SText(vm.label(r.pkg), 14.sp, SP.text, FontWeight.SemiBold)
            SText("${r.secs / 60} ${tx("mnt", "min")} ${r.secs % 60} ${tx("dtk", "s")}", 11.sp, SP.faint)
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                RStat(tx("Rata-rata", "Average"), String.format(Locale.US, "%.0f", r.avg))
                RStat("1% low", String.format(Locale.US, "%.0f", r.low1))
                RStat(tx("Suhu maks", "Max temp"), if (r.tMax > 0) "${r.tMax}°" else "--")
            }
            Canvas(Modifier.fillMaxWidth().height(44.dp)) {
                val s = r.fpsS
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
private fun SettingsTab(vm: AppViewModel) {
    val ctx = LocalContext.current
    LaunchedEffect(vm.modPath) { vm.refreshRates = Alpha.refreshList(); vm.refreshHz = Alpha.refreshGet() }
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        SText(tx("PENGATURAN", "SETTINGS"), 12.sp, SP.gold, spacing = 2.sp, modifier = Modifier.rise(0))
        Glass(Modifier.fillMaxWidth().rise(30)) {
            Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                SText(tx("Bahasa", "Language"), 12.sp, SP.dim)
                Seg(listOf("Indonesia", "English"), if (UiState.en) 1 else 0) { UiState.setEn(vm.prefs, it == 1) }
                SText(tx("Tampilan layar", "Screen layout"), 12.sp, SP.dim)
                Seg(listOf(tx("Landscape", "Landscape"), tx("Potret", "Portrait")), if (UiState.portrait) 1 else 0) { UiState.setPortrait(vm.prefs, it == 1) }
            }
        }
        SwitchRow(tx("Floating (logo FPS)", "Floating (FPS logo)"), tx("Logo melayang di game: ketuk untuk panel, ganti mode, rekam.", "Floating logo in games: tap for panel, mode switch, recording."), vm.bubbleOn, 60) { vm.updateBubbleOn(it) }
        SwitchRow(tx("Tampilkan FPS di floating", "Show FPS in floating"), tx("Angka FPS, CPU, GPU, dan suhu.", "FPS, CPU, GPU and temperature readout."), vm.hudOn, 90) { vm.updateHudOn(it) }
        SwitchRow(tx("Jangan ganggu saat game", "Do not disturb in games"), tx("Notifikasi dibisukan selama game, balik normal setelah ditutup.", "Mutes notifications during games and restores them afterwards."), vm.flag("GAME_DND_ON"), 120) { vm.setFlag("GAME_DND_ON", it) }
        if (vm.refreshRates.isNotEmpty()) {
            Glass(Modifier.fillMaxWidth().rise(150)) {
                Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    SText(tx("Refresh rate saat game", "Refresh rate in games"), 14.sp, SP.text, FontWeight.Medium)
                    val opts = listOf("off") + vm.refreshRates.map { it.toString() }
                    Seg(opts.map { if (it == "off") tx("Sistem", "System") else "$it Hz" }, opts.indexOf(vm.refreshHz).coerceAtLeast(0)) { vm.updateRefreshHz(opts[it]) }
                }
            }
        }
        Row(Modifier.fillMaxWidth().rise(180), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            QBtn(tx("Semua alat Alpha", "All Alpha tools"), false, Modifier.weight(1f)) { vm.go("tools") }
            QBtn(tx("Tampilan floating", "Floating look"), false, Modifier.weight(1f)) { vm.go("bubble") }
        }
        Row(Modifier.fillMaxWidth().rise(210), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            QBtn(tx("Suhu & pengaman", "Thermal guard"), false, Modifier.weight(1f)) { vm.go("therm") }
            QBtn(tx("Log", "Logs"), false, Modifier.weight(1f)) { vm.go("fulllog") }
        }
        Spacer(Modifier.height(8.dp))
    }
}

@Composable
private fun Seg(options: List<String>, sel: Int, onPick: (Int) -> Unit) {
    Row(Modifier.fillMaxWidth().clip(CircleShape).background(Color(0x22FFFFFF)).padding(3.dp)) {
        options.forEachIndexed { i, o ->
            val a = ownAnim(if (i == sel) 1f else 0f, 200)
            Box(Modifier.weight(1f).tap { onPick(i) }.clip(CircleShape).background(lerpColor(Color.Transparent, SP.gold, a)).padding(vertical = 8.dp), contentAlignment = Alignment.Center) {
                SText(o, 12.sp, lerpColor(SP.text, SP.ink, a), FontWeight.Medium)
            }
        }
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
