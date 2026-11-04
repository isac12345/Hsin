package com.hsin

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.Stroke

/** Efek level "Mewah": garis pindai turun pelan + kilau tepi layar berdenyut sesuai warna mode. Tidak menangkap sentuhan. */
@Composable
internal fun FancyFx(vm: AppViewModel) {
    val clock = LocalClock.current
    val cm = curMode(vm)
    val col = if (cm.isEmpty()) SP.gold else info(cm).color
    Canvas(Modifier.fillMaxSize()) {
        val t = clock.floatValue
        val y = ((t * 0.18f) % 1f) * size.height
        drawRect(Brush.verticalGradient(listOf(Color.Transparent, col.copy(alpha = 0.10f), Color.Transparent), startY = y - 40f, endY = y + 40f))
        var k = 0f
        while (k < size.height) { drawLine(Color(0x08FFFFFF), Offset(0f, k), Offset(size.width, k), 1f); k += 6f }
        val pulse = 0.35f + 0.25f * kotlin.math.sin(t * 2.2f)
        drawRect(col.copy(alpha = pulse * 0.5f), style = Stroke(3f))
    }
}
