package com.hsin

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.launch

/** Satu baris `hsinctl adapt list`: paket lalu token kunci=nilai. Kolom baru diabaikan, kolom hilang jadi null. */
data class AdaptRow(val pkg: String, val v: Map<String, String>) {
    private fun num(k: String): Int? = v[k]?.trim()?.removeSuffix("%")?.removeSuffix("ms")?.toIntOrNull()
    val beban: Int? get() = num("beban")
    val bebanCas: Int? get() = num("cas")           // "-" atau tidak ada = belum pernah saat mengisi daya
    val sesi: Int? get() = num("sesi")
    val p1Min: Int? get() = num("p1_min")
    val rata: Int? get() = num("rata")
    val jank: Int? get() = num("jank")
    val stallMs: Int? get() = num("stall")
    val terakhir: String get() = v["terakhir"].orEmpty()
}

fun parseAdaptList(text: String): List<AdaptRow> {
    val out = ArrayList<AdaptRow>()
    for (raw in text.lines()) {
        val line = raw.trim()
        if (line.isEmpty()) continue
        val sp = line.indexOf(' ')
        if (sp <= 0) continue
        val pkg = line.substring(0, sp)
        if (!pkg.contains('.') || pkg.contains('=')) continue
        val m = LinkedHashMap<String, String>()
        // nilai "terakhir" memuat spasi (tanggal dan jam): ambil sisa baris
        val rest = line.substring(sp + 1)
        val ti = rest.indexOf("terakhir=")
        val head = if (ti >= 0) rest.substring(0, ti) else rest
        if (ti >= 0) m["terakhir"] = rest.substring(ti + 9).trim()
        for (tok in head.split(' ')) {
            val i = tok.indexOf('=')
            if (i > 0) m[tok.substring(0, i)] = tok.substring(i + 1)
        }
        out.add(AdaptRow(pkg, m))
    }
    return out.sortedByDescending { it.terakhir }
}

@Composable
internal fun AdaptTab(vm: AppViewModel) {
    val ctx = LocalContext.current
    val scope = rememberCoroutineScope()
    var rows by remember { mutableStateOf<List<AdaptRow>?>(null) }
    var reload by remember { mutableIntStateOf(0) }
    var open by remember { mutableStateOf("") }
    var detail by remember { mutableStateOf("") }
    var confirm by remember { mutableStateOf(false) }
    LaunchedEffect(reload, vm.modPath) {
        if (vm.modPath.isEmpty()) return@LaunchedEffect
        rows = parseAdaptList(Hsin.adaptList().out)
    }
    fun label(p: String): String = try { ctx.packageManager.getApplicationLabel(ctx.packageManager.getApplicationInfo(p, 0)).toString() } catch (_: Exception) { p }
    val now = vm.status.adaptNow.split("|")
    Column(Modifier.fillMaxSize().padding(horizontal = 16.dp, vertical = 10.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        SText(tx("ADAPT", "ADAPT"), 12.sp, SP.gold, spacing = 2.sp, modifier = Modifier.rise(0))
        Section(tx("Sekarang", "Now")) {
            if (now.getOrNull(0).orEmpty().isEmpty()) SText(tx("Tidak ada app yang sedang beradaptasi.", "No app is adapting right now."), 13.sp, SP.dim)
            else SText(label(now[0]) + " · " + tx("beban", "load") + " " + now.getOrNull(1).orEmpty() + if (now.getOrNull(2) == "1") " · game" else "", 14.sp, SP.text)
        }
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
            HBtn(tx("Segarkan", "Refresh")) { reload++ }
            HBtn(tx("Salin laporan", "Copy report")) {
                val txt = (rows ?: emptyList()).joinToString("\n") { r -> "${r.pkg} beban=${r.beban ?: "-"} sesi=${r.sesi ?: "-"} fps=${r.rata ?: "-"} 1%low=${r.p1Min ?: "-"} jank=${r.jank ?: "-"}% stall=${r.stallMs ?: "-"}ms terakhir=${r.terakhir}" }
                (ctx.getSystemService(android.content.Context.CLIPBOARD_SERVICE) as android.content.ClipboardManager).setPrimaryClip(android.content.ClipData.newPlainText("adapt", txt))
                android.widget.Toast.makeText(ctx, tx("Laporan disalin", "Report copied"), android.widget.Toast.LENGTH_SHORT).show()
            }
            if (!confirm) HBtn(tx("Hapus semua catatan", "Clear all records"), color = SP.dim) { confirm = true }
            else {
                SText(tx("Hapus semua catatan Adapt?", "Clear all Adapt records?"), 12.sp, SP.text)
                HBtn(tx("Ya, hapus", "Yes, clear"), solid = true) { confirm = false; scope.launch { Hsin.adaptReset(); open = ""; reload++ } }
                HBtn(tx("Batal", "Cancel"), color = SP.dim) { confirm = false }
            }
        }
        val list = rows
        if (list == null) SText(tx("Memuat...", "Loading..."), 13.sp, SP.dim)
        else if (list.isEmpty()) SText(tx("Belum ada data. Buka beberapa app, lalu segarkan.", "No data yet. Open some apps, then refresh."), 13.sp, SP.dim)
        else LazyColumn(Modifier.weight(1f).fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            items(list, key = { it.pkg }) { r ->
                Glass(Modifier.fillMaxWidth().tap {
                    if (open == r.pkg) open = "" else { open = r.pkg; detail = ""; scope.launch { detail = Hsin.adaptGet(r.pkg).out.trim() } }
                }) {
                    Column(Modifier.padding(horizontal = 12.dp, vertical = 8.dp), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            SText(label(r.pkg), 14.sp, SP.text, modifier = Modifier.weight(1f))
                            SText(tx("beban", "load") + " " + (r.beban ?: "-") + (r.bebanCas?.let { " · " + tx("cas", "chg") + " " + it } ?: ""), 12.sp, SP.gold)
                        }
                        SText(
                            "FPS ${r.rata ?: "-"} · 1% low ${r.p1Min ?: "-"} · jank ${r.jank ?: "-"}% · " + tx("jeda", "stall") + " ${r.stallMs ?: "-"} ms · " + tx("sesi", "sessions") + " ${r.sesi ?: "-"}",
                            11.sp, SP.dim
                        )
                        SText(r.terakhir, 10.sp, SP.dim)
                        if (open == r.pkg && detail.isNotEmpty()) SText(detail, 10.sp, SP.dim)
                    }
                }
            }
        }
    }
}
