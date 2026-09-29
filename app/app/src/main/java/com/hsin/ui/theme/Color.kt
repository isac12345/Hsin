package com.hsin.ui.theme

import androidx.compose.ui.graphics.Color

// Single source of truth warna HSIN (APP_PLAN bagian 2). Token lain di
// codebase WAJIB memakai nilai dari sini; literal hex hanya boleh di file
// ini. Dark-only: tidak ada varian terang.
val Bg = Color(0xFF121214) // latar layar
val Surface = Color(0xFF1B1C1F) // kartu
val Outline = Color(0xFF3A3C42) // garis 1,5 dp
val Text = Color(0xFFECE8DF) // teks utama
val Muted = Color(0xFF9A978E) // teks sekunder
val Accent = Color(0xFFC8A97E) // satu-satunya aksen
val Ok = Color(0xFF7E9A85) // APPLIED, status siap
val Warn = Color(0xFFB9954F) // FALLBACK, WARN, DIUBAH
val Error = Color(0xFFB5604F) // FAILED
val Neutral = Color(0xFF6B6B70) // SKIPPED, DEFAULT, UNAVAILABLE

// Bayangan keras HCard. Hitam pekat (bukan abu-abu) supaya bayangan tetap
// terlihat di atas surface gelap tanpa perlu blur.
val Shadow = Color(0xFF000000)

// Nilai panjang untuk @Preview(backgroundColor = ...). Argumen anotasi
// WAJIB compile-time constant, jadi token Color tidak bisa dipakai langsung
// di sana; konstanta ini tetap di file yang sama supaya tetap satu sumber.
const val PreviewBg: Long = 0xFF121214L
