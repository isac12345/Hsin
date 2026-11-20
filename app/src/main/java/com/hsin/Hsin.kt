package com.hsin

import org.json.JSONArray
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Locale

/** Jembatan ke modul: semua perintah lewat common/hsinctl.sh (root). */
object Hsin {
    const val STATE = "/data/adb/hsin"

    private suspend fun ctl(args: String, timeout: Long = 20_000L): Root.Res {
        val m = Root.modPath()
        if (m.isEmpty()) return Root.Res(-3, "modul tidak ditemukan")
        return Root.exec("sh $m/common/hsinctl.sh $args 2>/dev/null", timeout)
    }

    fun kv(s: String): Map<String, String> {
        val m = LinkedHashMap<String, String>()
        for (line in s.lines()) {
            val i = line.indexOf('=')
            if (i <= 0) continue
            m[line.substring(0, i).trim()] = line.substring(i + 1).trim()
        }
        return m
    }

    private fun jsonArr(s: String): JSONArray? {
        val a = s.indexOf('[')
        val b = s.lastIndexOf(']')
        if (a < 0 || b < a) return null
        return try { JSONArray(s.substring(a, b + 1)) } catch (_: Exception) { null }
    }

    private fun b(m: Map<String, String>, k: String) = m[k] == "1"

    suspend fun status(timeout: Long = 20_000L): Status? {
        val r = ctl("status", timeout)
        val m = kv(r.out)
        if (m.isEmpty() || !m.containsKey("profile")) return null
        return Status(
            profile = m["profile"] ?: "none",
            active = m["active"] ?: "none",
            monitor = b(m, "monitor"),
            watchdog = b(m, "watchdog"),
            auto = b(m, "auto"),
            fasrsNode = b(m, "fasrs_node"),
            fasrsMode = m["fasrs_mode"].orEmpty(),
            cpuOwner = m["cpu_owner"].orEmpty(),
            tempC = (m["temp_mc"]?.toLongOrNull() ?: 0L) / 1000f,
            socTempC = (m["soc_temp_mc"]?.toLongOrNull() ?: 0L) / 1000f,
            batt = m["batt"]?.toIntOrNull() ?: -1,
            battStatus = m["batt_status"].orEmpty(),
            gamePkg = m["game_pkg"].orEmpty(),
            gameSecs = m["game_secs"]?.toLongOrNull() ?: 0L,
            hudPkg = m["hud_pkg"].orEmpty(),
            rec = b(m, "rec"),
            ovd = b(m, "ovd"),
            ovdLevel = m["ovd_level"].orEmpty(),
            ovdLast = m["ovd_last"].orEmpty(),
            thermalWarmC = m["thermal_warm_c"]?.toIntOrNull() ?: 75,
            ver = m["ver"]?.toIntOrNull() ?: 0,
            adaptNow = m["adapt_now"].orEmpty(),
            saranPkg = m["saran_pkg"].orEmpty(),
            saranNilai = m["saran_nilai"].orEmpty(),
            saranWhy = m["saran_why"].orEmpty(),
            adaptOwn = b(m, "adapt_own"),
            adaptOwnPkg = m["adapt_own_pkg"].orEmpty(),
            adaptCpu = m["adapt_cpu"].orEmpty(),
            adaptDs = m["adapt_ds"].orEmpty(),
            adaptFps = m["adapt_fps"].orEmpty(),
            adaptTier = m["adapt_tier"].orEmpty(),
            fpsRescue = m["fps_rescue"].orEmpty(),
            fpsdState = m["fpsd_state"].orEmpty(),
            adaptOwnSwitch = m["adapt_own_switch"] != "off",
            engineOff = m["engine_mode"] == "off",
            paused = m["paused"] == "1",
        )
    }

    /** Tandai saran sudah ditawarkan; apply=true memasang downscale dulu (aktif setelah game dibuka ulang). */
    suspend fun saranDone(pkg: String, nilai: String, apply: Boolean) {
        if (apply) ctl("gamefx set $pkg downscale $nilai")
        ctl("saran done $pkg")
    }

