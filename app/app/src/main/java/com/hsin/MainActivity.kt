package com.hsin

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import com.hsin.ui.components.HBadge
import com.hsin.ui.components.HButton
import com.hsin.ui.components.HCard
import com.hsin.ui.components.HSelectRow
import com.hsin.ui.components.HSlider
import com.hsin.ui.components.HStatus
import com.hsin.ui.components.ScreenScaffold
import com.hsin.ui.theme.HsinTheme

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            HSINApp()
        }
    }
}

// Akar UI. Navigasi berbasis state (tanpa library navigasi): indeks tab
// hidup di ViewModel nanti (A7); di A5 masih state lokal supaya scaffold
// bisa dirender tanpa data modul.
@Composable
fun HSINApp() {
    HsinTheme {
        var tab by remember { mutableIntStateOf(0) }
        ScreenScaffold(
            title = "HSIN",
            selectedIndex = tab,
            onSelectTab = { tab = it },
            subtitle = "beta · modul v5.0.0-beta1"
        ) {
            Column(verticalArrangement = Arrangement.spacedBy(com.hsin.ui.theme.Gap)) {
                HCard {
                    Column(verticalArrangement = Arrangement.spacedBy(com.hsin.ui.theme.Gap)) {
                        androidx.compose.material3.Text(
                            text = "Boot guard",
                            style = com.hsin.ui.theme.BodyLarge
                        )
                        HBadge("UNAVAILABLE", HStatus.UNAVAILABLE)
                    }
                }
                HSlider(label = "cpu_limit %", value = 70f, onValueChange = {})
                HSelectRow(label = "readahead sda", value = "2048", onClick = {})
                HButton(label = "Terapkan (1)", onClick = {})
            }
        }
    }
}
