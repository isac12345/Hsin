package com.hsin.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.tooling.preview.Preview
import com.hsin.data.state.LogPresenter
import com.hsin.data.state.UiState
import com.hsin.ui.ScreenPhase
import com.hsin.ui.ScreenStates
import com.hsin.ui.components.ContentTitle
import com.hsin.ui.components.EmptyView
import com.hsin.ui.components.ErrorView
import com.hsin.ui.components.HBadge
import com.hsin.ui.components.HButton
import com.hsin.ui.components.HCard
import com.hsin.ui.components.HSegmented
import com.hsin.ui.components.HStatus
import com.hsin.ui.components.LoadingView
import com.hsin.ui.theme.Caption
import com.hsin.ui.theme.Gap
import com.hsin.ui.theme.HsinTheme
import com.hsin.ui.theme.MonoCaption
import com.hsin.ui.theme.Muted
import com.hsin.ui.theme.PreviewBg
import com.hsin.ui.theme.TitleSmall

/**
 * Layar Log A12.
 *
 * Dua tab (`boot.log` / `apply.log`), masing-masing hanya N baris terakhir
 * ([LogPresenter.MAX_LINES], kontrak §3.6) — penggunaan memori dibatasi.
 * Tiap baris punya badge level ([LogPresenter.levelOf]); baris rusak tetap
 * tampil apa adanya tanpa crash.
 *
 * Tombol "Salin ringkasan laporan bug" menyalin [LogPresenter.buildBugReport]
 * (status boot guard + ringkasan capability + ekor log) ke clipboard.
 * Layar ini tidak memanggil root; refresh via [onRefresh].
 */
@Composable
fun LogScreen(
    state: UiState,
    onRefresh: () -> Unit,
    modifier: Modifier = Modifier,
) {
    var tab by remember { mutableIntStateOf(0) }
    val clipboard = LocalClipboardManager.current
    var copied by remember { mutableIntStateOf(0) }

    LaunchedEffect(Unit) {
        onRefresh()
    }

    val lines = if (tab == 0) state.logBoot else state.logApply

    Column(
        modifier = modifier.fillMaxWidth(),
        verticalArrangement = Arrangement.spacedBy(Gap),
    ) {
        // R2: judul konten besar "Log".
        ContentTitle("Log")
        // R2: fase eksplisit — tidak ada jalur yang merender blank.
        when (ScreenStates.log(state)) {
            ScreenPhase.LOADING -> LoadingView("Memuat log dari modul...")
            ScreenPhase.ERROR -> ErrorView(
                message = state.error?.let { com.hsin.ui.friendlyError(it.kind.name, it.detail) }
                    ?: "Terjadi kesalahan.",
                onRetry = onRefresh,
            )
            ScreenPhase.EMPTY -> {
                LogControlCard(
                    tab = tab,
                    onTab = { tab = it },
                    copied = copied,
                    onCopy = {
                        clipboard.setText(
                            AnnotatedString(
                                LogPresenter.buildBugReport(
                                    state.guard,
                                    state.capability,
                                    state.logBoot,
                                    state.logApply,
                                )
                            )
                        )
                        copied++
                    },
                    onRefresh = onRefresh,
                )
                EmptyView(
                    message = "Belum ada baris log (file hilang di modul = kosong, bukan error).",
                    actionLabel = "Muat ulang",
                    onAction = onRefresh,
                )
            }
            ScreenPhase.CONTENT -> {
                LogControlCard(
                    tab = tab,
                    onTab = { tab = it },
                    copied = copied,
                    onCopy = {
                        clipboard.setText(
                            AnnotatedString(
                                LogPresenter.buildBugReport(
                                    state.guard,
                                    state.capability,
                                    state.logBoot,
                                    state.logApply,
                                )
                            )
                        )
                        copied++
                    },
                    onRefresh = onRefresh,
                )
                lines.forEach { line ->
                    HCard {
                        Column(verticalArrangement = Arrangement.spacedBy(Gap)) {
                            Row(
                                modifier = Modifier.fillMaxWidth(),
                                horizontalArrangement = Arrangement.SpaceBetween,
                                verticalAlignment = Alignment.CenterVertically,
                            ) {
                                Text("baris log", style = Caption, color = Muted)
                                HBadge(LogPresenter.levelOf(line), levelStatus(LogPresenter.levelOf(line)))
                            }
                            Text(line, style = MonoCaption)
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun LogControlCard(
    tab: Int,
    onTab: (Int) -> Unit,
    copied: Int,
    onCopy: () -> Unit,
    onRefresh: () -> Unit,
) {
    HCard {
        Column(verticalArrangement = Arrangement.spacedBy(Gap)) {
            Text("Log", style = TitleSmall)
            // R3: toggle tersegmentasi (aktif = fill accent), tanpa ubah logic.
            HSegmented(
                options = listOf("boot.log", "apply.log"),
                selected = tab,
                onSelect = onTab,
            )
            HButton(
                label = if (copied > 0) "Disalin ($copied)" else "Salin ringkasan laporan bug",
                onClick = onCopy,
                primary = false,
            )
            HButton(label = "Muat ulang", onClick = onRefresh, primary = false)
        }
    }
}

private fun levelStatus(level: String): HStatus = when (level) {
    "ERROR", "FAILED", "CRITICAL", "PANIC" -> HStatus.FAILED
    "WARN", "WARNING", "HIGH" -> HStatus.WARN
    else -> HStatus.DEFAULT
}

@Preview(showBackground = true, backgroundColor = PreviewBg)
@Composable
private fun LogScreenPreview() {
    HsinTheme {
        LogScreen(state = UiState(), onRefresh = {})
    }
}

@Preview(showBackground = true, backgroundColor = PreviewBg)
@Composable
private fun LogScreenLoadingPreview() {
    HsinTheme {
        LogScreen(state = UiState(loadingLogs = true), onRefresh = {})
    }
}
