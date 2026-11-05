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
object ThemeHolder {
    /** Warna aksen aktif (dipakai SP.gold di seluruh app). Diset Host sesuai pilihan tema. */
    val accent = androidx.compose.runtime.mutableStateOf(Color(0xFFE8B95A))
}

object SP {
    val gold: Color get() = ThemeHolder.accent.value
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
fun ownAnim(target: Float, msIn: Int = 300): Float {
    val ms = if (UiState.reduceAnim) 1 else msIn
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
fun popKey(key: Any, msIn: Int = 340): Float {
    val ms = if (UiState.reduceAnim) 1 else msIn
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
        val red = UiState.reduceAnim
        if (!red) delay(delayMs.toLong())
        val t0 = withFrameNanosCompat()
        while (true) {
            val now = withFrameNanosCompat()
            val k = ((now - t0) / 1_000_000f / (if (red) 1f else 440f)).coerceIn(0f, 1f)
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
    var themeTick by mutableStateOf(0)
    var haptics by mutableStateOf(true)
    var reduceAnim = false
    var bgDim by mutableStateOf(1)
    fun setReduce(p: Prefs, on: Boolean) { reduceAnim = on; p.reduceAnim = on; themeTick++ }
    var animLevel by mutableStateOf(1)
    fun setAnim(p: Prefs, lvl: Int) { animLevel = lvl; p.animLevel = lvl; reduceAnim = lvl == 0; themeTick++ }
    var view: android.view.View? = null
    fun setHaptics(p: Prefs, on: Boolean) { haptics = on; p.haptics = on }
    /** Getar halus (bisa dimatikan di Pengaturan). */
    var sndPrefs: Prefs? = null
    fun buzz() {
        sndPrefs?.let { SoundFx.play(it, "click") }
        if (!haptics) return
        try { view?.performHapticFeedback(android.view.HapticFeedbackConstants.CONTEXT_CLICK) } catch (_: Exception) {}
    }
    fun buzz2() { try { view?.performHapticFeedback(android.view.HapticFeedbackConstants.CONTEXT_CLICK) } catch (_: Exception) {} }
    var portrait by mutableStateOf(false)
    var tab by mutableIntStateOf(0)
    var gameIdx by mutableIntStateOf(0)
    var toolsSub by mutableIntStateOf(0)   // sub-tab Alat terakhir, supaya Back dari fitur kembali ke tempat semula
    var splashDone = false          // loading hanya sekali per pembukaan app (bukan tiap kembali ke Beranda)
    var ritual by mutableStateOf("")   // paket game yang sedang diluncurkan lewat ritual
    fun startRitual(pkg: String) { if (ritual.isEmpty()) { ritual = pkg; buzz(); sndPrefs?.let { SoundFx.play(it, "ignition") } } }
    private var inited = false
    fun init(p: Prefs) {
        if (inited) return
        sndPrefs = p
        haptics = p.haptics
        reduceAnim = p.reduceAnim
        animLevel = p.animLevel
        bgDim = p.bgDim
        inited = true
        en = p.sp.getBoolean("hsin_en", false)
        portrait = false
    }
    fun setEn(p: Prefs, v: Boolean) { en = v; p.sp.edit().putBoolean("hsin_en", v).apply() }
    fun setPortrait(p: Prefs, v: Boolean) { portrait = v; p.sp.edit().putBoolean("hsin_portrait", v).apply() }
}

// ===================== mode =====================
internal class MInfo(val key: String, val nameId: String, val nameEn: String, val stars: Int, val color: Color, val tagId: String, val tagEn: String, val detId: String, val detEn: String)

internal val MODES = listOf(
    MInfo("hemat", "Hemat", "Saver", 1, Color(0xFF4FE3C1), "Irit baterai, tetap lancar", "Saves battery, stays smooth",
        "Hemat daya tanpa ngelag. Cocok untuk game ringan dan pemakaian harian.",
        "Efficient without lag. Good for light games and everyday use."),
    MInfo("seimbang", "Seimbang", "Balanced", 2, Color(0xFFE8B95A), "Lancar dan adem untuk sesi panjang", "Smooth and cool for long sessions",
        "Cukup kencang untuk kebanyakan game, suhu dan baterai tetap terjaga.",
        "Fast enough for most games while keeping heat and battery in check."),
    MInfo("performa", "Performa", "Performance", 3, Color(0xFFFF9A3C), "Tenaga tinggi untuk game berat", "High power for heavy games",
        "CPU dan GPU agresif, tetap dijaga pengaman panas.",
        "Aggressive CPU and GPU, still protected by the thermal guard."),
    MInfo("puncak", "Puncak", "Peak", 4, Color(0xFFFF4D5E), "Tenaga penuh, CPU dan GPU dikunci tertinggi", "Full power, CPU and GPU locked at top speed",
        "CPU dan GPU dikunci frekuensi tertinggi, batas panas dilonggarkan. Paling kencang, HP lebih hangat.",
        "CPU and GPU locked at top frequency, thermal limit relaxed. Fastest, phone runs warmer.")
)

internal fun info(k: String): MInfo = MODES.firstOrNull { it.key == k } ?: MODES[1]

@Composable
internal fun mname(m: MInfo): String = if (LocalEn.current) m.nameEn else m.nameId

internal fun starText(n: Int): String = "★".repeat(n) + "☆".repeat(4 - n)

internal fun curMode(vm: AppViewModel): String {
    if (vm.status.ovd) return "puncak"
    return when (vm.status.profile) { "battery" -> "hemat"; "performance" -> "performa"; "balanced" -> "seimbang"; else -> "" }
}

internal fun profMode(profile: String, ovd: Boolean): String =
    if (ovd) "puncak" else when (profile) { "battery" -> "hemat"; "performance" -> "performa"; else -> "seimbang" }

fun AppViewModel.chooseMode(key: String) {
    val prof = when (key) { "hemat" -> "battery"; "seimbang" -> "balanced"; else -> "performance" }
    if (!prefs.soundOn) UiState.buzz() else { if (UiState.haptics) UiState.buzz2(); SoundFx.play(prefs, if (key == "puncak") "overdrive" else prof) }
    status = status.copy(profile = prof, active = prof, ovd = key == "puncak")
    viewModelScope.launch {
        if (key != "puncak") Hsin.ovdStop()
        val r = Hsin.setProfile(prof)
        if (key == "puncak") {
            val o = Hsin.ovdStart()
            toast(if (o.ok) (if (UiState.en) "Peak mode on" else "Mode Puncak aktif") else o.out.lines().firstOrNull { it.isNotBlank() } ?: "Gagal")
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
    var splashDone by remember { mutableStateOf(UiState.splashDone) }
    LaunchedEffect(Unit) {
        if (UiState.splashDone) return@LaunchedEffect
        delay(1500)
        var n = 0
        while (!vm.loaded && n < 100) { delay(100); n++ }
        UiState.splashDone = true
        splashDone = true
    }
    BoxWithConstraints(Modifier.fillMaxSize().background(Color(0xFF0C0C0E))) {
        val land = maxWidth > maxHeight
        val compact = maxHeight < 420.dp
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
    val tk = popKey(UiState.tab, 320)
    Box(modifier.graphicsLayer { alpha = 0.15f + 0.85f * tk; translationX = (1f - tk) * 28.dp.toPx() }) {
        if (vm.loaded && !vm.rootOk) {
            NoticeCard(tx("Akses root belum diberikan", "Root access not granted"), tx("Buka manager root (KernelSU/Magisk/APatch) dan izinkan HSIN, lalu coba lagi.", "Open your root manager and allow HSIN, then retry."), vm)
        } else if (vm.loaded && vm.modPath.isEmpty()) {
            NoticeCard(tx("Modul HSIN belum aktif", "HSIN module is not active"), tx("Flash modul HSIN lewat manager root, reboot, lalu buka app ini lagi.", "Flash the HSIN module in your root manager, reboot, then open this app again."), vm)
        } else when (UiState.tab) {
            0 -> HomeTab(vm, land)
            1 -> GameTab(vm, land)
            2 -> RecordsTab(vm)
            3 -> AlatTab(vm, land)
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
    0 -> tx("Beranda", "Home"); 1 -> tx("Game", "Games"); 2 -> tx("Rekaman", "Records"); 3 -> tx("Alat", "Tools"); else -> tx("Pengaturan", "Settings")
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
            3 -> {
                // kunci pas
                drawLine(color, Offset(w * 0.22f, h * 0.80f), Offset(w * 0.60f, h * 0.42f), st.width * 1.4f, StrokeCap.Round)
                drawCircle(color, w * 0.22f, Offset(w * 0.68f, h * 0.32f), style = st)
                drawCircle(SP.ink, w * 0.07f, Offset(w * 0.74f, h * 0.26f))
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
        Logo(if (compact) 32 else 44)
        for (i in 0 until 5) NavItem(i, compact)
    }
}

@Composable
private fun NavBar() {
    Row(Modifier.fillMaxWidth().background(Color(0xCC000000)).padding(vertical = 6.dp), horizontalArrangement = Arrangement.SpaceEvenly) {
        for (i in 0 until 5) NavItem(i, false)
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
        if (!compact || sel) SText(navName(i), 10.sp, col)
    }
}

internal fun lerpColor(a: Color, b: Color, t: Float): Color = Color(
    red = a.red + (b.red - a.red) * t, green = a.green + (b.green - a.green) * t,
    blue = a.blue + (b.blue - a.blue) * t, alpha = a.alpha + (b.alpha - a.alpha) * t
)

// ===================== data live (CPU/GPU/suhu) =====================
internal class Live(val cpu: Int, val gpuMhz: Int, val gpuPct: Int, val tempC: Int)

@Composable
internal fun rememberLive(vm: AppViewModel, active: Boolean): Live {
    var live by remember { mutableStateOf(Live(-1, -1, -1, -1)) }
    LaunchedEffect(active, vm.modPath) {
        if (!active || vm.modPath.isEmpty()) return@LaunchedEffect
        var pt = 0L; var pi = 0L
        while (true) {
            val r = Root.exec("sh '${vm.modPath}/common/hud_sample.sh' --once x; echo cpu=\$(head -n 1 /proc/stat)", 10_000L)
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

internal fun ramInfo(ctx: Context): Pair<Float, Float> {
    val mi = ActivityManager.MemoryInfo()
    (ctx.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager).getMemoryInfo(mi)
    val tot = mi.totalMem / 1073741824f
    return Pair(tot - mi.availMem / 1073741824f, tot)
}

// ===================== REKAMAN (lihat Records.kt) =====================
@Composable
internal fun RecCard(vm: AppViewModel, r: FpsFile) {
    Glass(Modifier.fillMaxWidth().rise(60, r.name).tap { vm.fpsView = r.name; vm.go("perf") }) {
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
    LaunchedEffect(vm.modPath) { vm.refreshRates = Hsin.refreshList(); vm.refreshHz = Hsin.refreshGet() }
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        SText(tx("PENGATURAN", "SETTINGS"), 12.sp, SP.gold, spacing = 2.sp, modifier = Modifier.rise(0))
        Glass(Modifier.fillMaxWidth().rise(30)) {
            Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                SText(tx("Bahasa", "Language"), 12.sp, SP.dim)
                Seg(listOf("Indonesia", "English"), if (UiState.en) 1 else 0) { UiState.setEn(vm.prefs, it == 1) }
                SText(tx("Warna aksen", "Accent color"), 12.sp, SP.dim)
                Seg(listOf(tx("Emas", "Gold"), tx("Ikut mode", "Follow mode"), "Mint", tx("Merah", "Red")), vm.prefs.accentTheme) { vm.prefs.accentTheme = it; UiState.themeTick++ }
                SText(tx("Tema tampilan (Beranda + floating di game)", "Look theme (Home + in-game floating)"), 12.sp, SP.dim)
                Seg(listOf(tx("Kartu Miring", "Slant"), tx("Dasbor Bundar", "Round"), tx("Kubus Energi", "Cube")), vm.prefs.appTheme - 1) {
                    vm.prefs.appTheme = it + 1; vm.prefs.flStyle = 3 + it
                    vm.flChanged(); UiState.themeTick++; SoundFx.play(vm.prefs, "tab")
                }
                SText(tx("Gelap latar (kalau pakai gambar sendiri)", "Background dimming (custom image)"), 12.sp, SP.dim)
                Seg(listOf(tx("Ringan", "Light"), tx("Sedang", "Medium"), tx("Pekat", "Dark")), UiState.bgDim) { UiState.bgDim = it; vm.prefs.bgDim = it }
            }
        }
        SetupCheck(vm)
        SwitchRow(tx("Getar halus", "Haptic feedback"), tx("Getar ringan saat ganti mode dan mulai ritual.", "Light vibration when switching mode and starting the ritual."), UiState.haptics, 50) { UiState.setHaptics(vm.prefs, it) }
        Glass(Modifier.fillMaxWidth().rise(55)) {
            Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                SText(tx("Gaya animasi", "Animation style"), 13.sp, SP.text, FontWeight.Medium)
                Seg(listOf(tx("Minimal", "Minimal"), "Normal", tx("Mewah", "Fancy")), UiState.animLevel) { UiState.setAnim(vm.prefs, it); SoundFx.play(vm.prefs, "tab") }
                SText(tx("Minimal: tanpa gerak, hemat tenaga. Normal: halus. Mewah: garis pindai, kilau warna mode, dan efek ala game.", "Minimal: no motion, saves power. Normal: smooth. Fancy: scan line, mode-colour glow and game-style effects."), 11.sp, SP.faint)
            }
        }
        SwitchRow(tx("Suara app", "App sounds"), tx("Bunyi klik, ganti mode, dan ritual (dibuat sendiri, tanpa file). Bawaan mati.", "Click, mode-switch and ritual sounds (synthesized, no files). Off by default."), vm.prefs.soundOn, 56) { vm.prefs.soundOn = it; if (it) SoundFx.play(vm.prefs, "ignition") }
        if (vm.prefs.soundOn) {
            SText(tx("Volume suara", "Sound volume"), 12.sp, SP.dim)
            Seg(listOf("30%", "60%", "100%"), when { vm.prefs.soundVol <= 30 -> 0; vm.prefs.soundVol <= 60 -> 1; else -> 2 }) { vm.prefs.soundVol = intArrayOf(30, 60, 100)[it]; SoundFx.play(vm.prefs, "tab") }
        }
        SwitchRow(tx("Floating orb", "Floating orb"), tx("Cincin FPS melayang di game: ketuk untuk menu ganti mode, rekam, dan detail.", "FPS ring floating in games: tap for the menu to switch mode, record and see details."), vm.bubbleOn, 60) { vm.updateBubbleOn(it) }
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
            HBtn(tx("Tampilan orb", "Orb look"), Modifier.weight(1f)) { vm.go("bubble") }
            HBtn(tx("Tema dan warna", "Theme and color"), Modifier.weight(1f)) { vm.go("theme") }
        }
        Row(Modifier.fillMaxWidth().rise(210), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            HBtn(tx("Latar dan banner", "Background and banner"), Modifier.weight(1f)) { vm.go("bgbanner") }
            HBtn(tx("Statistik sesi", "Session stats"), Modifier.weight(1f)) { vm.go("stats") }
        }
        Glass(Modifier.fillMaxWidth().rise(240)) {
            Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                SText(tx("Pembaruan", "Updates"), 12.sp, SP.dim)
                SText("HSIN v${vm.appVer}", 14.sp, SP.text, FontWeight.Medium)
                if (vm.updateText.isNotEmpty()) Text(vm.updateText, color = SP.dim, fontSize = 11.sp, lineHeight = 14.sp)
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    HBtn(tx("Cek pembaruan", "Check for updates"), Modifier.weight(1f)) { vm.checkUpdate() }
                    if (vm.updateUrl.isNotEmpty()) HBtn(tx("Buka halaman", "Open page"), Modifier.weight(1f)) {
                        try { ctx.startActivity(android.content.Intent(android.content.Intent.ACTION_VIEW, android.net.Uri.parse(vm.updateUrl)).addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK)) } catch (_: Exception) {}
                    }
                }
            }
        }
        Spacer(Modifier.height(8.dp))
    }
}

@Composable
private fun SetupCheck(vm: AppViewModel) {
    val ctx = LocalContext.current
    var tick by remember { mutableIntStateOf(0) }
    LaunchedEffect(Unit) { while (true) { delay(2000); tick++ } }
    @Suppress("UNUSED_EXPRESSION") tick
    val overlay = android.provider.Settings.canDrawOverlays(ctx)
    val notif = androidx.core.app.NotificationManagerCompat.from(ctx).areNotificationsEnabled()
    val battOk = try { (ctx.getSystemService(android.content.Context.POWER_SERVICE) as android.os.PowerManager).isIgnoringBatteryOptimizations(ctx.packageName) } catch (_: Exception) { true }
    val modOk = vm.modPath.isNotEmpty()
    val verBad = modOk && vm.status.ver > 0 && vm.status.ver != vm.appVer
    val allOk = vm.rootOk && modOk && !verBad && overlay && notif && battOk
    fun open(a: String, pkgUri: Boolean = false) {
        try {
            val i = android.content.Intent(a)
            if (pkgUri) i.data = android.net.Uri.parse("package:" + ctx.packageName)
            if (a == android.provider.Settings.ACTION_APP_NOTIFICATION_SETTINGS) i.putExtra(android.provider.Settings.EXTRA_APP_PACKAGE, ctx.packageName)
            ctx.startActivity(i.addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK))
        } catch (_: Exception) {}
    }
    Glass(Modifier.fillMaxWidth().rise(20)) {
        Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            SText(if (allOk) tx("Cek awal: semua siap", "Setup check: all good") else tx("Cek awal: ada yang perlu dibenahi", "Setup check: something needs fixing"), 12.sp, if (allOk) Color(0xFF4FE3C1) else SP.gold, FontWeight.SemiBold)
            CheckRow(tx("Akses root", "Root access"), vm.rootOk, tx("Buka manager root dan izinkan HSIN", "Open your root manager and allow HSIN"), null)
            CheckRow(tx("Modul HSIN terpasang", "HSIN module installed"), modOk, tx("Flash zip modul di KernelSU lalu reboot", "Flash the module zip in your root manager and reboot"), null)
            if (verBad) CheckRow(tx("Versi modul cocok dengan app", "Module matches app version"), false, tx("Modul v${vm.status.ver}, app v${vm.appVer}: flash modul terbaru lalu reboot", "Module v${vm.status.ver}, app v${vm.appVer}: flash the latest module and reboot"), null)
            CheckRow(tx("Izin tampil di atas app (floating)", "Draw over other apps (floating)"), overlay, "", { open(android.provider.Settings.ACTION_MANAGE_OVERLAY_PERMISSION, true) })
            CheckRow(tx("Izin notifikasi", "Notifications"), notif, "", { open(android.provider.Settings.ACTION_APP_NOTIFICATION_SETTINGS) })
            CheckRow(tx("Tidak dihemat baterai (supaya floating tidak mati)", "Not battery-optimized (keeps floating alive)"), battOk, "", { open(android.provider.Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS) })
        }
    }
}

@Composable
private fun CheckRow(name: String, ok: Boolean, hint: String, fix: (() -> Unit)?) {
    Column {
        Row(verticalAlignment = Alignment.CenterVertically) {
            SText(if (ok) "✓" else "✗", 13.sp, if (ok) Color(0xFF4FE3C1) else SP.red, FontWeight.Bold, modifier = Modifier.width(18.dp))
            SText(name, 12.sp, SP.text, modifier = Modifier.weight(1f))
            if (!ok && fix != null) Box(Modifier.tap { fix() }.clip(CircleShape).border(1.dp, SP.gold, CircleShape).padding(horizontal = 10.dp, vertical = 3.dp)) { SText(tx("Perbaiki", "Fix"), 11.sp, SP.gold, FontWeight.SemiBold) }
        }
        if (!ok && hint.isNotEmpty()) Text(hint, color = SP.faint, fontSize = 10.sp, modifier = Modifier.padding(start = 18.dp))
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
