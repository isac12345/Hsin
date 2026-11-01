package com.hsin

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.horizontalScroll
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
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
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
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.util.Locale
import kotlin.math.cos
import kotlin.math.sin

// =====================================================================
//  Komponen kecil HSIN
// =====================================================================

@Composable
internal fun HBtn(t: String, modifier: Modifier = Modifier, color: Color = SP.gold, solid: Boolean = false, onClick: () -> Unit) {
    val sh = RoundedCornerShape(12.dp)
    Box(
        modifier.tap(onClick).clip(sh)
            .background(if (solid) color else SP.glassLo)
            .border(0.8.dp, if (solid) color else SP.line, sh)
            .padding(horizontal = 12.dp, vertical = 12.dp),
        contentAlignment = Alignment.Center
    ) { SText(t, 13.sp, if (solid) SP.ink else SP.text, FontWeight.SemiBold) }
}

@Composable
internal fun HSwitch(title: String, sub: String?, on: Boolean, color: Color = SP.gold, onChange: (Boolean) -> Unit) {
    Row(Modifier.fillMaxWidth().padding(vertical = 7.dp), verticalAlignment = Alignment.CenterVertically) {
        Column(Modifier.weight(1f)) {
            SText(title, 14.sp, SP.text, FontWeight.Medium)
            if (sub != null) Text(sub, color = SP.dim, fontSize = 11.sp, lineHeight = 14.sp)
        }
        Spacer(Modifier.width(8.dp))
        Switch(
            checked = on, onCheckedChange = onChange,
            colors = SwitchDefaults.colors(checkedThumbColor = SP.ink, checkedTrackColor = color, uncheckedThumbColor = SP.dim, uncheckedTrackColor = Color(0x33FFFFFF), uncheckedBorderColor = SP.line)
        )
    }
}

@Composable
internal fun HChips(options: List<String>, sel: Int, color: Color = SP.gold, onPick: (Int) -> Unit) {
    Row(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        options.forEachIndexed { i, o ->
            val a = ownAnim(if (i == sel) 1f else 0f, 200)
            Box(
                Modifier.tap { onPick(i) }.clip(RoundedCornerShape(10.dp))
                    .background(lerpColor(Color(0x22FFFFFF), color, a))
                    .padding(horizontal = 14.dp, vertical = 8.dp),
                contentAlignment = Alignment.Center
            ) { SText(o, 12.sp, lerpColor(SP.text, SP.ink, a), FontWeight.SemiBold) }
        }
    }
}

@Composable
internal fun Section(title: String, delayMs: Int = 0, modifier: Modifier = Modifier, content: @Composable () -> Unit) {
    Glass(modifier.fillMaxWidth().rise(delayMs)) {
        Column(Modifier.padding(horizontal = 14.dp, vertical = 12.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            SText(title, 11.sp, SP.gold, FontWeight.SemiBold, 1.2.sp)
            content()
        }
    }
}

// =====================================================================
//  BERANDA: Core Dial
// =====================================================================

@Composable
internal fun CoreDial(vm: AppViewModel, sizeDp: Dp) {
    val clock = LocalClock.current
    val cm = curMode(vm)
    val idx = MODES.indexOfFirst { it.key == cm }
    val pos = ownAnim(if (idx < 0) 1f else idx.toFloat(), 520)
    val i0 = pos.toInt().coerceIn(0, 3)
    val i1 = (i0 + 1).coerceAtMost(3)
    val col = lerpColor(MODES[i0].color, MODES[i1].color, (pos - i0).coerceIn(0f, 1f))
    val m = if (idx < 0) MODES[1] else MODES[idx]
    val pop = popKey(cm)
    val speed = 1f + pos * 0.9f
    Box(Modifier.size(sizeDp), contentAlignment = Alignment.Center) {
        Canvas(Modifier.fillMaxSize()) {
            val c = center
            val r = size.minDimension / 2f - 20.dp.toPx()
            val tl = Offset(c.x - r, c.y - r)
            val sz = Size(r * 2, r * 2)
            val glow = 0.28f + 0.08f * sin(clock.floatValue * 2f)
            drawCircle(Brush.radialGradient(listOf(col.copy(alpha = glow), Color.Transparent), c, r * 0.95f), r * 0.95f, c)
            rotate(clock.floatValue * 7f * speed, c) {
                drawCircle(Color(0x30FFFFFF), r + 12.dp.toPx(), c, style = Stroke(1.dp.toPx(), pathEffect = PathEffect.dashPathEffect(floatArrayOf(5.dp.toPx(), 8.dp.toPx()))))
            }
            rotate(-clock.floatValue * 5f * speed, c) {
                drawCircle(col.copy(alpha = 0.4f), r - 16.dp.toPx(), c, style = Stroke(1.dp.toPx(), pathEffect = PathEffect.dashPathEffect(floatArrayOf(2.dp.toPx(), 9.dp.toPx()))))
            }
            drawArc(Color(0x1FFFFFFF), 135f, 270f, false, tl, sz, style = Stroke(9.dp.toPx(), cap = StrokeCap.Round))
            drawArc(col, 135f, 270f * (pos / 3f).coerceIn(0f, 1f), false, tl, sz, style = Stroke(9.dp.toPx(), cap = StrokeCap.Round))
            for (i in 0..3) {
                val a = Math.toRadians(135.0 + 270.0 * i / 3.0)
                val p = Offset(c.x + r * cos(a).toFloat(), c.y + r * sin(a).toFloat())
                val on = i.toFloat() <= pos + 0.01f
                drawCircle(Color(0xFF141416), 11.dp.toPx(), p)
                drawCircle(if (on) MODES[i].color else Color(0x55FFFFFF), 11.dp.toPx(), p, style = Stroke(2.dp.toPx()))
                if (idx == i) drawCircle(MODES[i].color, 5.dp.toPx(), p)
            }
        }
        val rDp = sizeDp / 2 - 20.dp
        for (i in 0..3) {
            val a = Math.toRadians(135.0 + 270.0 * i / 3.0)
            val x = sizeDp / 2 + rDp * cos(a).toFloat() - 20.dp
            val y = sizeDp / 2 + rDp * sin(a).toFloat() - 20.dp
            Box(Modifier.offset(x, y).size(40.dp).tap { vm.chooseMode(MODES[i].key) })
        }
        Column(
            Modifier.padding(horizontal = sizeDp * 0.22f).graphicsLayer { alpha = pop; translationY = (1f - pop) * 10.dp.toPx() },
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            SText(tx("MODE", "MODE"), 10.sp, SP.dim, spacing = 2.sp)
            SText(if (idx < 0) "—" else mname(m), (sizeDp.value * 0.115f).coerceIn(18f, 34f).sp, col, FontWeight.Bold)
            SText(starText(if (idx < 0) 0 else m.stars), 13.sp, col)
            Spacer(Modifier.height(4.dp))
            Text(if (LocalEn.current) m.tagEn else m.tagId, color = SP.dim, fontSize = 11.sp, lineHeight = 14.sp, textAlign = TextAlign.Center, maxLines = 3)
        }
    }
}

@Composable
internal fun ModePills(vm: AppViewModel, modifier: Modifier = Modifier) {
    val cm = curMode(vm)
    Row(modifier.fillMaxWidth().rise(120), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        MODES.forEach { m ->
            val a = ownAnim(if (cm == m.key) 1f else 0f, 220)
            val sh = RoundedCornerShape(11.dp)
            Box(
                Modifier.weight(1f).tap { vm.chooseMode(m.key) }.clip(sh)
                    .background(lerpColor(SP.glass, m.color, a * 0.92f))
                    .border(1.dp, lerpColor(SP.line, m.color, a), sh).padding(vertical = 11.dp),
                contentAlignment = Alignment.Center
            ) { SText(mname(m), 12.sp, lerpColor(m.color, SP.ink, a), FontWeight.Bold) }
        }
    }
}

@Composable
internal fun HomeChips(vm: AppViewModel, live: Live) {
    val ctx = LocalContext.current
    val (u, t) = ramInfo(ctx)
    val tmp = if (live.tempC > 0) "${live.tempC}°" else "--"
    val bat = if (vm.status.batt >= 0) "${vm.status.batt}%" else "--"
    Row(Modifier.rise(0), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        MiniChip(SP.gold, String.format(Locale.US, "%.1f/%.1fG", u, t))
        MiniChip(if (live.tempC > 44) Color(0xFFFF9A3C) else Color(0xFF4FE3C1), tmp)
        MiniChip(Color(0xFF4FC3A1), bat)
    }
}

@Composable
private fun MiniChip(dot: Color, t: String) {
    Glass(radius = 9, alt = true) {
        Row(Modifier.padding(horizontal = 9.dp, vertical = 5.dp), verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.size(7.dp).clip(CircleShape).background(dot))
            Spacer(Modifier.width(6.dp))
            SText(t, 12.sp, SP.text, FontWeight.Medium)
        }
    }
}

