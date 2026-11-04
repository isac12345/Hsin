package com.hsin

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Paint
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.io.File
import java.util.Locale

// =====================================================================
//  REKAMAN: 3 tab (Layar | FPS | Sesi)
// =====================================================================
@Composable
internal fun RecordsTab(vm: AppViewModel) {
    var tab by remember { mutableIntStateOf(0) }
    Column(Modifier.fillMaxSize().padding(horizontal = 16.dp, vertical = 10.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        SText(tx("REKAMAN", "RECORDS"), 12.sp, SP.gold, spacing = 2.sp, modifier = Modifier.rise(0))
        HChips(listOf(tx("Layar", "Screen"), "FPS", tx("Sesi", "Sessions")), tab) { tab = it }
        Box(Modifier.weight(1f).fillMaxWidth()) {
            when (tab) {
                0 -> ScreenRecPane(vm)
                1 -> FpsRecPane(vm)
                else -> SessionsPane(vm)
            }
        }
    }
}

// ---------------------------------------------------------------- LAYAR
private fun fmtTime(ms: Long): String { val s = ms / 1000; return String.format(Locale.US, "%02d:%02d", s / 60, s % 60) }

private data class VidFile(val path: String, val sizeMb: Float)

@Composable
private fun ScreenRecPane(vm: AppViewModel) {
    val scope = rememberCoroutineScope()
    var files by remember { mutableStateOf<List<VidFile>>(emptyList()) }
    var reload by remember { mutableIntStateOf(0) }
    var count by remember { mutableIntStateOf(0) }
    var t0 by remember { mutableLongStateOf(0L) }
    var now by remember { mutableLongStateOf(0L) }
    val br = vm.conf["REC_BITRATE_MBPS"]?.toIntOrNull() ?: 8
    val recSize = vm.conf["REC_SIZE"].orEmpty().ifEmpty { "native" }
    val touch = vm.conf["REC_TOUCH"] == "1"
    val cdOn = vm.prefs.recCountdown
    val withFps = vm.prefs.recWithFps
    fun safe(f: String) = f.startsWith("/sdcard/Movies/HSIN/") && !f.contains("..") && f.none { it == '"' || it == '\'' || it == '$' || it == '`' || it == ';' }
    LaunchedEffect(vm.recOn) {
        if (vm.recOn) { t0 = android.os.SystemClock.elapsedRealtime(); while (true) { now = android.os.SystemClock.elapsedRealtime(); delay(500) } }
    }
    LaunchedEffect(vm.recOn, vm.modPath, reload) {
        if (vm.modPath.isEmpty()) return@LaunchedEffect
        val r = Root.exec("for f in \$(sh '${vm.modPath}/common/screenrec.sh' list 12); do echo \"\$f|\$(stat -c %s \"\$f\" 2>/dev/null)\"; done", 12_000L)
        files = r.out.lines().mapNotNull { l ->
            val p = l.trim().split('|')
            if (p.isNotEmpty() && p[0].endsWith(".mp4")) VidFile(p[0], (p.getOrNull(1)?.toLongOrNull() ?: 0L) / 1048576f) else null
        }
    }
    fun startStop() {
        val starting = !vm.recOn
        vm.toggleRec()
        if (withFps && FpsLog.on != starting) vm.toggleFpsLog()
    }
    val land = !UiState.portrait
    val left: @Composable () -> Unit = {
        // ---- kiri: tombol rekam bulat + pengaturan
        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Glass(Modifier.fillMaxWidth().rise(30)) {
                Column(Modifier.padding(14.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    val pulse = ownAnim(if (vm.recOn) 1f else 0f, 300)
                    val clock = LocalClock.current
                    Box(Modifier.size(128.dp).tap { if (vm.recOn) startStop() else if (count == 0) { if (cdOn) scope.launch { for (i in 3 downTo 1) { count = i; delay(1000) }; count = 0; startStop() } else startStop() } }, contentAlignment = Alignment.Center) {
                        Canvas(Modifier.fillMaxSize()) {
                            val c = if (vm.recOn) SP.red else SP.gold
                            val beat = if (vm.recOn && !UiState.reduceAnim) (0.5f + 0.5f * Math.sin(clock.floatValue * 6.0).toFloat()) else 0f
                            drawCircle(c.copy(alpha = 0.10f + 0.12f * beat), radius = size.minDimension / 2f)
                            drawCircle(c, radius = size.minDimension / 2f - 3.dp.toPx(), style = Stroke(3.dp.toPx()))
                            val inner = size.minDimension * (0.30f - 0.07f * pulse)
                            if (vm.recOn) drawRect(c, topLeft = Offset(center.x - inner * 0.9f, center.y - inner * 0.9f), size = Size(inner * 1.8f, inner * 1.8f))
                            else drawCircle(c, radius = inner)
                        }
                    }
                    SText(
                        if (vm.recOn) fmtTime((now - t0).coerceAtLeast(0L)) else if (count > 0) "$count" else tx("Siap merekam", "Ready to record"),
                        if (vm.recOn || count > 0) 26.sp else 13.sp, if (vm.recOn) SP.red else SP.text, FontWeight.Bold
                    )
                    SText(if (vm.recOn) tx("Ketuk untuk berhenti", "Tap to stop") else tx("Ketuk lingkaran untuk mulai", "Tap the circle to start"), 11.sp, SP.dim)
                }
            }
            Section(tx("PENGATURAN REKAM", "RECORD SETTINGS"), 60) {
                SText(tx("Resolusi", "Resolution"), 11.sp, SP.dim)
                val sizes = listOf("native", "1080", "720")
                HChips(listOf(tx("Asli", "Native"), "1080p", "720p"), sizes.indexOf(recSize).coerceAtLeast(0)) { vm.setConfKey("REC_SIZE", sizes[it]) }
                SText(tx("Kualitas (bitrate)", "Quality (bitrate)"), 11.sp, SP.dim)
                val qs = listOf(4, 8, 16)
                HChips(listOf(tx("Hemat 4", "Light 4"), "Normal 8", tx("Tinggi 16", "High 16")), qs.indexOf(qs.minByOrNull { Math.abs(it - br) }!!)) { vm.setConfKey("REC_BITRATE_MBPS", qs[it].toString()) }
                HSwitch(tx("Hitung mundur 3 detik", "3-second countdown"), tx("Sempat pindah ke game dulu.", "Time to switch to the game first."), cdOn) { vm.prefs.recCountdown = it; reload++ }
                HSwitch(tx("Tampilkan sentuhan layar", "Show screen touches"), tx("Titik sentuh ikut terlihat di video, kembali normal setelah selesai.", "Touch dots show in the video; restored when done."), touch) { vm.setConfKey("REC_TOUCH", if (it) "1" else "0") }
                HSwitch(tx("Ikut rekam FPS", "Also record FPS"), tx("Mulai dan berhenti bersamaan dengan video.", "Starts and stops together with the video."), withFps) { vm.prefs.recWithFps = it; reload++ }
                Text(tx("Tanpa suara: perekam bawaan Android tidak bisa menangkap suara internal maupun mikrofon.", "No audio: Android's built-in recorder cannot capture internal audio or the microphone."), color = SP.faint, fontSize = 10.sp, lineHeight = 13.sp)
            }
        }
    }
    val right: @Composable () -> Unit = {
        // ---- kanan: galeri video
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Section(tx("VIDEO TERSIMPAN", "SAVED VIDEOS"), 90) {
                if (files.isEmpty()) SText(tx("Belum ada video. Hasil disimpan di Movies/HSIN.", "No videos yet. Saved to Movies/HSIN."), 12.sp, SP.faint)
                files.forEach { f ->
                    val name = f.path.substringAfterLast('/').removePrefix("HSIN_").removeSuffix(".mp4")
                    val pretty = Regex("(\\d{4})(\\d{2})(\\d{2})_(\\d{2})(\\d{2})(\\d{2})").find(name)?.let { m -> "${m.groupValues[3]}/${m.groupValues[2]} ${m.groupValues[4]}:${m.groupValues[5]}" } ?: name
                    Row(Modifier.fillMaxWidth().padding(vertical = 3.dp), verticalAlignment = Alignment.CenterVertically) {
                        Box(Modifier.size(44.dp).clip(RoundedCornerShape(8.dp)).background(Color(0x22FFFFFF)), contentAlignment = Alignment.Center) { SText("▶", 16.sp, SP.gold) }
                        Column(Modifier.weight(1f).padding(horizontal = 10.dp)) {
                            SText(pretty, 13.sp, SP.text, FontWeight.Medium)
                            SText(String.format(Locale.US, "%.1f MB", f.sizeMb), 10.sp, SP.faint)
                        }
                        Box(Modifier.tap { if (safe(f.path)) scope.launch { Root.exec("am start -a android.intent.action.VIEW -d 'file://${f.path}' -t video/mp4 >/dev/null 2>&1", 8_000L) } }.clip(CircleShape).border(1.dp, SP.gold, CircleShape).padding(horizontal = 10.dp, vertical = 4.dp)) { SText(tx("Putar", "Play"), 11.sp, SP.gold) }
                        Spacer(Modifier.width(6.dp))
                        Box(Modifier.tap { if (safe(f.path)) scope.launch { Root.exec("rm -f '${f.path}' && am broadcast -a android.intent.action.MEDIA_SCANNER_SCAN_FILE -d 'file://${f.path}' >/dev/null 2>&1", 8_000L); reload++ } }.clip(CircleShape).border(1.dp, SP.red, CircleShape).padding(horizontal = 10.dp, vertical = 4.dp)) { SText(tx("Hapus", "Delete"), 11.sp, SP.red) }
                    }
                }
            }
        }
    }
    LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(bottom = 16.dp)) {
        item {
            if (land) Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                Box(Modifier.weight(1f)) { left() }
                Box(Modifier.weight(1f)) { right() }
            } else Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(10.dp)) { left(); right() }
        }
    }
}

