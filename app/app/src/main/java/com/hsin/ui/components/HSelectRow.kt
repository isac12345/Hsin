package com.hsin.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import com.hsin.ui.theme.Accent
import com.hsin.ui.theme.BodyLarge
import com.hsin.ui.theme.HsinTheme
import com.hsin.ui.theme.MonoBody
import com.hsin.ui.theme.Outline
import com.hsin.ui.theme.Pad
import com.hsin.ui.theme.PreviewBg
import com.hsin.ui.theme.TouchMin

// Baris pilihan dalam daftar opsi/knob. Target sentuh >= 44 dp, nilai
// selalu monospace (kolom angka harus sejajar antar baris).
@Composable
fun HSelectRow(
    label: String,
    value: String,
    onClick: (() -> Unit)?,
    modifier: Modifier = Modifier,
    selected: Boolean = false
) {
    Column(modifier = modifier.fillMaxWidth()) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .heightIn(min = TouchMin)
                .then(if (onClick != null) Modifier.clickable { onClick() } else Modifier)
                .padding(horizontal = Pad, vertical = 8.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = androidx.compose.foundation.layout.Arrangement.SpaceBetween
        ) {
            Text(text = label, style = BodyLarge)
            Text(text = value, style = MonoBody, color = if (selected) Accent else com.hsin.ui.theme.Text)
        }
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .height(1.dp)
                .background(Outline)
        )
    }
}

@Preview(name = "HSelectRow", showBackground = true, backgroundColor = PreviewBg)
@Composable
private fun HSelectRowPreview() {
    HsinTheme {
        Column {
            HSelectRow("governor policy0", "schedutil", onClick = {}, selected = true)
            HSelectRow("governor policy6", "powersave", onClick = {})
            HSelectRow("readahead sda", "2048", onClick = {})
        }
    }
}
