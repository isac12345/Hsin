package com.hsin

import android.app.Application
import android.content.ClipData
import android.graphics.Bitmap
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.net.Uri
import android.provider.Settings
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.isActive

class AppViewModel(private val app: Application) : AndroidViewModel(app) {
    val prefs = Prefs(app)
    private val pm: PackageManager = app.packageManager

    @Suppress("DEPRECATION")
    val appVer: Int = try { pm.getPackageInfo(app.packageName, 0).versionCode } catch (_: Exception) { 0 }

    // ---------- floating overlay ----------
    var flVer by mutableStateOf(0)
    fun flChanged() { flVer++ }

    // ---------- navigasi ----------
    var route by mutableStateOf("dash")
    var editPkg by mutableStateOf("")
    private val parents = mapOf(
        "auto" to "tools", "therm" to "tools",
        "stats" to "custom", "detect" to "games", "edit" to "games", "addgame" to "games",
        "bgbanner" to "custom", "bubble" to "custom", "theme" to "custom",
        "dexopt" to "tools", "batlab" to "tools", "fulllog" to "tools", "ramkeep" to "tools", "freeze" to "tools", "charge" to "tools", "sessions" to "records", "bench" to "tools", "memfx" to "tools", "perf" to "records", "diagnose" to "tools",
    )
    val tab: String get() = parents[route] ?: route

    fun go(r: String) {
        if (r == "tools" || r == "games" || r == "custom" || r == "records") {
            route = "dash"
            UiState.tab = when (r) { "games" -> 1; "records" -> 2; "tools" -> 3; else -> 4 }
            if (r == "tools") viewModelScope.launch { refreshTools() }
            if (r == "games") viewModelScope.launch { games = Hsin.games(); sessions = Hsin.sessions() }
            return
        }
        route = r
        when (r) {
            "games", "stats" -> viewModelScope.launch { games = Hsin.games(); sessions = Hsin.sessions() }
            "tools" -> viewModelScope.launch { refreshTools() }
            "batlab" -> viewModelScope.launch { battery = Hsin.battery() }
            "fulllog" -> viewModelScope.launch { loadFullLog() }
            "addgame", "detect" -> ensureApps()
            "dexopt", "ramkeep" -> ensureThirdParty()
            "freeze" -> { ensureThirdParty(); viewModelScope.launch { frozen = Hsin.freezeList() } }
            "charge" -> viewModelScope.launch { chargeInfo = Hsin.chargeStatus() }
            "memfx" -> viewModelScope.launch { conf = Hsin.conf(); loadMem() }
            "perf" -> loadFpsFiles()
            "dash", "therm" -> viewModelScope.launch { flags = Hsin.flags() }
            "auto" -> viewModelScope.launch { conf = Hsin.conf() }
            "diagnose" -> { diag = null; runDiagnose() }
        }
    }

    fun back(): Boolean {
        val p = parents[route] ?: return false
        go(p)
        return true
    }

    // ---------- state modul ----------
    var rootOk by mutableStateOf(false)
    var modPath by mutableStateOf("")
    var loaded by mutableStateOf(false)
    var status by mutableStateOf(Status())
    var statusOk by mutableStateOf(false)
    /** True bila pembacaan status terakhir gagal: nilai di [status] bisa basi. */
    var statusStale by mutableStateOf(false)
    var statusLastOkMs by mutableLongStateOf(0L)
    var conf by mutableStateOf<Map<String, String>>(emptyMap())
    var flags by mutableStateOf<Map<String, Boolean>>(emptyMap())
    var games by mutableStateOf<List<GameEntry>>(emptyList())
    var sessions by mutableStateOf<List<SessionEntry>>(emptyList())
    var health by mutableStateOf(Health())
    var device by mutableStateOf<Map<String, String>>(emptyMap())
    var render by mutableStateOf(RenderInfo())
    var renderChoice by mutableStateOf("default")
    var logs by mutableStateOf<List<LogLine>>(emptyList())
    var logFilter by mutableStateOf("ALL")
    var battery by mutableStateOf(BatteryInfo())
    var msg by mutableStateOf<String?>(null)
    var dialog by mutableStateOf<Dlg?>(null)
    var busy by mutableStateOf<String?>(null)
    var askOverlay by mutableStateOf(false)

    // ---------- tampilan ----------
    var cardAlpha by mutableStateOf(prefs.cardAlpha)
    var fit by mutableStateOf(prefs.fit)
    var accent by mutableStateOf(prefs.accent)
    var blur by mutableStateOf(prefs.blur)
    var contrast by mutableStateOf(prefs.contrast)
    var saver by mutableStateOf(prefs.saver)
    var bgVer by mutableStateOf(prefs.bgVer)
    var bannerVer by mutableStateOf(prefs.bannerVer)

    // Gambar custom di-decode SEKALI dan disimpan di sini, supaya pindah tab tidak
    // membuat banner/background berkedip balik ke bawaan (dulu di-decode ulang tiap tab).
    var bannerBmp by mutableStateOf<Bitmap?>(null)
    var bannerReady by mutableStateOf(false)
    var bgBmp by mutableStateOf<Bitmap?>(null)

    private fun reloadImages(banner: Boolean, bg: Boolean) {
        viewModelScope.launch {
            if (banner) {
                bannerBmp = withContext(Dispatchers.IO) { Imaging.decode(Imaging.bannerFile(app)) }
                bannerReady = true
            }
            if (bg) bgBmp = withContext(Dispatchers.IO) { Imaging.decode(Imaging.bgFile(app)) }
        }
    }

    init { reloadImages(true, true) }
    var bubbleOn by mutableStateOf(prefs.bubbleOn)
    var autostart by mutableStateOf(prefs.autostart)
    var hudOn by mutableStateOf(prefs.hudOn)
    var recOn by mutableStateOf(false)
    var refreshRates by mutableStateOf<List<Int>>(emptyList())
    var refreshHz by mutableStateOf("off")

    fun updateCardAlpha(v: Float) { cardAlpha = v; prefs.cardAlpha = v }
    fun updateFit(v: Int) { fit = v; prefs.fit = v }
    fun updateAccent(v: Int) { accent = v; prefs.accent = v }
    fun updateBlur(v: Int) { blur = v; prefs.blur = v }
    fun updateContrast(v: Int) { contrast = v; prefs.contrast = v }
    fun updateSaver(v: Boolean) { saver = v; prefs.saver = v }
    fun updateAutostart(v: Boolean) { autostart = v; prefs.autostart = v }

