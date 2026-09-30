package com.hsin.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import com.hsin.ui.theme.Accent
import com.hsin.ui.theme.Gap
import com.hsin.ui.theme.HsinTheme
import com.hsin.ui.theme.Neutral
import com.hsin.ui.theme.PreviewBg

/**
 * Bar proporsi R3 (kartu Frekuensi + RAM Monitor): nilai/maks.
 * Tanpa gradient/blur; rel memakai [Neutral], isi [Accent].
 */
@Composable
fun HBar(
    fraction: Float?,
    modifier: Modifier = Modifier,
) {
    val f = fraction?.coerceIn(0f, 1f) ?: 0f
    Box(
        modifier = modifier
            .fillMaxWidth()
            .height(8.dp)
            .clip(RoundedCornerShape(4.dp))
            .background(Neutral),
    ) {
        Box(
            modifier = Modifier
                .fillMaxWidth(f)
                .height(8.dp)
                .clip(RoundedCornerShape(4.dp))
                .background(Accent),
        )
    }
}

@Preview(name = "HBar", showBackground = true, backgroundColor = PreviewBg)
@Composable
private fun HBarPreview() {
    HsinTheme {
        Column(verticalArrangement = Arrangement.spacedBy(Gap)) {
            HBar(0.75f)
            HBar(0.3f)
            HBar(null)
        }
    }
}
