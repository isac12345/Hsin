package com.hsin

import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color

class Pal(val dark: Boolean, cardAlpha: Float) {
    val bg = if (dark) Color(0xFF0C0A10) else Color(0xFFEDEBE6)
    val text = if (dark) Color(0xFFECE9E4) else Color(0xFF1A1A1A)
    val dim = text.copy(alpha = 0.62f)
    val faint = text.copy(alpha = 0.38f)
    val card = (if (dark) Color(0xFF100D14) else Color.White).copy(alpha = cardAlpha)
    val line = text.copy(alpha = 0.18f)
    val pill = text
    val onPill = if (dark) Color(0xFF111111) else Color(0xFFF2F0EC)
    val track = (if (dark) Color.Black else Color(0xFF1A1A1A)).copy(alpha = if (dark) 0.4f else 0.08f)
    val ghost = text.copy(alpha = 0.08f)
    val warn = if (dark) Color(0xFFE6B86A) else Color(0xFF9A6B10)
    val bad = if (dark) Color(0xFFE57373) else Color(0xFFB3261E)
    val scrim = (if (dark) Color.Black else Color.White).copy(alpha = 0.25f)
    val navBg = bg.copy(alpha = 0.88f)
}

val LocalPal = staticCompositionLocalOf { Pal(true, 0.55f) }