    suspend fun setProfile(p: String): Root.Res = ctl("profile $p", 45_000L)

    suspend fun conf(): Map<String, String> = kv(ctl("conf all").out)

    suspend fun setAdaptOwn(on: Boolean): Boolean = ctl("adapt own ${if (on) "on" else "off"}").out.startsWith("OK")

    suspend fun setPaused(on: Boolean): Boolean = ctl("pause ${if (on) "on" else "off"}").out.startsWith("OK")

    suspend fun setEngineOff(off: Boolean): Boolean = ctl("engine mode ${if (off) "off" else "freeze"}").out.startsWith("OK")

    suspend fun setConf(k: String, v: String): Boolean = ctl("conf set $k $v").out.startsWith("OK")

    suspend fun flags(): Map<String, Boolean> = kv(ctl("flags").out).mapValues { it.value == "1" }

    suspend fun setFlag(name: String, on: Boolean): Boolean =
        ctl("flag ${if (on) "set" else "clear"} $name").out.startsWith("OK")

    suspend fun setThermalWarm(c: Int): Boolean = ctl("thermal set $c").out.startsWith("OK")

    suspend fun games(): List<GameEntry> {
        val arr = jsonArr(ctl("games").out) ?: return emptyList()
        val out = ArrayList<GameEntry>()
        for (i in 0 until arr.length()) {
            val o: JSONObject = arr.optJSONObject(i) ?: continue
            out.add(GameEntry(o.optString("package"), o.optString("profile", "balanced"), o.optString("fps")))
        }
        return out
    }

    private val PKG_RE = Regex("^[A-Za-z0-9._]+\\.[A-Za-z0-9._]+$")
    private val FPS_RE = Regex("^[0-9]{1,4}(,[0-9]{1,4})*$")

    suspend fun addGame(pkg: String, fps: String, profile: String): Root.Res {
        if (!PKG_RE.matches(pkg)) return Root.Res(1, "ERROR: package tidak valid")
        val f = fps.replace(" ", "").ifEmpty { "30,60" }
        if (!FPS_RE.matches(f)) return Root.Res(1, "ERROR: FPS tidak valid (contoh 30,60)")
        if (profile !in PROFILE_KEYS && profile != "adapt") return Root.Res(1, "ERROR: profil tidak valid")
        return ctl("game add $pkg $f $profile", 60_000L)
    }

    // ---- ekstra game (gamehooks.sh), HUD, rekam layar ----
    private val RENDER_KEYS = setOf("default", "skiagl", "skiavk")

    suspend fun gameRender(pkg: String): String {
        if (!PKG_RE.matches(pkg)) return "default"
        val v = ctl("gamerender get $pkg").out.trim()
        return if (v in RENDER_KEYS) v else "default"
    }

    suspend fun setGameRender(pkg: String, v: String): Root.Res {
        if (!PKG_RE.matches(pkg)) return Root.Res(1, "ERROR: package tidak valid")
        if (v !in RENDER_KEYS) return Root.Res(1, "ERROR: backend tidak valid")
        return ctl("gamerender set $pkg $v")
    }

    /** Opsi khusus game (PRIO/DND = on|off, LITE = 1). Kunci yang tidak ada = ikut pengaturan global. */
    suspend fun gameOpts(pkg: String): Map<String, String> {
        if (!PKG_RE.matches(pkg)) return emptyMap()
        val m = HashMap<String, String>()
        for (l in ctl("gameopt list $pkg").out.lines()) {
            val i = l.indexOf('=')
            if (i > 0) m[l.substring(0, i).trim()] = l.substring(i + 1).trim()
        }
        return m
    }

