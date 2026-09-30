package com.hsin.ui.components

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import com.hsin.ui.theme.Error
import com.hsin.ui.theme.Gap
import com.hsin.ui.theme.HsinTheme
import com.hsin.ui.theme.PreviewBg
import com.hsin.ui.theme.MonoCaption
import com.hsin.ui.theme.Neutral
import com.hsin.ui.theme.Ok
import com.hsin.ui.theme.Radius
import com.hsin.ui.theme.Text
import com.hsin.ui.theme.Warn

// Status aplikasi (kategori hasil apply + status readiness).
enum class HStatus { APPLIED, FALLBACK, WARN, DIUBAH, FAILED, SKIPPED, DEFAULT, UNAVAILABLE, READY }

fun HStatus.color(): Color = when (this) {
    HStatus.APPLIED, HStatus.READY -> Ok
    HStatus.FALLBACK, HStatus.WARN, HStatus.DIUBAH -> Warn
    HStatus.FAILED -> Error
    HStatus.SKIPPED, HStatus.DEFAULT, HStatus.UNAVAILABLE -> Neutral
}

// Badge HSIN: fill pastel + teks tinta (sesuai mockup, APP_PLAN bagian 2).
// Warna status dibawa fill + border; teks tetap Text agar terbaca.
@Composable
fun HBadge(
    label: String,
    status: HStatus,
    modifier: Modifier = Modifier
) {
    val c = status.color()
    Box(
        modifier = modifier
            .background(c.copy(alpha = 0.22f), RoundedCornerShape(Radius))
            .border(BorderStroke(1.dp, c), RoundedCornerShape(Radius))
            .padding(horizontal = Gap, vertical = 4.dp),
        contentAlignment = Alignment.Center
    ) {
        // Teks badge memakai Text (tinta): kontras ke fill pastel.
        Text(text = label, style = MonoCaption, color = Text)
    }
}

@Preview(name = "HBadge", showBackground = true, backgroundColor = PreviewBg)
@Composable
private fun HBadgePreview() {
    HsinTheme {
        Column(verticalArrangement = Arrangement.spacedBy(Gap)) {
            HBadge("APPLIED", HStatus.APPLIED)
            HBadge("FALLBACK", HStatus.FALLBACK)
            HBadge("FAILED", HStatus.FAILED)
            HBadge("UNAVAILABLE", HStatus.UNAVAILABLE)
        }
    }
}
