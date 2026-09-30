package com.hsin.ui.theme

import androidx.compose.ui.graphics.Color

// Single source of truth warna HSIN (APP_PLAN bagian 2, revisi terang
// 30 Sep 2026 — mockup menang untuk visual). Token lain WAJIB memakai
// nilai dari sini; literal hex hanya boleh di file ini.
val Bg = Color(0xFFF3EEE1) // latar layar (krem)
val Surface = Color(0xFFFCF9F1) // kartu (krem terang)
// Outline tinta 1,5 dp (bukan abu) — garis HCard duduk di atas kartu.
val Outline = Color(0xFF23211B) // garis 1,5 dp
val Text = Color(0xFF23211B) // teks utama (tinta)
val Muted = Color(0xFF8B8471) // teks sekunder
val Accent = Color(0xFFC26A45) // satu-satunya aksen (terakota)
val Ok = Color(0xFF7E9A85) // APPLIED, status siap (sage)
val Warn = Color(0xFFB9954F) // FALLBACK, WARN, DIUBAH (mustard)
val Error = Color(0xFFB5604F) // FAILED
val Neutral = Color(0xFF6B6B70) // SKIPPED, DEFAULT, UNAVAILABLE

// Bayangan keras HCard: hitam offset 3 dp tanpa blur (APP_PLAN bagian 2).
val Shadow = Color(0xFF000000)

// Nilai panjang untuk @Preview(backgroundColor = ...). Argumen anotasi
// WAJIB compile-time constant, jadi token Color tidak bisa dipakai langsung
// di sana; konstanta ini tetap di file yang sama supaya tetap satu sumber.
const val PreviewBg: Long = 0xFFF3EEE1L