    suspend fun setGameOpt(pkg: String, key: String, v: String): Root.Res {
        if (!PKG_RE.matches(pkg)) return Root.Res(1, "ERROR: package tidak valid")
        if (key !in setOf("PRIO", "DND", "LITE", "HZ", "OVD")) return Root.Res(1, "ERROR: opsi tidak dikenal")
        if (v !in setOf("on", "off", "1", "default") && v.toIntOrNull() !in 30..240) return Root.Res(1, "ERROR: nilai tidak valid")
        // modul lama menolak OVD=off; "default" artinya sama (ikut global)
        val vv = if (key == "OVD" && v == "off") "default" else v
        return ctl("gameopt set $pkg $key $vv")
    }

    /** Overdrive: hanya untuk game terdaftar yang sedang aktif. Pesan gagal ada di Res.out. */
    /** Ekspor log diagnosa satu berkas; mengembalikan path berkas atau null bila gagal. */
    suspend fun exportLog(): String? {
        val r = ctl("logexport", 30_000L)
        return r.out.lines().firstOrNull { it.startsWith("OK: ") }?.removePrefix("OK: ")?.trim()
    }

    // ---------------- memfx / alat v55 ----------------
    suspend fun memStatus(): Map<String, String> = kv(ctl("mem status").out)

    suspend fun mglruStatus(): Map<String, String> = kv(ctl("mglru status").out)

    suspend fun setMglru(on: Boolean): Map<String, String> = kv(ctl("mglru ${if (on) "on" else "off"}", 30_000L).out)

    suspend fun setMemclean(on: Boolean): Boolean = ctl("memclean ${if (on) "on" else "off"}").code == 0

    /** Cek fitur langsung: daftar (status, nama, keterangan) dengan status OK/GAGAL/LEWAT. */
    suspend fun livecheck(): Pair<List<Triple<String, String, String>>, String> {
        val r = ctl("livecheck", 90_000L)
        val rows = r.out.lines().mapNotNull { l ->
            val p = l.split('|', limit = 3)
            if (p.size == 3 && p[0] in listOf("OK", "GAGAL", "LEWAT")) Triple(p[0], p[1], p[2]) else null
        }
        return Pair(rows, "kode=${r.code} ${r.out.take(300)}")
    }

    suspend fun trim(): String = ctl("trim force", 180_000L).out.lines().lastOrNull { it.isNotBlank() }.orEmpty()

    suspend fun gameScan(): List<String> =
        ctl("game scan", 90_000L).out.lines().map { it.trim() }.filter { PKG_RE.matches(it) }

    suspend fun gameScanAdd(): String =
        ctl("game scan add", 300_000L).out.lines().lastOrNull { it.isNotBlank() }.orEmpty()

    suspend fun bugreport(): String? {
        val r = ctl("bugreport", 120_000L)
        return r.out.lines().firstOrNull { it.startsWith("OK: ") }?.removePrefix("OK: ")?.trim()
    }

    /** Opsi game v55: gamemode, downscale, fps, preload (nilai "off" = tidak diatur). */
    suspend fun gamefx(pkg: String): Map<String, String> {
        if (!PKG_RE.matches(pkg)) return emptyMap()
        return kv(ctl("gamefx get $pkg").out)
    }

    /** Preset game: "preset" (manual|grafik|stabil|performa) + nilai dipelajari "downscale,fps,mode" per preset (kosong = belum ada data). */
    suspend fun gamePreset(pkg: String): Map<String, String> {
        if (!PKG_RE.matches(pkg)) return emptyMap()
        return kv(ctl("gamepreset get $pkg").out)
    }

    /** Pengaturan otomatis per game: auto (on|off), downscale, fps, gamemode, data_n. */
    suspend fun gameAuto(pkg: String): Map<String, String> {
        if (!PKG_RE.matches(pkg)) return emptyMap()
        return kv(ctl("gameauto get $pkg").out)
    }

    suspend fun setGameAutoMode(pkg: String, on: Boolean): Root.Res =
        if (!PKG_RE.matches(pkg)) Root.Res(1, "ERROR: package tidak valid") else ctl("gameauto mode $pkg ${if (on) "on" else "off"}")