    // ---------- cek fitur ----------
    var liveRes by mutableStateOf<List<Triple<String, String, String>>>(emptyList())
    var liveBusy by mutableStateOf(false)
    var liveNote by mutableStateOf("")
    fun runLiveCheck() {
        if (liveBusy) return
        viewModelScope.launch {
            liveBusy = true; liveNote = ""; liveRes = emptyList()
            try {
                val (rows, raw) = Hsin.livecheck()
                liveRes = rows
                liveNote = if (rows.isEmpty()) "Tidak ada hasil. Detail: $raw" else ""
            } catch (e: Exception) {
                liveNote = "Gagal menjalankan: ${e.message}"
            }
            liveBusy = false
        }
    }

    // ---------- performa & rekam FPS ----------
    var fpsFiles by mutableStateOf<List<FpsFile>>(emptyList())
    var fpsSel by mutableStateOf<List<String>>(emptyList())
    var fpsLoading by mutableStateOf(false)
    var fpsSkipped by mutableStateOf(0)   // berkas CSV tanpa data FPS (sumber FPS tidak tersedia)
    var fpsView by mutableStateOf("")   // rekaman yang dibuka di tampilan detail

    fun loadFpsFiles() {
        viewModelScope.launch {
            fpsLoading = true
            val r = Root.exec(
                "for f in \$(ls -t /sdcard/Download/HSIN_fps_*.csv 2>/dev/null | head -6); do echo \"@@FILE \$f\"; cat \"\$f\"; done",
                40_000L,
            )
            val blocks = r.out.split("@@FILE ").drop(1)
            fpsFiles = blocks.mapNotNull { blk ->
                val nl = blk.indexOf('\n')
                if (nl < 0) null else FpsFile.parse(blk.substring(0, nl).trim().substringAfterLast('/'), blk.substring(nl + 1))
            }
            fpsSkipped = blocks.size - fpsFiles.size
            if (fpsFiles.none { it.name == fpsView }) fpsView = fpsFiles.firstOrNull()?.name.orEmpty()
            fpsSel = fpsSel.filter { n -> fpsFiles.any { it.name == n } }
            fpsLoading = false
        }
    }

    fun toggleFpsSel(name: String) {
        fpsSel = if (name in fpsSel) fpsSel - name else (fpsSel + name).takeLast(2)
    }

    fun toggleFpsLog() {
        if (!Settings.canDrawOverlays(app)) { askOverlay = true; return }
        BubbleService.start(app)
        app.startService(Intent(app, BubbleService::class.java).setAction(BubbleService.ACT_FPSLOG))
    }

    fun updateHudOn(on: Boolean) {
        if (on && !Settings.canDrawOverlays(app)) {
            askOverlay = true
            toast("Izinkan 'tampil di atas app lain' dulu")
            return
        }
        hudOn = on
        prefs.hudOn = on
        // HUD hidup di dalam BubbleService; pastikan service jalan
        if (on) BubbleService.start(app)
        else if (!prefs.bubbleOn) BubbleService.stop(app)
    }

    // ---------- tweak global (Layar / Performa / Alat) ----------
    var tw by mutableStateOf<Map<String, String>>(emptyMap())
    var twOver by mutableStateOf<Map<String, String>>(emptyMap())

    fun loadTweaks() {
        viewModelScope.launch { tw = Hsin.tweakList(); twOver = Hsin.tweakOver() }
    }

    /** v = null: kembali otomatis (ikut mode). */
    fun setTweak(key: String, v: String?) {
        viewModelScope.launch {
            val r = if (v == null) Hsin.tweakUnset(key) else Hsin.tweakSet(key, v)
            if (r.code != 0 || r.out.contains("ERROR")) toast((r.out.lines().firstOrNull { it.startsWith("ERROR") } ?: "Gagal").removePrefix("ERROR:").trim())
            tw = Hsin.tweakList(); twOver = Hsin.tweakOver()
        }
    }

    fun resetTweaks() {
        viewModelScope.launch {
            Hsin.tweakReset()
            tw = Hsin.tweakList(); twOver = Hsin.tweakOver()
            toast("Tweak kembali otomatis")
        }
    }

    fun setGameFps(pkg: String, v: String, onDone: () -> Unit = {}) {
        viewModelScope.launch {
            val r = Hsin.setGameFps(pkg, v)
            if (r.code != 0 || r.out.contains("ERROR")) toast((r.out.lines().firstOrNull { it.startsWith("ERROR") } ?: "Gagal").removePrefix("ERROR:").trim())
            onDone()
        }
    }

    fun updateRefreshHz(v: String) {
        viewModelScope.launch {
            val r = Hsin.setRefresh(v)
            if (r.code == 0) {
                refreshHz = v
                toast(if (v == "off") "Refresh rate game: ikut sistem" else "Refresh rate game: $v Hz")
            } else toast(r.out.lines().firstOrNull { it.isNotBlank() } ?: "Gagal")
            refreshHz = Hsin.refreshGet()
        }
    }

    fun toggleRec() {
        viewModelScope.launch {
            val r = if (recOn) Hsin.recStop() else Hsin.recStart()
            toast(r.out.lines().firstOrNull { it.isNotBlank() } ?: "Gagal")
            refreshStatus()
            recOn = status.rec
        }
    }

    fun launchGame(pkg: String) {
        viewModelScope.launch {
            val r = Hsin.launchGame(pkg)
            toast(r.out.lines().firstOrNull { it.isNotBlank() } ?: "Gagal")
        }
    }

    fun setGameRender(pkg: String, v: String, onDone: () -> Unit = {}) {
        viewModelScope.launch {
            val r = Hsin.setGameRender(pkg, v)
            if (r.code != 0) toast(r.out.lines().firstOrNull { it.isNotBlank() } ?: "Gagal")
            onDone()
        }
    }

    fun setGameOpt(pkg: String, key: String, v: String) {
        viewModelScope.launch {
            val r = Hsin.setGameOpt(pkg, key, v)
            if (r.code != 0) toast((r.out.lines().firstOrNull { it.isNotBlank() } ?: "Gagal").removePrefix("ERROR:").trim())
        }
    }

    fun updateBubbleOn(on: Boolean) {
        if (on) {
            if (!Settings.canDrawOverlays(app)) {
                askOverlay = true
                toast("Izinkan 'tampil di atas app lain' dulu")
                return
            }
            prefs.bubbleHidden = false
            prefs.bubbleOn = true
            bubbleOn = true
            BubbleService.start(app)
        } else {
            prefs.bubbleOn = false
            bubbleOn = false
            // HUD hidup di service yang sama: jangan dimatikan kalau HUD masih dipakai
            if (!prefs.hudOn) BubbleService.stop(app)
        }
    }

