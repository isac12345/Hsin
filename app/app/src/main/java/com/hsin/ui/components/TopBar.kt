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
import com.hsin.ui.theme.MonoCaption
import com.hsin.ui.theme.Outline
import com.hsin.ui.theme.OutlineThick
import com.hsin.ui.theme.Pad
import com.hsin.ui.theme.PreviewBg
import com.hsin.ui.theme.Surface
import com.hsin.ui.theme.TitleLarge

// TopBar HSIN: judul + subjudul status opsional, garis bawah outline.
// Tanpa elevation/bayangan (neobrutalism memakai garis, bukan shadow lembut).
@Composable
fun TopBar(
    title: String,
    modifier: Modifier = Modifier,
    subtitle: String? = null
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
        if (subtitle != null) {
            Text(
                text = subtitle,
                style = MonoCaption,
                modifier = Modifier.padding(start = Pad, end = Pad, bottom = Gap)
            )
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
            TopBar("Beranda", subtitle = "root: siap · modul: aktif")
        }
    }
}
