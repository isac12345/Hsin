package com.hsin.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.tooling.preview.Preview
import com.hsin.data.state.UiState
import com.hsin.ui.components.HBadge
import com.hsin.ui.components.HButton
import com.hsin.ui.components.HCard
import com.hsin.ui.components.HSelectRow
import com.hsin.ui.components.HSlider
import com.hsin.ui.components.HStatus
import com.hsin.ui.knob.KnobCategory
import com.hsin.ui.knob.KnobCategoryBuilder
import com.hsin.ui.knob.KnobCategoryUi
import com.hsin.ui.knob.KnobKind
import com.hsin.ui.knob.KnobRow
import com.hsin.ui.theme.BodyLarge
import com.hsin.ui.theme.Caption
import com.hsin.ui.theme.Gap
import com.hsin.ui.theme.HsinTheme
import com.hsin.ui.theme.PreviewBg

/**
 * Layar Knob.
 *
 * Dua tingkat: daftar kategori, lalu daftar knob di dalam kategori. Hanya
 * knob yang ada di capability `knobs` yang ditampilkan — knob yang tidak
 * tersedia TIDAK pernah muncul dengan nilai karangan (aturan A9).
 *
 * Layar ini tidak memanggil root; semua nilai berasal dari [UiState].
 */
@Composable
fun KnobScreen(
    state: UiState,
    onSetOverride: (String, String) -> Unit,
    modifier: Modifier = Modifier,
    onApply: () -> Unit = {},
) {
    var openCategory by remember { mutableStateOf<KnobCategory?>(null) }

    val cap = state.capability
    val categories = remember(cap, state.dirty) {
        if (cap == null) emptyList() else KnobCategoryBuilder.build(cap, state.dirty)
    }

    Column(
        modifier = modifier.fillMaxWidth(),
        verticalArrangement = Arrangement.spacedBy(Gap),
    ) {
        if (cap == null) {
            HCard {
                Column(verticalArrangement = Arrangement.spacedBy(Gap)) {
                    TextLine("Belum ada data knob", BodyLarge)
                    TextLine(
                        "Kemampuan perangkat belum dimuat. Periksa dari Beranda.",
                        Caption,
                    )
                }
            }
            return@Column
        }

        val dirty = state.dirtyCount
        HButton(
            label = if (dirty == 0) "Terapkan (0)" else "Terapkan ($dirty)",
            onClick = onApply,
            primary = true,
        )

        val open = openCategory
        if (open == null) {
            categories.forEach { cat ->
                CategoryRow(cat) { openCategory = cat }
            }
            GatedCard(state)
        } else {
            HButton(label = "Kembali", onClick = { openCategory = null }, primary = false)
            val catUi = categories.firstOrNull { it.category == open }
            if (catUi == null) {
                HCard {
                    TextLine("Kategori tidak tersedia lagi", BodyLarge)
                }
            } else {
                catUi.rows.forEach { row ->
                    KnobControl(row) { value -> onSetOverride(row.key, value) }
                }
            }
        }
    }
}

@Composable
private fun CategoryRow(cat: KnobCategoryUi, onClick: () -> Unit) {
    HCard {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            TextLine(cat.category.title, BodyLarge)
            Row(verticalAlignment = Alignment.CenterVertically) {
                if (cat.dirtyCount > 0) {
                    HBadge("DIUBAH ${cat.dirtyCount}", HStatus.DIUBAH)
                }
                HBadge("${cat.rows.size}", HStatus.DEFAULT)
            }
        }
    }
}

@Composable
private fun KnobControl(row: KnobRow, onChange: (String) -> Unit) {
    HCard {
        Column(verticalArrangement = Arrangement.spacedBy(Gap)) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                TextLine(row.label, BodyLarge)
                if (row.dirty) HBadge("DIUBAH", HStatus.DIUBAH)
            }
            when (row.kind) {
                KnobKind.CHOICE -> {
                    // Nilai saat ini = yang diminta user; daftar pilihan
                    // berasal dari `knobs`. APK tidak memetakan governor.
                    HSelectRow(
                        label = "Nilai",
                        value = row.current.ifBlank { "tidak terbaca" },
                        onClick = null,
                        selected = row.dirty,
                    )
                }
                KnobKind.SLIDER -> {
                    val lo = (row.range?.first ?: 0).toFloat()
                    val hi = (row.range?.last ?: 100).toFloat()
                    HSlider(
                        label = "Nilai",
                        value = row.current.toFloatOrNull() ?: lo,
                        onValueChange = { v ->
                            onChange(KnobCategoryBuilder.requestedValueFor(row, v))
                        },
                        valueRange = lo..hi,
                    )
                    TextLine("Batas ${row.range?.first} - ${row.range?.last} (dari modul)", Caption)
                }
                KnobKind.TOGGLE -> {
                    HSelectRow(
                        label = "Nilai",
                        value = row.current.ifBlank { "0" },
                        onClick = {
                            onChange(if (row.current == "1") "0" else "1")
                        },
                        selected = row.dirty,
                    )
                }
                KnobKind.LOCKED -> {
                    HSelectRow(label = "Nilai", value = "Tidak bisa diubah", onClick = null)
                    TextLine("Modul tidak melaporkan rentang untuk knob ini.", Caption)
                }
            }
            if (row.base.isNotBlank()) {
                TextLine("Awal: ${row.base}", Caption)
            }
        }
    }
}

/** Baris fitur bergate: terkunci, tanpa kontrol. */
@Composable
private fun GatedCard(state: UiState) {
    val feats = state.capability?.gated.orEmpty()
    if (feats.isEmpty()) return
    HCard {
        Column(verticalArrangement = Arrangement.spacedBy(Gap)) {
            TextLine(KnobCategory.GATED.title, BodyLarge)
            feats.forEach { f ->
                HSelectRow(label = f.label, value = "Terkunci", onClick = null)
            }
        }
    }
}

@Composable
private fun TextLine(text: String, style: androidx.compose.ui.text.TextStyle) {
    androidx.compose.material3.Text(text = text, style = style)
}

@Preview(showBackground = true, backgroundColor = PreviewBg)
@Composable
private fun KnobScreenEmptyPreview() {
    HsinTheme {
        KnobScreen(state = UiState(), onSetOverride = { _, _ -> })
    }
}
