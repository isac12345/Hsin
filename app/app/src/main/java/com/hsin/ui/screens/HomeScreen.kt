package com.hsin.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.tooling.preview.Preview
import com.hsin.data.state.UiState
import com.hsin.ui.HomePresenter
import com.hsin.ui.ScreenPhase
import com.hsin.ui.ScreenStates
import com.hsin.ui.friendlyError
import com.hsin.ui.NavActions
import com.hsin.ui.components.EmptyView
import com.hsin.ui.components.ErrorView
import com.hsin.ui.components.HBadge
import com.hsin.ui.components.HButton
import com.hsin.ui.components.HCard
import com.hsin.ui.components.HStatus
import com.hsin.ui.components.HSelectRow
import com.hsin.ui.components.LoadingView
import com.hsin.ui.theme.Gap
import com.hsin.ui.theme.HsinTheme
import com.hsin.ui.theme.Muted
import com.hsin.ui.theme.PreviewBg
import com.hsin.ui.theme.BodyLarge
import com.hsin.ui.theme.Caption
import com.hsin.ui.theme.TitleSmall

/**
 * Layar Beranda.
 *
 * Semuanya membaca [UiState] yang sudah diisi ViewModel; layar ini TIDAK
 * memanggil root sendiri. Root call hanya ada di `viewModelScope`
 * (lihat HsinViewModel).
 */
@Composable
fun HomeScreen(
    state: UiState,
    navActions: NavActions,
    onRefresh: () -> Unit,
    modifier: Modifier = Modifier,
) {
    var confirmRestore by remember { mutableStateOf(false) }

    Column(
        modifier = modifier.fillMaxWidth(),
        verticalArrangement = Arrangement.spacedBy(Gap),
    ) {
        // R2: fase eksplisit — tidak ada jalur yang merender blank.
        when (ScreenStates.home(state)) {
            ScreenPhase.LOADING -> LoadingView("Memuat status modul...")
            ScreenPhase.ERROR -> ErrorView(
                message = state.error?.let { friendlyError(it.kind.name, it.detail) }
                    ?: "Terjadi kesalahan.",
                onRetry = onRefresh,
            )
            ScreenPhase.EMPTY -> EmptyView(
                message = "Belum ada data modul. Periksa ulang untuk memuat status.",
                actionLabel = "Periksa ulang",
                onAction = onRefresh,
            )
            ScreenPhase.CONTENT -> HomeContent(state, navActions, onRefresh, onConfirmRestore = { confirmRestore = true })
        }
    }

    if (confirmRestore) {
        val c = HomePresenter.ConfirmRestore.RESTORE
        AlertDialog(
            onDismissRequest = { confirmRestore = false },
            title = { Text(c.title, style = TitleSmall) },
            text = { Text(c.body, style = BodyLarge) },
            confirmButton = {
                TextButton(onClick = {
                    confirmRestore = false
                    navActions.onRestoreBackupConfirmed()
                }) {
                    Text(c.confirmLabel, style = BodyLarge, color = com.hsin.ui.theme.Accent)
                }
            },
            dismissButton = {
                TextButton(onClick = { confirmRestore = false }) {
                    Text("Batal", style = BodyLarge, color = Muted)
                }
            },
            containerColor = com.hsin.ui.theme.Surface,
        )
    }
}

@Composable
private fun HomeContent(
    state: UiState,
    navActions: NavActions,
    onRefresh: () -> Unit,
    onConfirmRestore: () -> Unit,
) {
    StatusCard(state = state)

    ApplyCard(state = state)

    EdgeStatesCard(state = state)

    CapabilityCard(state = state)

    HButton(label = "Buka knob", onClick = navActions::onOpenKnobs, primary = true)
    HButton(label = "Pulihkan backup", onClick = onConfirmRestore, primary = false)
    HButton(label = "Periksa ulang", onClick = onRefresh, primary = false)

    // Error inline saat data sudah ada: isi tetap tampil, bukan layar gagal.
    state.error?.let { err ->
        ErrorCard(text = friendlyError(err.kind.name, err.detail))
    }
}

@Composable
private fun StatusCard(state: UiState) {
    HCard {
        Column(verticalArrangement = Arrangement.spacedBy(Gap)) {
            Text("Status", style = TitleSmall)
            HomePresenter.lines(state).forEach { line ->
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text(line.label, style = BodyLarge, color = Muted)
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(line.value, style = BodyLarge, color = com.hsin.ui.theme.Text)
                        Spacer()
                        StatusDot(line.status)
                    }
                }
            }
        }
    }
}

@Composable
private fun ApplyCard(state: UiState) {
    val apply = HomePresenter.lastApply(state)
    HCard {
        Column(verticalArrangement = Arrangement.spacedBy(Gap)) {
            Text("Hasil terakhir", style = TitleSmall)
            Text(apply.headline, style = BodyLarge)
            apply.detail?.let { Text(it, style = BodyLarge, color = Muted) }
        }
    }
}