@Composable
private fun StatRow(vm: AppViewModel, live: Live, col: Color) {
    val (u, tot) = ramInfo(LocalContext.current)
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        StatBox("CPU", live.cpu.toFloat(), 100f, "%", 0, col, Modifier.weight(1f).rise(300))
        if (live.gpuPct >= 0) StatBox("GPU", live.gpuPct.toFloat(), 100f, "%", 0, col, Modifier.weight(1f).rise(340))
        else StatBox("GPU", live.gpuMhz.toFloat(), 1000f, "", 0, col, Modifier.weight(1f).rise(340))
        StatBox(tx("Suhu", "Temp"), live.tempC.toFloat(), 60f, "°", 0, col, Modifier.weight(1f).rise(380))
        StatBox("RAM", u, tot, "G", 1, col, Modifier.weight(1f).rise(420))
    }
}

@Composable
private fun StatBox(name: String, v: Float, mx: Float, unit: String, dec: Int, col: Color, modifier: Modifier) {
    val shown = ownAnim(if (v < 0f) 0f else v, 500)
    val frac = ownAnim(if (v < 0f) 0f else (v / mx).coerceIn(0f, 1f), 500)
    Glass(modifier, radius = 10, alt = true) {
        Column(Modifier.padding(horizontal = 9.dp, vertical = 7.dp)) {
            SText(name, 10.sp, SP.dim)
            SText(if (v < 0f) "--" else (if (dec == 0) shown.toInt().toString() else String.format(Locale.US, "%.${dec}f", shown)) + unit, 16.sp, SP.text, FontWeight.SemiBold)
            Spacer(Modifier.height(5.dp))
            Box(Modifier.fillMaxWidth().height(3.dp).clip(CircleShape).background(Color(0x22FFFFFF))) {
                Box(Modifier.fillMaxWidth(frac).fillMaxHeight().background(col))
            }
        }
    }
}

@Composable
private fun gameModeLine(vm: AppViewModel, g: GameEntry): String {
    val opts by produceState<Map<String, String>>(emptyMap(), g.pkg, vm.games) { value = Hsin.gameOpts(g.pkg) }
    val fx by produceState<Map<String, String>>(emptyMap(), g.pkg, vm.games) { value = Hsin.gamefx(g.pkg) }
    val m = info(profMode(g.profile, opts["OVD"] == "on"))
    val res = fx["downscale"].orEmpty().toDoubleOrNull()?.let { "${Math.round(it * 100)}%" } ?: "100%"
    return if (LocalEn.current) "${m.nameEn} · Resolution $res" else "${m.nameId} · Resolusi $res"
}

