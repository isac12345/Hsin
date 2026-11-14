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

/** Versi hemat: mengembalikan state yang dibaca di graphicsLayer/draw, jadi tidak memicu recomposition tiap frame. */
@Composable
fun ownAnimS(target: Float, msIn: Int = 300): androidx.compose.runtime.FloatState {
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
    return s
}

@Composable
fun ownAnim(target: Float, msIn: Int = 300): Float = ownAnimS(target, msIn).floatValue

/** Mulai dari 0 lalu naik ke 1 tiap `key` berubah. Mengembalikan state untuk dibaca di draw phase. */
@Composable
fun popKeyS(key: Any, msIn: Int = 340): androidx.compose.runtime.FloatState {
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
    return s
}

@Composable
fun popKey(key: Any, msIn: Int = 340): Float = popKeyS(key, msIn).floatValue

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
    val s = ownAnimS(if (down) 0.95f else 1f, 80)
    val cb by rememberUpdatedState(onClick)
    return this
        .graphicsLayer { val v = s.floatValue; scaleX = v; scaleY = v }
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
    val th = UiState.theme
    val sh: androidx.compose.ui.graphics.Shape = when (th) {
        1 -> CutShape
        3 -> OctShape
        else -> RoundedCornerShape((radius * 1.5f).dp)
    }
    Box(
        modifier
            .clip(sh)
            .background(if (alt) SP.glassLo else SP.glass)
            .border(if (th == 2) 0.6.dp else 0.8.dp, if (th == 2) SP.line else SP.gold.copy(alpha = 0.28f), sh)
    ) { content() }
}

// ===================== state UI =====================
object UiState {
    var en by mutableStateOf(false)
    var themeTick by mutableStateOf(0)
    var haptics by mutableStateOf(true)
    var reduceAnim = false
    @Volatile var lastTouch = 0L
    var touchTick by mutableStateOf(0)
    var bgDim by mutableStateOf(1)
    fun setReduce(p: Prefs, on: Boolean) { reduceAnim = on; p.reduceAnim = on; themeTick++ }
    /** Tema app aktif: 1 Apex, 2 Turbo, 3 Nitro. */
    var theme by mutableStateOf(1)
    /** Hasil akhir: 1 animasi menyala, 0 mati (semua animasi instan, jam animasi berhenti). */
    var animLevel by mutableStateOf(1)
    var animMode by mutableStateOf(0)
    fun applyAnim(p: Prefs) {
        animMode = p.animMode
        p.animMode = animMode   // simpan eksplisit supaya migrasi lama tidak membaca reduce_anim sebagai Mati
        val on = when (animMode) { 1 -> true; 2 -> false; else -> !p.animAutoOff }
        animLevel = if (on) 1 else 0
        reduceAnim = !on
        p.reduceAnim = !on            // dibaca juga oleh floating
        PerfGuard.reset()
        PerfGuard.armed = animMode == 0 && on
        themeTick++
    }
    fun setAnimMode(p: Prefs, m: Int) {
        p.animMode = m
        if (m == 0) p.animAutoOff = false   // memilih Otomatis lagi = ukur ulang
        applyAnim(p)
    }
    /** Dipanggil PerfGuard saat frame terbukti tidak lancar. */
    fun demote(p: Prefs) { p.animAutoOff = true; applyAnim(p) }
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
        applyAnim(p)
        theme = p.appTheme
        bgDim = p.bgDim
        inited = true
        en = p.sp.getBoolean("hsin_en", java.util.Locale.getDefault().language != "in" && java.util.Locale.getDefault().language != "id")
        portrait = false
    }
    fun setEn(p: Prefs, v: Boolean) { en = v; p.sp.edit().putBoolean("hsin_en", v).apply() }
    fun setPortrait(p: Prefs, v: Boolean) { portrait = v; p.sp.edit().putBoolean("hsin_portrait", v).apply() }
}

// ===================== mode =====================
internal class MInfo(val key: String, val nameId: String, val nameEn: String, val stars: Int, val color: Color, val tagId: String, val tagEn: String, val detId: String, val detEn: String)

