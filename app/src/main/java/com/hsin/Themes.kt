package com.hsin

import androidx.compose.foundation.Canvas
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
import androidx.compose.ui.graphics.GenericShape
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
            Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(14.dp), verticalArrangement = Arrangement.spacedBy(10.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                CoreDial(vm, minOf(maxWidth - 28.dp, 300.dp))
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

@Composable
internal fun ThemedHome(vm: AppViewModel, land: Boolean) {
    val live = rememberLive(vm, true)
    val cm = curMode(vm)
    val col = if (cm.isEmpty()) SP.gold else info(cm).color
    when (vm.prefs.appTheme) {
        1 -> HomeSlant(vm, live, col, land)
        2 -> HomeRound(vm, live, col, land)
        else -> HomeCube(vm, live, col, land)
    }
}
