package com.hsin.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.tooling.preview.Preview
import com.hsin.ui.theme.Bg
import com.hsin.ui.theme.HsinTheme
import com.hsin.ui.theme.Pad

// Kerangka layar: bg + TopBar + area konten + BottomNav. Sengaja BUKAN
// Scaffold Material3 supaya tidak ada warna/inset default Material yang
// bocor ke token HSIN.
@Composable
fun ScreenScaffold(
    title: String,
    selectedIndex: Int,
    onSelectTab: (Int) -> Unit,
    modifier: Modifier = Modifier,
    subtitle: String? = null,
    content: @Composable () -> Unit
) {
    Column(
        modifier = modifier
            .fillMaxSize()
            .background(Bg)
    ) {
        TopBar(title = title, subtitle = subtitle)
        Box(
            modifier = Modifier
                .fillMaxSize()
                .padding(Pad)
        ) {
            content()
        }
        BottomNav(selectedIndex = selectedIndex, onSelect = onSelectTab)
    }
}

@Preview(name = "ScreenScaffold", showBackground = true, backgroundColor = Bg.value.toLong())
@Composable
private fun ScreenScaffoldPreview() {
    HsinTheme {
        ScreenScaffold(
            title = "Beranda",
            selectedIndex = 0,
            onSelectTab = {},
            subtitle = "boot guard: aktif"
        ) {
            HCard {
                HBadge("APPLIED", HStatus.APPLIED)
            }
        }
    }
}
