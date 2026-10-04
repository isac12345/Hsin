package com.hsin

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

@Composable
fun HText(
    text: String,
    modifier: Modifier = Modifier,
    size: TextUnit = 13.sp,
    color: Color = LocalPal.current.text,
    spacing: TextUnit = 0.5.sp,
    weight: FontWeight = FontWeight.Normal
) {
    Text(
        text = text,
        modifier = modifier,
        color = color,
        fontSize = size,
        fontFamily = FontFamily.Monospace,
        letterSpacing = spacing,
        fontWeight = weight
    )
}

@Composable
fun Label(text: String, modifier: Modifier = Modifier) {
    HText(text.uppercase(), modifier, 11.sp, LocalPal.current.dim, 2.sp)
}

@Composable
fun HCard(
    modifier: Modifier = Modifier,
    onClick: (() -> Unit)? = null,
    padV: Dp = 14.dp,
    content: @Composable ColumnScope.() -> Unit
) {
    val p = LocalPal.current
    val shape = RoundedCornerShape(20.dp)
    var m = modifier
        .fillMaxWidth()
        .clip(shape)
        .background(p.card)
        .border(BorderStroke(0.5.dp, p.line), shape)
    if (onClick != null) m = m.clickable { onClick() }
    Column(m.padding(horizontal = 16.dp, vertical = padV), content = content)
}

@Composable
fun HButton(
    text: String,
    modifier: Modifier = Modifier,
    primary: Boolean = false,
    enabled: Boolean = true,
    onClick: () -> Unit
) {
    val p = LocalPal.current
    val bg = if (primary) p.pill else p.ghost
    val fg = if (primary) p.onPill else p.text
    Box(
        modifier
            .clip(CircleShape)
            .background(bg)
            .border(BorderStroke(0.5.dp, if (primary) p.pill else p.line), CircleShape)
            .clickable(enabled = enabled) { onClick() }
            .padding(vertical = 12.dp, horizontal = 12.dp),
        contentAlignment = Alignment.Center
    ) {
        HText(text.uppercase(), size = 11.sp, color = if (enabled) fg else fg.copy(alpha = 0.4f), spacing = 1.4.sp)
    }
}

@Composable
fun Segmented(options: List<String>, selected: Int, onSelect: (Int) -> Unit, modifier: Modifier = Modifier) {
    val p = LocalPal.current
    Row(modifier.fillMaxWidth().clip(CircleShape).background(p.track).padding(4.dp)) {
        options.forEachIndexed { i, o ->
            val sel = i == selected
            Box(
                Modifier
                    .weight(1f)
                    .clip(CircleShape)
                    .background(if (sel) p.pill else Color.Transparent)
                    .clickable { onSelect(i) }
                    .padding(vertical = 9.dp),
                contentAlignment = Alignment.Center
            ) {
                HText(o.uppercase(), size = 11.sp, color = if (sel) p.onPill else p.dim, spacing = 1.4.sp)
            }
        }
    }
}

@Composable
fun InfoRow(k: String, v: String, vColor: Color = LocalPal.current.text) {
    Row(
        Modifier.fillMaxWidth().padding(vertical = 7.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically
    ) {
        HText(k, size = 12.sp, color = LocalPal.current.dim)
        HText(v, size = 12.sp, color = vColor, modifier = Modifier.padding(start = 12.dp))
    }
}

@Composable
fun Divider() {
    Box(Modifier.fillMaxWidth().height(0.5.dp).background(LocalPal.current.line))
}

@Composable
fun Sparkline(values: List<Float>, modifier: Modifier = Modifier) {
    val p = LocalPal.current
    Canvas(modifier) {
        if (values.size < 2) return@Canvas
        var lo = values.minOrNull() ?: 0f
        var hi = values.maxOrNull() ?: 1f
        if (hi - lo < 0.001f) { lo -= 1f; hi += 1f }
        val path = Path()
        var lastY = 0f
        values.forEachIndexed { i, x ->
            val px = size.width * i / (values.size - 1)
            val py = size.height - ((x - lo) / (hi - lo)) * size.height * 0.88f - size.height * 0.06f
            if (i == 0) path.moveTo(px, py) else path.lineTo(px, py)
            lastY = py
        }
        drawPath(path, p.text, style = Stroke(width = 1.6.dp.toPx(), cap = StrokeCap.Round))
        drawCircle(p.text, 2.5.dp.toPx(), Offset(size.width, lastY))
    }
}

fun fmtFreq(unit: String, raw: String): String {
    val n = raw.toLongOrNull() ?: return raw
    return when (unit) {
        "khz" -> if (n >= 1000000) String.format(java.util.Locale.US, "%.2f GHz", n / 1000000.0) else "${n / 1000} MHz"
        "hz" -> "${n / 1000000} MHz"
        else -> raw
    }
}
