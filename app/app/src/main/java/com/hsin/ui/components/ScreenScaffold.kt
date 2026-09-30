package com.hsin.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.res.vectorResource
import androidx.compose.ui.tooling.preview.Preview
import com.hsin.R
import com.hsin.ui.theme.PreviewBg
import com.hsin.ui.theme.Pad
import com.hsin.ui.theme.HsinTheme
import com.hsin.ui.theme.Bg

// Kerangka layar: bg + TopBar + area konten + BottomNav. Sengaja BUKAN
// Scaffold Material3 supaya tidak ada warna/inset default Material yang
// bocor ke token HSIN.
@Composable
fun ScreenScaffold(
    title: String,
    selectedIndex: Int,
    onSelectTab: (Int) -> Unit,
    modifier: Modifier = Modifier,
    content: @Composable () -> Unit
) {
    Column(
        modifier = modifier
            .fillMaxSize()
            .background(Bg)
    ) {
        TopBar(title = title)
        // Konten pakai weight(1f) — BUKAN fillMaxSize — supaya BottomNav
        // kebagian ruang. verticalScroll sentral di sini (bukan per layar)
        // supaya konten tidak terpotong di layar kecil (temuan L2 30 Sep:
        // Box fillMaxSize mendorong BottomNav keluar layar sejak A5).
        Box(
            modifier = Modifier
                .weight(1f)
                .verticalScroll(rememberScrollState())
                .padding(Pad)
        ) {
            content()
        }
        BottomNav(
            selectedIndex = selectedIndex,
            onSelect = onSelectTab,
            icons = navIcons(),
        )
    }
}

/**
 * Empat ikon tab dari vector drawable XML di `res/` (tanpa dependency baru,
 * APP_PLAN R2). Urutan WAJIB sama dengan [DEFAULT_TABS].
 */
@Composable
private fun navIcons(): List<ImageVector?> = listOf(
    ImageVector.vectorResource(R.drawable.ic_nav_home),
    ImageVector.vectorResource(R.drawable.ic_nav_knob),
    ImageVector.vectorResource(R.drawable.ic_nav_monitor),
    ImageVector.vectorResource(R.drawable.ic_nav_log),
)

@Preview(name = "ScreenScaffold", showBackground = true, backgroundColor = PreviewBg)
@Composable
private fun ScreenScaffoldPreview() {
    HsinTheme {
        ScreenScaffold(
            title = "HSIN",
            selectedIndex = 0,
            onSelectTab = {},
        ) {
            HCard {
                HBadge("APPLIED", HStatus.APPLIED)
            }
        }
    }
}