    suspend fun resetGameAuto(pkg: String): Root.Res =
        if (!PKG_RE.matches(pkg)) Root.Res(1, "ERROR: package tidak valid") else ctl("gameauto reset $pkg")

    suspend fun learnGamePreset(pkg: String, pct: Int): Root.Res {
        if (!PKG_RE.matches(pkg) || pct !in 10..100) return Root.Res(1, "ERROR: resolusi acuan tidak valid")
        return ctl("gamepreset learn $pkg $pct")
    }

    suspend fun setGamePreset(pkg: String, name: String): Root.Res {
        if (!PKG_RE.matches(pkg) || name !in setOf("manual", "grafik", "stabil", "performa")) return Root.Res(1, "ERROR: preset tidak valid")
        return ctl("gamepreset set $pkg $name")
    }

    suspend fun setGamefx(pkg: String, key: String, v: String): Root.Res {
        if (!PKG_RE.matches(pkg)) return Root.Res(1, "ERROR: package tidak valid")
        if (key !in setOf("gamemode", "downscale", "fps", "preload")) return Root.Res(1, "ERROR: opsi tidak dikenal")
        if (!Regex("^[a-z0-9.]+$").matches(v)) return Root.Res(1, "ERROR: nilai tidak valid")
        return ctl("gamefx set $pkg $key $v")
    }

    /** Cek nyata: apakah sistem benar-benar menyimpan skala resolusi untuk game ini. Teks kosong = tidak perlu ditampilkan. */
    suspend fun downscaleStatus(pkg: String, want: String): String {
        if (!PKG_RE.matches(pkg)) return ""
        val w = want.toDoubleOrNull()
        if (w == null || w >= 0.995) return ""
        val out = Root.exec("cmd game list-configs $pkg 2>&1 | head -n 12", 8_000L).out
        if (out.isBlank()) return "Belum bisa dicek di ROM ini. Cek setelah game dibuka."
        val m = Regex("(?i)downscale\\D{0,12}([0-9]*\\.?[0-9]+)").findAll(out).map { it.groupValues[1].toDoubleOrNull() }.filterNotNull().toList()
        val pct = Math.round(w * 100)
        return when {
            m.any { Math.abs(it - w) < 0.02 } -> "Terbaca sistem: $pct% (aktif saat game dibuka)"
            m.isNotEmpty() -> "Sistem masih membaca ${Math.round(m.first() * 100)}%, bukan $pct%. Buka game lewat HSIN agar dipasang."
            else -> "Disimpan $pct%, tapi ROM tidak menampilkannya. Kalau tampilan game tidak berubah, ROM ini menolak."
        }
    }

    suspend fun fpsDiag(pkg: String): String {
        if (!PKG_RE.matches(pkg)) return "package tidak valid"
        return ctl("hud diag $pkg", 25_000L).out.trim()
    }

    suspend fun chargeStatus(): Map<String, String> = kv(ctl("charge status").out)
    suspend fun chargeSet(n: Int): String = ctl("charge set $n", 20_000L).out.lines().lastOrNull { it.isNotBlank() }.orEmpty()
    suspend fun freezeList(): List<String> = ctl("freeze list").out.lines().map { it.trim() }.filter { it.isNotEmpty() }
    suspend fun freezeOn(pkg: String): String = ctl("freeze on $pkg", 25_000L).out.lines().lastOrNull { it.isNotBlank() }.orEmpty()
    suspend fun freezeOff(pkg: String): String = ctl("freeze off $pkg", 25_000L).out.lines().lastOrNull { it.isNotBlank() }.orEmpty()
    suspend fun freezeAllOff(): String = ctl("freeze alloff", 40_000L).out.lines().lastOrNull { it.isNotBlank() }.orEmpty()

    suspend fun restoreAll(): String = ctl("restore", 40_000L).out.trim()