internal val MODES = listOf(
    MInfo("adapt", "Adapt", "Adapt", 2, Color(0xFFD7DEE6), "Belajar dari pemakaianmu, makin pas", "Learns from your use, fits better each time",
        "Modul mengatur tenaga sendiri untuk tiap aplikasi: naik saat tersendat, turun saat lancar, lalu mengingatnya.",
        "The module tunes power per app by itself: up when it stutters, down when smooth, and remembers it."),
    MInfo("puncak", "Puncak", "Peak", 4, Color(0xFFFF4D5E), "Tenaga penuh, CPU dan GPU dikunci tertinggi", "Full power, CPU and GPU locked at top speed",
        "CPU dan GPU dikunci frekuensi tertinggi, batas panas dilonggarkan. Paling kencang, HP lebih hangat.",
        "CPU and GPU locked at top frequency, thermal limit relaxed. Fastest, phone runs warmer.")
)

internal fun info(k: String): MInfo = MODES.firstOrNull { it.key == k } ?: MODES[0]

@Composable
internal fun mname(m: MInfo): String = if (LocalEn.current) m.nameEn else m.nameId

internal fun starText(n: Int): String = "★".repeat(n) + "☆".repeat(4 - n)

internal fun curMode(vm: AppViewModel): String {
    if (vm.status.ovd) return "puncak"
    return if (vm.status.profile == "none") "" else "adapt"
}

internal fun profMode(profile: String, ovd: Boolean): String =
    if (ovd) "puncak" else "adapt"

fun AppViewModel.chooseMode(key: String) {
    val prof = if (key == "puncak") "performance" else "adapt"
    if (!prefs.soundOn) UiState.buzz() else { if (UiState.haptics) UiState.buzz2(); SoundFx.play(prefs, if (key == "puncak") "overdrive" else prof) }
    val old = status
    status = status.copy(profile = prof, active = prof, ovd = key == "puncak")
    pendMode(prof, key == "puncak")
    viewModelScope.launch {
        if (key != "puncak") Hsin.ovdStop()
        val r = Hsin.setProfile(prof)
        if (!r.ok) status = status.copy(profile = old.profile, active = old.active, ovd = old.ovd)
        if (key == "puncak") {
            val o = Hsin.ovdStart()
            toast(if (o.ok) (if (UiState.en) "Peak mode on" else "Mode Puncak aktif") else o.out.lines().firstOrNull { it.isNotBlank() } ?: "Gagal")
        } else {
            toast(if (r.ok) (if (UiState.en) "Mode applied" else "Mode diterapkan") else r.out.take(60))
        }
        pendClear()
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
        Image(painterResource(themeWall(UiState.theme)), null, contentScale = ContentScale.Crop, modifier = Modifier.fillMaxSize())
        Box(
            Modifier.fillMaxSize().background(
                if (land) Brush.horizontalGradient(listOf(Color(0xE60A0A0C), Color(0x990A0A0C), Color(0x330A0A0C)))
                else Brush.verticalGradient(listOf(Color(0x990A0A0C), Color(0xE60A0A0C)))
            )
        )
        Embers()
        if (land) {
            when (UiState.theme) {
                2 -> Column(Modifier.fillMaxSize().systemBarsPadding()) {
                    SpaceContent(vm, true, Modifier.weight(1f).fillMaxWidth())
                    NavTurbo(compact)
                }
                3 -> Row(Modifier.fillMaxSize().systemBarsPadding()) {
                    SpaceContent(vm, true, Modifier.weight(1f).fillMaxHeight())
                    NavNitro(compact)
                }
                else -> Row(Modifier.fillMaxSize().systemBarsPadding()) {
                    NavApex(compact)
                    SpaceContent(vm, true, Modifier.weight(1f).fillMaxHeight())
                }
            }
        } else {
            Column(Modifier.fillMaxSize().systemBarsPadding()) {
                SpaceContent(vm, false, Modifier.weight(1f).fillMaxWidth())
                NavBar()
            }
        }
        ModeFx(vm)
        Splash(splashDone)
    }
}

