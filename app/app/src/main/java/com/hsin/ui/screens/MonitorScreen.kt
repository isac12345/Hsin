package com.hsin.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.size
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalLifecycleOwner
import androidx.compose.ui.tooling.preview.Preview
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.repeatOnLifecycle
import com.hsin.data.state.RealtimeMetrics
import com.hsin.data.state.UiState
import com.hsin.ui.MonitorPresenter
import com.hsin.ui.components.HBadge
import com.hsin.ui.components.HButton
import com.hsin.ui.components.HCard
import com.hsin.ui.components.HStatus
import com.hsin.ui.theme.BodyLarge
import com.hsin.ui.theme.Caption
import com.hsin.ui.theme.Gap
import com.hsin.ui.theme.HsinTheme
import com.hsin.ui.theme.Muted
import com.hsin.ui.theme.PreviewBg
import com.hsin.ui.theme.TitleSmall
import kotlinx.coroutines.delay

/**
 * Layar Monitor A11.
 *
 * Polling on-demand ~2 detik, lifecycle-aware:
 * - `LaunchedEffect` terikat komposisi: saat user pindah tab, composable
 *   keluar komposisi dan efek dibatalkan → polling berhenti.
 * - `repeatOnLifecycle(STARTED)`: saat app ke background, lifecycle di bawah
 *   STARTED dan blok ditangguhkan → polling berhenti.
 * - Tombol Jeda/Lanjut menghentikan/menyambung tanpa keluar layar.
 *
 * Sumber metrik = `status` via ViewModel.refreshRealtime (kontrak §3.1).
 * Tak tersedia = "N/A" + badge UNAVAILABLE, bukan 0.
 */
@Composable
fun MonitorScreen(
    state: UiState,
    onTick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    var paused by remember { mutableStateOf(false) }
    val lifecycle = LocalLifecycleOwner.current.lifecycle

    LaunchedEffect(paused) {
        if (paused) return@LaunchedEffect
        lifecycle.repeatOnLifecycle(Lifecycle.State.STARTED) {
            onTick()
            while (true) {
                delay(2000L)
                onTick()
            }
        }
    }

    Column(
        modifier = modifier.fillMaxWidth(),
        verticalArrangement = Arrangement.spacedBy(Gap),
    ) {
        HCard {
            Column(verticalArrangement = Arrangement.spacedBy(Gap)) {
                Text("Monitor", style = TitleSmall)
                Text(
                    if (paused) "Dijeda — tidak ada polling" else "Memantau tiap ~2 dtk (berhenti saat pindah layar/background)",
                    style = Caption,
                    color = Muted,
                )
                HButton(
                    label = if (paused) "Lanjut" else "Jeda",
                    onClick = { paused = !paused },
                    primary = false,
                )
            }
        }
        HCard {
            Column(verticalArrangement = Arrangement.spacedBy(Gap)) {
                MonitorPresenter.lines(state.metrics).forEach { line ->
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Text(line.label, style = BodyLarge, color = Muted)
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Text(line.display, style = BodyLarge)
                            Spacer()
                            HBadge(
                                if (line.readable) "TERBACA" else "N/A",
                                if (line.readable) HStatus.READY else HStatus.UNAVAILABLE,
                            )
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun Spacer() {
    Box(modifier = Modifier.size(Gap))
}

@Preview(showBackground = true, backgroundColor = PreviewBg)
@Composable
private fun MonitorScreenPreview() {
    HsinTheme {
        MonitorScreen(state = UiState(metrics = RealtimeMetrics.unknown()), onTick = {})
    }
}