// ---------------------------------------------------------------- FPS
@Composable
private fun FpsRecPane(vm: AppViewModel) {
    LaunchedEffect(vm.modPath, FpsLog.saved) { vm.loadFpsFiles() }
    LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(bottom = 16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        item {
            Section(tx("REKAM FPS", "FPS RECORDING")) {
                Text(tx("Mulai game dari HSIN, ketuk floating, lalu pilih FPS. Atau pakai tombol di bawah. Hasil CSV di folder Download.", "Start a game from HSIN, tap the floating view, then pick FPS. Or use the button below. CSV goes to Downloads."), color = SP.dim, fontSize = 12.sp, lineHeight = 16.sp)
                HBtn(if (FpsLog.on) tx("■ HENTIKAN REKAM FPS", "■ STOP FPS LOG") else tx("● MULAI REKAM FPS", "● START FPS LOG"), Modifier.fillMaxWidth(), if (FpsLog.on) SP.red else SP.gold, solid = FpsLog.on) { vm.toggleFpsLog() }
            }
        }
        if (vm.fpsFiles.isEmpty()) item { SText(tx("Belum ada rekaman FPS.", "No FPS records yet."), 13.sp, SP.faint) }
        items(vm.fpsFiles, key = { it.name }) { r -> RecCard(vm, r) }
    }
}

