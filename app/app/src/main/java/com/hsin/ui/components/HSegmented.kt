package com.hsin.ui.components

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.tooling.preview.Preview
import com.hsin.ui.theme.Accent
import com.hsin.ui.theme.Bg
import com.hsin.ui.theme.BodyLarge
import com.hsin.ui.theme.Gap
import com.hsin.ui.theme.HsinTheme
import com.hsin.ui.theme.Outline
import com.hsin.ui.theme.OutlineThick
import com.hsin.ui.theme.Pad
import com.hsin.ui.theme.PreviewBg
import com.hsin.ui.theme.Radius
import com.hsin.ui.theme.Text
import com.hsin.ui.theme.TouchMin

/**
 * Toggle tersegmentasi R3 (tab boot.log/apply.log): opsi aktif = fill
 * [Accent] + teks tinta; nonaktif = transparan + teks tinta. Satu bingkai
 * outline tinta, tanpa dependency baru.
 */
@Composable
fun HSegmented(
    options: List<String>,
    selected: Int,
    onSelect: (Int) -> Unit,
    modifier: Modifier = Modifier,
) {
    Row(
        modifier = modifier
            .fillMaxWidth()
            .border(BorderStroke(OutlineThick, Outline), RoundedCornerShape(Radius))
            .clip(RoundedCornerShape(Radius)),
        horizontalArrangement = Arrangement.SpaceEvenly,
    ) {
        options.forEachIndexed { index, label ->
            val active = index == selected
            Box(
                modifier = Modifier
                    .weight(1f)
                    .heightIn(min = TouchMin)
                    .background(if (active) Accent else Color.Transparent)
                    .clickable { onSelect(index) }
                    .padding(horizontal = Pad),
                contentAlignment = Alignment.Center,
            ) {
                // Segmen aktif berlatar Accent (emas terang) jadi teksnya
                // Bg, bukan Text: Aksen+Text hanya 1.82:1 (lihat HButton).
                Text(text = label, style = BodyLarge, color = if (active) Bg else Text)
            }
        }
    }
}

@Preview(name = "HSegmented", showBackground = true, backgroundColor = PreviewBg)
@Composable
private fun HSegmentedPreview() {
    HsinTheme {
        Column(
            verticalArrangement = Arrangement.spacedBy(Gap),
        ) {
            HSegmented(options = listOf("boot.log", "apply.log"), selected = 0, onSelect = {})
            HSegmented(options = listOf("boot.log", "apply.log"), selected = 1, onSelect = {})
        }
    }
}