@Composable
private fun GamePicker(vm: AppViewModel) {
    val gs = vm.games
    Glass(Modifier.fillMaxWidth().rise(240)) {
        if (gs.isEmpty()) {
            Box(Modifier.fillMaxWidth().tap { vm.go("addgame") }.padding(vertical = 14.dp), contentAlignment = Alignment.Center) {
                SText(tx("+ Tambah game dulu", "+ Add a game first"), 14.sp, SP.gold, FontWeight.Medium)
            }
        } else {
            val idx = UiState.gameIdx.coerceIn(0, gs.size - 1)
            val g = gs[idx]
            val pop = popKey(g.pkg)
            Row(Modifier.fillMaxWidth().padding(horizontal = 6.dp, vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
                Box(Modifier.tap { UiState.gameIdx = (idx - 1 + gs.size) % gs.size }.padding(horizontal = 10.dp, vertical = 6.dp)) { SText("‹", 22.sp, SP.dim) }
                AppIcon(g.pkg, 40.dp)
                Column(Modifier.weight(1f).padding(horizontal = 10.dp).graphicsLayer { alpha = pop; translationX = (1f - pop) * 16.dp.toPx() }) {
                    SText(vm.label(g.pkg), 15.sp, SP.text, FontWeight.SemiBold)
                    SText(gameModeLine(vm, g), 11.sp, SP.dim)
                }
                Box(Modifier.tap { UiState.gameIdx = (idx + 1) % gs.size }.padding(horizontal = 10.dp, vertical = 6.dp)) { SText("›", 22.sp, SP.dim) }
            }
        }
    }
}

@Composable
private fun ActionRow(vm: AppViewModel, col: Color) {
    val gs = vm.games
    val dnd = vm.flag("GAME_DND_ON")
    Row(Modifier.fillMaxWidth().rise(300), horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
        HBtn(tx("RAM", "RAM"), Modifier.width(64.dp), col) { vm.cleanRam() }
        HBtn(tx("DND", "DND"), Modifier.width(64.dp), col, solid = dnd) { vm.setFlag("GAME_DND_ON", !dnd) }
        val clock = LocalClock.current
        val sh = RoundedCornerShape(12.dp)
        Box(
            Modifier.weight(1f).tap { if (gs.isNotEmpty()) UiState.startRitual(gs[UiState.gameIdx.coerceIn(0, gs.size - 1)].pkg) else vm.go("addgame") }
                .clip(sh).background(Brush.horizontalGradient(listOf(col, lerpColor(col, SP.goldHi, 0.5f))))
                .drawBehind {
                    val x = (((clock.floatValue % 2.6f) / 2.6f) * 1.7f - 0.3f) * size.width
                    drawRect(Brush.horizontalGradient(listOf(Color.Transparent, Color(0x55FFFFFF), Color.Transparent), startX = x, endX = x + size.width * 0.3f))
                }.padding(vertical = 14.dp),
            contentAlignment = Alignment.Center
        ) { SText(tx("▶  MULAI GAME", "▶  START GAME"), 15.sp, SP.ink, FontWeight.ExtraBold, 1.5.sp) }
    }
}

@Composable
internal fun HomeTab(vm: AppViewModel, land: Boolean) {
    val live = rememberLive(vm, true)
    val cm = curMode(vm)
    val col = if (cm.isEmpty()) SP.gold else info(cm).color
    if (land) {
        BoxWithConstraints(Modifier.fillMaxSize()) {
            val d = minOf(maxHeight - 20.dp, maxWidth * 0.44f, 330.dp)
            Row(Modifier.fillMaxSize().padding(horizontal = 14.dp, vertical = 10.dp), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                Box(Modifier.weight(0.9f).fillMaxHeight(), contentAlignment = Alignment.Center) { CoreDial(vm, d) }
                Column(Modifier.weight(1.1f).fillMaxHeight().verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    HomeChips(vm, live)
                    ModePills(vm)
                    StatRow(vm, live, col)
                    GamePicker(vm)
                    ActionRow(vm, col)
                }
            }
        }
    } else {
        BoxWithConstraints(Modifier.fillMaxSize()) {
            val d = minOf(maxWidth - 28.dp, 330.dp)
            Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(14.dp), verticalArrangement = Arrangement.spacedBy(10.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) { HomeChips(vm, live) }
                CoreDial(vm, d)
                ModePills(vm)
                StatRow(vm, live, col)
                GamePicker(vm)
                ActionRow(vm, col)
            }
        }
    }
}

// =====================================================================
//  GAME: rak + panel
// =====================================================================

@Composable
internal fun GameTab(vm: AppViewModel, land: Boolean) {
    val gs = vm.games
    if (gs.isEmpty()) {
        Column(Modifier.fillMaxSize().padding(24.dp), verticalArrangement = Arrangement.Center, horizontalAlignment = Alignment.CenterHorizontally) {
            SText(tx("Belum ada game", "No games yet"), 18.sp, SP.text, FontWeight.SemiBold)
            Spacer(Modifier.height(6.dp))
            Text(tx("Tambahkan game supaya HSIN bisa mengatur mode, resolusi, dan floating khusus game itu.", "Add a game so HSIN can set its own mode, resolution and floating."), color = SP.dim, fontSize = 13.sp, textAlign = TextAlign.Center)
            Spacer(Modifier.height(14.dp))
            HBtn(tx("+ Tambah game", "+ Add game"), Modifier.width(200.dp), solid = true) { vm.go("addgame") }
        }
        return
    }
    val idx = UiState.gameIdx.coerceIn(0, gs.size - 1)
    val g = gs[idx]
    if (land) {
        Row(Modifier.fillMaxSize().padding(horizontal = 14.dp, vertical = 10.dp), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            Column(Modifier.weight(0.85f).fillMaxHeight().verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                SText(tx("RAK GAME", "GAME SHELF"), 11.sp, SP.gold, FontWeight.SemiBold, 1.5.sp)
                gs.chunked(2).forEachIndexed { r, row ->
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        row.forEachIndexed { c, e -> GameTile(vm, e, r * 2 + c == idx, r * 2 + c, Modifier.weight(1f)) }
                        if (row.size == 1) Spacer(Modifier.weight(1f))
                    }
                }
                HBtn(tx("+ Tambah game", "+ Add game"), Modifier.fillMaxWidth()) { vm.go("addgame") }
            }
            Column(Modifier.weight(1.15f).fillMaxHeight().verticalScroll(rememberScrollState())) { GameDetail(vm, g) }
        }
    } else {
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(14.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            SText(tx("RAK GAME", "GAME SHELF"), 11.sp, SP.gold, FontWeight.SemiBold, 1.5.sp)
            Row(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                gs.forEachIndexed { i, e -> GameTile(vm, e, i == idx, i, Modifier.width(96.dp)) }
                Box(Modifier.size(width = 96.dp, height = 104.dp).tap { vm.go("addgame") }.clip(RoundedCornerShape(16.dp)).border(1.dp, SP.gold, RoundedCornerShape(16.dp)), contentAlignment = Alignment.Center) {
                    SText("+", 26.sp, SP.gold)
                }
            }
            GameDetail(vm, g)
        }
    }
}