    // ---------- util ----------
    private var toastJob: Job? = null
    fun toast(s: String) {
        msg = trn(s.removePrefix("ERROR:").removePrefix("OK:").trim())
        SoundFx.play(prefs, if (s.startsWith("ERROR") || s.startsWith("Gagal")) "bad" else "good")
        toastJob?.cancel()
        val bad = s.startsWith("ERROR") || s.startsWith("Gagal")
        toastJob = viewModelScope.launch { delay(if (bad) 3500 else 2500); msg = null }
    }

    fun label(pkg: String): String = try {
        pm.getApplicationLabel(pm.getApplicationInfo(pkg, 0)).toString()
    } catch (_: Exception) { pkg }

    // ---------- siklus hidup & polling ----------
    @Volatile var visible = false
    private var autoEnsured = false
    private var tick = 0

    init {
        viewModelScope.launch {
            bootstrap()
            while (true) {
                delay(2000)
                if (!visible || !rootOk) continue
                tick++
                refreshStatus()
                when (route) {
                    "batlab" -> battery = Hsin.battery()
                    "tools" -> if (tick % 2 == 0) { Hsin.health()?.let { health = it }; loadRecentLog() }
                }
            }
        }
    }

    private suspend fun bootstrap() {
        rootOk = Root.hasRoot()
        if (rootOk) {
            modPath = Root.modPath(true)
            if (modPath.isNotEmpty()) refreshAll()
        }
        loaded = true
        if ((prefs.bubbleOn || prefs.hudOn) && Settings.canDrawOverlays(app)) BubbleService.start(app)
        if (rootOk) compileSelfOnce()
    }

    /** Sekali per versi: kompilasi penuh app ini jadi kode native (root), supaya UI tidak patah-patah di HP lemah. Jalan pelan di latar. */
    private fun compileSelfOnce() {
        if (prefs.sp.getInt("self_compiled", 0) >= appVer || appVer == 0) return
        viewModelScope.launch {
            delay(45_000L)
            if (status.gamePkg.isNotEmpty()) return@launch   // jangan ganggu game
            // hanya saat layar mati atau sedang dicas
            val pw = app.getSystemService(android.content.Context.POWER_SERVICE) as android.os.PowerManager
            val chg = app.registerReceiver(null, android.content.IntentFilter(android.content.Intent.ACTION_BATTERY_CHANGED))
                ?.getIntExtra(android.os.BatteryManager.EXTRA_PLUGGED, 0) ?: 0
            if (pw.isInteractive && chg == 0) return@launch
            val r = Root.exec("nice -n 19 cmd package compile -f -m speed ${app.packageName}", 240_000L)
            if (r.out.contains("Success")) prefs.sp.edit().putInt("self_compiled", appVer).apply()
        }
    }

    suspend fun refreshAll() {
        refreshStatus()
        conf = Hsin.conf()
        flags = Hsin.flags()
        games = Hsin.games()
        sessions = Hsin.sessions()
        if (!prefs.gameOptsClean613 && games.isNotEmpty()) {
            for (g in games) {
                val o = Hsin.gameOpts(g.pkg)
                if (o["LITE"] != null) Hsin.setGameOpt(g.pkg, "LITE", "default")
                if (o["HZ"] != null && Hsin.gamefx(g.pkg)["fps"].let { it == null || it == "off" }) Hsin.setGameOpt(g.pkg, "HZ", "default")
            }
            prefs.gameOptsClean613 = true
        }
        Hsin.health()?.let { health = it }
        device = Hsin.device()
        Hsin.render()?.let { render = it; renderChoice = it.current }
        refreshRates = Hsin.refreshList()
        refreshHz = Hsin.refreshGet()
        recOn = status.rec
        refreshRes()
        loadRecentLog()
    }

    private suspend fun refreshTools() {
        Hsin.health()?.let { health = it }
        flags = Hsin.flags()
        device = Hsin.device()
        refreshRes()
        loadRecentLog()
    }

    /** Mode yang baru dipilih tampil seketika; polling tidak boleh menimpanya sebelum perintah selesai. */
    @Volatile private var pendProf: String? = null
    @Volatile private var pendOvd = false
    @Volatile private var pendUntil = 0L
    fun pendMode(prof: String, ovd: Boolean) { pendProf = prof; pendOvd = ovd; pendUntil = android.os.SystemClock.uptimeMillis() + 20_000L }
    fun pendClear() { pendUntil = 0L }

    suspend fun refreshStatus() {
        val s = Hsin.status()
        if (s == null) {
            statusOk = false
            statusStale = true
            return
        }
        statusStale = false
        statusLastOkMs = System.currentTimeMillis()
        val pp = pendProf
        status = if (pp != null && pendUntil > android.os.SystemClock.uptimeMillis()) s.copy(profile = pp, active = pp, ovd = pendOvd) else s
        statusOk = true
        if (!s.auto && !autoEnsured) {
            autoEnsured = true
            Hsin.autoStart()
        } else if (s.auto) autoEnsured = true
    }

    private suspend fun loadRecentLog() { logs = Hsin.parseLog(Hsin.logRaw(300)) }
    private suspend fun loadFullLog() { logs = Hsin.parseLog(Hsin.logRaw(800)) }

    // ---------- profil ----------
    fun setProfile(p: String) {
        viewModelScope.launch {
            val old = status
            status = status.copy(profile = p, active = p)
            pendMode(p, status.ovd)
            val r = Hsin.setProfile(p)
            if (!r.ok) status = status.copy(profile = old.profile, active = old.active)
            pendClear()
            val locked = status.gamePkg.isNotEmpty()
            toast(
                if (!r.ok) "Gagal ganti profil: ${r.out.take(60)}"
                else if (locked) "Tersimpan. Profil game dipakai selama game jalan"
                else "Profil ${profileLabel(p)} diterapkan"
            )
            refreshStatus()
        }
    }

    // ---------- flag & thermal & auto ----------
    fun flag(name: String): Boolean = flags[name] == true

    fun setFlag(name: String, on: Boolean) {
        viewModelScope.launch {
            flags = flags + (name to on)
            if (!Hsin.setFlag(name, on)) toast("Gagal menyimpan pengaturan")
            flags = Hsin.flags()
        }
    }

