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
import androidx.compose.ui.unit.dp
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
    // R3: grid status 2 kolom (kata mockup: Tersedia/Terpasang/Nonaktif).
    StatusGridCard(state = state)

    // R3: kartu "Terakhir diterapkan · HH:MM" (maks 3 baris + jam apply.log).
    LastAppliedCard(state = state)

    EdgeStatesCard(state = state)

    // R3: kartu kemampuan + catatan snapshot.
    CapabilityCard(state = state)

    HButton(label = "Buka knob", onClick = navActions::onOpenKnobs, primary = true)
    HButton(label = "Pulihkan backup", onClick = onConfirmRestore, primary = false)
    HButton(label = "Periksa ulang", onClick = onRefresh, primary = false)

    // Error inline saat data sudah ada: isi tetap tampil, bukan layar gagal.
    state.error?.let { err ->
        ErrorCard(text = friendlyError(err.kind.name, err.detail))
    }
}

/** Grid 2x2 dari [HomePresenter.grid]: label + nilai + badge (kecuali termal). */
@Composable
private fun StatusGridCard(state: UiState) {
    HCard {
        Column(verticalArrangement = Arrangement.spacedBy(Gap)) {
            Text("Status", style = TitleSmall)
            HomePresenter.grid(state).chunked(2).forEach { row ->
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(Gap),
                ) {
                    row.forEach { cell ->
                        Column(
                            modifier = Modifier.weight(1f),
                            verticalArrangement = Arrangement.spacedBy(4.dp),
                        ) {
                            Text(cell.label, style = Caption, color = Muted)
                            Text(cell.value, style = BodyLarge)
                            if (cell.showBadge) {
                                HBadge(cell.value, cell.status.toHStatus())
                            }
                        }
                    }
                }
            }
        }
    }
}

private fun HomePresenter.LineStatus.toHStatus(): HStatus = when (this) {
    HomePresenter.LineStatus.OK -> HStatus.READY
    HomePresenter.LineStatus.WARN -> HStatus.WARN
    HomePresenter.LineStatus.ERROR -> HStatus.FAILED
    HomePresenter.LineStatus.UNKNOWN -> HStatus.UNAVAILABLE
}

/** Kartu hasil apply terakhir; kosong = "Belum ada apply", bukan kartu hilang. */
@Composable
private fun LastAppliedCard(state: UiState) {
    val last = HomePresenter.lastApplied(state)
    HCard {
        Column(verticalArrangement = Arrangement.spacedBy(Gap)) {
            Text(last.title, style = TitleSmall)
            if (last.rows.isEmpty()) {
                Text("Belum ada apply", style = BodyLarge, color = Muted)
            } else {
                last.rows.forEach { row ->
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Text(
                            text = row.text,
                            style = BodyLarge,
                            color = Muted,
                            modifier = Modifier.weight(1f),
                        )
                        Spacer()
                        HBadge(row.badge, row.badge.toResultStatus())
                    }
                }
            }
        }
    }
}

private fun String.toResultStatus(): HStatus = when (this) {
    "APPLIED" -> HStatus.APPLIED
    "FALLBACK" -> HStatus.FALLBACK
    "FAILED" -> HStatus.FAILED
    "SKIPPED" -> HStatus.SKIPPED
    "UNAVAILABLE" -> HStatus.UNAVAILABLE
    else -> HStatus.DEFAULT
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
private fun CapabilityCard(state: UiState) {
    HCard {
        Column(verticalArrangement = Arrangement.spacedBy(Gap)) {
            Text("Kemampuan perangkat", style = TitleSmall)
            HomePresenter.capabilityRows(state).forEach { row ->
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text(row.label, style = BodyLarge, color = Muted)
                    Text(row.value, style = BodyLarge)
                }
            }
            Text(HomePresenter.CAPABILITY_FOOTNOTE, style = Caption, color = Muted)
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
