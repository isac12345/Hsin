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
import com.hsin.ui.theme.ErrorFill
import com.hsin.ui.theme.Gap
import com.hsin.ui.theme.HsinTheme
import com.hsin.ui.theme.PreviewBg
import com.hsin.ui.theme.MonoCaption
import com.hsin.ui.theme.NeutralFill
import com.hsin.ui.theme.OkFill
import com.hsin.ui.theme.Outline
import com.hsin.ui.theme.Radius
import com.hsin.ui.theme.Text
import com.hsin.ui.theme.WarnFill

// Status aplikasi (kategori hasil apply + status readiness).
enum class HStatus { APPLIED, FALLBACK, WARN, DIUBAH, FAILED, SKIPPED, DEFAULT, UNAVAILABLE, READY }

// Fill pastel badge per status (teks selalu tinta, lihat HBadge).
fun HStatus.fill(): Color = when (this) {
    HStatus.APPLIED, HStatus.READY -> OkFill
    HStatus.FALLBACK, HStatus.WARN, HStatus.DIUBAH -> WarnFill
    HStatus.FAILED -> ErrorFill
    HStatus.SKIPPED, HStatus.DEFAULT, HStatus.UNAVAILABLE -> NeutralFill
}

// Badge HSIN: FILL PASTEL + teks tinta (sesuai mockup terang, bukan
// outline-only). Garis tinta tipis 1 dp menjaga gaya neobrutalism.
@Composable
fun HBadge(
    label: String,
    status: HStatus,
    modifier: Modifier = Modifier
) {
    val fill = status.fill()
    Box(
        modifier = modifier
            .background(fill, RoundedCornerShape(Radius))
            .border(BorderStroke(1.dp, Outline), RoundedCornerShape(Radius))
            .padding(horizontal = Gap, vertical = 4.dp),
        contentAlignment = Alignment.Center
    ) {
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
