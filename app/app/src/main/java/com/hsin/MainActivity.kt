package com.hsin

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.text.BasicText
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

// Palet neobrutalism dark (APP_PLAN bagian 2). Dipindah ke token tema di A5.
private val HsinBg = Color(0xFF121214)
private val HsinText = Color(0xFFECE8DF)
private val HsinMuted = Color(0xFF9A978E)
private val HsinAccent = Color(0xFFC8A97E)

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            HSINApp()
        }
    }
}

// Akar UI: navigasi berbasis state (tanpa library navigasi, sesuai
// keputusan final). Layar penuh (Beranda/Knob/Monitor/Log) dibangun di
// A8-A12; scaffold A4 hanya membuktikan struktur + compile Compose.
@Composable
fun HSINApp() {
    var screen by remember { mutableStateOf("beranda") }
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(24.dp)
    ) {
        BasicText(
            text = "HSIN",
            style = TextStyle(color = HsinText, fontSize = 32.sp)
        )
        BasicText(
            text = "Status: siap",
            style = TextStyle(color = HsinMuted, fontSize = 14.sp)
        )
        Box(modifier = Modifier.weight(1f), contentAlignment = Alignment.Center) {
            BasicText(
                text = "Controller aktif — layar: $screen",
                style = TextStyle(color = HsinAccent, fontSize = 14.sp)
            )
        }
    }
}
