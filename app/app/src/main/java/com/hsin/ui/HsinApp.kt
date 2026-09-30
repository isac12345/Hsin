package com.hsin.ui

import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.tooling.preview.Preview
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.hsin.data.HsinViewModel
import com.hsin.data.state.UiState
import com.hsin.ui.components.ScreenScaffold
import com.hsin.ui.screens.HomeScreen
import com.hsin.ui.screens.KnobScreen
import com.hsin.ui.screens.LogScreen
import com.hsin.ui.screens.MonitorScreen
import com.hsin.ui.theme.HsinTheme

/**
 * Kerangka aplikasi: top bar + 4 tab + bottom nav.
 *
 * Navigasi berbasis state — indeks tab disimpan di sini (`remember`), bukan
 * lewat library navigasi (keputusan A4: nol dependency navigasi).
 * ViewModel diambil lewat `viewModel()` sehingga di-scope activity: state
 * edit knob bertahan saat pindah tab maupun saat rotasi.
 */
@Composable
fun HsinApp(
    modifier: Modifier = Modifier,
    viewModel: HsinViewModel = viewModel(),
) {
    val state by viewModel.uiState.collectAsStateWithLifecycle()
    var tab by remember { mutableIntStateOf(0) }

    val actions = remember(viewModel) {
        object : NavActions {
            override fun onOpenKnobs() {
                tab = Tab.KNOB.ordinal
            }

            override fun onRestoreBackupConfirmed() {
                viewModel.restoreBackup()
            }
        }
    }

    ScreenScaffold(
        title = "HSIN",
        selectedIndex = tab,
        onSelectTab = { tab = it },
        modifier = modifier,
    ) {
        when (Tab.entries[tab]) {
            Tab.BERANDA -> HomeScreen(
                state = state,
                navActions = actions,
                onRefresh = {
                    viewModel.refreshUiState()
                    viewModel.refreshStatus()
                    viewModel.refreshCapability()
                },
            )
            Tab.KNOB -> KnobScreen(
                state = state,
                onSetOverride = viewModel::setKnobOverride,
                onApply = { viewModel.applyDirtyKnobs() },
                onRefresh = viewModel::refreshCapability,
            )
            Tab.MONITOR -> MonitorScreen(
                state = state,
                onTick = viewModel::refreshRealtime,
            )
            Tab.LOG -> LogScreen(
                state = state,
                onRefresh = viewModel::refreshLogs,
            )
        }
    }
}

@Preview(showBackground = true, backgroundColor = com.hsin.ui.theme.PreviewBg)
@Composable
private fun HsinAppPreview() {
    HsinTheme {
        ScreenScaffold(
            title = "HSIN",
            selectedIndex = 0,
            onSelectTab = {},
        ) {
            HomeScreen(
                state = UiState(),
                navActions = object : NavActions {
                    override fun onOpenKnobs() = Unit
                    override fun onRestoreBackupConfirmed() = Unit
                },
                onRefresh = {},
            )
        }
    }
}
