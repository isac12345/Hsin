package com.hsin.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import com.hsin.ui.theme.Accent
import com.hsin.ui.theme.Bg
import com.hsin.ui.theme.Gap
import com.hsin.ui.theme.HsinTheme
import com.hsin.ui.theme.MonoCaption
import com.hsin.ui.theme.Outline
import com.hsin.ui.theme.OutlineThick
import com.hsin.ui.theme.Surface
import com.hsin.ui.theme.TouchMin

// Bottom nav 4 tab, state-based TANPA library navigasi:Pemanggil yang
// memegang state (selectedIndex) dan meneruskan onSelect.
@Composable
fun BottomNav(
    selectedIndex: Int,
    onSelect: (Int) -> Unit,
    modifier: Modifier = Modifier,
    labels: List<String> = DEFAULT_TABS
) {
    Column(modifier = modifier.fillMaxWidth().background(Surface)) {
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .height(OutlineThick)
                .background(Outline)
        )
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .heightIn(min = TouchMin),
            horizontalArrangement = Arrangement.SpaceEvenly,
            verticalAlignment = Alignment.CenterVertically
        ) {
            labels.forEachIndexed { index, label ->
                val selected = index == selectedIndex
                Box(
                    modifier = Modifier
                        .heightIn(min = TouchMin)
                        .clickable { onSelect(index) }
                        .padding(horizontal = Gap),
                    contentAlignment = Alignment.Center
                ) {
                    // Tab aktif ditandai GARIS accent di atas + teks accent
                    // (outline, bukan blok fill) supaya tetap konsisten dengan
                    // gaya kartu/badge.
                    Box(
                        modifier = Modifier
                            .height(OutlineThick)
                            .background(if (selected) Accent else Outline)
                    )
                    Text(
                        text = label,
                        style = MonoCaption,
                        color = if (selected) Accent else Outline
                    )
                }
            }
        }
    }
}

val DEFAULT_TABS = listOf("Beranda", "Knob", "Monitor", "Log")

@Preview(name = "BottomNav", showBackground = true, backgroundColor = Bg.value.toLong())
@Composable
private fun BottomNavPreview() {
    HsinTheme {
        Column {
            BottomNav(selectedIndex = 1, onSelect = {})
        }
    }
}