// ---------------------------------------------------------------- SESI
private fun mode(s: FpsSession) = if (s.ovdPct >= 50) "Puncak" else profileLabel(s.profile)

@Composable
private fun SessionsPane(vm: AppViewModel) {
    val list = vm.prefs.fpsSessions
    var open by remember { mutableIntStateOf(-1) }
    val ctx = LocalContext.current
    val scope = rememberCoroutineScope()
    LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(bottom = 16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        item {
            Text(
                if (list.isEmpty()) tx("Belum ada sesi. Main game dengan floating aktif; sesi tersimpan otomatis (minimal ±10 detik)." , "No sessions yet. Play a game with floating on; sessions save automatically (at least ~10 s).")
                else tx("Ketuk sesi untuk melihat grafik. Tahan pilihan A/B untuk membandingkan dua sesi.", "Tap a session for its graphs. Use A/B to compare two sessions."),
                color = SP.dim, fontSize = 12.sp, lineHeight = 16.sp
            )
        }
        items(list.size) { i ->
            val s = list[i]
            val isOpen = open == i
            Glass(Modifier.fillMaxWidth().rise(0, i)) {
                Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Row(Modifier.fillMaxWidth().tap { open = if (isOpen) -1 else i }, verticalAlignment = Alignment.CenterVertically) {
                        Column(Modifier.weight(1f)) {
                            SText(vm.label(s.pkg), 14.sp, SP.text, FontWeight.SemiBold)
                            SText(mode(s) + " · ${s.secs / 60}m ${s.secs % 60}s · " + java.text.SimpleDateFormat("dd/MM HH:mm", Locale.US).format(java.util.Date(s.epoch)), 11.sp, SP.faint)
                        }
                        SText("${s.avg}", 22.sp, verdictColor(s), FontWeight.Bold)
                        SText(" FPS", 11.sp, SP.dim)
                    }
                    SText(verdictText(s), 12.sp, verdictColor(s), FontWeight.Medium)
                    if (isOpen) SessionDetail(vm, s, i, ctx, scope)
                }
            }
        }
        val a = list.getOrNull(vm.cmpA); val b = list.getOrNull(vm.cmpB)
        if (a != null && b != null) item { CompareCard(vm, a, b) }
    }
}

