package com.hsin

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import androidx.activity.ComponentActivity
import androidx.activity.compose.BackHandler
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.activity.viewModels
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.withFrameNanos
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.blur
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.core.view.WindowCompat
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File

class MainActivity : ComponentActivity() {
    private val vm: AppViewModel by viewModels()

    private val notifPerm = registerForActivityResult(ActivityResultContracts.RequestPermission()) {
        openOverlaySettingsIfNeeded()
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        WindowCompat.setDecorFitsSystemWindows(window, false)
        setContent { HsinApp(vm) }
        handleLaunchIntent(intent)
        if (!vm.prefs.permAsked) {
            vm.prefs.permAsked = true
            vm.dialog = Dlg.Confirm(
                title = "Izin aplikasi",
                text = "HSIN butuh izin notifikasi (profil aktif) dan tampil di atas app lain (bubble). Keduanya boleh dilewati, fitur lain tetap jalan.",
                okLabel = "BERIKAN",
            ) { requestPerms() }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleLaunchIntent(intent)
    }

    /** Tile "Game terakhir" membuka app dengan paket game: langsung jalankan ritual luncur. */
    private fun handleLaunchIntent(i: Intent?) {
        val pkg = i?.getStringExtra("ritual").orEmpty()
        if (pkg.isNotEmpty()) { i?.removeExtra("ritual"); UiState.startRitual(pkg) }
    }

    private fun requestPerms() {
        if (Build.VERSION.SDK_INT >= 33 &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            notifPerm.launch(Manifest.permission.POST_NOTIFICATIONS)
        } else {
            openOverlaySettingsIfNeeded()
        }
    }

    private fun openOverlaySettingsIfNeeded() {
        if (!Settings.canDrawOverlays(this)) {
            startActivity(Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, Uri.parse("package:$packageName")))
        }
    }

    override fun onStart() {
        super.onStart()
        vm.visible = true
    }

    override fun onStop() {
        vm.visible = false
        super.onStop()
    }
}

@Composable
fun rememberFileBitmap(file: File, ver: Int): android.graphics.Bitmap? {
    val b by produceState<android.graphics.Bitmap?>(null, ver) {
        value = withContext(Dispatchers.IO) { Imaging.decode(file) }
    }
    return b
}

@Composable
fun Backdrop(vm: AppViewModel) {
    val bmp = vm.bgBmp
    if (bmp != null && !vm.saver) {
        val scale = when (vm.fit) {
            0 -> ContentScale.Crop
            1 -> ContentScale.Fit
            else -> ContentScale.FillBounds
        }
        var m = Modifier.fillMaxSize()
        if (vm.blur > 0 && Build.VERSION.SDK_INT >= 31) m = m.blur((vm.blur * 0.24f).dp)
        Image(bmp.asImageBitmap(), null, m, contentScale = scale)
        Box(Modifier.fillMaxSize().background(Color.Black.copy(alpha = when (UiState.bgDim) { 0 -> 0.3f; 2 -> 0.7f; else -> 0.5f })))
    } else {
        // tanpa background pilihan: pakai wallpaper bawaan HSIN supaya tidak ada layar kosong/hitam
        Image(painterResource(themeWall(UiState.theme)), null, Modifier.fillMaxSize(), contentScale = ContentScale.Crop)
        Box(Modifier.fillMaxSize().background(Brush.verticalGradient(listOf(Color(0xCC0A0A0C), Color(0xE60A0A0C)))))
    }
}

@Composable
fun Banner(vm: AppViewModel) {
    val custom = vm.bannerBmp
    Box(Modifier.fillMaxWidth().padding(top = 10.dp, bottom = 10.dp).height(124.dp).clip(RoundedCornerShape(22.dp))) {
        if (custom != null) {
            Image(custom.asImageBitmap(), null, Modifier.fillMaxSize(), contentScale = ContentScale.Crop)
        } else if (vm.bannerReady) {
            Image(painterResource(themeBanner(UiState.theme)), null, Modifier.fillMaxSize(), contentScale = ContentScale.Crop)
        }
        Box(Modifier.fillMaxSize().background(Brush.verticalGradient(listOf(Color.Transparent, Color.Black.copy(alpha = 0.7f)))))
        Column(Modifier.align(Alignment.BottomStart).padding(16.dp)) {
            txt("HSIN", 21.sp, Paper, FontWeight.Medium, spacing = 4.sp)
            txt("game booster", 11.sp, Color.White.copy(alpha = 0.7f), spacing = 3.sp)
        }
    }
}