@Composable
private fun SpaceContent(vm: AppViewModel, land: Boolean, modifier: Modifier) {
    val tk = popKeyS(UiState.tab, if (UiState.theme == 3) 260 else 190)
    val hold = remember { intArrayOf(UiState.tab, 1) }
    if (UiState.tab != hold[0]) { hold[1] = if (UiState.tab > hold[0]) 1 else -1; hold[0] = UiState.tab }
    val dir = hold[1]
    val th = UiState.theme
    Box(modifier.graphicsLayer {
        val t = tk.floatValue
        when (th) {
            // Turbo: masuk dari atas/bawah
            2 -> { alpha = t; translationY = -dir * (1f - t) * 40.dp.toPx(); val sc = 1.05f - 0.05f * t; scaleX = sc; scaleY = sc }
            // Nitro: iris dari tengah
            3 -> { alpha = 0.2f + 0.8f * t; val sc = 0.96f + 0.04f * t; scaleX = sc; scaleY = sc; if (t < 1f) { clip = true; shape = IrisShape(t) } }
            // Apex: geser menyamping
            else -> { alpha = 0.15f + 0.85f * t; translationX = dir * (1f - t) * 60.dp.toPx() }
        }
    }) {
        if (vm.loaded && !vm.rootOk) {
            NoticeCard(tx("Akses root belum diberikan", "Root access not granted"), tx("Buka manager root (KernelSU/Magisk/APatch) dan izinkan HSIN, lalu coba lagi.", "Open your root manager and allow HSIN, then retry."), vm)
        } else if (vm.loaded && vm.modPath.isEmpty()) {
            NoticeCard(tx("Modul HSIN belum aktif", "HSIN module is not active"), tx("Flash modul HSIN lewat manager root, reboot, lalu buka app ini lagi.", "Flash the HSIN module in your root manager, reboot, then open this app again."), vm)
        } else when (UiState.tab) {
            0 -> HomeTab(vm, land)
            1 -> GameTab(vm, land)
            2 -> RecordsTab(vm)
            3 -> AlatTab(vm, land)
            5 -> AdaptTab(vm)
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
    val off = ownAnim(if (done) 1f else 0f, 250)
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
/** Urutan tombol navigasi: Beranda, Game, Adapt, Rekaman, Alat, Pengaturan. */
internal val NAV_ORDER = listOf(0, 1, 5, 2, 3, 4)

@Composable
internal fun navName(i: Int): String = when (i) {
    0 -> tx("Beranda", "Home"); 1 -> tx("Game", "Games"); 2 -> tx("Rekaman", "Records"); 3 -> tx("Alat", "Tools"); 5 -> "Adapt"; else -> tx("Pengaturan", "Settings")
}

@Composable
internal fun NavIcon(i: Int, color: Color, modifier: Modifier = Modifier) {
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
            5 -> {
                drawCircle(color, w * 0.30f, Offset(w / 2, h / 2), style = st)
                for (k in 0 until 8) {
                    val a = Math.toRadians(k * 45.0)
                    drawCircle(color, w * 0.075f, Offset(w / 2 + (w * 0.42f * Math.cos(a)).toFloat(), h / 2 + (h * 0.42f * Math.sin(a)).toFloat()))
                }
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
        for (i in NAV_ORDER) NavItem(i, compact)
    }
}

@Composable
private fun NavBar() {
    Row(Modifier.fillMaxWidth().background(Color(0xCC000000)).padding(vertical = 6.dp), horizontalArrangement = Arrangement.SpaceEvenly) {
        for (i in NAV_ORDER) NavItem(i, false)
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
            // app tidak terlihat: berhenti memanggil su sama sekali
            if (!vm.visible) { delay(1000); continue }
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
                SText(tx("Gelap latar (kalau pakai gambar sendiri)", "Background dimming (custom image)"), 12.sp, SP.dim)
                Seg(listOf(tx("Ringan", "Light"), tx("Sedang", "Medium"), tx("Pekat", "Dark")), UiState.bgDim) { UiState.bgDim = it; vm.prefs.bgDim = it }
            }
        }
        SetupCheck(vm)
        SwitchRow(tx("Getar halus", "Haptic feedback"), tx("Getar singkat saat ganti mode dan saat mulai game.", "Short vibration when switching mode and starting a game."), UiState.haptics, 50) { UiState.setHaptics(vm.prefs, it) }
        Glass(Modifier.fillMaxWidth().rise(55)) {
            Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                SText(tx("Gaya animasi", "Animation style"), 13.sp, SP.text, FontWeight.Medium)
                Seg(listOf(tx("Otomatis", "Auto"), tx("Hidup", "On"), tx("Mati", "Off")), UiState.animMode) { UiState.setAnimMode(vm.prefs, it); SoundFx.play(vm.prefs, "tab") }
                val st = if (UiState.animLevel == 1) tx("menyala", "on") else tx("mati", "off")
                SText(tx("Otomatis: animasi mati sendiri kalau HP tidak lancar. Sekarang: $st.", "Auto: animation turns off by itself if the phone lags. Now: $st."), 11.sp, SP.faint)
            }
        }
        SwitchRow(tx("Suara app", "App sounds"), tx("Suara saat klik, ganti mode, dan mulai game. Dibuat langsung oleh app. Bawaan mati.", "Sounds for clicks, mode changes and starting a game. Generated by the app. Off by default."), vm.prefs.soundOn, 56) { vm.prefs.soundOn = it; if (it) SoundFx.play(vm.prefs, "ignition") }
        if (vm.prefs.soundOn) {
            SText(tx("Volume suara", "Sound volume"), 12.sp, SP.dim)
            Seg(listOf("30%", "60%", "100%"), when { vm.prefs.soundVol <= 30 -> 0; vm.prefs.soundVol <= 60 -> 1; else -> 2 }) { vm.prefs.soundVol = intArrayOf(30, 60, 100)[it]; SoundFx.play(vm.prefs, "tab") }
        }
        SwitchRow(tx("Floating orb", "Floating orb"), tx("Cincin FPS melayang di game: ketuk untuk menu ganti mode, rekam, dan detail.", "FPS ring floating in games: tap for the menu to switch mode, record and see details."), vm.bubbleOn, 60) { vm.updateBubbleOn(it) }
        SwitchRow(tx("Tampilkan FPS di floating", "Show FPS in floating"), tx("Angka FPS, CPU, GPU, dan suhu.", "FPS, CPU, GPU and temperature readout."), vm.hudOn, 90) { vm.updateHudOn(it) }
        SwitchRow(tx("Jangan ganggu saat game", "Do not disturb in games"), tx("Notifikasi dibisukan selama game, balik normal setelah ditutup.", "Mutes notifications during games and restores them afterwards."), vm.flag("GAME_DND_ON"), 120) { vm.setFlag("GAME_DND_ON", it) }
        Row(Modifier.fillMaxWidth().rise(180), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            HBtn(tx("Tampilan orb", "Orb look"), Modifier.weight(1f)) { vm.go("bubble") }
            HBtn(tx("Latar dan banner", "Background and banner"), Modifier.weight(1f)) { vm.go("bgbanner") }
        }
        Row(Modifier.fillMaxWidth().rise(210), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            HBtn(tx("Statistik sesi", "Session stats"), Modifier.weight(1f)) { vm.go("stats") }
        }
        Glass(Modifier.fillMaxWidth().rise(240)) {
            Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                SText(tx("Pembaruan", "Updates"), 12.sp, SP.dim)
                SText("HSIN v5.0", 14.sp, SP.text, FontWeight.Medium)
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
    Row(Modifier.fillMaxWidth().clip(btnShape()).background(Color(0x22FFFFFF)).padding(3.dp)) {
        options.forEachIndexed { i, o ->
            val a = ownAnim(if (i == sel) 1f else 0f, 200)
            Box(Modifier.weight(1f).tap { onPick(i) }.clip(btnShape()).background(lerpColor(Color.Transparent, SP.gold, a)).padding(vertical = 8.dp), contentAlignment = Alignment.Center) {
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