@Composable
private fun GameTile(vm: AppViewModel, g: GameEntry, sel: Boolean, index: Int, modifier: Modifier) {
    val a = ownAnim(if (sel) 1f else 0f, 220)
    val sh = RoundedCornerShape(16.dp)
    Column(
        modifier.tap { UiState.gameIdx = index }.graphicsLayer { val k = 1f + 0.04f * a; scaleX = k; scaleY = k }
            .clip(sh).background(lerpColor(SP.glass, Color(0xCC2A2214), a))
            .border(1.dp, lerpColor(SP.line, SP.gold, a), sh).padding(horizontal = 8.dp, vertical = 10.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        AppIcon(g.pkg, 50.dp)
        Spacer(Modifier.height(6.dp))
        SText(vm.label(g.pkg), 11.sp, lerpColor(SP.dim, SP.text, a), FontWeight.Medium)
    }
}

private val FPS_KEYS = listOf("off", "30", "45", "60", "90", "120")

@Composable
private fun GameDetail(vm: AppViewModel, g: GameEntry) {
    var ver by remember { mutableIntStateOf(0) }
    val opts by produceState<Map<String, String>>(emptyMap(), g.pkg, ver, vm.games) { value = Hsin.gameOpts(g.pkg) }
    val fx by produceState<Map<String, String>>(emptyMap(), g.pkg, ver) { value = Hsin.gamefx(g.pkg) }
    val cur = profMode(g.profile, opts["OVD"] == "on")
    val col = info(cur).color
    var res by remember(g.pkg, fx["downscale"]) { mutableFloatStateOf(((fx["downscale"]?.toDoubleOrNull() ?: 1.0) * 100).toFloat().coerceIn(50f, 100f)) }
    Glass(Modifier.fillMaxWidth().rise(60, g.pkg)) {
        Column(Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                AppIcon(g.pkg, 44.dp)
                Column(Modifier.padding(start = 10.dp)) {
                    SText(vm.label(g.pkg), 17.sp, SP.text, FontWeight.Bold)
                    SText(g.pkg, 11.sp, SP.faint)
                }
            }
            SText(tx("Mode game ini", "This game's mode"), 11.sp, SP.dim)
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                for (m in MODES) {
                    val sel = cur == m.key
                    val a = ownAnim(if (sel) 1f else 0f, 200)
                    val sh = RoundedCornerShape(10.dp)
                    Box(
                        Modifier.weight(1f).tap {
                            val prof = when (m.key) { "hemat" -> "battery"; "seimbang" -> "balanced"; else -> "performance" }
                            vm.addGame(g.pkg, g.fps, prof) { ver++ }
                            vm.setGameOpt(g.pkg, "OVD", if (m.key == "puncak") "on" else "off")
                            ver++
                        }.clip(sh).background(lerpColor(Color(0x22FFFFFF), m.color, a)).border(1.dp, lerpColor(Color(0x22FFFFFF), m.color, a), sh).padding(vertical = 9.dp),
                        contentAlignment = Alignment.Center
                    ) { SText(mname(m), 12.sp, lerpColor(m.color, SP.ink, a), FontWeight.Bold) }
                }
            }
            Row(verticalAlignment = Alignment.CenterVertically) {
                SText(tx("Resolusi", "Resolution"), 12.sp, SP.dim, modifier = Modifier.width(64.dp))
                Slider(
                    value = res, onValueChange = { res = it },
                    onValueChangeFinished = {
                        val v = if (res >= 99.5f) "off" else String.format(Locale.US, "%.2f", res / 100f)
                        vm.setGameFx(g.pkg, "downscale", v)
                    },
                    valueRange = 50f..100f, steps = 9,
                    colors = SliderDefaults.colors(thumbColor = col, activeTrackColor = col, inactiveTrackColor = Color(0x33FFFFFF), activeTickColor = Color.Transparent, inactiveTickColor = Color.Transparent),
                    modifier = Modifier.weight(1f)
                )
                SText("${res.toInt()}%", 13.sp, SP.text, FontWeight.SemiBold, modifier = Modifier.width(44.dp))
            }
            SText(tx("Batas FPS", "FPS cap"), 11.sp, SP.dim)
            HChips(FPS_KEYS.map { if (it == "off") tx("Bebas", "Free") else it }, FPS_KEYS.indexOf(fx["fps"] ?: "off").coerceAtLeast(0), col) {
                vm.setGameFx(g.pkg, "fps", FPS_KEYS[it]); ver++
            }
            HSwitch(tx("Mode Puncak otomatis", "Auto Peak mode"), tx("Tenaga penuh tiap game ini dibuka; berhenti saat panas atau baterai < 15%.", "Full power every time this game opens; stops when hot or battery < 15%."), opts["OVD"] == "on", col) {
                vm.setGameOpt(g.pkg, "OVD", if (it) "on" else "default"); ver++
            }
            HSwitch(tx("Mode ringan", "Light mode"), tx("Hanya profil yang jalan; tanpa prioritas, DND, dan refresh rate.", "Profile only; no priority, DND or refresh rate."), opts["LITE"] == "1", col) {
                vm.setGameOpt(g.pkg, "LITE", if (it) "1" else "default"); ver++
            }
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                HBtn(tx("▶  LUNCURKAN", "▶  LAUNCH"), Modifier.weight(1f), col, solid = true) { UiState.startRitual(g.pkg) }
                HBtn(tx("Lanjutan", "Advanced")) { vm.editPkg = g.pkg; vm.go("edit") }
                HBtn(tx("Hapus", "Remove"), color = SP.red) { vm.removeGame(g.pkg) }
            }
        }
    }
}

