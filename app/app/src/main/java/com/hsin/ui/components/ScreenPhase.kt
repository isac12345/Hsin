package com.hsin.ui.components

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.tooling.preview.Preview
import com.hsin.ui.theme.BodyLarge
import com.hsin.ui.theme.Accent
import com.hsin.ui.theme.Gap
import com.hsin.ui.theme.HsinTheme
import com.hsin.ui.theme.PreviewBg
import com.hsin.ui.theme.TitleLarge

/**
 * Elemen fase layar R2 (aturan APP_PLAN §0.11: tidak ada layar blank).
 *
 * Tiap layar memakai [ContentTitle] (hanya Knob/Log) + satu dari
 * [LoadingView]/[ErrorView]/[EmptyView]/konten. Fase mana yang tampil
 * diputus pure resolver [com.hsin.ui.ScreenStates] supaya bisa unit-test
 * tanpa Android; file ini hanya menampilkan.
 */

/** Judul konten besar — hanya layar Knob ("Knob") dan Log ("Log"). */
@Composable
fun ContentTitle(
    text: String,
    modifier: Modifier = Modifier,
) {
    Text(
        text = text,
        style = TitleLarge,
        modifier = modifier.fillMaxWidth(),
    )
}

/** Fase Memuat: progres + teks. Tidak pernah layar kosong. */
@Composable
fun LoadingView(
    text: String,
    modifier: Modifier = Modifier,
) {
    HCard(modifier = modifier) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(Gap),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            CircularProgressIndicator(color = Accent)
            Text(text = text, style = BodyLarge)
        }
    }
}

/** Fase Gagal: pesan ramah (tanpa exception mentah) + tombol coba lagi. */
@Composable
fun ErrorView(
    message: String,
    onRetry: () -> Unit,
    modifier: Modifier = Modifier,
) {
    HCard(modifier = modifier) {
        Column(verticalArrangement = Arrangement.spacedBy(Gap)) {
            HBadge("GAGAL", HStatus.FAILED)
            Text(text = message, style = BodyLarge)
            HButton(label = "Coba lagi", onClick = onRetry, primary = true)
        }
    }
}

/** Fase Kosong: pesan + aksi (bukan kartu hilang, bukan layar blank). */
@Composable
fun EmptyView(
    message: String,
    modifier: Modifier = Modifier,
    actionLabel: String? = null,
    onAction: (() -> Unit)? = null,
) {
    HCard(modifier = modifier) {
        Column(verticalArrangement = Arrangement.spacedBy(Gap)) {
            Text(text = message, style = BodyLarge)
            if (actionLabel != null && onAction != null) {
                HButton(label = actionLabel, onClick = onAction, primary = false)
            }
        }
    }
}

@Preview(name = "ContentTitle", showBackground = true, backgroundColor = PreviewBg)
@Composable
private fun ContentTitlePreview() {
    HsinTheme { ContentTitle("Knob") }
}

@Preview(name = "LoadingView", showBackground = true, backgroundColor = PreviewBg)
@Composable
private fun LoadingViewPreview() {
    HsinTheme { LoadingView("Memuat status modul...") }
}

@Preview(name = "ErrorView", showBackground = true, backgroundColor = PreviewBg)
@Composable
private fun ErrorViewPreview() {
    HsinTheme { ErrorView("Modul HSIN belum terpasang. Pasang modul lalu reboot.", onRetry = {}) }
}

@Preview(name = "EmptyView", showBackground = true, backgroundColor = PreviewBg)
@Composable
private fun EmptyViewPreview() {
    HsinTheme { EmptyView("Belum ada baris log.", actionLabel = "Muat ulang", onAction = {}) }
}
