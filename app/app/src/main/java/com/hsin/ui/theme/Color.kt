package com.hsin.ui.theme

import androidx.compose.ui.graphics.Color

// Single source of truth warna HSIN (APP_PLAN bagian 2, revisi 30 Sep 2026:
// neobrutalism TERANG mengikuti mockup /sdcard/hsin/docs/ui/). Token lain di
// codebase WAJIB memakai nilai dari sini; literal hex hanya boleh di file
// ini. Hex bertanda "sementara": diukur dari mockup, dikunci setelah
// screenshot L2 (aturan APP_PLAN bagian 2).
val Bg = Color(0xFFF3EEE1) // latar layar (krem)
val Surface = Color(0xFFFCF9F1) // kartu (krem terang)
val Outline = Color(0xFF23211B) // garis 1,5 dp (tinta, bukan abu)
val Text = Color(0xFF23211B) // teks utama (tinta)
val Muted = Color(0xFF8B8471) // teks sekunder
val Accent = Color(0xFFC26A45) // satu-satunya aksen (terakota)
val Ok = Color(0xFF7E9A85) // APPLIED, status siap (sage)
val Warn = Color(0xFFB9954F) // FALLBACK, WARN, DIUBAH (mustard)
val Error = Color(0xFFB5604F) // FAILED
val Neutral = Color(0xFF6B6B70) // SKIPPED, DEFAULT, UNAVAILABLE

// Fill pastel untuk HBadge: badge = fill pastel + teks tinta (sesuai mockup,
// bukan outline-only). Turunan terang dari token status di atas; sementara,
// dikunci setelah L2.
val OkFill = Color(0xFFD8E2D5) // pastel sage
val WarnFill = Color(0xFFEBDFC0) // pastel mustard
val ErrorFill = Color(0xFFE6C8BE) // pastel terakota pucat
val NeutralFill = Color(0xFFDBD6C7) // pastel abu krem

// Bayangan keras HCard. Hitam pekat offset 3 dp tanpa blur (neobrutalism).
val Shadow = Color(0xFF000000)

// Nilai panjang untuk @Preview(backgroundColor = ...). Argumen anotasi
// WAJIB compile-time constant, jadi token Color tidak bisa dipakai langsung
// di sana; konstanta ini tetap di file yang sama supaya tetap satu sumber.
const val PreviewBg: Long = 0xFFF3EEE1L