// =====================================================================
//  ALAT (dibuat baru; menggantikan layar "Tools" lama)
// =====================================================================

@Composable
internal fun AlatTab(vm: AppViewModel, land: Boolean) {
    var sub by remember { mutableIntStateOf(0) }
    LaunchedEffect(vm.modPath) {
        vm.go("tools")
        vm.refreshRates = Hsin.refreshList(); vm.refreshHz = Hsin.refreshGet()
    }
    val names = listOf(tx("Mesin", "Engine"), tx("Layar", "Display"), tx("Bersih", "Clean"), tx("Log", "Logs"), tx("Sistem", "System"))
    Column(Modifier.fillMaxSize().padding(horizontal = 14.dp, vertical = 10.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        HChips(names, sub) { sub = it }
        Column(Modifier.weight(1f).fillMaxWidth().verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            when (sub) {
                0 -> AlatMesin(vm, land)
                1 -> AlatLayar(vm)
                2 -> AlatBersih(vm, land)
                3 -> AlatLog(vm)
                else -> AlatSistem(vm, land)
            }
            Spacer(Modifier.height(6.dp))
        }
    }
}

@Composable
private fun TwoCol(land: Boolean, left: @Composable () -> Unit, right: @Composable () -> Unit) {
    if (land) {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(10.dp)) { left() }
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(10.dp)) { right() }
        }
    } else {
        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) { left(); right() }
    }
}

@Composable
private fun AlatMesin(vm: AppViewModel, land: Boolean) {
    TwoCol(land, {
        Section(tx("PENGENDALI CPU", "CPU CONTROL")) {
            HSwitch(tx("Kunci CPU pintar", "Smart CPU control"), tx("fas-rs menyesuaikan frekuensi CPU mengikuti beban game.", "fas-rs adapts CPU frequency to game load."), !vm.flag("GB_FASRS_FORCE_HSIN")) { vm.setFlag("GB_FASRS_FORCE_HSIN", !it) }
            HSwitch(tx("Turbo setelah dingin", "Turbo after cooldown"), tx("Boost penuh lagi begitu suhu turun.", "Full boost again once the phone cools down."), vm.flag("GB_COOLDOWN_EXTREME")) { vm.setFlag("GB_COOLDOWN_EXTREME", it) }
            HSwitch(tx("Fokus inti game", "Game core focus"), tx("Game dipersempit ke inti terbaik (cpuset).", "Game is narrowed to the best cores (cpuset)."), !vm.flag("NO_CPUSET")) { vm.setFlag("NO_CPUSET", !it) }
        }
        Section(tx("PENGAMAN", "SAFETY"), 60) {
            HBtn(tx("Suhu dan pengaman panas", "Thermal guard"), Modifier.fillMaxWidth()) { vm.go("therm") }
            HBtn(tx("Mode otomatis (baterai / mengisi)", "Auto mode (battery / charging)"), Modifier.fillMaxWidth()) { vm.go("auto") }
        }
    }, {
        Section(tx("SAAT GAME BERJALAN", "WHILE PLAYING"), 30) {
            HSwitch(tx("Prioritas game", "Game priority"), tx("Proses game diberi prioritas CPU, I/O, dan memori.", "Game process gets CPU, I/O and memory priority."), !vm.flag("GAME_PRIO_OFF")) { vm.setFlag("GAME_PRIO_OFF", !it) }
            HSwitch(tx("Jangan ganggu otomatis", "Auto Do Not Disturb"), tx("Notifikasi dibisukan selama game, dipulihkan saat keluar.", "Mutes notifications during games and restores them afterwards."), vm.flag("GAME_DND_ON")) { vm.setFlag("GAME_DND_ON", it) }
        }
        if (vm.refreshRates.isNotEmpty()) {
            Section(tx("REFRESH RATE SAAT GAME", "GAME REFRESH RATE"), 90) {
                val keys = listOf("off") + vm.refreshRates.map { it.toString() }
                HChips(keys.map { if (it == "off") tx("Sistem", "System") else "$it Hz" }, keys.indexOf(vm.refreshHz).coerceAtLeast(0)) { vm.updateRefreshHz(keys[it]) }
                Text(tx("Dikunci ke angka itu selama game lalu dikembalikan. Tidak semua ROM menurut.", "Locked to that rate during the game, then restored. Not every ROM obeys."), color = SP.dim, fontSize = 11.sp)
            }
        }
    })
}

