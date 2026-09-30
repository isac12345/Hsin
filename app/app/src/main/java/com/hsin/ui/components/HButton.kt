package com.hsin.ui.components

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import com.hsin.ui.theme.TouchMin
import com.hsin.ui.theme.Text
import com.hsin.ui.theme.Radius
import com.hsin.ui.theme.PreviewBg
import com.hsin.ui.theme.Outline
import com.hsin.ui.theme.HsinTheme
import com.hsin.ui.theme.Gap
import com.hsin.ui.theme.Accent

// Tombol utama = fill accent + teks tinta. Sekunder = outline tinta,
// isi transparan. Tanpa gradient/blur. Target sentuh >= 44 dp.
@Composable
fun HButton(
    label: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    primary: Boolean = true
) {
    Button(
        onClick = onClick,
        modifier = modifier.heightIn(min = TouchMin),
        shape = RoundedCornerShape(Radius),
        colors = if (primary) {
            ButtonDefaults.buttonColors(containerColor = Accent, contentColor = Text)
        } else {
            ButtonDefaults.buttonColors(containerColor = Color.Transparent, contentColor = Text)
        },
        border = if (primary) null else BorderStroke(1.dp, Outline)
    ) {
        Text(text = label, color = Text)
    }
}

@Preview(name = "HButton", showBackground = true, backgroundColor = PreviewBg)
@Composable
private fun HButtonPreview() {
    HsinTheme {
        Column(verticalArrangement = Arrangement.spacedBy(Gap)) {
            Row(horizontalArrangement = Arrangement.spacedBy(Gap)) {
                HButton("Terapkan (2)", onClick = {})
                HButton("Pulihkan backup", onClick = {}, primary = false)
            }
        }
    }
}
