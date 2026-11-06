package com.hsin

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

fun fmtDur(s: Long): String {
    val h = s / 3600
    val m = (s % 3600) / 60
    val sec = s % 60
    return if (h > 0) "${h}j ${m}m" else if (m > 0) "${m}m ${sec}d" else "${sec}d"
}

fun fmtClock(s: Long): String = "%02d:%02d".format(s / 60, s % 60)

fun renderName(k: String): String = when (k) {
    "default" -> "Default"
    "skiagl" -> "OpenGL (Skia)"
    "skiavk" -> "Vulkan (Skia)"
    else -> k
}

// ---------------------------------------------------------------- AUTO-PROFILE
@Composable
fun AutoScreen(vm: AppViewModel) {
    BackBtn { vm.back() }
    var battOn by remember(vm.conf) { mutableStateOf(vm.confStr("AUTO_BATT_ON", "0") == "1") }
    var pct by remember(vm.conf) { mutableStateOf((vm.confStr("AUTO_BATT_PCT", "20").toIntOrNull() ?: 20).toFloat()) }
    var battProf by remember(vm.conf) { mutableStateOf(vm.confStr("AUTO_BATT_PROFILE", "battery")) }
    var chgOn by remember(vm.conf) { mutableStateOf(vm.confStr("AUTO_CHG_ON", "0") == "1") }
    var chgProf by remember(vm.conf) { mutableStateOf(vm.confStr("AUTO_CHG_PROFILE", "balanced")) }

    HsinCard {
        Label("Baterai rendah")
        ToggleRow("Aktif", null, battOn) { battOn = it }
        SliderRow("Batas baterai", pct, 5f..50f, "${pct.toInt()}%", { pct = it })
        Seg(PROFILE_LABELS, PROFILE_KEYS.indexOf(battProf), { battProf = PROFILE_KEYS[it] })
    }
    HsinCard {
        Label("Lagi charging")
        ToggleRow("Aktif", null, chgOn) { chgOn = it }
        Seg(PROFILE_LABELS, PROFILE_KEYS.indexOf(chgProf), { chgProf = PROFILE_KEYS[it] })
    }
    // profil otomatis per jenis app (dijalankan modul tiap ±10 dtk, tidak mengganggu game)
    val catOn = vm.confStr("CAT_ON", "0") == "1"
    HsinCard {
        Label("Per jenis app")
        ToggleRow("Aktif", "Video, sosmed, musik, dan browser di depan memakai profil pilihanmu; kembali normal saat keluar.", catOn) { vm.setConfKey("CAT_ON", if (it) "1" else "0") }
        if (catOn) {
            val opts = listOf("none") + PROFILE_KEYS
            val optLabels = listOf("OFF") + PROFILE_LABELS
            listOf("VIDEO" to "Video", "SOCIAL" to "Sosmed", "MUSIC" to "Musik", "BROWSER" to "Browser").forEach { (k, name) ->
                val cur = vm.confStr("CAT_$k", "none")
                Label(name, Modifier.padding(top = 6.dp))
                Seg(optLabels, opts.indexOf(cur).coerceAtLeast(0), { vm.setConfKey("CAT_$k", opts[it]) })
            }
        }
    }
    Pill("SIMPAN", { vm.saveAuto(battOn, pct.toInt(), battProf, chgOn, chgProf) }, solid = true)
}

