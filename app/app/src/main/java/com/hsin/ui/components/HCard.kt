package com.hsin.ui.components

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.tooling.preview.Preview
import com.hsin.ui.theme.HsinTheme
import com.hsin.ui.theme.MonoBody
import com.hsin.ui.theme.Outline
import com.hsin.ui.theme.OutlineThick
import com.hsin.ui.theme.Pad
import com.hsin.ui.theme.PreviewBg
import com.hsin.ui.theme.Radius
import com.hsin.ui.theme.Shadow
import com.hsin.ui.theme.ShadowOffset
import com.hsin.ui.theme.Surface
import com.hsin.ui.theme.Text

// Kartu HSIN: surface + outline 1,5 dp + bayangan KERAS hitam offset 3 dp.
// Bayangan sengaja bukan shadow()/elevation Material (memakai blur); di sini
// Box hitam di belakang kartu supaya tepinya tajam dan buram nol.
@Composable
fun HCard(
    modifier: Modifier = Modifier,
    content: @Composable () -> Unit
) {
    Box(modifier = modifier) {
        Box(
            modifier = Modifier
                .matchParentSize()
                .padding(start = ShadowOffset, top = ShadowOffset)
                .background(Shadow, RoundedCornerShape(Radius))
        )
        Box(
            modifier = Modifier
                .matchParentSize()
                .background(Surface, RoundedCornerShape(Radius))
                .border(BorderStroke(OutlineThick, Outline), RoundedCornerShape(Radius))
        ) {
            Box(modifier = Modifier.padding(Pad)) { content() }
        }
    }
}

@Preview(name = "HCard", showBackground = true, backgroundColor = PreviewBg)
@Composable
private fun HCardPreview() {
    HsinTheme {
        HCard {
            Column {
                Text("readahead sda", style = MonoBody, color = Text)
                Text("diminta 2048 → diterapkan 2048", style = MonoBody, color = Text)
            }
        }
    }
}