    suspend fun ovdStart(): Root.Res = ctl("ovd start", 20_000L)

    /** Satu panggilan `hsinctl diagnose`; keluaran diparse di Diagnose.kt. */
    /** `hsinctl adapt list|get|reset`: dipanggil hanya saat halaman dibuka atau tombol ditekan, tanpa polling. */
    suspend fun adaptList(): Root.Res = ctl("adapt list", 15_000L)
    suspend fun adaptGet(pkg: String): Root.Res = if (pkg.all { it.isLetterOrDigit() || it == '.' || it == '_' }) ctl("adapt get $pkg", 10_000L) else Root.Res(1, "")
    suspend fun adaptReset(): Root.Res = ctl("adapt reset", 15_000L)

    suspend fun diagnose(): Root.Res = ctl("diagnose", 25_000L)

    /** `hsinctl framepacing status`: framepacing=, framepredict=, tersimpan=. Kosong bila modul lama. */
    suspend fun framepacing(): Map<String, String> = kv(ctl("framepacing status").out)

    suspend fun setFramepacing(on: Boolean): Root.Res = ctl("framepacing ${if (on) "on" else "off"}", 20_000L)

    /** Jalankan ulang monitor modul lewat watchdog.sh (latar belakang; skrip itu berupa loop). */
    suspend fun restartMonitor(): Root.Res {
        val m = Root.modPath()
        if (m.isEmpty()) return Root.Res(-3, "modul tidak ditemukan")
        return Root.exec("nohup sh $m/common/watchdog.sh >/dev/null 2>&1 & echo started", 10_000L)
    }

    /** Isi $STATE/.fps_rescue (satu baris epoch|paket|aksi|penyebab), kosong bila tidak ada. */
    suspend fun fpsRescue(): String =
        Root.exec("cat $STATE/.fps_rescue 2>/dev/null", 6_000L).out.lines().firstOrNull { it.isNotBlank() }.orEmpty().trim()

    suspend fun ovdStop(): Root.Res = ctl("ovd stop", 20_000L)

    suspend fun launchGame(pkg: String): Root.Res {
        if (!PKG_RE.matches(pkg)) return Root.Res(1, "ERROR: package tidak valid")
        return ctl("game launch $pkg", 20_000L)
    }

    suspend fun refreshList(): List<Int> =
        ctl("refresh list").out.lines().mapNotNull { it.trim().toIntOrNull() }.filter { it in 30..240 }

    suspend fun refreshGet(): String {
        val v = ctl("refresh get").out.trim()
        return if (v == "off" || v.toIntOrNull() != null) v else "off"
    }

    suspend fun setRefresh(v: String): Root.Res {
        if (v != "off" && v.toIntOrNull() == null) return Root.Res(1, "ERROR: nilai tidak valid")
        return ctl("refresh set $v")
    }

    // ---- tweak global (display / performa / alat), bukan per game ----
    private val TW_KEYS = setOf("display_refresh", "display_night", "display_font_scale", "perf_turbo",
        "perf_trip", "perf_cpuidle", "tools_dac", "tools_bypass", "tools_led")
    private val TW_VAL = Regex("^[A-Za-z0-9._:-]+$")

    /** Nilai sekarang + HAS_* (kemampuan HP). */
    suspend fun tweakList(): Map<String, String> = kv(ctl("tweak list", 25_000L).out)

    /** Override yang dipilih user (kunci tanpa override = otomatis ikut mode). */
    suspend fun tweakOver(): Map<String, String> = kv(ctl("tweak over").out)

    suspend fun tweakSet(key: String, v: String): Root.Res {
        if (key !in TW_KEYS || !TW_VAL.matches(v)) return Root.Res(1, "ERROR: nilai tidak valid")
        return ctl("tweak set $key $v", 25_000L)
    }

    suspend fun tweakReset(): Root.Res = ctl("tweak reset", 25_000L)

