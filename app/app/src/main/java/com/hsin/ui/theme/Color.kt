package com.hsin.ui.theme

import androidx.compose.ui.graphics.Color

// Single source of truth warna HSIN (APP_PLAN bagian 2). Token lain di
// codebase WAJIB memakai nilai dari sini; literal hex hanya boleh di file
// ini. Palet GELAP + HBadge outline-only adalah spec yang disetujui user;
// jangan dikembalikan ke tema terang/fill-pastel tanpa persetujuan baru.
val Bg = Color(0xFF121214) // latar layar
val Surface = Color(0xFF1B1C1F) // kartu
// Outline 3.89:1 vs bg dan 3.54:1 vs Surface (ambang non-teks 3:1, diukur
// terhadap Surface karena garis HCard duduk di atas kartu). Tetap 4x lebih
// redup dari Text, jadi terbaca sebagai "garis muted".
val Outline = Color(0xFF727272) // garis 1,5 dp
val Text = Color(0xFFECE8DF) // teks utama
val Muted = Color(0xFF9A978E) // teks sekunder
val Accent = Color(0xFFC8A97E) // satu-satunya aksen
val Ok = Color(0xFF7E9A85) // APPLIED, status siap (sage)
val Warn = Color(0xFFB9954F) // FALLBACK, WARN, DIUBAH (mustard)
val Error = Color(0xFFB5604F) // FAILED
val Neutral = Color(0xFF6B6B70) // SKIPPED, DEFAULT, UNAVAILABLE

// Bayangan keras HCard: satu token dipakai dua fungsi (garis kartu + bayangan
// offset 3 dp tanpa blur). Hitam pekat #000000 SALAH di atas bg gelap —
// kontrasnya cuma 1.12:1 sehingga bayangan tak terlihat sama sekali. Pakai
// Outline, yang sudah lolos ambang 3:1.
val Shadow = Color(0xFF727272)

// Nilai panjang untuk @Preview(backgroundColor = ...). Argumen anotasi
// WAJIB compile-time constant, jadi token Color tidak bisa dipakai langsung
// di sana; konstanta ini tetap di file yang sama supaya tetap satu sumber.
const val PreviewBg: Long = 0xFF121214L
