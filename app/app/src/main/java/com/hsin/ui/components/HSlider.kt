package com.hsin.ui.components

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.tooling.preview.Preview
import com.hsin.ui.theme.Accent
import com.hsin.ui.theme.Gap
import com.hsin.ui.theme.HsinTheme
import com.hsin.ui.theme.PreviewBg
import com.hsin.ui.theme.MonoBody
import com.hsin.ui.theme.MonoCaption
import com.hsin.ui.theme.Outline
import com.hsin.ui.theme.TouchMin
import com.hsin.ui.theme.Text

// Slider HSIN untuk nilai kontinu (mis. persentase/level log). Aksen hanya
// di thumb + track aktif. Area sentuh dijaga >= 44 dp (TDI: Slider default
// jauh lebih rendah dari 44 dp).
@Composable
fun HSlider(
    label: String,
    value: Float,
    onValueChange: (Float) -> Unit,
    modifier: Modifier = Modifier,
    valueRange: ClosedFloatingPointRange<Float> = 0f..100f,
    enabled: Boolean = true
) {
    Column(modifier = modifier.padding(vertical = Gap)) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(text = label, style = MonoCaption)
            // Angka selalu monospace + tampil bulat: nilai log/knob tidak
            // perlu desimal di layar.
            Text(text = "${value.toInt()}", style = MonoBody, color = Accent)
        }
        Slider(
            value = value,
            onValueChange = onValueChange,
            valueRange = valueRange,
            enabled = enabled,
            colors = SliderDefaults.colors(
                thumbColor = Accent,
                activeTrackColor = Accent,
                inactiveTrackColor = Outline
            ),
            modifier = Modifier
                .fillMaxWidth()
                .height(TouchMin)
        )
    }
}

@Preview(name = "HSlider", showBackground = true, backgroundColor = PreviewBg)
@Composable
private fun HSliderPreview() {
    HsinTheme {
        Column {
            HSlider("cpu_limit %", value = 70f, onValueChange = {})
            HSlider("vfs_cache_pressure", value = 100f, onValueChange = {})
        }
    }
}
