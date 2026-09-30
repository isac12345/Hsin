package com.hsin.ui.screens

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.tooling.preview.Preview
import com.hsin.data.state.UiState
import com.hsin.ui.ScreenPhase
import com.hsin.ui.ScreenStates
import com.hsin.ui.components.ContentTitle
import com.hsin.ui.components.EmptyView
import com.hsin.ui.components.ErrorView
import com.hsin.ui.components.HBadge
import com.hsin.ui.components.HButton
import com.hsin.ui.components.HCard
import com.hsin.ui.components.HSelectRow
import com.hsin.ui.components.HSlider
import com.hsin.ui.components.HStatus
import com.hsin.ui.components.LoadingView
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
 * A10: baris hasil per knob dibaca dari [UiState.applyResults] (langsung
 * dari modul, kontrak §3.11): `diminta X → diterapkan Y (alasan)` dengan
 * badge APPLIED/FALLBACK/SKIPPED/UNAVAILABLE/FAILED. Sukses parsial =
 * badge berbeda per knob, bukan satu status global.
 *
 * Layar ini tidak memanggil root; semua nilai berasal dari [UiState].
 */
@Composable
fun KnobScreen(
    state: UiState,
    onSetOverride: (String, String) -> Unit,
    modifier: Modifier = Modifier,
    onApply: () -> Unit = {},
    onRefresh: () -> Unit = {},
) {
    var openCategory by remember { mutableStateOf<KnobCategory?>(null) }

    val cap = state.capability
    val categories = remember(cap, state.dirty) {
        if (cap == null) emptyList() else KnobCategoryBuilder.build(cap, state.dirty)
    }
    val contentCount = categories.size + (cap?.gated?.size ?: 0)

    Column(
        modifier = modifier.fillMaxWidth(),
        verticalArrangement = Arrangement.spacedBy(Gap),
    ) {
        // R2: judul konten besar "Knob" (Beranda/Monitor langsung kartu).
        ContentTitle("Knob")
        // R2: fase eksplisit — tidak ada jalur yang merender blank.
        when (ScreenStates.knob(state, contentCount)) {
            ScreenPhase.LOADING -> LoadingView("Memuat knob dari modul...")
            ScreenPhase.ERROR -> ErrorView(
                message = state.error?.let { com.hsin.ui.friendlyError(it.kind.name, it.detail) }
                    ?: "Terjadi kesalahan.",
                onRetry = onRefresh,
            )
            ScreenPhase.EMPTY -> EmptyView(
                message = if (cap == null) {
                    "Belum ada data knob. Kemampuan perangkat belum dimuat."
                } else {
                    "Tidak ada knob terdeteksi (scan kosong)."
                },
                actionLabel = "Muat ulang",
                onAction = onRefresh,
            )
            ScreenPhase.CONTENT -> KnobContent(
                state = state,
                categories = categories,
                openCategory = openCategory,
                onOpenCategory = { openCategory = it },
                onSetOverride = onSetOverride,
                onApply = onApply,
            )
        }
    }
}

@Composable
private fun KnobContent(
    state: UiState,
    categories: List<com.hsin.ui.knob.KnobCategoryUi>,
    openCategory: KnobCategory?,
    onOpenCategory: (KnobCategory?) -> Unit,
    onSetOverride: (String, String) -> Unit,
    onApply: () -> Unit,
) {
    Column(verticalArrangement = Arrangement.spacedBy(Gap)) {
        val dirty = state.dirtyCount
        HButton(
            label = when {
                state.isApplying -> "Menerapkan..."
                dirty == 0 -> "Terapkan (0)"
                else -> "Terapkan ($dirty)"
            },
            onClick = { if (!state.isApplying && dirty > 0) onApply() },
            primary = true,
        )
        if (state.isApplying) {
            HCard {
                TextLine("Menerapkan knob, UI tetap bisa dipakai...", Caption)
            }
        }

        val open = openCategory
        if (open == null) {
            categories.forEach { cat ->
                CategoryRow(cat) { onOpenCategory(cat.category) }
            }
            GatedCard(state)
        } else {
            HButton(label = "Kembali", onClick = { onOpenCategory(null) }, primary = false)
            val catUi = categories.firstOrNull { it.category == open }
            if (catUi == null) {
                HCard {
                    TextLine("Kategori tidak tersedia lagi", BodyLarge)
                }
            } else {
                catUi.rows.forEach { row ->
                    KnobControl(row, state.applyResults[row.key]) { value -> onSetOverride(row.key, value) }
                }
            }
        }
    }
}