    suspend fun tweakUnset(key: String): Root.Res {
        if (key !in TW_KEYS) return Root.Res(1, "ERROR: opsi tidak dikenal")
        return ctl("tweak unset $key", 25_000L)
    }

    /** Satu nilai FPS untuk game: batas FPS + refresh layar (10..240 atau off). */
    suspend fun setGameFps(pkg: String, v: String): Root.Res {
        if (!PKG_RE.matches(pkg)) return Root.Res(1, "ERROR: package tidak valid")
        if (v != "off" && v.toIntOrNull() !in 10..240) return Root.Res(1, "ERROR: fps 10-240 atau off")
        return ctl("gamefps set $pkg $v")
    }

    suspend fun recStart(): Root.Res = ctl("rec start", 15_000L)
    suspend fun recStop(): Root.Res = ctl("rec stop", 30_000L)

    suspend fun removeGame(pkg: String): Root.Res {
        if (!PKG_RE.matches(pkg)) return Root.Res(1, "ERROR: package tidak valid")
        return ctl("game remove $pkg", 60_000L)
    }

    suspend fun sessions(): List<SessionEntry> {
        val out = ArrayList<SessionEntry>()
        for (line in ctl("sessions 30").out.lines()) {
            val p = line.trim().split('|')
            if (p.size < 7) continue
            out.add(
                SessionEntry(
                    epoch = p[0].toLongOrNull() ?: continue,
                    pkg = p[1],
                    durSecs = p[2].toLongOrNull() ?: 0L,
                    peakC = (p[3].toLongOrNull() ?: 0L) / 1000f,
                    battStart = p[4].toIntOrNull() ?: 0,
                    battEnd = p[5].toIntOrNull() ?: 0,
                    profile = p[6],
                )
            )
        }
        return out.reversed()
    }

    suspend fun health(): Health? {
        val r = ctl("health")
        val m = kv(r.out)
        if (m.isEmpty()) return null
        return Health(
            uperf = b(m, "uperf"), fasrs = b(m, "fasrs"), monitor = b(m, "monitor"),
            watchdog = b(m, "watchdog"), auto = b(m, "auto"), bootGuard = b(m, "bootguard"),
            bootFail = m["boot_fail"]?.toIntOrNull() ?: 0,
        )
    }

    suspend fun device(redetect: Boolean = false): Map<String, String> {
        val r = ctl(if (redetect) "redetect" else "device", 60_000L)
        val m = LinkedHashMap<String, String>()
        for (line in r.out.lines()) {
            val i = line.indexOf('=')
            if (i <= 0 || line.startsWith("#")) continue
            m[line.substring(0, i).trim()] = line.substring(i + 1).trim().trim('"')
        }
        return m
    }

    suspend fun render(): RenderInfo? {
        val r = ctl("render get")
        val a = r.out.indexOf('{')
        val z = r.out.lastIndexOf('}')
        if (a < 0 || z < a) return null
        return try {
            val o = JSONObject(r.out.substring(a, z + 1))
            val av = o.optJSONArray("available")
            val list = ArrayList<String>()
            if (av != null) for (i in 0 until av.length()) list.add(av.optString(i))
            RenderInfo(o.optString("current", "default"), list.ifEmpty { listOf("default") }, o.optInt("api"))
        } catch (_: Exception) { null }
    }

    suspend fun setRender(v: String): Root.Res = ctl("render set $v", 30_000L)

    suspend fun autoStart(): Root.Res = ctl("autoctl start")

    suspend fun logRaw(n: Int): String = ctl("log $n").out

    private val LOG_FULL = Regex("^\\[(\\d{4}-\\d{2}-\\d{2} \\d{2}:\\d{2}:\\d{2})\\] \\[([^\\]]+)\\] (?:\\[([^\\]]+)\\] )?(.*)$")
    private val LOG_SHORT = Regex("^\\[([^\\]]+)\\] (?:\\[([^\\]]+)\\] )?(.*)$")