@Composable
private fun AlatLayar(vm: AppViewModel) {
    val ri = vm.resInfo
    Section(tx("RESOLUSI LAYAR HP", "PHONE DISPLAY RESOLUTION")) {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            Column(Modifier.weight(1f)) {
                SText(tx("Asli", "Native"), 11.sp, SP.dim)
                SText(if (ri != null) "${ri.nat.w}×${ri.nat.h} · ${ri.nat.d}" else "...", 15.sp, SP.text, FontWeight.SemiBold)
            }
            Column(Modifier.weight(1f)) {
                SText(tx("Aktif", "Active"), 11.sp, SP.dim)
                SText(if (ri != null) "${ri.act.w}×${ri.act.h} · ${Math.round(ri.act.w * 100f / ri.nat.w)}%" else "...", 15.sp, SP.gold, FontWeight.SemiBold)
            }
        }
        val opts = listOf(60, 70, 80, 90, 100)
        HChips(opts.map { "$it%" }, opts.indexOf(vm.resPct).coerceAtLeast(0)) { vm.resPct = opts[it] }
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            HBtn(tx("TERAPKAN", "APPLY"), Modifier.weight(1f), solid = vm.resCountdown == 0) { if (vm.resCountdown == 0) vm.applyRes() }
            HBtn(tx("KEMBALIKAN", "RESET"), Modifier.weight(1f)) { if (vm.resCountdown == 0) vm.resetRes() }
        }
        if (vm.resCountdown > 0) {
            Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).border(1.dp, SP.gold, RoundedCornerShape(12.dp)).padding(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                SText(tx("Layar oke? Kembali otomatis dalam ${vm.resCountdown} detik.", "Screen OK? Reverts in ${vm.resCountdown}s."), 13.sp, SP.text)
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    HBtn(tx("PERTAHANKAN", "KEEP"), Modifier.weight(1f), solid = true) { vm.keepRes() }
                    HBtn(tx("BATALKAN", "REVERT"), Modifier.weight(1f)) { vm.revertRes() }
                }
            }
        }
        Text(tx("Ini untuk seluruh layar HP. Resolusi khusus game ada di tab Game.", "This changes the whole phone display. Per-game resolution is in the Games tab."), color = SP.dim, fontSize = 11.sp)
    }
}

@Composable
private fun AlatBersih(vm: AppViewModel, land: Boolean) {
    TwoCol(land, {
        Section(tx("BERSIHKAN RAM", "CLEAN RAM")) {
            HBtn(tx("BERSIHKAN SEKARANG", "CLEAN NOW"), Modifier.fillMaxWidth(), solid = true) { vm.cleanRam() }
            Text(tx("Hanya menutup proses latar belakang. Terminal, root manager, HSIN, launcher, keyboard, dan game yang sedang jalan tidak disentuh.", "Only closes background processes. Terminal, root manager, HSIN, launcher, keyboard and the running game are left alone."), color = SP.dim, fontSize = 11.sp, lineHeight = 14.sp)
            HBtn(tx("App dilindungi (${vm.prefs.ramKeep.size})", "Protected apps (${vm.prefs.ramKeep.size})"), Modifier.fillMaxWidth()) { vm.go("ramkeep") }
            HBtn(tx("Tutup semua app", "Close all apps"), Modifier.fillMaxWidth()) { vm.askCloseApps() }
        }
    }, {
        Section(tx("PERAWATAN", "MAINTENANCE"), 40) {
            HBtn(tx("Optimasi app (dexopt)", "Optimize apps (dexopt)"), Modifier.fillMaxWidth()) { vm.go("dexopt") }
            HBtn(tx("Memori dan penyetelan", "Memory tuning"), Modifier.fillMaxWidth()) { vm.go("memfx") }
            HBtn(tx("Lab baterai", "Battery lab"), Modifier.fillMaxWidth()) { vm.go("batlab") }
        }
    })
}

@Composable
private fun AlatLog(vm: AppViewModel) {
    val filters = listOf("ALL" to tx("Semua", "All"), "ERROR" to "Error", "CPU" to "CPU", "GAME" to "Game", "INPUT" to "Input")
    Section(tx("CATATAN MODUL", "MODULE LOG")) {
        HChips(filters.map { it.second }, filters.indexOfFirst { it.first == vm.logFilter }.coerceAtLeast(0)) { vm.logFilter = filters[it].first }
        val shown = vm.logs.filter { Hsin.logMatches(it, vm.logFilter) }.takeLast(10).reversed()
        if (shown.isEmpty()) SText(tx("Belum ada log.", "No log yet."), 12.sp, SP.faint)
        shown.forEach { l ->
            Row(Modifier.fillMaxWidth().padding(vertical = 2.dp)) {
                SText(relTime(l.timeMs), 11.sp, SP.faint, modifier = Modifier.width(34.dp))
                SText(l.cat, 11.sp, SP.gold, FontWeight.Medium, modifier = Modifier.width(78.dp))
                SText((l.status + " " + l.msg).trim(), 11.sp, SP.dim, modifier = Modifier.weight(1f))
            }
        }
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            HBtn(tx("Semua log", "Full log"), Modifier.weight(1f)) { vm.go("fulllog") }
            HBtn(tx("Salin", "Copy"), Modifier.weight(1f)) { vm.copyLog() }
            HBtn(tx("Ekspor", "Export"), Modifier.weight(1f)) { vm.exportLog() }
        }
    }
}