    fun setThermalWarm(c: Int) {
        viewModelScope.launch {
            if (Hsin.setThermalWarm(c)) { status = status.copy(thermalWarmC = c); toast("Batas suhu $c°C disimpan") }
            else toast("Gagal menyimpan batas suhu")
        }
    }

    fun setBootGuard(on: Boolean) {
        viewModelScope.launch {
            health = health.copy(bootGuard = on)
            Hsin.setFlag("BOOT_GUARD_OFF", !on)
            Hsin.health()?.let { health = it }
            toast(if (on) "Boot guard aktif" else "Boot guard dimatikan")
        }
    }

    fun confStr(k: String, d: String): String = conf[k] ?: d

    fun saveAuto(battOn: Boolean, pct: Int, battProf: String, chgOn: Boolean, chgProf: String) {
        viewModelScope.launch {
            val ok = Hsin.setConf("AUTO_BATT_ON", if (battOn) "1" else "0") &&
                Hsin.setConf("AUTO_BATT_PCT", pct.toString()) &&
                Hsin.setConf("AUTO_BATT_PROFILE", battProf) &&
                Hsin.setConf("AUTO_CHG_ON", if (chgOn) "1" else "0") &&
                Hsin.setConf("AUTO_CHG_PROFILE", chgProf)
            conf = Hsin.conf()
            Hsin.autoStart()
            toast(if (ok) "Aturan auto-profile tersimpan" else "Sebagian gagal disimpan")
        }
    }

    // ---------- game ----------
    fun addGame(pkg: String, fps: String, profile: String, after: () -> Unit = {}) {
        viewModelScope.launch {
            busy = "Menyimpan game..."
            val r = Hsin.addGame(pkg, fps, profile)
            games = Hsin.games()
            busy = null
            if (r.out.startsWith("OK")) { toast("${label(pkg)} disimpan"); after() }
            else toast(r.out.lineSequence().firstOrNull { it.startsWith("ERROR") } ?: "Gagal menyimpan game")
        }
    }

    fun addGames(pkgs: List<String>, profile: String, after: () -> Unit = {}) {
        viewModelScope.launch {
            busy = "Menambah ${pkgs.size} game..."
            var ok = 0
            for (p in pkgs) if (Hsin.addGame(p, "", profile).out.startsWith("OK")) ok++
            games = Hsin.games()
            busy = null
            toast("$ok game ditambahkan")
            after()
        }
    }

    fun removeGame(pkg: String) {
        viewModelScope.launch {
            busy = "Menghapus..."
            Hsin.removeGame(pkg)
            games = Hsin.games()
            busy = null
            toast("${label(pkg)} dihapus")
        }
    }

    // ---------- daftar app (tanpa root) ----------
    var apps by mutableStateOf<List<AppItem>>(emptyList())
    private var appsLoading = false

    private val gamePrefixes = listOf(
        "com.kurogame.", "com.mihoyo.", "com.miHoYo.", "com.HoYoverse.", "com.hoyoverse.", "com.tencent.ig",
        "com.tencent.tmgp", "com.pubg", "com.activision.", "com.mobile.legends", "com.moonton.", "com.garena.",
        "com.supercell.", "com.proximabeta", "com.netease.", "com.levelinfinite.", "com.hypergryph.",
        "com.YoStarEN.", "com.YoStarJP.", "com.epicgames.", "com.riotgames.", "com.roblox.", "com.mojang.",
        "com.innersloth.", "com.dts.freefire", "com.nexon.", "com.gryphline.", "com.lilithgames.", "com.sunborn.",
        "com.habby.", "com.fantome.", "com.ea.", "com.gameloft.", "com.king.", "com.zhiliaoapp.musically.go",
    )

    // Bank paket game (assets/gamebank.txt, sumber Encore Tweaks, Apache-2.0). Dimuat sekali, hanya saat daftar app dibuka.
    private val gameBank: Set<String> by lazy {
        try {
            app.assets.open("gamebank.txt").bufferedReader().useLines { seq ->
                seq.map { it.trim() }.filter { it.isNotEmpty() && !it.startsWith("#") }.toHashSet()
            }
        } catch (_: Exception) {
            emptySet()
        }
    }

    @Suppress("DEPRECATION")
    private fun isGameApp(ai: ApplicationInfo): Boolean {
        if (ai.category == ApplicationInfo.CATEGORY_GAME) return true
        if ((ai.flags and ApplicationInfo.FLAG_IS_GAME) != 0) return true
        if (ai.packageName in gameBank) return true
        return gamePrefixes.any { ai.packageName.startsWith(it) }
    }

    fun ensureApps() {
        if (apps.isNotEmpty() || appsLoading) return
        appsLoading = true
        viewModelScope.launch {
            apps = withContext(Dispatchers.IO) {
                val i = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
                pm.queryIntentActivities(i, 0)
                    .map { it.activityInfo.applicationInfo }
                    .distinctBy { it.packageName }
                    .filter { it.packageName != app.packageName }
                    .map { AppItem(it.packageName, pm.getApplicationLabel(it).toString(), isGameApp(it)) }
                    .sortedWith(compareByDescending<AppItem> { it.isGame }.thenBy { it.label.lowercase() })
            }
            appsLoading = false
        }
    }

    fun loadThirdParty(): List<AppItem> =
        pm.getInstalledApplications(0)
            .filter { (it.flags and ApplicationInfo.FLAG_SYSTEM) == 0 && it.packageName != app.packageName }
            .map { AppItem(it.packageName, pm.getApplicationLabel(it).toString(), isGameApp(it)) }
            .sortedBy { it.label.lowercase() }

    var thirdParty by mutableStateOf<List<AppItem>>(emptyList())

    fun ensureThirdParty() {
        if (thirdParty.isNotEmpty()) return
        viewModelScope.launch { thirdParty = withContext(Dispatchers.IO) { loadThirdParty() } }
    }

    // ---------- render ----------
    fun applyRender() {
        viewModelScope.launch {
            busy = "Mengganti render..."
            val r = Hsin.setRender(renderChoice)
            busy = null
            Hsin.render()?.let { render = it }
            dialog = Dlg.Info(
                "Render", r.out.ifEmpty { "Selesai" },
                if (r.out.startsWith("OK")) "TUTUP SEMUA APP" else null,
                if (r.out.startsWith("OK")) ({ askCloseApps() }) else null,
            )
        }
    }