private fun verdictText(s: FpsSession): String {
    val badJank = s.secs > 0 && s.jank * 60 / maxOf(1, s.secs) > 8
    return when {
        s.gStab >= 85 && !badJank -> "Lancar"
        s.gStab >= 60 -> "Sedikit patah"
        else -> "Banyak patah"
    }
}
private fun verdictColor(s: FpsSession): Color = when (verdictText(s)) { "Lancar" -> Mint; "Sedikit patah" -> Color(0xFFE8B95A); else -> Color(0xFFFF6B78) }

@Composable
private fun SessionDetail(vm: AppViewModel, s: FpsSession, idx: Int, ctx: Context, scope: kotlinx.coroutines.CoroutineScope) {
    val en = LocalEn.current
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        // Total vs Gameplay
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            SText(tx("TOTAL", "TOTAL"), 10.sp, SP.gold, FontWeight.SemiBold, 1.sp)
            SText("${s.avg} FPS · 1% low ${s.low1}", 12.sp, SP.text)
            SText(tx("Stabil ", "Stable ") + "${s.stab}%", 11.sp, SP.dim)
        }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            SText(tx("GAMEPLAY (tanpa 5 dtk awal)", "GAMEPLAY (first 5 s skipped)"), 10.sp, Mint, FontWeight.SemiBold, 1.sp)
            SText("${if (s.gAvg > 0) s.gAvg else s.avg} FPS · 1% low ${if (s.gLow1 > 0) s.gLow1 else s.low1}", 12.sp, SP.text)
            SText(tx("Stabil ", "Stable ") + "${if (s.gStab > 0) s.gStab else s.stab}%", 11.sp, SP.dim)
        }
    }
    SText("Jank ${s.jank} / ${tx("besar", "big")} ${s.bigJank} · ${tx("frame terlama", "longest frame")} ${s.maxFt} ms" + if (s.watt10 > 0) " · ${s.watt10 / 10}.${s.watt10 % 10} W" else "", 11.sp, SP.dim)
    if (s.sFps.size >= 2) {
        LineGraph(tx("FPS per detik", "FPS per second"), listOf(s.sFps), listOf(SP.gold), 64.dp, minZero = true)
        if (s.sJank.any { it > 0 }) BarGraph(tx("Jank", "Jank"), s.sJank, SP.red, 40.dp)
        if (s.sTemp.any { it > 0 }) LineGraph(tx("Suhu (°C)", "Temperature (°C)"), listOf(s.sTemp), listOf(Color(0xFFFF9A3C)), 48.dp, minZero = false)
        if (s.sWatt.any { it > 0 }) LineGraph(tx("Daya (W×10)", "Power (W×10)"), listOf(s.sWatt), listOf(Color(0xFF60A5FA)), 48.dp, minZero = true)
    } else SText(tx("Sesi lama ini belum punya data per detik.", "This older session has no per-second data."), 11.sp, SP.faint)
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        HBtn("A", Modifier.weight(0.5f), if (vm.cmpA == idx) Mint else SP.gold, solid = vm.cmpA == idx) { vm.cmpA = if (vm.cmpA == idx) -1 else idx }
        HBtn("B", Modifier.weight(0.5f), if (vm.cmpB == idx) Mint else SP.gold, solid = vm.cmpB == idx) { vm.cmpB = if (vm.cmpB == idx) -1 else idx }
        HBtn("CSV", Modifier.weight(1f)) { scope.launch { vm.toast(exportCsv(ctx, vm, s)) } }
        HBtn(tx("Gambar", "Image"), Modifier.weight(1f)) { scope.launch { vm.toast(exportImage(ctx, vm, s, en)) } }
    }
}