@Composable
private fun AlatSistem(vm: AppViewModel, land: Boolean) {
    TwoCol(land, {
        Section(tx("KESEHATAN MODUL", "MODULE HEALTH")) {
            val h = vm.health
            HealthRow("Uperf", h.uperf); HealthRow("fas-rs", h.fasrs); HealthRow(tx("Pemantau", "Monitor"), h.monitor)
            HealthRow(tx("Penjaga", "Watchdog"), h.watchdog); HealthRow(tx("Mode otomatis", "Auto mode"), h.auto)
            HSwitch("Boot guard", if (h.bootFail > 0) tx("gagal: ${h.bootFail}x", "failed: ${h.bootFail}x") else null, h.bootGuard) { vm.setBootGuard(it) }
            HBtn(tx("Cek ulang", "Recheck"), Modifier.fillMaxWidth()) { vm.checkHealth() }
        }
        Section(tx("CEK FITUR", "FEATURE CHECK"), 40) {
            Text(tx("Menguji sungguhan apakah tweak jalan di HP ini (± 10 detik). Buka game dulu bila ingin ikut cek sumber FPS.", "Really tests whether the tweaks work on this phone (~10 s). Open a game first to include the FPS source."), color = SP.dim, fontSize = 11.sp, lineHeight = 14.sp)
            HBtn(if (vm.liveBusy) tx("Menguji...", "Testing...") else tx("CEK SEMUA FITUR", "CHECK ALL FEATURES"), Modifier.fillMaxWidth(), solid = !vm.liveBusy) { if (!vm.liveBusy) vm.runLiveCheck() }
            if (vm.liveNote.isNotEmpty()) SText(vm.liveNote, 11.sp, SP.red)
            vm.liveRes.forEach { (st, name, note) ->
                Column {
                    SText((if (st == "OK") "✓ " else if (st == "GAGAL") "✗ " else "– ") + name, 12.sp, if (st == "OK") Color(0xFF4FE3C1) else if (st == "GAGAL") SP.red else SP.dim, FontWeight.Medium)
                    Text(note, color = SP.faint, fontSize = 10.sp)
                }
            }
        }
    }, {
        Section(tx("PERANGKAT", "DEVICE"), 20) {
            val d = vm.device
            KVRow("SoC", d["SOC_VENDOR"].orEmpty().ifEmpty { "—" })
            KVRow("GPU", d["GPU_VENDOR"].orEmpty().ifEmpty { "—" })
            KVRow("CPU", d["CPU_POLICIES"].orEmpty().ifEmpty { "—" })
            KVRow(tx("Penyimpanan", "Storage"), d["STORAGE_DEVICES"].orEmpty().ifEmpty { "—" })
            HBtn(tx("Deteksi ulang", "Redetect"), Modifier.fillMaxWidth()) { vm.redetect() }
        }
        Section(tx("MODUL", "MODULE"), 60) {
            HSwitch(tx("Jalan otomatis saat boot", "Start on boot"), null, vm.autostart) { vm.updateAutostart(it) }
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                HBtn("Refresh", Modifier.weight(1f)) { vm.refreshButton() }
                HBtn(tx("Cari modul", "Find module"), Modifier.weight(1f)) { vm.findModule() }
            }
            SText(when { !vm.rootOk -> tx("Root belum diberikan", "Root not granted"); vm.modPath.isEmpty() -> tx("Root OK · modul tidak ditemukan", "Root OK · module not found"); else -> "Root OK · ${vm.modPath}" }, 11.sp, SP.faint)
        }
        Section(tx("TENTANG", "ABOUT"), 90) {
            SText("HSIN by somwan", 15.sp, SP.text, FontWeight.SemiBold)
            Text("Uperf · fas-rs" + if (vm.status.ver > 0) " · v${vm.status.ver}" else "", color = SP.dim, fontSize = 12.sp)
            Text("Credit: Matt Yang & yinwanxi (Uperf), shadow3 & shadow3aaa (fas-rs)", color = SP.faint, fontSize = 11.sp)
        }
    })
}

@Composable
private fun HealthRow(name: String, ok: Boolean) {
    Row(Modifier.fillMaxWidth().padding(vertical = 3.dp), verticalAlignment = Alignment.CenterVertically) {
        SText(name, 13.sp, SP.dim, modifier = Modifier.weight(1f))
        Box(Modifier.size(8.dp).clip(CircleShape).background(if (ok) Color(0xFF4FE3C1) else SP.red))
        Spacer(Modifier.width(6.dp))
        SText(if (ok) tx("jalan", "on") else tx("mati", "off"), 12.sp, SP.text)
    }
}

@Composable
private fun KVRow(k: String, v: String) {
    Row(Modifier.fillMaxWidth().padding(vertical = 2.dp)) {
        SText(k, 12.sp, SP.dim, modifier = Modifier.weight(0.4f))
        SText(v, 12.sp, SP.text, modifier = Modifier.weight(0.6f))
    }
}

// =====================================================================
//  RITUAL LUNCUR: satu kali ketuk, langkah jalan sendiri lalu game dibuka
// =====================================================================