/**
 * Banner kasus tepi A13: guard aktif, transport error, versi tidak cocok,
 * degraded (parsial), dan catatan node read-only. Semua dari presenter
 * murni ([ErrorStatesPresenter]) — layar hanya menampilkan.
 */
@Composable
private fun EdgeStatesCard(state: UiState) {
    val banners = com.hsin.ui.ErrorStatesPresenter.allBanners(state)
    val readOnly = com.hsin.ui.ErrorStatesPresenter.readOnlyNotes(state.applyResults)
    if (banners.isEmpty() && readOnly.isEmpty()) return
    HCard {
        Column(verticalArrangement = Arrangement.spacedBy(Gap)) {
            Text("Perhatian", style = TitleSmall)
            banners.forEach { b ->
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Column(modifier = Modifier.weight(1f)) {
                        Text(b.title, style = BodyLarge)
                        Text(b.body, style = BodyLarge, color = Muted)
                    }
                    Spacer()
                    HBadge(
                        when (b.tone) {
                            com.hsin.ui.ErrorStatesPresenter.Tone.ERROR -> "GAGAL"
                            com.hsin.ui.ErrorStatesPresenter.Tone.WARN -> "PERHATIAN"
                            com.hsin.ui.ErrorStatesPresenter.Tone.INFO -> "INFO"
                        },
                        when (b.tone) {
                            com.hsin.ui.ErrorStatesPresenter.Tone.ERROR -> HStatus.FAILED
                            com.hsin.ui.ErrorStatesPresenter.Tone.WARN -> HStatus.WARN
                            com.hsin.ui.ErrorStatesPresenter.Tone.INFO -> HStatus.DEFAULT
                        },
                    )
                }
            }
            readOnly.forEach { note ->
                Text("read-only: $note", style = BodyLarge, color = Muted)
            }
        }
    }
}

@Composable
private fun CapabilityCard(state: UiState) {    HCard {
        Column(verticalArrangement = Arrangement.spacedBy(Gap)) {
            Text("Kemampuan perangkat", style = TitleSmall)
            HSelectRow(
                label = "Ringkasan",
                value = HomePresenter.capabilitySummary(state),
                onClick = null,
            )
        }
    }
}

@Composable
private fun ErrorCard(text: String) {
    HCard {
        Column(verticalArrangement = Arrangement.spacedBy(Gap)) {
            HBadge("PERLU TINDAKAN", HStatus.FAILED)
            Text(text, style = BodyLarge)
        }
    }
}

@Composable
private fun Spacer() {
    Box(modifier = Modifier.size(Gap))
}

/** Titik status kecil; memakai HBadge agar token warna tidak bocor. */
@Composable
private fun StatusDot(status: HomePresenter.LineStatus) {
    val badge = when (status) {
        HomePresenter.LineStatus.OK -> "SIAP" to HStatus.READY
        HomePresenter.LineStatus.WARN -> "PERHATIAN" to HStatus.WARN
        HomePresenter.LineStatus.ERROR -> "GAGAL" to HStatus.FAILED
        HomePresenter.LineStatus.UNKNOWN -> "N/A" to HStatus.UNAVAILABLE
    }
    HBadge(badge.first, badge.second)
}

private object NoopNavActions : NavActions {
    override fun onOpenKnobs() = Unit
    override fun onRestoreBackupConfirmed() = Unit
}

@Preview(showBackground = true, backgroundColor = PreviewBg)
@Composable
private fun HomeScreenPreview() {
    HsinTheme {
        HomeScreen(
            state = UiState(),
            navActions = NoopNavActions,
            onRefresh = {},
        )
    }
}

@Preview(showBackground = true, backgroundColor = PreviewBg)
@Composable
private fun HomeScreenLoadingPreview() {
    HsinTheme {
        HomeScreen(
            state = UiState(loadingCapability = true),
            navActions = NoopNavActions,
            onRefresh = {},
        )
    }
}

@Preview(showBackground = true, backgroundColor = PreviewBg)
@Composable
private fun HomeScreenErrorPreview() {
    HsinTheme {
        HomeScreen(
            state = UiState(
                error = com.hsin.data.state.UiError(
                    kind = com.hsin.data.state.UiErrorKind.MODULE_NOT_FOUND,
                    detail = "",
                    retryable = false,
                ),
            ),
            navActions = NoopNavActions,
            onRefresh = {},
        )
    }
}

@Preview(showBackground = true, backgroundColor = PreviewBg)
@Composable
private fun HomeScreenGuardActivePreview() {
    HsinTheme {
        HomeScreen(
            state = UiState(
                guard = com.hsin.data.state.GuardState(
                    active = 1,
                    failCount = 2,
                    threshold = 2,
                    cooldownRemainingSec = 86400,
                    lastReason = "boot gagal 2 x berturut-turut",
                ),
                activeProfile = "manual",
                applyStatus = "ok",
            ),
            navActions = NoopNavActions,
            onRefresh = {},
        )
    }
}