@Composable
private fun CompareCard(vm: AppViewModel, a: FpsSession, b: FpsSession) {
    Section(tx("PERBANDINGAN", "COMPARISON")) {
        Row(Modifier.fillMaxWidth()) {
            Spacer(Modifier.weight(1f))
            SText("A: " + mode(a), 11.sp, SP.gold, FontWeight.SemiBold, modifier = Modifier.weight(1f))
            SText("B: " + mode(b), 11.sp, Mint, FontWeight.SemiBold, modifier = Modifier.weight(1f))
        }
        @Composable
        fun r(n: String, x: String, y: String) {
            Row(Modifier.fillMaxWidth().padding(vertical = 1.dp)) {
                SText(n, 11.sp, SP.dim, modifier = Modifier.weight(1f)); SText(x, 12.sp, SP.text, modifier = Modifier.weight(1f)); SText(y, 12.sp, SP.text, modifier = Modifier.weight(1f))
            }
        }
        r(tx("FPS rata-rata", "Average FPS"), "${a.avg}", "${b.avg}")
        r("1% low", "${a.low1}", "${b.low1}")
        r(tx("Gameplay rata-rata", "Gameplay avg"), "${a.gAvg}", "${b.gAvg}")
        r("Jank", "${a.jank}/${a.bigJank}", "${b.jank}/${b.bigJank}")
        r(tx("Kestabilan", "Stability"), "${a.stab}%", "${b.stab}%")
        r(tx("Daya", "Power"), if (a.watt10 > 0) "${a.watt10 / 10.0} W" else "--", if (b.watt10 > 0) "${b.watt10 / 10.0} W" else "--")
        if (a.sFps.size >= 2 && b.sFps.size >= 2) LineGraph(tx("FPS: A (emas) vs B (hijau)", "FPS: A (gold) vs B (green)"), listOf(a.sFps, b.sFps), listOf(SP.gold, Mint), 70.dp, minZero = true)
        val d = b.avg - a.avg
        SText("B " + (if (d >= 0) tx("lebih tinggi ", "higher by ") else tx("lebih rendah ", "lower by ")) + Math.abs(d) + " FPS" + tx(" dari A.", " than A."), 12.sp, Mint)
    }
}

// ---------------------------------------------------------------- GRAFIK
@Composable
internal fun LineGraph(title: String, series: List<List<Int>>, colors: List<Color>, h: androidx.compose.ui.unit.Dp, minZero: Boolean) {
    Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
        SText(title, 10.sp, SP.dim, FontWeight.Medium)
        Canvas(Modifier.fillMaxWidth().height(h).clip(RoundedCornerShape(6.dp)).background(Color(0x14FFFFFF))) {
            val all = series.flatten().filter { it > 0 || minZero }
            if (all.isEmpty()) return@Canvas
            var mx = (all.maxOrNull() ?: 1).toFloat(); var mn = if (minZero) 0f else (all.filter { it > 0 }.minOrNull() ?: 0).toFloat()
            if (mx - mn < 4f) { mx = mn + 4f }
            for (g in 1..3) { val y = size.height * g / 4f; drawLine(Color(0x1AFFFFFF), Offset(0f, y), Offset(size.width, y), 1f) }
            series.forEachIndexed { k, v ->
                if (v.size < 2) return@forEachIndexed
                val p = Path(); val st = size.width / (v.size - 1)
                v.forEachIndexed { i, x ->
                    val y = size.height - ((x - mn) / (mx - mn)).coerceIn(0f, 1f) * (size.height - 4f) - 2f
                    if (i == 0) p.moveTo(0f, y) else p.lineTo(i * st, y)
                }
                drawPath(p, colors[k % colors.size], style = Stroke(1.6.dp.toPx(), cap = StrokeCap.Round))
            }
        }
    }
}

@Composable
internal fun BarGraph(title: String, v: List<Int>, color: Color, h: androidx.compose.ui.unit.Dp) {
    Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
        SText(title, 10.sp, SP.dim, FontWeight.Medium)
        Canvas(Modifier.fillMaxWidth().height(h).clip(RoundedCornerShape(6.dp)).background(Color(0x14FFFFFF))) {
            val mx = maxOf(1, v.maxOrNull() ?: 1).toFloat()
            val bw = size.width / v.size
            v.forEachIndexed { i, x -> if (x > 0) { val bh = x / mx * (size.height - 2f); drawRect(color, Offset(i * bw, size.height - bh), Size(maxOf(1.5f, bw - 1f), bh)) } }
        }
    }
}