    fun parseLog(raw: String): List<LogLine> {
        val fmt = SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.US)
        val out = ArrayList<LogLine>()
        for (line in raw.lines()) {
            if (line.isBlank()) continue
            val m = LOG_FULL.matchEntire(line)
            if (m != null) {
                val t = try { fmt.parse(m.groupValues[1])?.time } catch (_: Exception) { null }
                out.add(LogLine(t, m.groupValues[2], m.groupValues[3], m.groupValues[4], line))
                continue
            }
            val s = LOG_SHORT.matchEntire(line)
            if (s != null) out.add(LogLine(null, s.groupValues[1], s.groupValues[2], s.groupValues[3], line))
            else out.add(LogLine(null, "LOG", "", line, line))
        }
        return out
    }

    fun logMatches(l: LogLine, f: String): Boolean = when (f) {
        "ERROR" -> l.status.uppercase() in setOf("ERROR", "FAILED", "WARN", "WARNING") || l.msg.contains("ERROR")
        "CPU" -> l.cat.uppercase().startsWith("CPU")
        "GAME" -> l.cat.uppercase().let { it.startsWith("GAME") || it == "SESSION" }
        "INPUT" -> l.cat.uppercase().startsWith("INPUT")
        else -> true
    }

    suspend fun battery(): BatteryInfo {
        val r = Root.exec(
            "b=/sys/class/power_supply/battery; for k in capacity status health temp voltage_now current_now " +
                "cycle_count charge_full charge_full_design technology; do echo \"\$k=\$(cat \$b/\$k 2>/dev/null)\"; done",
            10_000L
        )
        val m = kv(r.out)
        val temp = (m["temp"]?.toIntOrNull() ?: 0) / 10f
        val vRaw = m["voltage_now"]?.toLongOrNull() ?: 0L
        val iRaw = m["current_now"]?.toLongOrNull() ?: 0L
        val vMv = if (vRaw > 100000) (vRaw / 1000).toInt() else vRaw.toInt()
        val iMa = if (kotlin.math.abs(iRaw) > 20000) (iRaw / 1000).toInt() else iRaw.toInt()
        val full = m["charge_full"]?.toLongOrNull() ?: 0L
        val design = m["charge_full_design"]?.toLongOrNull() ?: 0L
        val hp = if (full > 0 && design > 0) ((full * 100) / design).toInt().coerceIn(0, 120) else -1
        return BatteryInfo(
            level = m["capacity"]?.toIntOrNull() ?: -1,
            status = m["status"].orEmpty(),
            health = m["health"].orEmpty(),
            tempC = temp,
            voltageMv = vMv,
            currentMa = iMa,
            cycles = m["cycle_count"]?.toIntOrNull() ?: -1,
            healthPct = hp,
            tech = m["technology"].orEmpty(),
        )
    }

    // ---------- resolusi ----------
    data class Res3(val w: Int, val h: Int, val d: Int)
    data class ResInfo(val nat: Res3, val act: Res3, val hasOverride: Boolean)

    suspend fun resolution(): ResInfo? {
        val r = Root.exec("wm size; wm density", 10_000L)
        var pw = 0; var ph = 0; var ow = 0; var oh = 0; var pd = 0; var od = 0
        val sizeRe = Regex("(\\d+)x(\\d+)")
        for (line in r.out.lines()) {
            val l = line.lowercase()
            if (l.startsWith("physical size")) sizeRe.find(l)?.let { pw = it.groupValues[1].toInt(); ph = it.groupValues[2].toInt() }
            else if (l.startsWith("override size")) sizeRe.find(l)?.let { ow = it.groupValues[1].toInt(); oh = it.groupValues[2].toInt() }
            else if (l.startsWith("physical density")) pd = l.filter { it.isDigit() }.toIntOrNull() ?: 0
            else if (l.startsWith("override density")) od = l.filter { it.isDigit() }.toIntOrNull() ?: 0
        }
        if (pw == 0 || ph == 0) return null
        val nat = Res3(pw, ph, pd)
        val act = Res3(if (ow > 0) ow else pw, if (oh > 0) oh else ph, if (od > 0) od else pd)
        return ResInfo(nat, act, ow > 0 || od > 0)
    }

    private fun even(v: Double): Int { val i = Math.round(v).toInt(); return if (i % 2 == 0) i else i + 1 }

    fun resCommand(nat: Res3, pct: Int): String {
        if (pct >= 100) return "wm size reset; wm density reset"
        val w = even(nat.w * pct / 100.0)
        val h = even(nat.h * pct / 100.0)
        val d = Math.round(nat.d * pct / 100.0).toInt()
        return "wm size ${w}x${h}; wm density $d"
    }

    fun restoreCommand(info: ResInfo): String =
        if (!info.hasOverride) "wm size reset; wm density reset"
        else "wm size ${info.act.w}x${info.act.h}; wm density ${info.act.d}"

    /** Terapkan resolusi dengan pengaman: kalau tidak dikonfirmasi, perangkat sendiri mengembalikannya. */
    suspend fun applyResWithGuard(cmd: String, restore: String, guardSecs: Int) {
        Root.exec("rm -f $STATE/.res_keep; nohup sh -c 'sleep $guardSecs; [ -f $STATE/.res_keep ] || { $restore; }' >/dev/null 2>&1 &", 8_000L)
        Root.exec(cmd, 15_000L)
    }

    suspend fun keepRes() { Root.exec("touch $STATE/.res_keep", 5_000L) }

    suspend fun revertRes(restore: String) {
        Root.exec("touch $STATE/.res_keep; $restore", 15_000L)
    }

    suspend fun resetRes() { Root.exec("touch $STATE/.res_keep; wm size reset; wm density reset", 15_000L) }

    // ---------- dexopt & tutup app ----------
    suspend fun dexopt(pkg: String, mode: String): Boolean {
        val cmd = if (mode == "reset") "cmd package compile --reset $pkg" else "cmd package compile -m $mode -f $pkg"
        val r = Root.exec(cmd, 900_000L)
        return r.out.contains("Success", ignoreCase = true)
    }

    /**
     * Bersihkan RAM ringan: `am kill` hanya mematikan proses latar belakang yang aman dimatikan (bukan force-stop,
     * jadi layanan foreground, alarm, dan notifikasi tidak terpotong). Mengembalikan RAM kosong yang bertambah (MB).
     */
    suspend fun cleanRam(pkgs: List<String>): Int {
        val list = pkgs.filter { PKG_RE.matches(it) }
        if (list.isEmpty()) return 0
        val sb = StringBuilder()
        sb.append("a=\$(sed -n 's/^MemAvailable: *\\([0-9]*\\).*/\\1/p' /proc/meminfo); ")
        sb.append("for p in ${list.joinToString(" ")}; do am kill \"\$p\" >/dev/null 2>&1; done; sleep 1.5; ")
        sb.append("b=\$(sed -n 's/^MemAvailable: *\\([0-9]*\\).*/\\1/p' /proc/meminfo); ")
        sb.append("echo \"freed_kb=\$((b - a))\"")
        val r = Root.exec(sb.toString(), 60_000L)
        val kb = r.out.lines().firstOrNull { it.startsWith("freed_kb=") }?.removePrefix("freed_kb=")?.trim()?.toLongOrNull() ?: 0L
        return (kb / 1024L).toInt().coerceAtLeast(0)
    }

    suspend fun forceStop(pkgs: List<String>): Root.Res {
        val list = pkgs.filter { PKG_RE.matches(it) }
        val sb = StringBuilder()
        if (list.isNotEmpty()) sb.append("for p in ${list.joinToString(" ")}; do am force-stop \"\$p\"; done; ")
        sb.append("am kill-all; echo done")
        return Root.exec(sb.toString(), 120_000L)
    }
}