    // ---------- resolusi ----------
    var resInfo by mutableStateOf<Hsin.ResInfo?>(null)
    var resPct by mutableStateOf(100)
    var resCountdown by mutableStateOf(0)
    private var resJob: Job? = null
    private var resRestore: String = ""

    suspend fun refreshRes() {
        val r = Hsin.resolution() ?: return
        resInfo = r
        if (resCountdown == 0) {
            val pct = Math.round(r.act.w * 100f / r.nat.w)
            resPct = listOf(60, 70, 80, 90, 100).minByOrNull { kotlin.math.abs(it - pct) } ?: 100
        }
    }

    fun applyRes() {
        val info = resInfo ?: run { toast("Info layar belum terbaca"); return }
        resJob?.cancel()
        resRestore = Hsin.restoreCommand(info)
        val target = Hsin.resCommand(info.nat, resPct)
        resJob = viewModelScope.launch {
            resCountdown = 10
            Hsin.applyResWithGuard(target, resRestore, 13)
            refreshRes()
            var n = 10
            while (n > 0 && resCountdown > 0) {
                delay(1000)
                n--
                resCountdown = n
            }
            if (resCountdown == 0 && n == 0) {
                Hsin.revertRes(resRestore)
                refreshRes()
                toast("Tidak dikonfirmasi, resolusi dikembalikan")
            }
        }
    }

    fun keepRes() {
        resJob?.cancel()
        resCountdown = 0
        viewModelScope.launch { Hsin.keepRes(); refreshRes(); toast("Resolusi dipertahankan") }
    }

    fun revertRes() {
        resJob?.cancel()
        resCountdown = 0
        viewModelScope.launch { Hsin.revertRes(resRestore.ifEmpty { "wm size reset; wm density reset" }); refreshRes(); toast("Resolusi dikembalikan") }
    }

    fun resetRes() {
        resJob?.cancel()
        resCountdown = 0
        viewModelScope.launch { Hsin.resetRes(); refreshRes(); toast("Resolusi direset") }
    }

    // ---------- tutup semua app ----------
    private val protectedExact = setOf(
        "android", "com.android.systemui", "com.android.phone", "com.android.server.telecom",
        "com.android.bluetooth", "com.android.nfc", "com.android.shell", "com.android.keychain",
        "com.android.se", "com.google.android.gms", "com.google.android.gsf",
        "com.topjohnwu.magisk", "me.weishu.kernelsu", "com.rifsxd.ksunext", "me.bmax.apatch",
    )
    private val rootManagerWords = listOf("magisk", "kernelsu", "ksu", "apatch", "mmrl", "termux")
    private fun isProtected(p: String, prot: Set<String>): Boolean =
        p in prot || rootManagerWords.any { p.contains(it, ignoreCase = true) }

    private val protectedContains = listOf(
        "dialer", "telecom", "incallui", "inputmethod", "keyboard", "launcher", "systemui", "wallpaper",
        "permissioncontroller", "packageinstaller", "bluetooth", "nfc", "emergency", "clock", "alarm", "calendar",
    )

