package com.hsin

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            HSINApp()
        }
    }
}

@Composable
fun HSINApp() {
    var screen by remember { mutableStateOf("beranda") }
    MaterialTheme {
        Surface(modifier = Modifier.fillMaxSize(), color = androidx.compose.ui.graphics.Color(0xFF121214)) {
            Scaffold { inner ->
                Column(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(inner)
                        .padding(24.dp)
                ) {
                    Text(
                        text = "HSIN",
                        fontSize = 32.sp,
                        color = androidx.compose.ui.graphics.Color(0xFFECE8DF)
                    )
                    Text(
                        text = "Status: siap • screen=$screen",
                        color = androidx.compose.ui.graphics.Color(0xFF9A978E),
                        fontSize = 14.sp
                    )
                    Box(modifier = Modifier.weight(1f), contentAlignment = Alignment.Center) {
                        Text(
                            text = "Controller aktif — navigasi state: $screen",
                            color = androidx.compose.ui.graphics.Color(0xFFC8A97E)
                        )
                    }
                }
            }
        }
    }
}