// ---------------------------------------------------------------- THERMAL
@Composable
fun ThermScreen(vm: AppViewModel) {
    BackBtn { vm.back() }
    val st = vm.status
    var warm by remember(st.thermalWarmC) { mutableStateOf(st.thermalWarmC.toFloat()) }
    val w = warm.toInt()
    val perf = st.active == "performance"
    val warmEff = if (perf) w + 10 else w
    val highEff = if (perf) w + 15 else w + 10
    val state = when {
        st.socTempC >= 95 -> "KRITIS"
        st.socTempC >= highEff -> "PANAS"
        st.socTempC >= warmEff -> "HANGAT"
        else -> "AMAN"
    }
    val stateColor = when (state) { "AMAN" -> Mint; "HANGAT" -> Amber; else -> Coral }
    HsinCard {
        Label("Suhu sensor terpanas")
        Row(verticalAlignment = Alignment.Bottom) {
            txt("%.1f°C".format(st.socTempC), 28.sp, weight = FontWeight.Medium)
            Box(Modifier.width(12.dp))
            txt(state, 12.sp, stateColor, spacing = 1.sp, modifier = Modifier.padding(bottom = 4.dp))
        }
        ToggleRow(
            "Turun profil otomatis", null,
            !vm.flag("THERMAL_GUARD_OFF"),
        ) { vm.setFlag("THERMAL_GUARD_OFF", !it) }
        if (vm.flag("THERMAL_GUARD_OFF")) txt("Proteksi mati. Batas kritis 95°C tetap jalan.", 12.sp, Amber)
    }
    HsinCard {
        Label("Batas suhu")
        SliderRow("Hangat mulai dari", warm, 60f..90f, "$w°C", { warm = it }, { vm.setThermalWarm(warm.toInt()) })
        Divider()
        KV("Hangat", "$warmEff°C")
        Divider()
        KV("Panas", "$highEff°C")
        Divider()
        KV("Kritis", "95°C")
        Divider()
        KV("Boost balik", "< ${w - 5}°C")
    }
}

// ---------------------------------------------------------------- STATISTIK
@Composable
fun StatsScreen(vm: AppViewModel) {
    BackBtn { vm.back() }
    val fmt = SimpleDateFormat("dd MMM HH:mm", Locale.getDefault())
    val last = vm.sessions.firstOrNull()
    if (last == null) {
        HsinCard { txt("Belum ada sesi game tercatat. Sesi dicatat setelah game dimainkan minimal 1 menit.", 12.sp, muted()) }
        return
    }
    HsinCard {
        Label("Sesi terakhir · ${vm.label(last.pkg)}")
        KV("Durasi main", fmtDur(last.durSecs))
        Divider()
        KV("Suhu puncak", "%.1f°C".format(last.peakC))
        Divider()
        KV("Baterai", "${last.battStart}% → ${last.battEnd}%")
        Divider()
        val drain = if (last.durSecs >= 300) "%.1f%%/jam".format((last.battStart - last.battEnd) * 3600f / last.durSecs) else "—"
        KV("Drain baterai", drain)
        Divider()
        KV("Profil", profileLabel(last.profile))
    }
    val recent = vm.sessions.take(7).reversed()
    HsinCard {
        Label("Suhu puncak ${recent.size} sesi")
        Row(Modifier.fillMaxWidth().height(90.dp), horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.Bottom) {
            recent.forEachIndexed { i, s ->
                val frac = ((s.peakC - 30f) / 50f).coerceIn(0.06f, 1f)
                Box(
                    Modifier.weight(1f).height((84f * frac).dp).clip(RoundedCornerShape(4.dp))
                        .background(if (i == recent.size - 1) Mint else Color(0xFF3A3D44)),
                )
            }
        }
        Row(Modifier.fillMaxWidth().padding(top = 4.dp), horizontalArrangement = Arrangement.SpaceBetween) {
            txt("lama", 12.sp, muted()); txt("baru", 12.sp, muted())
        }
    }
    HsinCard {
        Label("Riwayat")
        vm.sessions.take(15).forEach { s ->
            KV("${vm.label(s.pkg)} · ${fmt.format(Date(s.epoch * 1000))}", fmtDur(s.durSecs))
        }
    }
}

