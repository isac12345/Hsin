package com.hsin.ui.theme

import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.sp

// Tipografi: teks biasa pakai font sistem; MONOSPACE HANYA untuk angka dan
// baris log (APP_PLAN: "Nilai angka dan log memakai font monospace").
val TitleLarge = TextStyle(fontSize = 22.sp, color = Text, fontFamily = FontFamily.Default)
val TitleSmall = TextStyle(fontSize = 16.sp, color = Text, fontFamily = FontFamily.Default)
val BodyLarge = TextStyle(fontSize = 14.sp, color = Text, fontFamily = FontFamily.Default)
val Caption = TextStyle(fontSize = 12.sp, color = Muted, fontFamily = FontFamily.Default)

// Gaya angka/log: lebar karakter tetap supaya kolom angka sejajar.
val Mono = FontFamily.Monospace
val MonoLarge = TextStyle(fontSize = 16.sp, color = Text, fontFamily = Mono)
val MonoBody = TextStyle(fontSize = 13.sp, color = Text, fontFamily = Mono)
val MonoCaption = TextStyle(fontSize = 12.sp, color = Muted, fontFamily = Mono)