@Composable
fun BottomNav(vm: AppViewModel) {
    val ui = LocalUi.current
    val tabs = listOf("dash" to "DASH", "games" to "GAMES", "custom" to "CUSTOM", "tools" to "TOOLS")
    Row(
        Modifier.padding(horizontal = 14.dp, vertical = 10.dp).fillMaxWidth().clip(CircleShape)
            .background(Color(0xE61B1D21)).padding(5.dp),
    ) {
        tabs.forEach { (r, t) ->
            val on = vm.tab == r
            Box(
                Modifier.weight(1f).clip(CircleShape).background(if (on) ui.accent else Color.Transparent)
                    .clickable { vm.go(r) }.padding(vertical = 12.dp),
                contentAlignment = Alignment.Center,
            ) { txt(t, 12.sp, if (on) Ink else Color.White.copy(alpha = 0.55f), spacing = 1.4.sp, maxLines = 1) }
        }
    }
}

@Composable
fun DialogHost(vm: AppViewModel) {
    val d = vm.dialog ?: return
    val shape = RoundedCornerShape(22.dp)
    Dialog(onDismissRequest = { vm.dialog = null }) {
        Column(
            Modifier.clip(shape).background(Color(0xFF15171A)).border(BorderStroke(0.6.dp, Color.White.copy(alpha = 0.15f)), shape).padding(18.dp),
        ) {
            when (d) {
                is Dlg.Confirm -> {
                    var chk by remember(d) { mutableStateOf(d.checkDefault) }
                    txt(d.title, 15.sp, weight = FontWeight.Medium, spacing = 1.sp)
                    txt(d.text, 12.sp, muted(), modifier = Modifier.padding(top = 8.dp))
                    if (d.checkLabel != null) ToggleRow(d.checkLabel, null, chk) { chk = it }
                    Row(Modifier.fillMaxWidth()) {
                        Box(Modifier.weight(1f)) { Pill("BATAL", { vm.dialog = null }) }
                        Box(Modifier.padding(start = 8.dp).weight(1f)) {
                            Pill(d.okLabel, { vm.dialog = null; d.onOk(chk) }, solid = true)
                        }
                    }
                }
                is Dlg.Info -> {
                    txt(d.title, 15.sp, weight = FontWeight.Medium, spacing = 1.sp)
                    txt(d.text, 12.sp, muted(), modifier = Modifier.padding(top = 8.dp))
                    Row(Modifier.fillMaxWidth()) {
                        Box(Modifier.weight(1f)) { Pill("TUTUP", { vm.dialog = null }, solid = d.action == null) }
                        if (d.actionLabel != null && d.action != null) {
                            Box(Modifier.padding(start = 8.dp).weight(1f)) {
                                Pill(d.actionLabel, { vm.dialog = null; d.action.invoke() }, solid = true)
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
fun HsinApp(vm: AppViewModel) {
    val ctx = LocalContext.current
    UiState.init(vm.prefs)
    UiState.view = androidx.compose.ui.platform.LocalView.current
    val cmode = curMode(vm)
    UiState.themeTick
    val accent = when (vm.prefs.accentTheme) {
        1 -> if (cmode.isEmpty()) Color(0xFFE8B95A) else info(cmode).color
        2 -> Color(0xFF4FE3C1)
        3 -> Color(0xFFFF4D5E)
        else -> Color(0xFFE8B95A)
    }
    ThemeHolder.accent.value = accent
    val ui = UiCfg(accent, vm.cardAlpha, vm.contrast / 100f, vm.saver)
    val clock = remember { mutableFloatStateOf(0f) }
    DisposableEffect(Unit) {
        (ctx as? android.app.Activity)?.let { PerfGuard.attach(it) }
        PerfGuard.onDemote = {
            UiState.demote(vm.prefs)
            vm.toast(if (UiState.en) "Animation turned off to keep the app smooth. Turn it on again in Settings." else "Animasi dimatikan otomatis agar app tetap lancar. Bisa dinyalakan lagi di Pengaturan.")
        }
        onDispose { PerfGuard.onDemote = null; PerfGuard.detach() }
    }
    // Jam animasi hanya berjalan saat animasi menyala: mati = tidak ada frame berkala sama sekali
    LaunchedEffect(UiState.animLevel) {
        if (UiState.animLevel == 0) return@LaunchedEffect
        val t0 = withFrameNanos { it }
        var last = 0L
        while (true) {
            val n = withFrameNanos { it }
            if (n - last >= 14_000_000L) { last = n; clock.floatValue = (n - t0) / 1_000_000_000f }   // maksimal ~60 pembaruan/detik, hemat di layar 120 Hz
        }
    }
    LaunchedEffect(UiState.portrait) {
        (ctx as? android.app.Activity)?.requestedOrientation =
            android.content.pm.ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE
    }
    LaunchedEffect(vm.askOverlay) {
        if (vm.askOverlay) {
            vm.askOverlay = false
            ctx.startActivity(
                Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, Uri.parse("package:${ctx.packageName}"))
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            )
        }
    }

    CompositionLocalProvider(LocalUi provides ui, LocalClock provides clock, LocalEn provides UiState.en) {
        MaterialTheme(colorScheme = darkColorScheme()) {
            BackHandler(enabled = vm.route != "dash") {
                if (vm.route in setOf("games", "custom", "tools", "records")) vm.go("dash") else if (!vm.back()) vm.go("dash")
            }
            BackHandler(enabled = vm.route == "dash" && UiState.tab != 0 && UiState.ritual.isEmpty()) { UiState.tab = 0 }
            BackHandler(enabled = UiState.ritual.isNotEmpty()) { UiState.ritual = "" }
            Box(Modifier.fillMaxSize().background(Color.Black)) {
                if (vm.route == "dash") {
                    SpaceRoot(vm)
                } else {
                    Backdrop(vm)
                    Column(Modifier.fillMaxSize().systemBarsPadding()) {
                        Row(Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 8.dp)) {
                            Box(
                                Modifier.clip(CircleShape).background(SP.glass).border(1.dp, SP.gold.copy(alpha = 0.6f), CircleShape).tap {
                                    if (vm.route in setOf("games", "custom", "tools", "records")) vm.go("dash") else if (!vm.back()) vm.go("dash")
                                }.padding(horizontal = 12.dp, vertical = 5.dp)
                            ) { SText("‹ " + tx("Kembali", "Back"), 12.sp, SP.gold, FontWeight.SemiBold) }
                        }
                        key(vm.route) {
                            val scroll = rememberScrollState()
                            Column(Modifier.weight(1f).verticalScroll(scroll).padding(horizontal = 14.dp)) {
                                when (vm.route) {
                                    "auto" -> AutoScreen(vm)
                                    "therm" -> ThermScreen(vm)
                                    "stats" -> StatsScreen(vm)
                                    "detect" -> DetectScreen(vm)
                                    "addgame" -> AddGameScreen(vm)
                                    "bgbanner" -> BgBannerScreen(vm)
                                    "bubble" -> BubbleScreen(vm)
                                    "dexopt" -> DexoptScreen(vm)
                                    "ramkeep" -> RamKeepScreen(vm)
                                    "freeze" -> FreezeScreen(vm)
                                    "sessions" -> SessionsScreen(vm)
                                    "bench" -> BenchScreen(vm)
                                    "charge" -> ChargeScreen(vm)
                                    "memfx" -> MemFxScreen(vm)
                                    "perf" -> PerfScreen(vm)
                                    "batlab" -> BatLabScreen(vm)
                                    "fulllog" -> FullLogScreen(vm)
                                }
                                Spacer(Modifier.height(12.dp))
                            }
                        }
                    }
                }

                val m = vm.msg
                if (m != null) {
                    Box(Modifier.align(Alignment.BottomCenter).navigationBarsPadding().padding(bottom = 24.dp, start = 24.dp, end = 24.dp)) {
                        // jenis pesan: gagal/tidak = merah, sukses = hijau, lainnya = emas; ikon di depan
                        val bad = Regex("(?i)gagal|tidak |error|could not|not ").containsMatchIn(m)
                        val good = Regex("(?i)disimpan|saved|diganti|dihapus|selesai|berhasil|aktif|ditambahkan|dikembalikan|dipertahankan|restored|kept|changed").containsMatchIn(m)
                        val tone = if (bad) Color(0xFFFF6B78) else if (good) Color(0xFF4FE3C1) else SP.gold
                        Row(Modifier.clip(RoundedCornerShape(16.dp)).background(tone).padding(horizontal = 14.dp, vertical = 10.dp), verticalAlignment = Alignment.CenterVertically) {
                            SText(if (bad) "⚠" else if (good) "✓" else "ℹ", 14.sp, SP.ink, FontWeight.Bold)
                            Spacer(Modifier.width(8.dp))
                            SText(m, 13.sp, SP.ink, FontWeight.Medium)
                        }
                    }
                }
                val b = vm.busy
                if (b != null) {
                    Box(
                        Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.55f))
                            .clickable(interactionSource = remember { MutableInteractionSource() }, indication = null) {},
                        contentAlignment = Alignment.Center,
                    ) {
                        Box(Modifier.clip(RoundedCornerShape(18.dp)).background(Color(0xFF15171A)).padding(horizontal = 22.dp, vertical = 16.dp)) {
                            txt(b, 13.sp)
                        }
                    }
                }
                RitualOverlay(vm)
            IntroOverlay(vm)
                DialogHost(vm)
            }
        }
    }
}
