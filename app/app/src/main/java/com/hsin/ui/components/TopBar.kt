package com.hsin.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import com.hsin.ui.theme.Gap
import com.hsin.ui.theme.HsinTheme
import com.hsin.ui.theme.Outline
import com.hsin.ui.theme.OutlineThick
import com.hsin.ui.theme.Pad
import com.hsin.ui.theme.PreviewBg
import com.hsin.ui.theme.Surface
import com.hsin.ui.theme.TitleLarge

// TopBar HSIN: judul "HSIN" saja, tanpa subtitle. Subtitle versi modul yang
// di-hardcode DILARANG (APP_PLAN bagian 1); versi modul hanya tampil bila
// kontrak menyediakannya (pending bagian 3). Garis bawah outline, tanpa
// elevation/bayangan.
@Composable
fun TopBar(
    title: String,
    modifier: Modifier = Modifier
) {
    Column(
        modifier = modifier
            .fillMaxWidth()
            .background(Surface)
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = Pad, vertical = Gap),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(text = title, style = TitleLarge)
        }
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .height(OutlineThick)
                .background(Outline)
        )
    }
}

@Preview(name = "TopBar", showBackground = true, backgroundColor = PreviewBg)
@Composable
private fun TopBarPreview() {
    HsinTheme {
        Column {
            TopBar("HSIN")
        }
    }
}