@Composable
private fun CategoryRow(cat: KnobCategoryUi, onClick: () -> Unit) {
    HCard {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .clickable(onClick = onClick),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            // R3: "Nama + N knob + chevron" sesuai mockup.
            Column {
                TextLine(cat.category.title, BodyLarge)
                TextLine("${cat.rows.size} knob", Caption)
            }
            Row(verticalAlignment = Alignment.CenterVertically) {
                if (cat.dirtyCount > 0) {
                    HBadge("DIUBAH ${cat.dirtyCount}", HStatus.DIUBAH)
                }
                TextLine("›", BodyLarge)
            }
        }
    }
}

@Composable
private fun KnobControl(
    row: KnobRow,
    result: com.hsin.data.repository.HsinRepository.KnobResult?,
    onChange: (String) -> Unit,
) {
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
                    // Dropdown pilihan dari `knobs` — nilai dikirim apa adanya.
                    var expanded by remember { mutableStateOf(false) }
                    Box(modifier = Modifier.fillMaxWidth()) {
                        HSelectRow(
                            label = "Nilai",
                            value = row.current.ifBlank { "tidak terbaca" },
                            onClick = { expanded = true },
                            selected = row.dirty,
                        )
                        DropdownMenu(
                            expanded = expanded,
                            onDismissRequest = { expanded = false },
                        ) {
                            row.choices.forEach { c ->
                                DropdownMenuItem(
                                    text = { Text(c) },
                                    onClick = {
                                        expanded = false
                                        if (c != row.current) onChange(c)
                                    },
                                )
                            }
                        }
                    }
                    TextLine("${row.choices.size} pilihan (dari modul)", Caption)
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
            ResultLine(row, result)
        }
    }
}

/**
 * Baris hasil per knob (A10, kontrak §3.11).
 *
 * - Belum diubah + belum ada hasil: `SAAT INI`.
 * - Diubah tapi belum apply: `DIUBAH`.
 * - Sesudah apply: badge kategori modul + `diminta X → diterapkan Y (alasan)`.
 * Nilai diterapkan HANYA dari modul — tidak pernah dikarang dari rc.
 */
@Composable
private fun ResultLine(
    row: KnobRow,
    result: com.hsin.data.repository.HsinRepository.KnobResult?,
) {
    if (result == null) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            TextLine(if (row.dirty) "DIUBAH — belum diterapkan" else "SAAT INI", Caption)
            HBadge(
                if (row.dirty) "DIUBAH" else "SAAT INI",
                if (row.dirty) HStatus.DIUBAH else HStatus.DEFAULT,
            )
        }
        return
    }
    val status = when (result.category) {
        "APPLIED" -> HStatus.APPLIED
        "FALLBACK" -> HStatus.FALLBACK
        "FAILED" -> HStatus.FAILED
        "SKIPPED" -> HStatus.SKIPPED
        "UNAVAILABLE" -> HStatus.UNAVAILABLE
        else -> HStatus.DEFAULT
    }
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        TextLine(
            "diminta ${result.requested} → diterapkan ${result.applied} (${result.reason})",
            Caption,
        )
        HBadge(result.category.ifBlank { "N/A" }, status)
    }
}

/** Baris fitur bergate: terkunci, tanpa kontrol — tampilkan alasan modul. */
@Composable
private fun GatedCard(state: UiState) {
    val feats = state.capability?.gated.orEmpty()
    if (feats.isEmpty()) return
    HCard {
        Column(verticalArrangement = Arrangement.spacedBy(Gap)) {
            TextLine(KnobCategory.GATED.title, BodyLarge)
            feats.forEach { f ->
                HSelectRow(
                    label = f.label,
                    value = if (f.available) "Tersedia" else "Terkunci",
                    onClick = null,
                )
                if (f.why.isNotBlank()) TextLine(f.why, Caption)
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

@Preview(showBackground = true, backgroundColor = PreviewBg)
@Composable
private fun KnobScreenLoadingPreview() {
    HsinTheme {
        KnobScreen(state = UiState(loadingCapability = true), onSetOverride = { _, _ -> })
    }
}

@Preview(showBackground = true, backgroundColor = PreviewBg)
@Composable
private fun KnobScreenErrorPreview() {
    HsinTheme {
        KnobScreen(
            state = UiState(
                error = com.hsin.data.state.UiError(
                    kind = com.hsin.data.state.UiErrorKind.TIMEOUT,
                    detail = "",
                    retryable = true,
                ),
            ),
            onSetOverride = { _, _ -> },
        )
    }
}
