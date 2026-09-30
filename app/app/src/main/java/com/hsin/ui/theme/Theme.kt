package com.hsin.ui.theme

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Typography
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable

// Override TOTAL: semua slot colorScheme diisi dari token HSIN supaya tidak
// ada warna default Material3 yang bocor ke komponen mana pun.
val HsinColorScheme = darkColorScheme(
    primary = Accent,
    onPrimary = Text,
    primaryContainer = Surface,
    onPrimaryContainer = Text,
    inversePrimary = Accent,
    secondary = Accent,
    onSecondary = Text,
    secondaryContainer = Surface,
    onSecondaryContainer = Text,
    tertiary = Muted,
    onTertiary = Text,
    tertiaryContainer = Surface,
    onTertiaryContainer = Text,
    background = Bg,
    onBackground = Text,
    surface = Surface,
    onSurface = Text,
    surfaceVariant = Surface,
    onSurfaceVariant = Muted,
    surfaceTint = Accent,
    inverseSurface = Outline,
    inverseOnSurface = Surface,
    outline = Outline,
    outlineVariant = Outline,
    error = Error,
    onError = Text,
    errorContainer = Surface,
    onErrorContainer = Text,
    scrim = Bg
)

// Tipografi Material3 ditimpa dengan token HSIN (angka/log = monospace).
val HsinTypography = Typography(
    titleLarge = TitleLarge,
    titleMedium = TitleSmall,
    bodyLarge = BodyLarge,
    bodyMedium = BodyLarge,
    bodySmall = Caption,
    labelLarge = BodyLarge,
    labelMedium = Caption,
    labelSmall = Caption
)

// Dark-only sesuai spec user: palet gelap, tanpa dynamic color (dynamic color
// akan menimpa token HSIN dengan warna sistem).
@Composable
fun HsinTheme(content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme = HsinColorScheme,
        typography = HsinTypography,
        content = content
    )
}
