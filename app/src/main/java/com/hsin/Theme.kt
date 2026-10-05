package com.hsin

import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color

val THEME_NAMES = listOf("Carbon", "Terminal", "Paper", "Blueprint")

/** Empat palet. Bentuk dan font sama di semua tema (sederhana, tanpa hiasan). */
class Pal(val theme: Int, cardAlpha: Float) {
    val dark = theme != 2
    val bg = when (theme) {
        1 -> Color(0xFF050805)
        2 -> Color(0xFFF1EEE6)
        3 -> Color(0xFF0B2545)
        else -> Color(0xFF111214)
    }
    val text = when (theme) {
        1 -> Color(0xFFB9F5B9)
        2 -> Color(0xFF1A1A1A)
        3 -> Color(0xFFD8F1FF)
        else -> Color(0xFFE9EBEE)
    }
    val accent = when (theme) {
        1 -> Color(0xFF7DFF7D)
        2 -> Color(0xFFD6361F)
        3 -> Color(0xFF5FD0FF)
        else -> Color(0xFFC6FF2E)
    }
    private val cardBase = when (theme) {
        1 -> Color(0xFF0A110A)
        2 -> Color(0xFFFBF9F4)
        3 -> Color(0xFF0D2D55)
        else -> Color(0xFF1A1C1F)
    }
    val dim = text.copy(alpha = 0.64f)
    val faint = text.copy(alpha = 0.40f)
    val card = cardBase.copy(alpha = cardAlpha)
    val line = text.copy(alpha = 0.20f)
    val pill = if (theme == 0) Color(0xFFECE9E4) else accent.let { if (theme == 2) Color(0xFF1A1A1A) else it }
    val onPill = if (theme == 2) Color(0xFFF2F0EC) else Color(0xFF0B0B0B)
    val track = text.copy(alpha = 0.18f)
    val ghost = text.copy(alpha = 0.08f)
    val warn = if (dark) Color(0xFFE6B86A) else Color(0xFF9A6B10)
    val bad = if (dark) Color(0xFFE57373) else Color(0xFFB3261E)
    val scrim = (if (dark) Color.Black else Color.White).copy(alpha = if (dark) 0.34f else 0.72f)
    val navBg = bg.copy(alpha = 0.90f)
}

val LocalPal = staticCompositionLocalOf { Pal(0, 0.72f) }