// ---------------------------------------------------------------- AUTO-DETECT
@Composable
fun DetectScreen(vm: AppViewModel) {
    BackBtn { vm.back() }
    val reg = vm.games.map { it.pkg }.toSet()
    val found = vm.apps.filter { it.isGame && it.pkg !in reg }
    var sel by remember { mutableStateOf<Set<String>?>(null) }
    var prof by remember { mutableStateOf(2) }
    val chosen = (sel ?: found.map { it.pkg }.toSet()).filter { p -> found.any { it.pkg == p } }
    HsinCard {
        Label("Game ditemukan · ${found.size}")
        if (vm.apps.isEmpty()) txt("Membaca daftar app...", 12.sp, muted())
        else if (found.isEmpty()) txt("Tidak ada game baru. Tambah manual lewat tombol + di tab Games.", 12.sp, muted())
        found.forEach { a ->
            val on = a.pkg in chosen
            Row(
                Modifier.fillMaxWidth().clickable { sel = if (on) chosen.toSet() - a.pkg else chosen.toSet() + a.pkg }.padding(top = 10.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Box(
                    Modifier.size(22.dp).clip(RoundedCornerShape(6.dp)).background(if (on) Mint else Color.Transparent),
                    contentAlignment = Alignment.Center,
                ) { if (on) txt("✓", 14.sp, Color(0xFF04342C)) else Box(Modifier.size(22.dp).clip(RoundedCornerShape(6.dp)).background(Color.White.copy(alpha = 0.12f))) }
                Box(Modifier.width(10.dp))
                AppIcon(a.pkg, 36.dp)
                Column(Modifier.weight(1f).padding(start = 10.dp)) {
                    txt(a.label, 13.sp, maxLines = 1)
                    txt(a.pkg, 11.sp, muted(), maxLines = 1)
                }
            }
        }
    }
    if (found.isNotEmpty()) {
        HsinCard {
            Label("Profil awal")
            Seg(PROFILE_LABELS, prof, { prof = it })
            Pill("TAMBAH ${chosen.size} GAME", {
                if (chosen.isNotEmpty()) vm.addGames(chosen.toList(), PROFILE_KEYS[prof]) { vm.back() }
            }, solid = true, enabled = chosen.isNotEmpty())
        }
    }
}

// ---------------------------------------------------------------- TAMBAH GAME
@Composable
fun AddGameScreen(vm: AppViewModel) {
    var q by remember { mutableStateOf("") }
    var pick by remember { mutableStateOf("") }
    var prof by remember { mutableStateOf(2) }
    var fps by remember { mutableStateOf("") }
    val reg = vm.games.map { it.pkg }.toSet()
    val list = vm.apps.filter { it.pkg !in reg && (q.isBlank() || it.label.contains(q, true) || it.pkg.contains(q, true)) }
    HsinCard {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.weight(1f)) { txt("GAMES", 16.sp, weight = FontWeight.Medium, spacing = 3.sp) }
            SmallPill("CLOSE", { vm.back() })
        }
        Pill("DETEKSI GAME OTOMATIS  ›", { vm.go("detect") })
        Field(q, { q = it }, "Cari aplikasi...")
        Box(Modifier.fillMaxWidth().height(300.dp)) {
            if (vm.apps.isEmpty()) txt("Membaca daftar app...", 12.sp, muted(), modifier = Modifier.padding(top = 12.dp))
            LazyColumn(Modifier.fillMaxWidth()) {
                items(list, key = { it.pkg }) { a ->
                    val on = a.pkg == pick
                    Row(
                        Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp))
                            .background(if (on) Color.White.copy(alpha = 0.1f) else Color.Transparent)
                            .clickable { pick = a.pkg }.padding(vertical = 8.dp, horizontal = 4.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        AppIcon(a.pkg, 40.dp)
                        Column(Modifier.weight(1f).padding(start = 12.dp)) {
                            txt(a.label, 14.sp, weight = FontWeight.Medium, maxLines = 1)
                            txt(a.pkg, 12.sp, muted(), maxLines = 1)
                        }
                        if (a.isGame) SmallPill("GAME")
                    }
                }
            }
        }
        txt(if (pick.isEmpty()) "Pilih aplikasi di atas" else "Dipilih: ${vm.label(pick)}", 12.sp, muted(), modifier = Modifier.padding(top = 8.dp))
        Seg(PROFILE_LABELS, prof, { prof = it })
        Field(fps, { fps = it.filter { c -> c.isDigit() || c == ',' } }, "FPS target (opsional, mis. 30,60,90)")
        Pill("ADD", { if (pick.isNotEmpty()) vm.addGame(pick, fps, PROFILE_KEYS[prof]) { vm.back() } }, solid = true, enabled = pick.isNotEmpty())
    }
}