@Composable
internal fun RitualOverlay(vm: AppViewModel) {
    val pkg = UiState.ritual
    if (pkg.isEmpty()) return
    val clock = LocalClock.current
    val ctx = LocalContext.current
    val en = LocalEn.current
    val names = if (en) listOf("Clean RAM", "Apply mode", "Resolution", "Do not disturb", "Floating", "Open game")
    else listOf("Bersihkan RAM", "Terapkan mode", "Resolusi game", "Jangan ganggu", "Siapkan floating", "Buka game")
    val subs = if (en) listOf("Background apps only", "Profile for this game", "Applied by the module at launch", "Silence notifications", "FPS orb inside the game", "Starting now")
    else listOf("Hanya app latar belakang", "Profil khusus game ini", "Dipasang modul saat buka", "Notifikasi dibisukan", "Orb FPS di dalam game", "Dimulai sekarang")
    val results = remember(pkg) { mutableStateOf(List(6) { "" }) }
    var step by remember(pkg) { mutableIntStateOf(-1) }
    var cancelled by remember(pkg) { mutableStateOf(false) }
    var done by remember(pkg) { mutableStateOf(false) }
    var mode by remember(pkg) { mutableStateOf(info("seimbang")) }
    fun setRes(i: Int, v: String) { results.value = results.value.toMutableList().also { it[i] = v } }

    LaunchedEffect(pkg) {
        val g = vm.games.firstOrNull { it.pkg == pkg }
        val opts = Hsin.gameOpts(pkg)
        val fx = Hsin.gamefx(pkg)
        mode = info(profMode(g?.profile ?: "balanced", opts["OVD"] == "on"))
        step = 0
        val mb = vm.cleanRamQuiet()
        setRes(0, if (mb > 0) "+$mb MB" else "OK")
        delay(350)
        if (cancelled) { UiState.ritual = ""; return@LaunchedEffect }
        step = 1
        val gProf = g?.profile ?: "balanced"
        val modeOk = if (opts["OVD"] == "on") true else if (gProf in PROFILE_KEYS) Hsin.setProfile(gProf).ok else true
        delay(350)
        setRes(1, (if (en) mode.nameEn else mode.nameId) + if (modeOk) "" else if (en) " ✗" else " ✗")
        if (!modeOk) vm.toast(if (en) "Mode could not be applied" else "Mode gagal diterapkan")
        if (cancelled) { UiState.ritual = ""; return@LaunchedEffect }
        step = 2; delay(450)
        setRes(2, fx["downscale"].orEmpty().toDoubleOrNull()?.let { "${Math.round(it * 100)}%" } ?: "100%")
        step = 3; delay(450); setRes(3, if (vm.flag("GAME_DND_ON") && opts["LITE"] != "1") (if (en) "On" else "Aktif") else (if (en) "Off" else "Mati"))
        step = 4; delay(450)
        if (vm.bubbleOn && android.provider.Settings.canDrawOverlays(ctx)) { BubbleService.start(ctx); setRes(4, if (en) "Ready" else "Siap") } else setRes(4, if (en) "Off" else "Mati")
        if (cancelled) { UiState.ritual = ""; return@LaunchedEffect }
        step = 5
        val r = Hsin.launchGame(pkg)
        setRes(5, if (r.ok) (if (en) "Go" else "Mulai") else (if (en) "Failed" else "Gagal"))
        if (r.ok) {
            // verifikasi jujur: tunggu game benar-benar di depan
            var seen = false
            for (k in 0 until 6) { delay(700); if (Hsin.status()?.gamePkg == pkg) { seen = true; break } }
            if (!seen) setRes(5, if (en) "Starting…" else "Memuat…")
        }
        if (!r.ok) vm.toast(r.out.lines().firstOrNull { it.isNotBlank() } ?: "Gagal")
        step = 6
        done = r.ok
        delay(900)
        UiState.ritual = ""
    }

    val col = mode.color
    BoxWithConstraints(
        Modifier.fillMaxSize().background(Color(0xF2090A0D))
            .pointerInput(Unit) { detectTapGestures { } }
    ) {
        val wide = maxWidth > maxHeight
        Canvas(Modifier.fillMaxSize()) {
            for (i in 0 until 16) {
                val seed = i * 0.6180339f
                val x = ((seed * 7.31f) % 1f)
                val y = 1f - ((clock.floatValue * (0.05f + (i % 4) * 0.02f) + seed) % 1f)
                drawCircle(col.copy(alpha = 0.55f * sin(y * 3.1416f)), (1.5f + i % 3) * density, Offset(x * size.width, y * size.height))
            }
        }
        val content: @Composable (Modifier, Modifier) -> Unit = { m1, m2 ->
            Column(m1, horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center) {
                Box(Modifier.size(if (wide) 110.dp else 96.dp).graphicsLayer { val k = 1f + 0.03f * sin(clock.floatValue * 3f); scaleX = k; scaleY = k }
                    .drawBehind { drawCircle(Brush.radialGradient(listOf(col.copy(alpha = 0.5f), Color.Transparent), center, size.minDimension), size.minDimension) },
                    contentAlignment = Alignment.Center) { AppIcon(pkg, 72.dp) }
                Spacer(Modifier.height(10.dp))
                SText(vm.label(pkg), 18.sp, SP.text, FontWeight.Bold)
                SText(tx("Mode ", "Mode ") + (if (en) mode.nameEn else mode.nameId), 12.sp, col, FontWeight.SemiBold)
            }
            Column(m2, verticalArrangement = Arrangement.spacedBy(5.dp)) {
                SText(if (done) tx("Selamat bermain", "Have fun") else tx("Menyiapkan HP kamu...", "Getting your phone ready..."), 17.sp, SP.text, FontWeight.Bold)
                val prog = ownAnim(((step.coerceIn(0, 6)) / 6f), 400)
                Box(Modifier.fillMaxWidth().height(4.dp).clip(CircleShape).background(Color(0x22FFFFFF))) { Box(Modifier.fillMaxWidth(prog).fillMaxHeight().background(col)) }
                Spacer(Modifier.height(2.dp))
                for (i in 0 until 6) {
                    val finished = i < step || done
                    val cur = i == step && !done
                    val a = ownAnim(if (finished || cur) 1f else 0f, 250)
                    Glass(Modifier.fillMaxWidth(), radius = 10, alt = true) {
                        Row(Modifier.padding(horizontal = 10.dp, vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
                            Box(
                                Modifier.size(22.dp).clip(CircleShape).background(if (finished) col else Color.Transparent)
                                    .border(1.5.dp, if (finished) col else if (cur) col.copy(alpha = 0.5f + 0.5f * sin(clock.floatValue * 8f)) else Color(0x44FFFFFF), CircleShape),
                                contentAlignment = Alignment.Center
                            ) { SText(if (finished) "✓" else "${i + 1}", 11.sp, if (finished) SP.ink else SP.dim, FontWeight.Bold) }
                            Column(Modifier.weight(1f).padding(horizontal = 10.dp)) {
                                SText(names[i], 13.sp, lerpColor(SP.dim, SP.text, a), FontWeight.SemiBold)
                                SText(subs[i], 10.sp, SP.faint)
                            }
                            SText(results.value[i], 12.sp, col, FontWeight.Bold)
                        }
                    }
                }
                if (!done && step < 5) {
                    Box(Modifier.fillMaxWidth().tap { cancelled = true }.padding(top = 4.dp), contentAlignment = Alignment.Center) { SText(tx("Batal", "Cancel"), 12.sp, SP.dim) }
                }
            }
        }
        if (wide) Row(Modifier.fillMaxSize().padding(horizontal = 28.dp, vertical = 14.dp), horizontalArrangement = Arrangement.spacedBy(24.dp), verticalAlignment = Alignment.CenterVertically) { content(Modifier.weight(0.7f), Modifier.weight(1.3f)) }
        else Column(Modifier.fillMaxSize().padding(20.dp).verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(14.dp, Alignment.CenterVertically)) { content(Modifier.fillMaxWidth(), Modifier.fillMaxWidth()) }
    }
}