    private fun protectedPackages(): Set<String> {
        val s = HashSet<String>(protectedExact)
        s.add(app.packageName)
        try {
            val home = pm.resolveActivity(Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME), PackageManager.MATCH_DEFAULT_ONLY)
            home?.activityInfo?.packageName?.let { s.add(it) }
        } catch (_: Exception) { }
        try {
            val ime = Settings.Secure.getString(app.contentResolver, "default_input_method")
            if (!ime.isNullOrEmpty()) s.add(ime.substringBefore('/'))
        } catch (_: Exception) { }
        return s
    }

    private fun systemLaunchables(prot: Set<String>): List<String> {
        val i = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        return pm.queryIntentActivities(i, 0)
            .map { it.activityInfo.applicationInfo }
            .filter { (it.flags and ApplicationInfo.FLAG_SYSTEM) != 0 }
            .map { it.packageName }
            .distinct()
            .filter { p -> !isProtected(p, prot) && protectedContains.none { p.contains(it, ignoreCase = true) } }
    }

    fun askCloseApps() {
        dialog = Dlg.Confirm(
            title = "Tutup semua app",
            text = "Semua app pihak ketiga ditutup, termasuk game yang sedang jalan. HSIN, Termux, dan manager root tidak ikut ditutup.",
            okLabel = "TUTUP",
            checkLabel = "Termasuk app sistem (bukan layanan inti)",
            checkDefault = false,
            onOk = { includeSystem -> closeApps(includeSystem) },
        )
    }

    // ---------- memori & alat (v55) ----------
    var memInfo by mutableStateOf<Map<String, String>>(emptyMap())
    var mglru by mutableStateOf<Map<String, String>>(emptyMap())
    var scanList by mutableStateOf<List<String>?>(null)

    fun loadMem() {
        viewModelScope.launch {
            memInfo = Hsin.memStatus()
            mglru = Hsin.mglruStatus()
        }
    }

    fun setMglru(on: Boolean) {
        viewModelScope.launch {
            busy = "Mengatur MGLRU..."
            mglru = Hsin.setMglru(on)
            conf = Hsin.conf()
            busy = null
            val real = mglru["enabled"] == "1"
            toast(if (on && !real) "MGLRU gagal menyala (kernel tidak mendukung)" else if (on) "MGLRU menyala" else "MGLRU dikembalikan ke semula")
        }
    }

    fun setMemclean(on: Boolean) {
        viewModelScope.launch {
            Hsin.setMemclean(on)
            conf = Hsin.conf()
        }
    }

    fun setConfKey(k: String, v: String) {
        viewModelScope.launch {
            Hsin.setConf(k, v)
            conf = Hsin.conf()
        }
    }

    fun runTrim() {
        viewModelScope.launch {
            busy = "Menjalankan TRIM..."
            val r = Hsin.trim()
            busy = null
            toast(r.ifEmpty { "Selesai" })
        }
    }

    fun scanAndAdd() {
        viewModelScope.launch {
            busy = "Mencari game terpasang..."
            val l = Hsin.gameScan()
            if (l.isEmpty()) { busy = null; toast("Tidak ada game baru yang dikenal"); return@launch }
            Hsin.gameScanAdd()
            games = Hsin.games()
            busy = null
            toast("${l.size} game baru ditambahkan")
        }
    }

    var diagText by mutableStateOf("")
    var diagPkg by mutableStateOf("")
    /** Diagnosa FPS untuk satu game tertentu (tombol "Perbaiki FPS game ini" di rak game): tunggu sabar sampai 3 kali. */
    fun fpsDiagFor(pkg: String) {
        viewModelScope.launch {
            busy = "Mendiagnosa FPS..."
            diagPkg = pkg
            var out = ""
            for (i in 0 until 3) {
                out = Hsin.fpsDiag(pkg)
                if (out.isNotBlank() && !out.contains("tidak ada frame", true)) break
                delay(2000)
            }
            diagText = out.ifEmpty { "Tidak ada hasil dari modul. Buka game dulu lalu coba lagi." }
            busy = null
        }
    }
    fun fpsDiag() {
        viewModelScope.launch {
            busy = "Mendiagnosa FPS..."
            val pkg = status.hudPkg.ifEmpty { status.gamePkg }.ifEmpty { prefs.lastGame }
            diagText = if (pkg.isEmpty()) "Belum ada game yang dibuka. Buka game lewat HSIN lalu coba lagi." else Hsin.fpsDiag(pkg).ifEmpty { "Tidak ada hasil dari modul." }
            busy = null
        }
    }

    fun restoreAll() {
        viewModelScope.launch {
            busy = "Mengembalikan ke normal..."
            val r = Hsin.restoreAll()
            busy = null
            toast(r.ifEmpty { "Selesai" })
            refreshButton()
        }
    }

    var updateText by mutableStateOf("")
    var updateUrl by mutableStateOf("")
    fun checkUpdate() {
        viewModelScope.launch {
            updateText = "Memeriksa..."
            val res = withContext(Dispatchers.IO) {
                try {
                    val c = java.net.URL("https://api.github.com/repos/isac12345/Hsin/releases/latest").openConnection() as java.net.HttpURLConnection
                    c.connectTimeout = 8000; c.readTimeout = 8000
                    c.setRequestProperty("Accept", "application/vnd.github+json")
                    if (c.responseCode == 404) "NONE|"
                    else {
                        val j = org.json.JSONObject(c.inputStream.bufferedReader().readText())
                        (j.optString("tag_name") + "|" + j.optString("html_url"))
                    }
                } catch (e: Exception) { "ERR|" }
            }
            val (tag, url) = res.split("|").let { it[0] to it.getOrElse(1) { "" } }
            updateUrl = url
            updateText = when {
                tag == "ERR" -> "Tidak bisa terhubung ke GitHub."
                tag == "NONE" || tag.isEmpty() -> "Belum ada rilis di GitHub. Hasil build ada di tab Actions repo isac12345/Hsin."
                else -> {
                    "Rilis terbaru: $tag (versi kode app kamu: $appVer)"
                }
            }
        }
    }

    fun scanGames() {
        viewModelScope.launch {
            busy = "Mencari game terpasang..."
            scanList = Hsin.gameScan()
            busy = null
            toast(if (scanList.isNullOrEmpty()) "Tidak ada game baru yang dikenal" else "${scanList!!.size} game baru ditemukan")
        }
    }

    fun scanAdd() {
        viewModelScope.launch {
            busy = "Mendaftarkan game..."
            val r = Hsin.gameScanAdd()
            scanList = null
            games = Hsin.games()
            busy = null
            toast(r.removePrefix("OK: ").ifEmpty { "Selesai" })
        }
    }

    fun makeBugreport() {
        viewModelScope.launch {
            busy = "Membuat arsip laporan..."
            val path = Hsin.bugreport()
            busy = null
            toast(if (path != null) "Disimpan: $path" else "Gagal membuat laporan")
        }
    }

    // ---------- opsi game v55 ----------
    var gameFx by mutableStateOf<Map<String, String>>(emptyMap())

    fun loadGameFx(pkg: String) {
        viewModelScope.launch { gameFx = Hsin.gamefx(pkg) }
    }

    fun gameAutoMode(pkg: String, on: Boolean, done: () -> Unit) {
        viewModelScope.launch {
            val r = Hsin.setGameAutoMode(pkg, on)
            if (r.code != 0) toast(r.out.lines().firstOrNull { it.isNotBlank() } ?: "Gagal")
            gameFx = Hsin.gamefx(pkg)
            done()
        }
    }

    fun gameAutoReset(pkg: String, okMsg: String, done: () -> Unit) {
        viewModelScope.launch {
            val r = Hsin.resetGameAuto(pkg)
            toast(if (r.code == 0) okMsg else r.out.lines().firstOrNull { it.isNotBlank() } ?: "Gagal")
            gameFx = Hsin.gamefx(pkg)
            done()
        }
    }

    fun learnGamePreset(pkg: String, pct: Int, okMsg: String, done: () -> Unit) {
        viewModelScope.launch {
            val r = Hsin.learnGamePreset(pkg, pct)
            toast(if (r.code == 0) okMsg else r.out.lines().firstOrNull { it.isNotBlank() } ?: "Gagal")
            done()
        }
    }

    fun setGamePreset(pkg: String, name: String, okMsg: String, done: () -> Unit) {
        viewModelScope.launch {
            val r = Hsin.setGamePreset(pkg, name)
            toast(if (r.code == 0) okMsg else r.out.lines().firstOrNull { it.isNotBlank() } ?: "Gagal")
            gameFx = Hsin.gamefx(pkg)
            done()
        }
    }

    fun setGameFx(pkg: String, key: String, v: String) {
        gameFx = gameFx + (key to v)
        viewModelScope.launch {
            val r = Hsin.setGamefx(pkg, key, v)
            if (r.code != 0) toast(r.out.lines().firstOrNull { it.isNotBlank() } ?: "Gagal")
            gameFx = Hsin.gamefx(pkg)
        }
    }

    fun exportLog() {
        viewModelScope.launch {
            busy = "Mengekspor log..."
            val path = Hsin.exportLog()
            busy = null
            toast(if (path != null) "Log disimpan: $path" else "Gagal mengekspor log")
        }
    }

    var benchBusy by mutableStateOf(false)
    var benchVer by mutableStateOf(0)
    var cmpA by mutableStateOf(-1)
    var cmpB by mutableStateOf(-1)
    var benchStep by mutableStateOf("")
    private suspend fun cpuBench(): Pair<Long, Long> = withContext(Dispatchers.Default) {
        fun run(threads: Int): Long {
            val total = java.util.concurrent.atomic.AtomicLong(0)
            val end = System.nanoTime() + 3_000_000_000L
            val ts = (0 until threads).map {
                Thread {
                    var n = 0L; var x = 1.0001
                    while (System.nanoTime() < end) {
                        for (i in 0 until 20000) { x = x * 1.0000001 + 0.0000001; if (x > 1e9) x = 1.0001 }
                        n += 20000
                    }
                    total.addAndGet(n + (x.toLong() and 0))
                }.also { it.start() }
            }
            ts.forEach { it.join() }
            return total.get() / 1_000_000L
        }
        Pair(run(1), run(Runtime.getRuntime().availableProcessors().coerceAtLeast(2)))
    }

    /** Uji CPU 3 dtk tunggal + 3 dtk semua inti; skor = juta iterasi. Dibandingkan antar mode. */
    fun runBench() {
        if (benchBusy) return
        benchBusy = true
        viewModelScope.launch {
            val (one, all) = cpuBench()
            val mode = profileLabel(status.profile)
            prefs.benchHist = listOf(listOf(System.currentTimeMillis().toString(), mode, one.toString(), all.toString())) + prefs.benchHist
            benchBusy = false
            benchVer++
        }
    }

    /** Uji otomatis Hemat, Seimbang, Performa berurutan dengan jeda dingin; profil awal dipulihkan. Puncak butuh game, jadi tidak ikut. */
    fun runBenchAll() {
        if (benchBusy) return
        benchBusy = true
        viewModelScope.launch {
            val orig = status.profile
            try {
                val seq = listOf("battery", "balanced", "performance")
                seq.forEachIndexed { i, p ->
                    benchStep = trn("Mode ") + profileLabel(p) + " (" + (i + 1) + "/3)"
                    Hsin.setProfile(p)
                    delay(2500)
                    val (one, all) = cpuBench()
                    prefs.benchHist = listOf(listOf(System.currentTimeMillis().toString(), profileLabel(p), one.toString(), all.toString())) + prefs.benchHist
                    benchVer++
                    if (i < seq.size - 1) {
                        for (t in 12 downTo 1) { benchStep = trn("Jeda dingin ") + t + " " + trn("dtk"); delay(1000) }
                    }
                }
            } finally {
                if (orig in PROFILE_KEYS) Hsin.setProfile(orig)
                benchStep = ""
                benchBusy = false
                benchVer++
                toast("Uji semua mode selesai")
            }
        }
    }
    var frozen by mutableStateOf<List<String>>(emptyList())
    var chargeInfo by mutableStateOf<Map<String, String>>(emptyMap())
    fun freezeApp(pkg: String) {
        viewModelScope.launch {
            busy = "Membekukan..."
            val r = Hsin.freezeOn(pkg)
            frozen = Hsin.freezeList()
            busy = null
            toast(r)
        }
    }
    fun unfreezeApp(pkg: String) {
        viewModelScope.launch {
            val r = if (pkg.isEmpty()) Hsin.freezeAllOff() else Hsin.freezeOff(pkg)
            frozen = Hsin.freezeList()
            toast(r)
        }
    }
    fun setChargeLimit(n: Int) {
        viewModelScope.launch {
            val r = Hsin.chargeSet(n)
            chargeInfo = Hsin.chargeStatus()
            toast(r)
        }
    }

    fun toggleRamKeep(pkg: String) {
        prefs.ramKeep = if (pkg in prefs.ramKeep) prefs.ramKeep - pkg else prefs.ramKeep + pkg
        ramKeepVer++
    }
    var ramKeepVer by mutableStateOf(0)

    /** Bersihkan RAM: tutup proses latar belakang app pihak ketiga, kecuali yang dilindungi, yang di depan, dan game aktif. */
    fun cleanRam() {
        viewModelScope.launch {
            busy = "Membersihkan RAM..."
            val prot = protectedPackages()
            val keep = prefs.ramKeep
            val front = setOf(status.hudPkg, status.gamePkg).filter { it.isNotEmpty() }.toSet()
            val targets = withContext(Dispatchers.IO) {
                pm.getInstalledApplications(0)
                    .filter { (it.flags and ApplicationInfo.FLAG_SYSTEM) == 0 }
                    .map { it.packageName }
                    .filter { !isProtected(it, prot) && it !in keep && it !in front }
            }
            val mb = Hsin.cleanRam(targets)
            SoundFx.play(prefs, "clean")
            busy = null
            toast(if (mb > 0) "RAM bebas bertambah sekitar $mb MB" else "Selesai, tidak ada RAM tambahan yang bisa dibebaskan")
        }
    }

    /** Seperti cleanRam tapi diam (tanpa dialog/toast): dipakai ritual luncur. Mengembalikan MB yang bebas. */
    suspend fun cleanRamQuiet(): Int {
        val prot = protectedPackages()
        val keep = prefs.ramKeep
        val front = setOf(status.hudPkg, status.gamePkg).filter { it.isNotEmpty() }.toSet()
        val targets = withContext(Dispatchers.IO) {
            pm.getInstalledApplications(0)
                .filter { (it.flags and ApplicationInfo.FLAG_SYSTEM) == 0 }
                .map { it.packageName }
                .filter { !isProtected(it, prot) && it !in keep && it !in front }
        }
        return Hsin.cleanRam(targets)
    }

    private fun closeApps(includeSystem: Boolean) {
        viewModelScope.launch {
            busy = "Menutup app..."
            val prot = protectedPackages()
            val third = withContext(Dispatchers.IO) {
                pm.getInstalledApplications(0)
                    .filter { (it.flags and ApplicationInfo.FLAG_SYSTEM) == 0 }
                    .map { it.packageName }
                    .filter { !isProtected(it, prot) }
            }
            val sys = if (includeSystem) withContext(Dispatchers.IO) { systemLaunchables(prot) } else emptyList()
            val all = third + sys
            Hsin.forceStop(all)
            busy = null
            toast("${all.size} app ditutup" + if (includeSystem) " (${sys.size} sistem)" else "")
        }
    }

    // ---------- dexopt ----------
    var dexMode by mutableStateOf("speed-profile")
    var dexSel by mutableStateOf<Set<String>>(emptySet())
    var dexRunning by mutableStateOf(false)
    var dexDone by mutableStateOf(0)
    var dexTotal by mutableStateOf(0)
    var dexCurrent by mutableStateOf("")
    var dexOk by mutableStateOf(0)
    var dexFail by mutableStateOf(0)
    private var dexJob: Job? = null

    fun dexToggle(pkg: String) { dexSel = if (pkg in dexSel) dexSel - pkg else dexSel + pkg }
    fun dexSelectAll(all: List<String>) { dexSel = all.toSet() }
    fun dexClear() { dexSel = emptySet() }

    fun dexStart() {
        if (dexRunning || dexSel.isEmpty()) return
        val list = dexSel.toList()
        dexJob = viewModelScope.launch {
            dexRunning = true
            dexDone = 0; dexOk = 0; dexFail = 0; dexTotal = list.size
            try {
                for (p in list) {
                    if (!isActive) break
                    dexCurrent = label(p)
                    if (Hsin.dexopt(p, dexMode)) dexOk++ else dexFail++
                    dexDone++
                }
                toast("Dexopt selesai: $dexOk berhasil, $dexFail gagal")
            } catch (e: CancellationException) {
                toast("Dexopt dibatalkan")
                throw e
            } finally {
                dexRunning = false
                dexCurrent = ""
            }
        }
    }

    fun dexCancel() { dexJob?.cancel() }

    // ---------- device / modul ----------
    // ---------- diagnose, frame pacing, restart monitor ----------
    var diag by mutableStateOf<DiagOutcome?>(null)
    var diagBusy by mutableStateOf(false)
    var fp by mutableStateOf<Map<String, String>>(emptyMap())

    /** Satu kali baca `hsinctl diagnose`; hanya dipanggil dari tombol (tanpa polling). */
    fun runDiagnose() {
        if (diagBusy) return
        viewModelScope.launch {
            diagBusy = true
            try {
                val r = Hsin.diagnose()
                diag = classifyDiagnose(r.code, r.out)
            } catch (e: CancellationException) {
                throw e
            } catch (_: Exception) {
                diag = DiagOutcome(null, "invalid")
            } finally {
                diagBusy = false
            }
        }
    }

    private fun diagStamp(): String = java.text.SimpleDateFormat("yyyy-MM-dd HH:mm", java.util.Locale.US).format(java.util.Date())

    fun copyDiagnose() {
        val m = diag?.kv ?: return
        val cm = app.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        cm.setPrimaryClip(ClipData.newPlainText("hsin.diagnose", diagReportText(m, diagStamp())))
        toast("Laporan disalin")
    }

    fun saveDiagnose() {
        val m = diag?.kv ?: return
        viewModelScope.launch {
            val day = java.text.SimpleDateFormat("yyyyMMdd-HHmm", java.util.Locale.US).format(java.util.Date())
            val name = "HSIN-diagnose-$day.txt"
            val ok = withContext(Dispatchers.IO) {
                try {
                    val tmp = java.io.File(app.cacheDir, name)
                    tmp.writeText(diagReportText(m, diagStamp()))
                    val r = Root.execBlocking("mkdir -p /sdcard/Download && cp '${tmp.absolutePath}' '/sdcard/Download/$name' && chmod 666 '/sdcard/Download/$name'", 10_000L)
                    tmp.delete()
                    r.ok
                } catch (_: Exception) { false }
            }
            toast(if (ok) "Laporan disimpan: Download/$name" else "Gagal menyimpan laporan")
        }
    }

    fun loadFramepacing() {
        viewModelScope.launch { fp = Hsin.framepacing() }
    }

    fun setFramepacing(on: Boolean) {
        viewModelScope.launch {
            val r = Hsin.setFramepacing(on)
            val okMsg = r.out.trimStart().startsWith("OK")
            toast(if (okMsg) (if (on) "Frame pacing dinyalakan" else "Frame pacing dimatikan") else "Gagal: " + r.out.lines().firstOrNull { it.isNotBlank() }.orEmpty().removePrefix("ERROR:").trim().take(60))
            fp = Hsin.framepacing()
        }
    }

    fun restartMonitor() {
        viewModelScope.launch {
            val r = Hsin.restartMonitor()
            toast(if (r.ok && r.out.contains("started")) "Monitor dimulai ulang. Reboot bila ragu." else "Gagal memulai ulang monitor")
        }
    }

    fun redetect() {
        viewModelScope.launch {
            busy = "Mendeteksi ulang..."
            device = Hsin.device(redetect = true)
            busy = null
            toast("Deteksi ulang selesai")
        }
    }

    fun refreshButton() {
        viewModelScope.launch {
            busy = "Memuat ulang..."
            rootOk = Root.hasRoot()
            if (rootOk) { if (modPath.isEmpty()) modPath = Root.modPath(true); refreshAll() }
            busy = null
            toast("Dimuat ulang")
        }
    }

    fun findModule() {
        viewModelScope.launch {
            busy = "Mencari modul..."
            rootOk = Root.hasRoot()
            modPath = if (rootOk) Root.modPath(true) else ""
            if (modPath.isNotEmpty()) refreshAll()
            busy = null
            toast(if (modPath.isNotEmpty()) "Modul ditemukan" else "Modul tidak ditemukan")
        }
    }

    fun checkHealth() {
        viewModelScope.launch {
            Hsin.health()?.let { health = it }
            toast("Health check diperbarui")
        }
    }

    fun copyLog() {
        val text = logs.takeLast(200).joinToString("\n") { it.raw }
        val cm = app.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        cm.setPrimaryClip(ClipData.newPlainText("hsin.log", text))
        toast("Log disalin")
    }

    // ---------- gambar ----------
    fun setBackground(uri: Uri) {
        viewModelScope.launch {
            val ok = withContext(Dispatchers.IO) { Imaging.import(app, uri, Imaging.bgFile(app), maxOf(app.resources.displayMetrics.widthPixels, app.resources.displayMetrics.heightPixels)) }
            if (ok) { prefs.bgVer = prefs.bgVer + 1; bgVer = prefs.bgVer; reloadImages(false, true); toast("Background diganti") } else toast("Gagal membaca gambar")
        }
    }

    fun clearBackground() {
        Imaging.bgFile(app).delete()
        prefs.bgVer = prefs.bgVer + 1; bgVer = prefs.bgVer
        bgBmp = null
        toast("Background dihapus")
    }

    fun setBanner(uri: Uri) {
        viewModelScope.launch {
            val ok = withContext(Dispatchers.IO) { Imaging.import(app, uri, Imaging.bannerFile(app), maxOf(app.resources.displayMetrics.widthPixels, app.resources.displayMetrics.heightPixels)) }
            if (ok) { prefs.bannerVer = prefs.bannerVer + 1; bannerVer = prefs.bannerVer; reloadImages(true, false); toast("Banner diganti") } else toast("Gagal membaca gambar")
        }
    }

    fun resetBanner() {
        Imaging.bannerFile(app).delete()
        prefs.bannerVer = prefs.bannerVer + 1; bannerVer = prefs.bannerVer
        bannerBmp = null
        toast("Banner default dipakai")
    }
}
