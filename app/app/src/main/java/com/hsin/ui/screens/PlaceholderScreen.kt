package com.hsin.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.tooling.preview.Preview
import com.hsin.ui.components.HCard
import com.hsin.ui.theme.BodyLarge
import com.hsin.ui.theme.Caption
import com.hsin.ui.theme.Gap
import com.hsin.ui.theme.HsinTheme
import com.hsin.ui.theme.PreviewBg
import androidx.compose.material3.Text

/**
 * Placeholder untuk tab yang dikerjakan di langkah berikutnya (Knob A9,
 * Monitor A13, Log A14). Sengaja jujur: UI belum diimplementasikan pada
 * langkah ini, bukan menampilkan data karangan.
 */
@Composable
fun PlaceholderScreen(tabTitle: String, modifier: Modifier = Modifier) {
    Column(
        modifier = modifier.fillMaxWidth(),
        verticalArrangement = Arrangement.spacedBy(Gap),
    ) {
        HCard {
            Column(verticalArrangement = Arrangement.spacedBy(Gap)) {
                Text(tabTitle, style = BodyLarge)
                Text("Layar ini dikerjakan pada langkah berikutnya.", style = Caption)
            }
        }
    }
}

@Preview(showBackground = true, backgroundColor = PreviewBg)
@Composable
private fun PlaceholderPreview() {
    HsinTheme {
        PlaceholderScreen("Knob")
    }
}