// ---------------------------------------------------------------- EKSPOR
private suspend fun exportCsv(ctx: Context, vm: AppViewModel, s: FpsSession): String {
    val sb = StringBuilder("detik,fps,suhu_c,daya_w,jank\n")
    val n = s.sFps.size
    val step = if (n > 0) s.secs.toFloat() / n else 1f
    for (i in 0 until n) sb.append(String.format(Locale.US, "%.0f,%d,%d,%.1f,%d\n", i * step, s.sFps[i], s.sTemp.getOrNull(i) ?: 0, (s.sWatt.getOrNull(i) ?: 0) / 10.0, s.sJank.getOrNull(i) ?: 0))
    val name = "HSIN_sesi_${vm.label(s.pkg).filter { it.isLetterOrDigit() }.ifEmpty { "game" }}_${s.epoch / 1000}.csv"
    val tmp = File(ctx.cacheDir, name)
    return try {
        tmp.writeText(sb.toString())
        val r = Root.exec("mkdir -p /sdcard/Download && cp '${tmp.absolutePath}' '/sdcard/Download/$name'", 8_000L)
        tmp.delete()
        if (r.code == 0) "CSV: Download/$name" else "Gagal menyimpan CSV"
    } catch (_: Exception) { "Gagal menyimpan CSV" }
}

private suspend fun exportImage(ctx: Context, vm: AppViewModel, s: FpsSession, en: Boolean): String {
    val w = 1080; val h = 760
    val bmp = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
    val c = android.graphics.Canvas(bmp)
    c.drawColor(0xFF121215.toInt())
    val p = Paint(Paint.ANTI_ALIAS_FLAG)
    fun text(t: String, x: Float, y: Float, size: Float, col: Int, bold: Boolean = false) { p.color = col; p.textSize = size; p.isFakeBoldText = bold; c.drawText(t, x, y, p) }
    text("HSIN", 40f, 70f, 34f, 0xFFE8B95A.toInt(), true)
    text(vm.label(s.pkg) + " · " + mode(s), 40f, 125f, 44f, 0xFFF4F1EA.toInt(), true)
    text(java.text.SimpleDateFormat("dd/MM/yyyy HH:mm", Locale.US).format(java.util.Date(s.epoch)) + " · ${s.secs / 60}m ${s.secs % 60}s", 40f, 165f, 26f, 0xAAF4F1EA.toInt())
    val gA = if (s.gAvg > 0) s.gAvg else s.avg
    val stats = listOf("${s.avg}" to (if (en) "avg FPS" else "FPS rata-rata"), "${s.low1}" to "1% low", "${s.stab}%" to (if (en) "stability" else "kestabilan"), "${s.jank}/${s.bigJank}" to "jank", "$gA" to (if (en) "gameplay avg" else "rata-rata gameplay"))
    stats.forEachIndexed { i, (v, k) -> val x = 40f + i * 200f; text(v, x, 240f, 44f, 0xFFF4F1EA.toInt(), true); text(k, x, 272f, 22f, 0x99F4F1EA.toInt()) }
    fun graph(v: List<Int>, top: Float, hh: Float, col: Int) {
        p.color = 0x14FFFFFF; c.drawRect(40f, top, w - 40f, top + hh, p)
        if (v.size < 2) return
        val mx = maxOf(1, v.maxOrNull() ?: 1).toFloat()
        val path = android.graphics.Path()
        v.forEachIndexed { i, x -> val px = 40f + i * (w - 80f) / (v.size - 1); val py = top + hh - (x / mx) * (hh - 8f) - 4f; if (i == 0) path.moveTo(px, py) else path.lineTo(px, py) }
        p.style = Paint.Style.STROKE; p.strokeWidth = 4f; p.color = col; c.drawPath(path, p); p.style = Paint.Style.FILL
    }
    text(if (en) "FPS per second" else "FPS per detik", 40f, 330f, 24f, 0xAAF4F1EA.toInt())
    graph(s.sFps, 342f, 190f, 0xFFE8B95A.toInt())
    text(if (en) "Temperature" else "Suhu", 40f, 566f, 24f, 0xAAF4F1EA.toInt())
    graph(s.sTemp, 578f, 110f, 0xFFFF9A3C.toInt())
    text("Jank " + s.jank + "  ·  " + (if (en) "longest frame " else "frame terlama ") + s.maxFt + " ms" + if (s.watt10 > 0) "  ·  ${s.watt10 / 10.0} W" else "", 40f, 730f, 24f, 0xAAF4F1EA.toInt())
    val name = "HSIN_sesi_${s.epoch / 1000}.png"
    val tmp = File(ctx.cacheDir, name)
    return try {
        tmp.outputStream().use { bmp.compress(Bitmap.CompressFormat.PNG, 100, it) }
        val r = Root.exec("mkdir -p /sdcard/Download && cp '${tmp.absolutePath}' '/sdcard/Download/$name'", 8_000L)
        tmp.delete()
        if (r.code == 0) "PNG: Download/$name" else "Gagal menyimpan gambar"
    } catch (_: Exception) { "Gagal menyimpan gambar" }
}
