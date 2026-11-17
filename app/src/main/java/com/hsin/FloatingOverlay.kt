package com.hsin

import android.app.ActivityManager
import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.DashPathEffect
import android.graphics.Paint
import android.graphics.Path
import android.graphics.PixelFormat
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.SystemClock
import android.provider.Settings
import android.util.TypedValue
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import android.view.ViewConfiguration
import android.view.WindowManager
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.Toast
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import java.io.BufferedReader
import java.io.InputStreamReader
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min

/**
 * Satu jendela overlay: RINGKAS (pil), PENUH (panel), MEREKAM, dan BAR TIPIS.
 * Menggantikan bubble profil + HudOverlay lama. Semua angka dari satu stream
 * hud_sample.sh --loop; tidak ada proses/polling kedua.
 */
class FloatingOverlay(private val ctx: Context, private val prefs: Prefs) {

    companion object {
        private const val PANEL = 0xE0141416.toInt()
        private const val CARD = 0x0FFFFFFF
        private const val BORDER = 0x1FFFFFFF
        private const val TEXT = 0xFFF4F1EA.toInt()
        private const val LABEL = 0xFFA6B0C3.toInt()
        private const val HINT = 0xFF98A2B3.toInt()
        private const val SEG_TEXT = 0xFFB4BDCE.toInt()
        private const val DARK = 0xFF1B1203.toInt()
        private const val RED = 0xFFE5484D.toInt()
        private const val REC_TAG = 0xFFFF9AA0.toInt()
        private const val CPU = 0xFF60A5FA.toInt()
        private const val GPU = 0xFFF5A524.toInt()
        private const val RAM = 0xFF34D399.toInt()
        private const val TEMP = 0xFFFB7185.toInt()
        private const val P_BATTERY = 0xFF4FE3C1.toInt()
        private const val P_BALANCED = 0xFFE8B95A.toInt()
        private const val P_PERF = 0xFFFF9A3C.toInt()
        private const val P_ADAPT = 0xFFD7DEE6.toInt()
        private const val OD = 0xFFFF4D5E.toInt()
        private const val OD_TEXT = 0xFFFF9AA0.toInt()
        private const val OD_END = 0xFFB82E3C.toInt()
        private const val OD_GLOW = 0xB3FF4D5E.toInt()
        private const val MODE_PILL = 0
        private const val MODE_PANEL = 1
        private const val MODE_THIN = 2
        private const val MODE_MENU = 3
        private const val MENU_BOX = 264
        private const val ORB = 64
        private const val MENU_R = 104
        private val PROFILE_TEXT = listOf("Hemat", "Seimbang", "Performa")
    }

    @Volatile var lastFps = 0
    private var holdFps = 0f
    private var holdAt = 0L
    var onProfile: ((String) -> Unit)? = null
    var onRec: (() -> Unit)? = null
    var onHidden: (() -> Unit)? = null
    var onOvd: ((Boolean) -> Unit)? = null
    var onRam: (() -> Unit)? = null
    var onShot: (() -> Unit)? = null
    var onPause: (() -> Unit)? = null
    private var fpsTarget = 0f
    private var panelBat: TextView? = null
    private var panelLow: TextView? = null
    private val fpsWin = ArrayDeque<Float>()
    private var fpsDisp = 0f
    private var fpsTextOn = false
    private var flashUntil = 0L
    private var flashOn = false
    private var scanView: ScanView? = null
    private var scanT0 = 0L
    @Volatile var noFpsTicks = 0
    var onDnd: (() -> Unit)? = null
    private var dndOn = false
    fun setDnd(on: Boolean) { dndOn = on; paintTiles() }
    var onSession: ((FpsSession) -> Unit)? = null

    private val wm = ctx.getSystemService(Context.WINDOW_SERVICE) as WindowManager
    private val am = ctx.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private val probe = View(ctx)
    private var probeOn = false

    private val scale: Float get() = prefs.flScale / 100f
    private fun px(v: Number): Int = (v.toFloat() * scale).toInt().coerceAtLeast(1)
    private fun pf(v: Number): Float = v.toFloat() * scale

    private var root: FrameLayout? = null
    private var lp: WindowManager.LayoutParams? = null
    private var attached = false
    private var addedAt = 0L
    private var mode = MODE_PILL
    private var builtLand = true

    private var pill: View? = null
    private var panel: View? = null
    private var thin: View? = null

    private var fpsPill: TextView? = null
    private var fpsMenu: TextView? = null
    private var menu: FrameLayout? = null
    private var menuInfo: TextView? = null
    private val menuBtns = ArrayList<TextView>()
    private val orbs = ArrayList<OrbView>()
    private var adaptLoad = -1
    private val loadTags = ArrayList<TextView>()
    private fun paintLoadTag(t: TextView) { t.text = if (odOn) "PUNCAK" else if (adaptLoad >= 0) "B$adaptLoad" else "B-" }
    private var panelWheel: AdaptWheelView? = null
    private var modeSw: ModeSwitch? = null
    private var fpsBig: TextView? = null
    private var fpsThin: TextView? = null
    private var fpsPillLbl: TextView? = null
    private var idleRun = 0

    // ---- statistik FPS: per sesi game dan per rekaman (1 sampel/detik, hanya saat ada frame)
    private var sesPkg = ""
    private var sesStart = 0L
    private var sesOvdTicks = 0
    private var sesProfile = ""
    private val sesFps = ArrayList<Float>(1024)
    private val sesTempL = ArrayList<Float>(1024)
    private val sesWattL = ArrayList<Int>(1024)
    private val sesJankL = ArrayList<Int>(1024)
    private var sesJank = 0
    private var sesBig = 0
    private var sesMaxFt = 0
    private var sesWattSum = 0L
    private var sesWattN = 0

    /** Daya sesaat dalam 0,1 W dari arus x tegangan baterai (0 = tidak terbaca). Satuan arus berbeda tiap kernel, ditebak dari besarnya. */
    private fun readWatt10(): Int {
        return try {
            val bm = ctx.getSystemService(Context.BATTERY_SERVICE) as android.os.BatteryManager
            val cur = Math.abs(bm.getLongProperty(android.os.BatteryManager.BATTERY_PROPERTY_CURRENT_NOW))
            if (cur <= 0L) return 0
            val bi = ctx.registerReceiver(null, android.content.IntentFilter(android.content.Intent.ACTION_BATTERY_CHANGED))
            val mv = bi?.getIntExtra(android.os.BatteryManager.EXTRA_VOLTAGE, 0) ?: 0
            if (mv <= 0) return 0
            val ma = if (cur > 20000L) cur / 1000.0 else cur.toDouble()   // >20000 dianggap mikroampere
            Math.round(ma * mv / 1_000_000.0 * 10.0).toInt().coerceIn(0, 300)
        } catch (_: Exception) { 0 }
    }
    private val recFps = ArrayList<Float>(512)

    // ---- rekam data FPS ke CSV (bukan video) ----
    private var csvOn = false
    private var csvStart = 0L
    private val csvBuf = StringBuilder()
    private var csvRows = 0
    private var csvBtnLbl: TextView? = null
    private var csvDot: View? = null

    fun toggleFpsLog() {
        if (!csvOn) {
            csvOn = true
            FpsLog.on = true; FpsLog.rows = 0
            csvStart = SystemClock.elapsedRealtime()
            csvRows = 0
            csvBuf.setLength(0)
            csvBuf.append("t_detik,paket,fps,gpu_persen,gpu_mhz,cpu_persen,suhu_soc,suhu_baterai,profil,overdrive\n")
            paintCsv()
            Toast.makeText(ctx, trn("Rekam data FPS dimulai"), Toast.LENGTH_SHORT).show()
        } else {
            csvOn = false
            FpsLog.on = false
            paintCsv()
            saveCsv()
        }
    }

    private fun paintCsv() {
        paintThinBtns()
        paintMenu()
        csvBtnLbl?.text = if (csvOn) "Stop FPS" else trn("Rekam FPS")
        csvDot?.background = GradientDrawable().apply {
            shape = if (csvOn) GradientDrawable.RECTANGLE else GradientDrawable.OVAL
            cornerRadius = pf(3)
            setColor(Color.WHITE)
        }
    }

    private fun csvRow(s: Sample) {
        if (csvRows >= 40000) return
        val t = (SystemClock.elapsedRealtime() - csvStart) / 1000.0
        csvBuf.append("%.1f".format(java.util.Locale.US, t)).append(',').append(curFg).append(',')
        csvBuf.append(s.fps?.let { "%.1f".format(java.util.Locale.US, it) } ?: "").append(',')
        csvBuf.append(s.gpu?.toString() ?: "").append(',').append(s.gpuMhz?.toString() ?: "").append(',')
        csvBuf.append(s.cpu?.toString() ?: "").append(',')
        csvBuf.append(s.socC?.let { "%.0f".format(java.util.Locale.US, it) } ?: "").append(',')
        csvBuf.append(s.batC?.let { "%.0f".format(java.util.Locale.US, it) } ?: "").append(',')
        csvBuf.append(profile).append(',').append(if (odOn) 1 else 0).append('\n')
        csvRows++
        FpsLog.rows = csvRows
    }

    private fun saveCsv() {
        if (csvRows == 0) {
            Toast.makeText(ctx, trn("Tidak ada data FPS yang terekam"), Toast.LENGTH_SHORT).show()
            return
        }
        val text = csvBuf.toString()
        val rows = csvRows
        csvBuf.setLength(0)
        scope.launch(Dispatchers.IO) {
            val ts = java.text.SimpleDateFormat("yyyyMMdd_HHmmss", java.util.Locale.US).format(java.util.Date())
            val name = "HSIN_fps_$ts.csv"
            val tmp = java.io.File(ctx.cacheDir, name)
            val ok = try {
                tmp.writeText(text)
                val r = Root.exec("mkdir -p /sdcard/Download && cp '${tmp.absolutePath}' /sdcard/Download/$name && echo OK", 20_000L)
                r.out.contains("OK")
            } catch (_: Exception) { false }
            try { tmp.delete() } catch (_: Exception) { }
            kotlinx.coroutines.withContext(Dispatchers.Main) {
                FpsLog.saved++
                Toast.makeText(ctx, if (ok) "Data FPS ($rows baris) disimpan: Download/$name" else "Gagal menyimpan data FPS", Toast.LENGTH_LONG).show()
            }
        }
    }

    /** Dipanggil tiap polling status: pkg = game terdaftar yang aktif (kosong = tidak ada). Ganti game = sesi lama selesai. */
    fun setSession(pkg: String) {
        if (pkg == sesPkg) return
        endSession()
        sesPkg = pkg
        sesStart = System.currentTimeMillis()
        sesOvdTicks = 0
        sesProfile = profile
        sesFps.clear(); sesTempL.clear(); sesWattL.clear(); sesJankL.clear()
        sesJank = 0; sesBig = 0; sesMaxFt = 0; sesWattSum = 0L; sesWattN = 0
    }

    private fun endSession() {
        if (sesPkg.isEmpty()) return
        val st = FpsSession.stats(sesFps)
        if (st != null) {
            val n = sesFps.size
            val gp = if (n > 15) sesFps.subList(5, n) else sesFps   // versi Gameplay: abaikan 5 detik pertama
            val gst = FpsSession.stats(gp) ?: st
            onSession?.invoke(FpsSession(sesStart, sesPkg, st.first, st.second, n,
                ((System.currentTimeMillis() - sesStart) / 1000L).toInt(), sesOvdTicks * 100 / n, sesProfile,
                sesJank, sesBig, sesMaxFt, FpsSession.stability(sesFps),
                if (sesWattN > 0) (sesWattSum / sesWattN).toInt() else 0,
                gst.first, gst.second, FpsSession.stability(gp),
                FpsSession.down(sesFps), FpsSession.down(sesTempL), FpsSession.down(sesWattL), FpsSession.down(sesJankL, sum = true)))
        }
        sesFps.clear()
        sesPkg = ""
    }

    private fun finishRecording() {
        val st = FpsSession.stats(recFps)
        recFps.clear()
        if (st != null) Toast.makeText(ctx, "Rekaman: rata-rata ${st.first} FPS, 1% terendah ${st.second} FPS", Toast.LENGTH_LONG).show()
    }
    private var fpsBigLbl: TextView? = null
    private var fpsThinLbl: TextView? = null
    private val valViews = arrayOfNulls<TextView>(4)
    private val barViews = arrayOfNulls<BarView>(4)
    private val cards = arrayOfNulls<View>(4)
    private val thinVals = arrayOfNulls<TextView>(4)
    private var autoLogged = false
    private var thinBatGrp: View? = null
    private var thinBatV: TextView? = null
    private var lastBat = -1
    private val thinGroups = arrayOfNulls<View>(4)
    private val rings = ArrayList<RingView>()
    private var segButtons = ArrayList<TextView>()
    private var segRow: View? = null
    private var odRow: LinearLayout? = null
    private var odFlame: FlameView? = null
    private var odName: TextView? = null
    private var odSmall: TextView? = null
    private var odStatusLine: TextView? = null
    private var odOn = false
    private var odLevel = ""
    private var odAvail = false
    private var topRow: View? = null
    private var bigRow: View? = null
    private var gridRow: View? = null
    private var footRow: View? = null
    private var hintRec: View? = null
    private var graph: GraphView? = null
    private var panelBox: LinearLayout? = null
    private var themeTitle: TextView? = null
    private var tileRec: View? = null
    private var tileFps: View? = null
    private var tileDnd: View? = null

    private var profile = "none"
    private var recOn = false
    private var recStart = 0L
    private var started = false
    private var screenW = 0
    private var screenH = 0
    private val lastInt = IntArray(4) { -1 }

    private var game = ""
    private var job: Job? = null
    private var proc: Process? = null
    private var prevTs = ""
    private var curFg = ""
    private var cpuTotal = 0L
    private var cpuIdle = 0L
    private var gpuMaxMhz = 0

    // ---------------- publik ----------------

    fun attach() {
        if (prefs.bubbleHidden) return
        if (!Settings.canDrawOverlays(ctx)) return
        if (root == null) build()
        addWindow()
    }

    fun detach() {
        removeWindow()
        stopStream()
    }

    /** Sembunyikan floating sebentar saat screenshot. */
    fun setShotHidden(h: Boolean) {
        root?.visibility = if (h) View.INVISIBLE else View.VISIBLE
    }

    fun release() {
        removeWindow()
        if (probeOn) {
            try { wm.removeView(probe) } catch (_: Exception) { }
            probeOn = false
        }
        stopStream()
        if (csvOn) {
            // rekaman FPS jangan hilang kalau service mati: simpan di thread sendiri (scope akan dibatalkan)
            val text = csvBuf.toString(); val rows = csvRows
            csvOn = false; FpsLog.on = false; csvBuf.setLength(0); csvRows = 0
            if (rows > 0) Thread {
                try {
                    val name = "HSIN_fps_" + java.text.SimpleDateFormat("yyyyMMdd_HHmmss", java.util.Locale.US).format(java.util.Date()) + ".csv"
                    val tmp = java.io.File(ctx.cacheDir, name); tmp.writeText(text)
                    Root.execBlocking("mkdir -p /sdcard/Download && cp '${tmp.absolutePath}' /sdcard/Download/$name", 20_000L)
                    tmp.delete(); FpsLog.saved++
                } catch (_: Exception) { }
            }.start()
        }
        FpsLog.on = false
        scope.cancel()
    }

    /** Pilihan "Tampilan awal" berubah: ciutkan langsung ke bentuk itu (kecuali panel sedang dibuka). */
    fun applyStartMode() {
        mode = MODE_PILL
        rebuild()
    }

    fun rebuild() {
        val m = mode
        removeWindow()
        root = null
        valViews.fill(null)
        barViews.fill(null)
        cards.fill(null)
        thinVals.fill(null)
        thinBatGrp = null; thinBatV = null; lastBat = -1
        thinGroups.fill(null)
        rings.clear()
        orbs.clear(); loadTags.clear()
        panelWheel = null; modeSw = null
        menuBtns.clear()
        menu = null
        menuInfo = null
        fpsMenu = null
        segButtons = ArrayList()
        graph = null
        segRow = null
        odRow = null
        odFlame = null
        odName = null
        odSmall = null
        topRow = null
        bigRow = null
        gridRow = null
        footRow = null
        hintRec = null
        fpsPill = null
        fpsBig = null
        fpsThin = null
        fpsPillLbl = null
        fpsBigLbl = null
        fpsThinLbl = null
        panelBox = null
        themeTitle = null; tileRec = null; tileFps = null; tileDnd = null; scanView = null
        mode = m
        if (!prefs.bubbleHidden) {
            build()
            addWindow()
        }
    }

    fun setProfileState(p: String, rec: Boolean) {
        val changed = p != profile || rec != recOn
        profile = p
        if (rec != recOn) {
            if (rec) recFps.clear() else finishRecording()
            recOn = rec
            recStart = if (rec) SystemClock.elapsedRealtime() else 0L
        }
        if (changed) {
            flashT0 = SystemClock.uptimeMillis()
            val acc = accentColor()
            for (r in rings) { r.accent = acc; r.invalidate() }
            paintSeg()
            applyRec()
        }
        if (recOn) tickTimer()
    }

    fun setGame(pkg: String) {
        // aliran mati sendiri (su mati / pipa putus) atau jendela hilang: jangan berhenti di sini, mulai ulang
        val healthy = job?.isActive == true && attached
        if (pkg == game && healthy) return
        stopStream()
        game = pkg
        prevTs = ""
        cpuTotal = 0L
        cpuIdle = 0L
        gpuMaxMhz = 0
        for (i in lastInt.indices) lastInt[i] = -1
        if (pkg.isEmpty() || prefs.bubbleHidden) return
        attach()
        job = scope.launch(Dispatchers.IO) { loop(pkg) }
    }

    // ---------------- data ----------------

    private class Sample(val fps: Float?, val gpu: Int?, val gpuMhz: Int?, val cpu: Int?, val tempC: Float?, val socC: Float? = null, val batC: Float? = null,
                         val jank: Int = 0, val bigJank: Int = 0, val maxFtMs: Int = 0)
    private var jankLastTs = 0L
    private var jankAcc = 0
    private var bigAcc = 0
    private var maxAcc = 0

    private suspend fun loop(pkg: String) {
        var mine: Process? = null
        try {
            val mod = Root.modPath()
            if (mod.isEmpty()) return
            val p = ProcessBuilder("su", "-c", "sh '$mod/common/hud_sample.sh' --loop '$pkg'")
                .redirectErrorStream(true)
                .start()
            proc = p
            mine = p
            val br = BufferedReader(InputStreamReader(p.inputStream))
            val block = ArrayList<String>(32)
            while (true) {
                val line = br.readLine() ?: break
                if (line == "--") {
                    val s = parse(block)
                    block.clear()
                    scope.launch { apply(s) }
                } else if (block.size < 32) {
                    block.add(line)
                }
            }
        } catch (e: Exception) {
            android.util.Log.e("FloatingOverlay", "stream gagal: ${e.message}")
        } finally {
            try { mine?.destroyForcibly() } catch (_: Exception) { }
            if (proc === mine) proc = null
        }
    }

    private fun stopStream() {
        game = ""
        job?.cancel()
        job = null
        try { proc?.destroyForcibly() } catch (_: Exception) { }
        proc = null
    }

    private fun parse(lines: List<String>): Sample {
        val m = HashMap<String, String>()
        for (l in lines) {
            val i = l.indexOf('=')
            if (i > 0) m[l.substring(0, i)] = l.substring(i + 1).trim()
        }
        var ts = m["last_ts"].orEmpty()
        val x10 = m["fps_x10"]?.toIntOrNull()
        // Ganti app di depan: timestamp lama milik app sebelumnya tidak boleh dianggap "macet".
        val fgPkg = m["pkg"].orEmpty()
        if (fgPkg != curFg) { curFg = fgPkg; prevTs = "" }
        // Jalur layer: timestamp frame mentah dikirim script (shell ROM ini 32-bit, tidak bisa menghitung
        // angka 14 digit), FPS dihitung di sini dengan Long 64-bit seperti Smollming.
        val lat = m["lat"].orEmpty()
        var fpsLat: Float? = null
        if (lat.isNotEmpty()) {
            val arr = ArrayList<Long>(80)
            for (tok in lat.split(' ')) {
                val v = tok.toLongOrNull() ?: continue
                if (v > 0L) arr.add(v)
            }
            if (arr.size >= 3) {
                arr.sort()
                val last = arr[arr.size - 1]
                ts = last.toString()
                if (ts == prevTs) {
                    fpsLat = 0f
                } else {
                    val lo = last - 1_000_000_000L
                    var first = last
                    var n = 0
                    for (v in arr) {
                        if (v >= lo) {
                            n++
                            if (v < first) first = v
                        }
                    }
                    // jank: frame lebih lama dari 2x rata-rata 3 frame sebelumnya DAN > 83 ms; big jank > 125 ms.
                    // Hanya frame baru (di atas jankLastTs) yang dihitung, jendela sampel saling tumpang tindih.
                    var jk = 0; var bj = 0; var mx = 0
                    if (jankLastTs > 0L) {
                        for (i in 4 until arr.size) {
                            if (arr[i] <= jankLastTs) continue
                            val d = (arr[i] - arr[i - 1]) / 1_000_000L
                            val a3 = (arr[i - 1] - arr[i - 4]) / 3_000_000L
                            if (d > mx) mx = d.toInt()
                            if (d > 83L && d > 2L * a3) { jk++; if (d > 125L) bj++ }
                        }
                    }
                    jankLastTs = last
                    jankAcc = jk; bigAcc = bj; maxAcc = mx
                    val span = last - first
                    if (n > 1 && span > 0L) {
                        val f = ((n - 1) * 1_000_000_000.0 / span).toFloat()
                        if (f.isFinite() && f <= 480f) fpsLat = f
                    }
                }
            }
        }
        val fps: Float? = when {
            lat.isNotEmpty() -> fpsLat?.coerceAtMost(maxHz)
            x10 == null || ts.isEmpty() -> null
            ts == prevTs -> 0f
            x10 < 0 || x10 > 2400 -> null      // di atas 240 FPS = angka ngawur (mis. daftar layer berubah)
            else -> (x10 / 10f).coerceAtMost(maxHz)   // FPS tidak mungkin melebihi refresh rate layar
        }
        if (ts.isNotEmpty()) prevTs = ts

        var cpu: Int? = null
        val parts = m["cpu"].orEmpty().split(Regex("\\s+")).filter { it.isNotEmpty() }
        if (parts.size >= 9 && parts[0] == "cpu") {
            val v = parts.drop(1).take(8).map { it.toLongOrNull() ?: 0L }
            val total = v.sum()
            val idle = v[3] + v[4]
            val dt = total - cpuTotal
            val di = idle - cpuIdle
            if (cpuTotal > 0L && dt > 0L) cpu = (((dt - di) * 100) / dt).toInt().coerceIn(0, 100)
            cpuTotal = total
            cpuIdle = idle
        }
        val gpu = m["gpu"]?.toIntOrNull()?.coerceIn(0, 100)
        val gpuMhz = m["gpu_freq"]?.toIntOrNull()?.takeIf { it in 1..5000 }
        val soc = m["soc_mc"]?.toIntOrNull() ?: 0
        val bat = m["temp_mc"]?.toIntOrNull() ?: 0
        // suhu ngawur (> 105 C, sensor error) dibuang supaya tidak merusak grafik/statistik
        val socC = (soc / 1000f).takeIf { it in 1f..105f }
        val batC = (bat / 1000f).takeIf { it in 1f..105f }
        val t = socC ?: batC
        val sm = Sample(fps, gpu, gpuMhz, cpu, t, socC, batC, jankAcc, bigAcc, maxAcc)
        jankAcc = 0; bigAcc = 0; maxAcc = 0
        return sm
    }

    @Suppress("DEPRECATION")
    /** Refresh rate tertinggi yang didukung layar; FPS yang terbaca tidak boleh melewatinya. */
    private val maxHz: Float by lazy {
        try { wm.defaultDisplay.supportedModes.maxOf { it.refreshRate }.coerceIn(30f, 240f) } catch (_: Throwable) { 120f }
    }

    private fun hzNow(): Int = try { Math.round(wm.defaultDisplay.refreshRate) } catch (_: Throwable) { 60 }

    private fun apply(s: Sample) {
        if (prefs.bubbleHidden) return
        if (recOn) tickTimer()
        if (csvOn) csvRow(s)
        // tahan angka FPS terakhir yang valid 2,5 dtk supaya tidak berkedip ke 0/-- saat sampel meleset
        val nowMs = SystemClock.uptimeMillis()
        val raw = s.fps
        if (raw != null && raw >= 1f) { holdFps = raw; holdAt = nowMs }
        val shown: Float? = if ((raw == null || raw < 1f) && holdFps > 0f && nowMs - holdAt < 2500L && idleRun < 3) holdFps else raw
        val fpsText = when {
            !prefs.flMFps -> null
            shown == null -> hzNow().toString()   // tidak ada pembaca FPS (app biasa): tampilkan refresh rate layar
            else -> shown.toInt().toString()
        }
        val fv = s.fps
        if (fv != null && fv >= 1f) {
            if (sesPkg.isNotEmpty() && sesFps.size < 7200) {
                sesFps.add(fv); if (odOn) sesOvdTicks++
                sesJank += s.jank; sesBig += s.bigJank
                if (s.maxFtMs > sesMaxFt) sesMaxFt = s.maxFtMs
                val w = readWatt10()
                if (w > 0) { sesWattSum += w; sesWattN++ }
                sesTempL.add(s.tempC ?: 0f); sesWattL.add(if (w > 0) w else 0); sesJankL.add(s.jank)
            }
            if (recOn && recFps.size < 3600) recFps.add(fv)
        }
        // Layar diam (tidak ada frame baru) memang 0 FPS; 3 detik berturut-turut ditandai IDLE supaya tidak dikira error.
        idleRun = if (s.fps != null && s.fps < 0.5f) idleRun + 1 else 0
        if (fv != null) { lastFps = fv.toInt(); for (o in orbs) o.setFps(fv) }
        if (mode == MODE_MENU) updateMenuInfo(s.tempC)
        val lbl = if (shown == null) "Hz" else if (idleRun >= 3) "IDLE" else "FPS"
        setText(fpsPillLbl, lbl)
        setText(fpsThinLbl, lbl)
        setText(fpsBigLbl, lbl)
        fpsText?.toFloatOrNull()?.let { fpsWin.addLast(it); if (fpsWin.size > 120) fpsWin.removeFirst() }
        if (mode == MODE_PANEL) {
            panelLow?.let { v -> val st = FpsSession.stats(fpsWin.toList()); setText(v, st?.second?.toString() ?: "--") }
            panelBat?.let { v ->
                val bi = ctx.registerReceiver(null, android.content.IntentFilter(android.content.Intent.ACTION_BATTERY_CHANGED))
                val lv = bi?.getIntExtra(android.os.BatteryManager.EXTRA_LEVEL, -1) ?: -1
                val sc = bi?.getIntExtra(android.os.BatteryManager.EXTRA_SCALE, 100) ?: 100
                setText(v, if (lv >= 0 && sc > 0) "${lv * 100 / sc}%" else "--")
            }
        }
        noFpsTicks = if (s.fps == null) noFpsTicks + 1 else 0
        if (prefs.flStyle >= 3) {
            // tema gaming: angka FPS menghitung naik halus (diatur di loop frame) dan berkedip merah saat patah
            if (fpsText != null) { fpsTarget = fpsText.toFloatOrNull() ?: fpsTarget; fpsTextOn = true } else fpsTextOn = false
            if (s.jank > 0 || s.bigJank > 0) flashUntil = nowMs + 450L
        } else if (fpsText != null) {
            setText(fpsPill, fpsText)
            setText(fpsMenu, fpsText)
            setText(fpsThin, fpsText)
            if (mode == MODE_PANEL) setText(fpsBig, fpsText)
        }
        if (mode != MODE_PILL && mode != MODE_MENU && s.fps != null && prefs.flGraph) graph?.add(s.fps)

        if (mode == MODE_PILL || mode == MODE_MENU) return
        // String hanya dibuat kalau angka berubah (tidak ada alokasi tiap tick).
        val cpuV = s.cpu
        if (prefs.flMCpu && cpuV != null && lastInt[0] != cpuV) metric(0, cpuV, cpuV.toString() + "%", cpuV / 100f)
        val gpuV = s.gpu
        if (prefs.flMGpu) {
            if (gpuV != null) {
                if (lastInt[1] != gpuV) metric(1, gpuV, gpuV.toString() + "%", gpuV / 100f)
            } else {
                // Kernel tanpa node beban GPU: tampilkan frekuensi (MHz). Nilai negatif = penanda mode MHz.
                val mhz = s.gpuMhz
                if (mhz != null) {
                    if (mhz > gpuMaxMhz) gpuMaxMhz = mhz
                    if (lastInt[1] != -mhz) metric(1, -mhz, (mhz * 100 / gpuMaxMhz).toString() + "%", mhz.toFloat() / gpuMaxMhz.toFloat())
                }
            }
        }
        if (prefs.flMRam) {
            val mi = ActivityManager.MemoryInfo()
            am.getMemoryInfo(mi)
            if (mi.totalMem > 0) {
                val used = ((mi.totalMem - mi.availMem) * 10 / 1_073_741_824L).toInt()
                if (lastInt[2] != used) metric(2, used, (used / 10).toString() + "." + (used % 10) + "G", (mi.totalMem - mi.availMem).toFloat() / mi.totalMem.toFloat())
            }
        }
        if (prefs.flMBatt && thinBatV != null) {
            val bi = ctx.registerReceiver(null, android.content.IntentFilter(android.content.Intent.ACTION_BATTERY_CHANGED))
            val lv = bi?.getIntExtra(android.os.BatteryManager.EXTRA_LEVEL, -1) ?: -1
            val sc = bi?.getIntExtra(android.os.BatteryManager.EXTRA_SCALE, 100) ?: 100
            if (lv >= 0 && sc > 0) {
                val pct = lv * 100 / sc
                if (pct != lastBat) { lastBat = pct; setText(thinBatV, pct.toString() + "%") }
            }
        }
        val tempV = s.tempC
        if (prefs.flMTemp && tempV != null) {
            val t = tempV.toInt()
            if (lastInt[3] != t) metric(3, t, t.toString() + "\u00B0", (t / 100f).coerceIn(0f, 1f))
        }
    }

    private fun metric(idx: Int, value: Int, text: String, frac: Float) {
        if (lastInt[idx] != value) {
            lastInt[idx] = value
            setText(valViews[idx], text)
            setText(thinVals[idx], text)
        }
        val bar = barViews[idx] ?: return
        if (abs(bar.frac - frac) > 0.004f) {
            bar.frac = frac
            bar.invalidate()
        }
    }

    private fun tickTimer() {
        val start = recStart
        val secs = if (start > 0L) ((SystemClock.elapsedRealtime() - start) / 1000L).toInt() else 0
        val mm = secs / 60
        val ss = secs % 60
        val txt = (if (mm < 10) "0" else "") + mm + ":" + (if (ss < 10) "0" else "") + ss
        val tv = topRow?.findViewWithTag<TextView>("timer")
        setText(tv, txt)
    }

    // ---------------- jendela ----------------

    private fun build() {
        if (!started) {
            started = true
            mode = MODE_PILL
        }
        val f = FrameLayout(ctx)
        builtLand = landscape()
        pill = buildPill()
        menu = buildMenu()
        panel = buildPanel()
        thin = buildThin()
        pill?.layoutParams = FrameLayout.LayoutParams(FrameLayout.LayoutParams.WRAP_CONTENT, FrameLayout.LayoutParams.WRAP_CONTENT)
        thin?.layoutParams = FrameLayout.LayoutParams(FrameLayout.LayoutParams.WRAP_CONTENT, FrameLayout.LayoutParams.WRAP_CONTENT)
        f.addView(pill)
        f.addView(menu)
        f.addView(panel)
        f.addView(thin)
        val sv = ScanView(); sv.visibility = View.GONE; scanView = sv
        f.addView(sv, FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT))
        root = f
        paintSeg()
        applyRec()
        applyMetrics()
        applyMode()
        touch(f)
    }

    private fun addWindow() {
        // jendela hilang tanpa kita minta (sistem membuangnya): anggap belum terpasang, pasang ulang
        // (beri waktu 3 dtk setelah addView: isAttachedToWindow baru true di frame berikutnya)
        if (attached && root?.isAttachedToWindow == false && SystemClock.uptimeMillis() - addedAt > 3000L) {
            try { root?.let { wm.removeViewImmediate(it) } } catch (_: Exception) { }
            attached = false; lp = null
        }
        if (attached) return
        val r = root ?: return
        if (!Settings.canDrawOverlays(ctx)) return
        if (gameFg) ensureProbe()
        val p = WindowManager.LayoutParams(
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
                WindowManager.LayoutParams.FLAG_WATCH_OUTSIDE_TOUCH or
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
                WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
            PixelFormat.TRANSLUCENT,
        )
        p.gravity = Gravity.TOP or Gravity.START
        fullDisplay(p)
        p.x = savedX()
        p.y = savedY()
        if (prefs.flStyle == 2 && Build.VERSION.SDK_INT >= 31) {
            // kaca: blur latar jika ROM mengizinkan (kalau tidak, tetap tembus pandang)
            p.flags = p.flags or WindowManager.LayoutParams.FLAG_BLUR_BEHIND
            p.blurBehindRadius = 28
        }
        lp = p
        try {
            wm.addView(r, p)
            attached = true
            if (!shownOnce) {
                shownOnce = true
                for (o in orbs) o.appear()
                SoundFx.play(prefs, "wheelin")
            }
            if (mode == MODE_PANEL) { applyMode(); anchorPanel() }
            addedAt = SystemClock.uptimeMillis()
            markActive()
            startLoop()
        } catch (_: Exception) {
            // "sudah ditambahkan": jendela memang ada, jangan kehilangan lp/attached (itu yang mematikan geser)
            attached = r.parent != null || r.isAttachedToWindow
            if (attached) lp = p
            return
        }
        r.post { clamp() }
    }

    private var shownOnce = false

    private fun removeWindow() {
        shownOnce = false
        stopLoop()
        root?.let { v -> if (attached) try { wm.removeView(v) } catch (_: Exception) { } }
        attached = false
        lp = null
    }

    /**
     * Jendela probe transparan seluas layar. Ukurannya yang dipakai untuk batas
     * geser, karena HP ini kadang melaporkan metrik portrait saat game landscape.
     */
    /**
     * Jendela probe seluas layar HANYA dipasang saat game di depan. Di app biasa (Play Store dll.) jendela
     * seluas layar membuat Android menganggap layar "tertutup" dan app sensitif mengabaikan semua sentuhan.
     */
    private var gameFg = false
    private fun syncProbe(game: Boolean) {
        if (game == gameFg) return
        gameFg = game
        if (prefs.flAutoLog) {
            if (game && !csvOn) { toggleFpsLog(); autoLogged = true }
            else if (!game && csvOn && autoLogged) { toggleFpsLog(); autoLogged = false }
        }
        if (game) {
            if (attached) ensureProbe()
        } else if (probeOn) {
            try { wm.removeView(probe) } catch (_: Exception) { }
            probeOn = false
            screenW = 0; screenH = 0
            if (attached) repos()
        }
    }

    /** Kembalikan posisi sesuai bentuk: panel gaming dipasang ulang ke titik tengah/tepinya, bentuk lain ke posisi tersimpan. */
    private fun repos() {
        if (mode == MODE_PANEL && prefs.flStyle >= 3) { anchorPanel(); return }
        lp?.let { q -> q.x = savedX(); q.y = savedY() }
        clamp()
    }

    private fun ensureProbe() {
        if (probeOn) return
        val p = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE or
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
                WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
            PixelFormat.TRANSLUCENT,
        )
        p.gravity = Gravity.TOP or Gravity.START
        fullDisplay(p)
        // Android 12+: overlay seluas layar dengan alpha jendela > 0,8 dianggap "menutupi" app di belakangnya,
        // dan app sensitif (Play Store: profil/pembayaran) lalu mengabaikan semua sentuhan = tampak beku.
        // Jendela probe isinya kosong, jadi alpha rendah tidak mengubah tampilan tapi membuat sentuhan lolos.
        p.alpha = 0.1f
        try {
            wm.addView(probe, p)
            probeOn = true
        } catch (_: Exception) {
            probeOn = false
            return
        }
        probe.addOnLayoutChangeListener { v, _, _, _, _, _, _, _, _ ->
            if (v.width > 0 && v.height > 0 && (v.width != screenW || v.height != screenH)) {
                screenW = v.width
                screenH = v.height
                if (attached && landscape() != builtLand) {
                    rebuild()
                } else if (attached) {
                    repos()
                }
            }
        }
    }

    private fun landscape(): Boolean {
        val w = realW()
        val h = realH()
        return w > h
    }

    private fun savedX(): Int = if (landscape()) prefs.flXl else prefs.flXp
    private fun savedY(): Int = if (landscape()) prefs.flYl else prefs.flYp

    private fun savePos() {
        val p = lp ?: return
        if (mode == MODE_PANEL && prefs.flStyle >= 3) return
        val off = if (mode == MODE_MENU) menuPad() else 0
        if (landscape()) {
            prefs.flXl = p.x + off
            prefs.flYl = p.y + off
        } else {
            prefs.flXp = p.x + off
            prefs.flYp = p.y + off
        }
    }

    /** Ukuran layar fisik saat ini (termasuk area poni/lubang kamera), searah rotasi. Jendela overlay memakai koordinat ini. */
    private fun realBounds(): android.graphics.Rect {
        return try {
            if (Build.VERSION.SDK_INT >= 30) wm.maximumWindowMetrics.bounds
            else { val m = android.util.DisplayMetrics(); @Suppress("DEPRECATION") wm.defaultDisplay.getRealMetrics(m); android.graphics.Rect(0, 0, m.widthPixels, m.heightPixels) }
        } catch (_: Exception) { android.graphics.Rect(0, 0, ctx.resources.displayMetrics.widthPixels, ctx.resources.displayMetrics.heightPixels) }
    }
    /** Tepi atas/bawah yang aman (poni, status bar) hanya untuk potret; lanskap tetap rapat ke tepi. */
    private fun safeTopBottom(): IntArray {
        val z = intArrayOf(0, 0)
        if (realH() <= realW() || Build.VERSION.SDK_INT < 30) return z
        return try {
            val wi = wm.currentWindowMetrics.windowInsets
            val a = wi.getInsetsIgnoringVisibility(android.view.WindowInsets.Type.statusBars() or android.view.WindowInsets.Type.displayCutout())
            val n = wi.getInsetsIgnoringVisibility(android.view.WindowInsets.Type.navigationBars())
            intArrayOf(a.top, n.bottom)
        } catch (_: Exception) { z }
    }
    private fun realW(): Int = realBounds().width()
    private fun realH(): Int = realBounds().height()

    /** Jendela memakai seluruh layar fisik (termasuk area poni/lubang kamera), supaya koordinat overlay dan probe sama. */
    private fun fullDisplay(p: WindowManager.LayoutParams) {
        if (Build.VERSION.SDK_INT >= 28) {
            p.layoutInDisplayCutoutMode = if (Build.VERSION.SDK_INT >= 30)
                WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_ALWAYS
            else WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
        }
    }

    private fun clamp() {
        if (mode == MODE_PANEL && prefs.flStyle >= 3) return   // posisi panel diatur anchorPanel()
        val r = root ?: return
        val p = lp ?: return
        if (!attached) return
        val sw = realW()
        val sh = realH()
        p.x = p.x.coerceIn(0, max(0, sw - r.width))
        p.y = p.y.coerceIn(0, max(0, sh - r.height))
        try { wm.updateViewLayout(r, p) } catch (_: Exception) { }
    }

    private fun moveTo(x: Int, y: Int) {
        val r = root ?: return
        val p = lp ?: return
        if (!attached) return
        p.x = x
        p.y = y
        try { wm.updateViewLayout(r, p) } catch (_: Exception) { }
    }

    private fun touch(v: View) {
        val slop = ViewConfiguration.get(ctx).scaledTouchSlop
        var dx = 0f
        var dy = 0f
        var sx = 0
        var sy = 0
        var moved = false
        var downAt = 0L
        v.setOnTouchListener { _, e ->
            when (e.actionMasked) {
                MotionEvent.ACTION_OUTSIDE -> {
                    if (mode == MODE_MENU) setMode(MODE_PILL)
                    false
                }
                MotionEvent.ACTION_DOWN -> {
                    if (mode == MODE_MENU) {
                        // area kosong di sekitar menu: tutup menu dan jangan telan sentuhan
                        val c = px(MENU_BOX) / 2f
                        val d = Math.hypot((e.x - c).toDouble(), (e.y - c).toDouble())
                        if (d > px(orbDp()) / 2f + px(4)) { setMode(MODE_PILL); return@setOnTouchListener false }
                    }
                    markActive()
                    snapping = false
                    dx = e.rawX
                    dy = e.rawY
                    sx = lp?.x ?: 0
                    sy = lp?.y ?: 0
                    moved = false
                    downAt = SystemClock.uptimeMillis()
                    true
                }
                MotionEvent.ACTION_MOVE -> {
                    val mx = e.rawX - dx
                    val my = e.rawY - dy
                    if (!moved && (abs(mx) > slop || abs(my) > slop)) moved = true
                    if (moved) moveTo(sx + mx.toInt(), sy + my.toInt())
                    true
                }
                MotionEvent.ACTION_UP -> {
                    val held = SystemClock.uptimeMillis() - downAt
                    if (moved) {
                        savePos()
                        clamp()
                        markActive()
                        if (mode == MODE_PILL) startSnap()
                    } else if (held >= 500L) {
                        cycleMode()
                    } else {
                        val now = SystemClock.uptimeMillis()
                        if (now - lastTapAt < 300L && mode == MODE_PILL) {
                            lastTapAt = 0L
                            pendingToggle?.let { v.removeCallbacks(it) }
                            onRec?.invoke()
                        } else {
                            lastTapAt = now
                            val r = Runnable { toggle() }
                            pendingToggle = r
                            if (mode == MODE_PILL) v.postDelayed(r, 290L) else r.run()
                        }
                    }
                    true
                }
                MotionEvent.ACTION_CANCEL -> {
                    if (moved) {
                        savePos()
                        clamp()
                    }
                    true
                }
                else -> false
            }
        }
    }

    // ---------------- animasi (jam sendiri, tidak bergantung skala animator sistem) ----------------

    private var lastActive = 0L
    private var loopOn = false
    private var lastTick = 0L
    private var menuT0 = 0L
    private var snapping = false
    private var snapT0 = 0L
    private var snapFrom = 0
    private var snapTo = 0
    private var flashT0 = 0L
    private var dimA = 1f
    private var lastTapAt = 0L
    private var pendingToggle: Runnable? = null

    private fun markActive() {
        lastActive = SystemClock.uptimeMillis()
        if (dimA < 1f) { dimA = 1f; root?.alpha = 1f }
    }

    private fun startLoop() {
        if (loopOn) return
        loopOn = true
        root?.postOnAnimation(frame)
    }

    private fun stopLoop() {
        loopOn = false
        root?.removeCallbacks(frame)
    }

    private fun easeOutBack(t: Float): Float {
        val c1 = 1.70158f
        val c3 = c1 + 1f
        val u = t - 1f
        return 1f + c3 * u * u * u + c1 * u * u
    }

    private fun easeOut(t: Float): Float { val u = 1f - t; return 1f - u * u * u }

    private fun startSnap() {
        val r = root ?: return
        val p = lp ?: return
        val sw = realW()
        val margin = px(4)
        snapFrom = p.x
        snapTo = if (p.x + r.width / 2 < sw / 2) margin else sw - r.width - margin
        if (snapTo == snapFrom) return
        snapT0 = SystemClock.uptimeMillis()
        snapping = true
    }

    private fun startMenuPop() {
        menuT0 = SystemClock.uptimeMillis()
        popFrame(menuT0)
    }

    /** Tombol menu muncul berurutan dari pusat orb (ease-out-back), kartu info menyusul. */
    private fun popFrame(now: Long): Boolean {
        if (menuBtns.isEmpty()) return false
        val el = now - menuT0
        var busy = false
        val boxC = px(MENU_BOX) / 2f
        for ((i, b) in menuBtns.withIndex()) {
            val t = ((el - i * 55L) / 280f).coerceIn(0f, 1f)
            val e = easeOutBack(t)
            val lpb = b.layoutParams as FrameLayout.LayoutParams
            val bc = lpb.leftMargin + b.width.coerceAtLeast(px(52)) / 2f
            val bcy = lpb.topMargin + b.height.coerceAtLeast(px(52)) / 2f
            b.scaleX = e; b.scaleY = e
            b.alpha = (t * 2.2f).coerceIn(0f, 1f)
            b.translationX = (boxC - bc) * (1f - e)
            b.translationY = (boxC - bcy) * (1f - e)
            if (t < 1f) busy = true
        }
        menuInfo?.alpha = ((el - 120L) / 220f).coerceIn(0f, 1f)
        if (el < 400L) busy = true
        return busy
    }

    private var enterT0 = 0L
    private var enterPending = false
    private var lastOrient = 0L
    private val frame = object : Runnable {
        override fun run() {
            if (!loopOn) return
            val now = SystemClock.uptimeMillis()
            val r = root
            if (r == null || !attached) { loopOn = false; return }
            // layar diputar saat floating sudah dibangun: bangun ulang sesuai ukuran/orientasi baru (dihitung dari layar fisik)
            if (now - lastOrient > 400L) {
                lastOrient = now
                if (landscape() != builtLand) { loopOn = false; r.post { rebuild() }; return }
            }
            // masuk panel/kapsul: membesar halus + memudar masuk (jam sendiri, tidak ikut skala animasi sistem)
            if (enterT0 != 0L) {
                val v: View? = if (mode == MODE_PANEL) panel else if (mode == MODE_THIN) thin else null
                if (v != null) {
                    val st = prefs.flStyle
                    val t = if (prefs.reduceAnim) 1f else ((now - enterT0) / (if (st >= 3 && v === panel) 180f else 160f)).coerceIn(0f, 1f)
                    val e = easeOut(t)
                    if (st >= 3 && v === panel) {
                        // tema gaming: panel meluncur masuk dari tepinya sendiri
                        v.alpha = e
                        v.scaleX = 1f; v.scaleY = 1f; v.translationX = 0f; v.translationY = 0f
                        if (t >= 1f) { v.alpha = 1f; enterT0 = 0L }
                    } else {
                    v.alpha = e
                    val sc = 0.92f + 0.08f * e
                    v.pivotX = 0f; v.pivotY = 0f
                    v.scaleX = sc; v.scaleY = sc
                    if (t >= 1f) { v.alpha = 1f; v.scaleX = 1f; v.scaleY = 1f; enterT0 = 0L }
                    }
                } else enterT0 = 0L
            }
            if (mode == MODE_MENU) {
                popFrame(now)
                if (now - lastActive > 5000L) setMode(MODE_PILL)
            }
            if (snapping) {
                val t = ((now - snapT0) / 240f).coerceIn(0f, 1f)
                moveTo(snapFrom + ((snapTo - snapFrom) * easeOut(t)).toInt(), lp?.y ?: 0)
                if (t >= 1f) { snapping = false; savePos() }
            }
            // redup setelah 5 dtk diam (hanya bentuk orb)
            val wantDim = if (mode == MODE_PILL && now - lastActive > 5000L) 0.45f else 1f
            if (kotlin.math.abs(dimA - wantDim) > 0.01f) {
                dimA += (wantDim - dimA) * 0.12f
                r.alpha = dimA
            }
            if (now - lastTick >= 90L) {
                lastTick = now
                for (o in orbs) o.tick(now)
                if (prefs.flStyle >= 3 && fpsTextOn) {
                    fpsDisp = fpsTarget   // angka FPS langsung, tanpa animasi
                    val txt = fpsDisp.toInt().toString()
                    val fl = now < flashUntil
                    setText(fpsPill, txt); setText(fpsMenu, txt); setText(fpsThin, txt)
                    if (mode == MODE_PANEL) setText(fpsBig, txt)
                    if (fl != flashOn) {
                        flashOn = fl
                        val col = if (fl) RED else TEXT
                        fpsPill?.setTextColor(col); fpsMenu?.setTextColor(col); fpsThin?.setTextColor(col); fpsBig?.setTextColor(col)
                    }
                }
                val sv = scanView
                if (sv != null && sv.visibility == View.VISIBLE) {
                    val t = (now - scanT0) / 520f
                    if (t >= 1f) sv.visibility = View.GONE else { sv.pos = t; sv.invalidate() }
                }
            }
            // animasi mati: tidak minta frame tiap vsync kalau tidak ada yang bergerak
            val moving = enterT0 != 0L || snapping || mode == MODE_MENU || scanView?.visibility == View.VISIBLE || kotlin.math.abs(dimA - wantDim) > 0.01f
            if (!moving) r.postDelayed(this, if (prefs.reduceAnim) 250L else 100L) else r.postOnAnimation(this)
        }
    }

    private fun hide() {
        prefs.bubbleHidden = true
        onHidden?.invoke()
        Toast.makeText(ctx, "Orb disembunyikan. Munculkan lagi lewat notifikasi.", Toast.LENGTH_LONG).show()
    }

    private fun orbDp(): Int = ORB

    private fun menuPad(): Int = (px(MENU_BOX) - px(orbDp())) / 2

    private fun setMode(n: Int) {
        val old = mode
        if (old == n) return
        val p = lp
        if (p != null && attached) {
            if (old == MODE_PANEL && prefs.flStyle >= 3) { p.x = savedX(); p.y = savedY() }
            if (old == MODE_MENU) { p.x += menuPad(); p.y += menuPad() }
            if (n == MODE_MENU) { p.x -= menuPad(); p.y -= menuPad() }
        }
        mode = n
        if (n == MODE_PANEL) { SoundFx.play(prefs, "wheelin"); panelWheel?.appear() } else if (n == MODE_MENU) SoundFx.play(prefs, "tap") else if (old == MODE_MENU || old == MODE_PANEL) SoundFx.play(prefs, "tap")
        applyMode()
        if (n == MODE_PANEL && prefs.flStyle >= 3) { panel?.alpha = 0f; enterT0 = 0L; enterPending = true; markActive() }
        else if (n == MODE_PANEL || n == MODE_THIN) { enterT0 = SystemClock.uptimeMillis(); markActive() }
        if (n == MODE_PANEL) {
            anchorPanel()
            // cadangan: kalau pendengar layout tidak sempat menyala, mulai animasi masuk juga
            root?.postDelayed({ if (enterPending) { enterPending = false; enterT0 = SystemClock.uptimeMillis() } }, 300L)
        }
        if (n == MODE_MENU) { layoutMenu(); markActive(); startMenuPop() }
        else for (b in menuBtns) { b.scaleX = 1f; b.scaleY = 1f; b.alpha = 1f; b.translationX = 0f; b.translationY = 0f }
        root?.post { clamp() }
    }

    private fun toggle() {
        setMode(if (mode == MODE_PILL) MODE_PANEL else MODE_PILL)
    }

    private fun openDetail() {
        setMode(if (prefs.flStartThin) MODE_THIN else MODE_PANEL)
    }

    /** Putar mode: Hemat > Seimbang > Performa > Puncak > Hemat. */
    private fun cycleMode() {
        // Dua mode saja: Adapt <-> Puncak
        if (odOn) {
            onOvd?.invoke(false)
            onProfile?.invoke("adapt")
            return
        }
        if (odAvail) onOvd?.invoke(true) else onProfile?.invoke("adapt")
    }

    private fun modeName(): String = if (odOn) "Puncak" else "Adapt"

    private fun updateMenuInfo(tempC: Float?) {
        val t = if (tempC != null) " \u00B7 " + tempC.toInt() + "\u00B0" else ""
        setText(menuInfo, modeName() + t)
    }

    /** Tombol melingkar di sisi yang lega (kiri/kanan layar). */
    private fun layoutMenu() {
        val m = menu ?: return
        val sw = realW()
        val cxScreen = (lp?.x ?: 0) + px(MENU_BOX) / 2
        val right = cxScreen < sw / 2
        val base = if (right) 0.0 else 180.0
        val angs = doubleArrayOf(-62.0, -21.0, 21.0, 62.0)
        val c = px(MENU_BOX) / 2f
        val shH = realH()
        val cyScreen = (lp?.y ?: 0) + px(MENU_BOX) / 2
        // dekat tepi atas/bawah layar: putar sebaran tombol ke arah yang lega (hindari bar atas game)
        val vShift = when { cyScreen < px(MENU_R + 70) -> 38.0; cyScreen > shH - px(MENU_R + 70) -> -38.0; else -> 0.0 }
        val r = pf(MENU_R)
        for ((i, b) in menuBtns.withIndex()) {
            val a = Math.toRadians(base + (if (right) angs[i] + vShift else -(angs[i] + vShift)))
            val half = px(52) / 2f
            val lpb = b.layoutParams as FrameLayout.LayoutParams
            lpb.leftMargin = (c + r * Math.cos(a) - half).toInt()
            lpb.topMargin = (c + r * Math.sin(a) - half).toInt()
            b.layoutParams = lpb
        }
        val ib = menuInfo
        if (ib != null) {
            val lpi = ib.layoutParams as FrameLayout.LayoutParams
            lpi.gravity = Gravity.TOP or Gravity.CENTER_HORIZONTAL
            lpi.topMargin = if (vShift > 0.0) (c + pf(orbDp()) / 2f + pf(8)).toInt() else (c - pf(orbDp()) / 2f - pf(8) - px(26)).toInt()
            ib.layoutParams = lpi
        }
        paintMenu()
        m.requestLayout()
    }

    private fun paintMenu() {
        if (menuBtns.size < 4) return
        val acc = accentColor()
        menuBtns[0].apply {
            text = if (odOn) "PUN" else "ADP"
            setTextColor(Color.BLACK)
            background = roundBg(acc, pf(26), 0)
        }
        menuBtns[1].apply {
            text = "FPS"
            setTextColor(if (csvOn) Color.WHITE else TEXT)
            background = roundBg(if (csvOn) 0xFFE5484D.toInt() else 0xE61B1B1E.toInt(), pf(26), if (csvOn) 0 else acc)
        }
        menuBtns[2].apply {
            text = if (recOn) "STOP" else "REC"
            setTextColor(Color.WHITE)
            background = roundBg(if (recOn) 0xFFE5484D.toInt() else 0xE61B1B1E.toInt(), pf(26), 0xFFE5484D.toInt())
        }
        menuBtns[3].apply {
            text = "INFO"
            setTextColor(TEXT)
            background = roundBg(0xE61B1B1E.toInt(), pf(26), BORDER)
        }
        for (o in orbs) { o.accent = acc; o.invalidate() }
    }

    private fun menuBtn(onClick: () -> Unit): TextView =
        textView("", 10f, TEXT, true).apply {
            gravity = Gravity.CENTER
            letterSpacing = 0.04f
            isClickable = true
            setOnClickListener { markActive(); onClick() }
        }

    private fun buildMenu(): FrameLayout {
        val m = FrameLayout(ctx)
        m.layoutParams = FrameLayout.LayoutParams(px(MENU_BOX), px(MENU_BOX))
        val acts = listOf<() -> Unit>({ cycleMode() }, { toggleFpsLog() }, { onRec?.invoke() }, { openDetail() })
        for (a in acts) {
            val b = menuBtn(a)
            m.addView(b, FrameLayout.LayoutParams(px(52), px(52)))
            menuBtns.add(b)
        }
        // tahan tombol mode = langsung ke Puncak
        menuBtns[0].setOnLongClickListener {
            markActive()
            if (odOn) Toast.makeText(ctx, "✓ " + trn("Sudah di mode Puncak"), Toast.LENGTH_SHORT).show()
            else if (odAvail) onOvd?.invoke(true)
            else Toast.makeText(ctx, "ℹ " + trn("Puncak hanya aktif saat game berjalan"), Toast.LENGTH_SHORT).show()
            true
        }
        val info = textView("", 11f, TEXT, true).apply {
            gravity = Gravity.CENTER
            setPadding(px(10), px(3), px(10), px(3))
            background = roundBg(0xCC141416.toInt(), pf(10), 0)
        }
        menuInfo = info
        m.addView(info, FrameLayout.LayoutParams(FrameLayout.LayoutParams.WRAP_CONTENT, FrameLayout.LayoutParams.WRAP_CONTENT))
        val orb = buildOrb(true)
        val olp = FrameLayout.LayoutParams(px(orbDp()), px(orbDp()))
        olp.leftMargin = (px(MENU_BOX) - px(orbDp())) / 2
        olp.topMargin = olp.leftMargin
        m.addView(orb, olp)
        return m
    }

    private fun applyMode() {
        pill?.visibility = if (mode == MODE_PILL) View.VISIBLE else View.GONE
        menu?.visibility = if (mode == MODE_MENU) View.VISIBLE else View.GONE
        panel?.visibility = if (mode == MODE_PANEL) View.VISIBLE else View.GONE
        thin?.visibility = if (mode == MODE_THIN) View.VISIBLE else View.GONE
        for (i in lastInt.indices) lastInt[i] = -1
        if (mode == MODE_PANEL) graph?.clear()
        applyTouchFlags()
    }

    /** Bar ringkas bisa dibuat tembus sentuh (tampil saja) supaya tidak menghalangi layar game. */
    private fun applyTouchFlags() {
        val p = lp ?: return
        val r = root ?: return
        if (!attached) return
        val through = mode == MODE_THIN && prefs.flBarThrough
        val nf = if (through) p.flags or WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE else p.flags and WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE.inv()
        if (nf != p.flags) { p.flags = nf; try { wm.updateViewLayout(r, p) } catch (_: Exception) { } }
    }

    // ---------------- tampilan ----------------

    private fun panelColor(): Int {
        val a = (prefs.flAlpha / 100f * 255).toInt().coerceIn(0, 255)
        return when (prefs.flStyle) {
            1 -> Color.argb(maxOf(a, 200), 11, 13, 16)          // HUD: hampir hitam pekat
            2 -> Color.argb((a * 0.42f).toInt().coerceAtLeast(70), 255, 255, 255)  // kaca: putih tembus
            3 -> Color.argb(maxOf(a, 215), 12, 15, 26)           // Kartu Miring
            4 -> Color.argb(maxOf(a, 215), 12, 12, 18)           // Dasbor Bundar
            5 -> Color.argb(maxOf(a, 225), 7, 9, 15)             // Kubus Energi
            else -> Color.argb(a, 20, 20, 22)
        }
    }

    /** Warna neon tiap tema gaming: 3 cyan, 4 merah, 5 cyan terang. */
    private fun themeNeon(st: Int): Int = when (st) { 4 -> 0xFFFF1F3D.toInt(); 3 -> 0xFF22D3EE.toInt(); else -> 0xFF2DE0FF.toInt() }

    private fun accentColor(): Int {
        if (odOn) return OD
        if (prefs.flAccentFixed) return prefs.flAccentColor
        return P_ADAPT
    }

    private fun roundBg(colorIn: Int, radiusIn: Float, strokeIn: Int): GradientDrawable {
        var color = colorIn; var radius = radiusIn; var stroke = strokeIn
        when (prefs.flStyle) {
            1 -> {                                   // HUD: sudut kecil, garis tipis
                radius *= 0.55f
                if (color == CARD) color = 0x0DFFFFFF
            }
            2 -> {                                   // kaca: sudut besar, garis terang
                radius *= 1.15f
                if (color == CARD) color = 0x24FFFFFF
                if (stroke == BORDER) stroke = 0x4DFFFFFF
            }
        }
        val st = prefs.flStyle
        if (st >= 3) {                               // tema gaming: sudut tajam + garis neon warna tema
            radius *= if (st == 4) 0.9f else 0.3f
            if (color == CARD) color = 0x1AFFFFFF
            if (stroke == BORDER) stroke = themeNeon(st)
        }
        return GradientDrawable().apply {
            setColor(color)
            cornerRadius = radius
            if (stroke != 0) setStroke(if (st >= 3) px(2) else px(1), stroke)
        }
    }

    private fun textView(s: String, sizePx: Float, color: Int, bold: Boolean): TextView =
        TextView(ctx).apply {
            text = trn(s)
            setTextColor(color)
            setTextSize(TypedValue.COMPLEX_UNIT_PX, pf(sizePx))
            typeface = Typeface.create("sans-serif", if (bold) Typeface.BOLD else Typeface.NORMAL)
            includeFontPadding = false
            gravity = Gravity.CENTER_VERTICAL
        }

    private fun setText(tv: TextView?, s: String) {
        if (tv != null && tv.text.toString() != s) tv.text = s
    }

    private fun fpsLabel(sizePx: Float, spacing: Float): TextView =
        textView("FPS", sizePx, LABEL, true).apply { letterSpacing = spacing }

    private fun buildPill(): View = buildOrb(false)

    /** Orb HSIN: cincin FPS (penuh = 90 FPS) berwarna sesuai mode, angka FPS di tengah. */
    private fun buildOrb(forMenu: Boolean): View {
        val f = FrameLayout(ctx)
        val orb = OrbView()
        orbs.add(orb)
        f.addView(orb, FrameLayout.LayoutParams(px(orbDp()), px(orbDp())))
        val b = textView("--", 15f, TEXT, true).apply { gravity = Gravity.CENTER; letterSpacing = -0.04f }
        if (forMenu) fpsMenu = b else fpsPill = b
        f.addView(b, FrameLayout.LayoutParams(px(orbDp()), px(orbDp())))
        val tag = textView("", 8f, P_ADAPT, true).apply { gravity = Gravity.CENTER }
        loadTags.add(tag)
        paintLoadTag(tag)
        f.addView(tag, FrameLayout.LayoutParams(px(orbDp()), px(orbDp())).apply { topMargin = px(orbDp() * 0.30f.toInt().coerceAtLeast(0) + 11) })
        f.layoutParams = FrameLayout.LayoutParams(px(orbDp()), px(orbDp()))
        return f
    }

    private fun buildThin(): View {
        val row = LinearLayout(ctx).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(px(8), 0, px(6), 0)
            background = roundBg(panelColor(), pf(26), BORDER)
            minimumHeight = px(46)
        }
        val ring = RingView(32, accentColor())
        rings.add(ring)
        row.addView(ring)
        val b = textView("--", 24f, TEXT, true).apply { letterSpacing = -0.02f }
        fpsThin = b
        row.addView(b, LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT).apply { marginStart = px(14) })
        val l2 = fpsLabel(10f, 0.08f)
        fpsThinLbl = l2
        row.addView(l2, LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT).apply { marginStart = px(5) })
        val sep = View(ctx).apply { setBackgroundColor(0x24FFFFFF) }
        row.addView(sep, LinearLayout.LayoutParams(px(1), px(24)).apply { marginStart = px(14); marginEnd = px(14) })
        val mNames = listOf("CPU", "GPU", "RAM", "SUHU")
        val groupViews = arrayOfNulls<View>(5)
        for (i in 0 until 4) {
            val grp = LinearLayout(ctx).apply { orientation = LinearLayout.HORIZONTAL; gravity = Gravity.BOTTOM }
            grp.addView(textView(mNames[i], 10f, LABEL, true).apply { letterSpacing = 0.1f })
            val v = textView("--", 15f, TEXT, true)
            grp.addView(v, LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT).apply { marginStart = px(4) })
            thinVals[i] = v
            thinGroups[i] = grp
            groupViews[i] = grp
        }
        val bg = LinearLayout(ctx).apply { orientation = LinearLayout.HORIZONTAL; gravity = Gravity.BOTTOM }
        bg.addView(textView("BAT", 10f, LABEL, true).apply { letterSpacing = 0.1f })
        val bv = textView("--", 15f, TEXT, true)
        bg.addView(bv, LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT).apply { marginStart = px(4) })
        thinBatGrp = bg; thinBatV = bv
        bg.visibility = if (prefs.flMBatt) View.VISIBLE else View.GONE
        groupViews[4] = bg
        // urutan metrik di kapsul dipilih pengguna (huruf C G R T B)
        var firstG = true
        for (ch in prefs.flOrder) {
            val gi = "CGRTB".indexOf(ch)
            val gv = if (gi >= 0) groupViews[gi] else null
            if (gv != null && gv.parent == null) {
                row.addView(gv, LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT).apply { marginStart = if (firstG) 0 else px(14) })
                firstG = false
            }
        }
        for (gv in groupViews) if (gv != null && gv.parent == null) {
            row.addView(gv, LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT).apply { marginStart = px(14) })
        }
        val spacer = View(ctx)
        row.addView(spacer, LinearLayout.LayoutParams(0, 1, 1f))
        // tombol cepat: profil (ketuk = ganti), Overdrive, rekam data FPS
        val bp = thinBtn { 
            onProfile?.invoke("adapt")
        }
        thinProf = bp
        row.addView(bp, LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT, px(40)).apply { marginStart = px(12) })
        val bo = thinBtn { if (odOn || odAvail) onOvd?.invoke(!odOn) }
        thinOd = bo
        row.addView(bo, LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT, px(40)).apply { marginStart = px(8) })
        val bc = thinBtn { toggleFpsLog() }
        thinCsv = bc
        row.addView(bc, LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT, px(40)).apply { marginStart = px(8) })
        paintThinBtns()
        val rb = recCircle()
        row.addView(rb, LinearLayout.LayoutParams(px(44), px(44)).apply { marginStart = px(8) })
        return row
    }

    private var thinProf: TextView? = null
    private var thinOd: TextView? = null
    private var thinCsv: TextView? = null

    private fun thinBtn(onClick: () -> Unit): TextView =
        textView("", 12f, Color.WHITE, true).apply {
            gravity = Gravity.CENTER
            setPadding(px(12), 0, px(12), 0)
            isClickable = true
            setOnClickListener { onClick() }
        }

    private fun paintThinBtns() {
        thinProf?.apply {
            text = "ADAPT"
            val mc = P_ADAPT
            setTextColor(mc)
            background = roundBg((mc and 0x00FFFFFF) or 0x26000000, pf(20), (mc and 0x00FFFFFF) or 0x80000000.toInt())
        }
        thinOd?.apply {
            text = "PUNCAK"
            setTextColor(if (odOn) Color.WHITE else OD_TEXT)
            background = if (odOn) GradientDrawable(GradientDrawable.Orientation.LEFT_RIGHT, intArrayOf(OD, OD_END)).apply { cornerRadius = pf(20) }
                         else roundBg(0x1AFF4D5E, pf(20), 0x8CFF4D5E.toInt())
            alpha = if (!odOn && !odAvail) 0.5f else 1f
        }
        thinCsv?.apply {
            text = if (csvOn) "STOP" else "FPS"
            background = roundBg(if (csvOn) 0xCCE5484D.toInt() else 0x33FFFFFF, pf(20), 0)
        }
    }

    private fun recCircle(): View {
        val box = FrameLayout(ctx).apply {
            background = roundBg(0x2EE5484D, pf(22), 0)
            isClickable = true
            contentDescription = trn("Mulai rekam")
            setOnClickListener { onRec?.invoke() }
        }
        val dot = View(ctx).apply {
            background = GradientDrawable().apply { shape = GradientDrawable.OVAL; setColor(RED) }
        }
        box.addView(dot, FrameLayout.LayoutParams(px(16), px(16), Gravity.CENTER))
        return box
    }

    private fun csvButton(): View {
        val row = LinearLayout(ctx).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(px(14), 0, px(16), 0)
            background = roundBg(0x33FFFFFF, pf(22), 0)
            minimumHeight = px(44)
            isClickable = true
            setOnClickListener { toggleFpsLog() }
        }
        val dot = View(ctx)
        csvDot = dot
        row.addView(dot, LinearLayout.LayoutParams(px(12), px(12)))
        val lbl = textView(if (csvOn) "Stop FPS" else trn("Rekam FPS"), 13f, Color.WHITE, true)
        csvBtnLbl = lbl
        row.addView(lbl, LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT).apply { marginStart = px(8) })
        paintCsv()
        return row
    }

    private fun recButton(stop: Boolean): View {
        val row = LinearLayout(ctx).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(px(14), 0, px(18), 0)
            background = roundBg(RED, pf(22), 0)
            minimumHeight = px(44)
            isClickable = true
            setOnClickListener { onRec?.invoke() }
        }
        val sq = View(ctx).apply {
            background = GradientDrawable().apply {
                cornerRadius = pf(if (stop) 3 else 7)
                setColor(Color.WHITE)
            }
        }
        row.addView(sq, LinearLayout.LayoutParams(px(14), px(14)))
        row.addView(textView(if (stop) "Berhenti" else "Rekam", 14f, Color.WHITE, true), LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT).apply { marginStart = px(8) })
        return row
    }

    private fun buildPanel(): View {
        if (prefs.flStyle >= 3) return buildGamePanel(prefs.flStyle)
        val box = LinearLayout(ctx).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(px(16), px(16), px(16), px(16))
            background = roundBg(panelColor(), pf(20), BORDER)
        }
        panelBox = box
        var first = true
        fun add(v: View, m: Int = 14) {
            box.addView(v, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT).apply {
                topMargin = if (first) 0 else px(m)
            })
            first = false
        }

        val seg = LinearLayout(ctx).apply {
            orientation = LinearLayout.HORIZONTAL
            setPadding(px(4), px(4), px(4), px(4))
            background = roundBg(CARD, pf(14), 0)
        }
        segButtons = ArrayList()
        for ((i, k) in PROFILE_KEYS.withIndex()) {
            val b = textView(if (i == 0) "ADAPT" else "", 13f, SEG_TEXT, true).apply {
                gravity = Gravity.CENTER
                isClickable = true
                setOnClickListener { if (!odOn) onProfile?.invoke("adapt") }
                if (i > 0) visibility = View.GONE
            }
            seg.addView(b, LinearLayout.LayoutParams(0, px(44), 1f).apply { marginStart = if (i == 0) 0 else px(6) })
            segButtons.add(b)
        }
        val odChip = buildOdRow()
        seg.addView(odChip, LinearLayout.LayoutParams(0, px(44), 1.15f).apply { marginStart = px(6) })
        segRow = seg
        add(seg)
        val st = odSmall
        if (st != null) {
            (st.parent as? ViewGroup)?.removeView(st)
            st.textSize = 11f
            add(st, 8)
            odStatusLine = st
        }

        val top = LinearLayout(ctx).apply { orientation = LinearLayout.HORIZONTAL; gravity = Gravity.CENTER_VERTICAL }
        val dot = View(ctx).apply {
            background = GradientDrawable().apply { shape = GradientDrawable.OVAL; setColor(RED) }
        }
        top.addView(dot, LinearLayout.LayoutParams(px(12), px(12)))
        val tm = textView("00:00", 20f, TEXT, true).apply { tag = "timer"; letterSpacing = 0.02f }
        top.addView(tm, LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT).apply { marginStart = px(10) })
        top.addView(textView("REC", 11f, REC_TAG, true).apply { letterSpacing = 0.12f }, LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT).apply { marginStart = px(10) })
        top.addView(View(ctx), LinearLayout.LayoutParams(0, 1, 1f))
        top.addView(recButton(true), LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT, px(44)))
        topRow = top
        add(top)

        val big = LinearLayout(ctx).apply { orientation = LinearLayout.HORIZONTAL; gravity = Gravity.BOTTOM }
        val nb = textView("--", 60f, TEXT, true).apply { letterSpacing = -0.03f }
        fpsBig = nb
        big.addView(nb)
        val l3 = fpsLabel(13f, 0.1f)
        fpsBigLbl = l3
        big.addView(l3, LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT).apply { marginStart = px(6) })
        if (prefs.flGraph) {
            big.addView(View(ctx), LinearLayout.LayoutParams(0, 1, 1f))
            val g = GraphView(GPU)
            graph = g
            big.addView(g)
        }
        bigRow = big
        add(big)

        val grid = LinearLayout(ctx).apply { orientation = LinearLayout.HORIZONTAL }
        val names = listOf("CPU PAKAI", "GPU PAKAI", "RAM PAKAI", trn("SUHU HP"))
        for (i in 0 until 4) {
            grid.addView(card(names[i], i), LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f).apply { marginStart = if (i == 0) 0 else px(8) })
        }
        gridRow = grid
        add(grid)

        val foot = LinearLayout(ctx).apply { orientation = LinearLayout.HORIZONTAL; gravity = Gravity.CENTER_VERTICAL }
        foot.addView(recButton(false), LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT, px(44)))
        foot.addView(csvButton(), LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT, px(44)).apply { marginStart = px(8) })
        foot.addView(View(ctx), LinearLayout.LayoutParams(0, 1, 1f))
        val hint = textView("Ketuk: ringkas\nTahan: sembunyikan", 11f, HINT, false).apply {
            gravity = Gravity.END
            setLineSpacing(0f, 1.4f)
        }
        foot.addView(hint, LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT).apply { marginStart = px(12) })
        footRow = foot
        add(foot)

        val recHint = textView("Profil terkunci selama merekam. Satu sesi = satu file video.", 11f, HINT, false).apply {
            setLineSpacing(0f, 1.4f)
        }
        hintRec = recHint
        add(recHint)

        val flp = FrameLayout.LayoutParams(px(380), FrameLayout.LayoutParams.WRAP_CONTENT)
        box.layoutParams = flp
        return box
    }


    // ---------------- panel tema gaming (tata letak sendiri per tema) ----------------

    private fun panelBg(edge: Int): GradientDrawable {
        val st = prefs.flStyle
        if (st < 3) return roundBg(panelColor(), pf(20), edge)
        val edgeCol = if (edge == BORDER) 0x33FFFFFF else edge
        return GradientDrawable().apply {
            setColor(panelColor())
            cornerRadius = pf(16)
            setStroke(px(1), edgeCol)
        }
    }

    private fun lpw(w: Int, h: Int, wt: Float = 0f, ms: Int = 0, mt: Int = 0) =
        LinearLayout.LayoutParams(w, h, wt).apply { marginStart = ms; topMargin = mt }

    /** Tombol bulat bertanda (tema gaming). */
    private fun roundTile(label: String, col: Int, glyph: String, onClick: () -> Unit, list: Boolean = false): Pair<View, View> {
        val circle = FrameLayout(ctx).apply {
            background = GradientDrawable().apply { shape = GradientDrawable.OVAL; setColor(0xFF22252E.toInt()); setStroke(px(2), col) }
            isClickable = true
            setOnClickListener { markActive(); onClick() }
        }
        circle.addView(textView(glyph, 15f, col, true).apply { gravity = Gravity.CENTER }, FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT))
        val lbl = textView(label, 11f, 0xFFCFD2DD.toInt(), true).apply { gravity = Gravity.CENTER }
        val box = LinearLayout(ctx).apply {
            orientation = if (list) LinearLayout.HORIZONTAL else LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            isClickable = true
            setOnClickListener { markActive(); onClick() }
        }
        if (list) {
            box.gravity = Gravity.CENTER_VERTICAL
            box.setPadding(px(8), px(5), px(8), px(5))
            box.background = roundBg(0x14FFFFFF, pf(10), 0)
            lbl.gravity = Gravity.CENTER_VERTICAL
            box.addView(circle, LinearLayout.LayoutParams(px(32), px(32)))
            box.addView(lbl, lpw(LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT, ms = px(10)))
        } else {
            box.addView(circle, LinearLayout.LayoutParams(px(46), px(46)))
            box.addView(lbl, lpw(LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT, mt = px(4)))
        }
        return Pair(box, circle)
    }

    private fun paintTiles() {
        val rc = tileRec; val fc = tileFps
        if (rc != null) rc.background = GradientDrawable().apply { shape = GradientDrawable.OVAL; setColor(if (recOn) RED else 0xFF22252E.toInt()); setStroke(px(2), RED) }
        if (fc != null) fc.background = GradientDrawable().apply { shape = GradientDrawable.OVAL; setColor(if (csvOn) themeNeon(prefs.flStyle) else 0xFF22252E.toInt()); setStroke(px(2), themeNeon(prefs.flStyle)) }
        tileDnd?.background = GradientDrawable().apply { shape = GradientDrawable.OVAL; setColor(if (dndOn) 0xFFE8B95A.toInt() else 0xFF22252E.toInt()); setStroke(px(2), 0xFFE8B95A.toInt()) }
        val tt = themeTitle
        if (tt != null) { tt.text = trn(modeName()).uppercase(); tt.setTextColor(accentColor()) }
    }

    private fun buildSegRow(vertical: Boolean, grid: Boolean = false): LinearLayout {
        val seg = LinearLayout(ctx).apply {
            orientation = if (vertical || grid) LinearLayout.VERTICAL else LinearLayout.HORIZONTAL
            setPadding(px(4), px(4), px(4), px(4))
            background = roundBg(CARD, pf(14), 0)
        }
        segButtons = ArrayList()
        val lines = ArrayList<LinearLayout>()
        if (grid) for (r in 0 until 2) {
            val l = LinearLayout(ctx).apply { orientation = LinearLayout.HORIZONTAL }
            seg.addView(l, lpw(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT, mt = if (r == 0) 0 else px(4)))
            lines.add(l)
        }
        for ((i, k) in PROFILE_KEYS.withIndex()) {
            val b = textView(if (i == 0) "ADAPT" else "", 12f, SEG_TEXT, true).apply {
                gravity = Gravity.CENTER; isClickable = true; maxLines = 1
                setOnClickListener { if (!odOn) onProfile?.invoke("adapt") }
                if (i > 0) visibility = View.GONE
            }
            if (grid) lines[i / 2].addView(b, lpw(0, px(38), 1f, if (i % 2 == 0) 0 else px(4)))
            else if (vertical) seg.addView(b, lpw(LinearLayout.LayoutParams.MATCH_PARENT, px(36), mt = if (i == 0) 0 else px(4)))
            else seg.addView(b, lpw(0, px(40), 1f, if (i == 0) 0 else px(5)))
            segButtons.add(b)
        }
        val odChip = buildOdRow()
        if (grid) lines[1].addView(odChip, lpw(0, px(38), 1f, px(4)))
        else if (vertical) seg.addView(odChip, lpw(LinearLayout.LayoutParams.MATCH_PARENT, px(36), mt = px(4)))
        else seg.addView(odChip, lpw(0, px(40), 1.15f, px(5)))
        segRow = seg
        return seg
    }

    private var anchorL: android.view.ViewTreeObserver.OnGlobalLayoutListener? = null

    private fun anchorPanel() {
        val st = prefs.flStyle
        if (st < 3) return
        val r = root ?: return
        if (!attached) return
        val sw = realW()
        val sh = realH()
        panel?.let { pv ->
            val l = pv.layoutParams
            val want = FrameLayout.LayoutParams.WRAP_CONTENT
            if (l != null && l.height != want) { l.height = want; pv.layoutParams = l }
        }
        // pasang SATU pendengar tetap: tiap ukuran panel berubah (isi kartu, tombol rekam) posisi dihitung ulang
        anchorL?.let { try { r.viewTreeObserver.removeOnGlobalLayoutListener(it) } catch (_: Exception) { } }
        var lw = -1; var lh = -1; var lx = -1; var ly = -1
        val l = object : android.view.ViewTreeObserver.OnGlobalLayoutListener {
            override fun onGlobalLayout() {
                val p = lp ?: return
                if (mode != MODE_PANEL || !attached) return
                // yang diratakan adalah panel yang kelihatan, bukan jendela: jendela bisa lebih lebar dari panel
                val pv = panel ?: r
                var ox = 0; var oy = 0
                var v: View? = pv
                while (v != null && v !== r) { ox += v.left; oy += v.top; v = v.parent as? View }
                val w = pv.width; val h = pv.height
                if (w <= 0 || h <= 0 || (w == lw && h == lh && ox == lx && oy == ly)) return
                lw = w; lh = h; lx = ox; ly = oy
                val pos = if (prefs.flPanelPos != 0) prefs.flPanelPos else when (st) { 4 -> 2; else -> 4 }
                var tx = when (pos) { 3 -> 0; 4 -> sw - w; else -> (sw - w) / 2 }
                val si = safeTopBottom()
                var ty = when (pos) { 2 -> sh - h - si[1]; 3, 4 -> (sh - h) / 2; else -> si[0] }
                tx = tx.coerceIn(0, max(0, sw - w)) - ox; ty = ty.coerceIn(0, max(0, sh - h)) - oy
                if (p.x != tx || p.y != ty) { p.x = tx; p.y = ty; try { wm.updateViewLayout(r, p) } catch (_: Exception) { } }
                if (enterPending) { enterPending = false; enterT0 = SystemClock.uptimeMillis() }
            }
        }
        anchorL = l
        r.viewTreeObserver.addOnGlobalLayoutListener(l)
        r.requestLayout()
    }

    /** Panel ringkas: roda + angka FPS, empat angka sistem, empat tombol ikon, saklar Adapt/Puncak. */
    private fun buildGamePanel(st: Int): View {
        val sw = realW()
        val WRAP = LinearLayout.LayoutParams.WRAP_CONTENT
        val MATCH = LinearLayout.LayoutParams.MATCH_PARENT
        val box = LinearLayout(ctx).apply { orientation = LinearLayout.VERTICAL }
        panelBox = box
        box.background = panelBg(BORDER)
        box.setPadding(px(12), px(10), px(12), px(10))

        themeTitle = textView("", 10f, accentColor(), true)
        val nb = textView("--", 16f, TEXT, true).apply { gravity = Gravity.CENTER; letterSpacing = -0.04f }
        fpsBig = nb
        fpsBigLbl = fpsLabel(10f, 0.1f)
        val wheel = AdaptWheelView(ctx) { false }
        wheel.setPuncak(odOn); wheel.setLoad(adaptLoad, false)
        panelWheel = wheel
        val wheelBox = FrameLayout(ctx)
        wheelBox.addView(wheel, FrameLayout.LayoutParams(px(70), px(70)))
        wheelBox.addView(nb, FrameLayout.LayoutParams(px(70), px(70)))

        val names = listOf("CPU", "GPU", "RAM", "SUHU")
        val stats = LinearLayout(ctx).apply { orientation = LinearLayout.VERTICAL }
        for (r in 0 until 2) {
            val line = LinearLayout(ctx).apply { orientation = LinearLayout.HORIZONTAL }
            for (c in 0 until 2) {
                val i = r * 2 + c
                val cell = LinearLayout(ctx).apply { orientation = LinearLayout.VERTICAL; setPadding(px(4), px(1), px(4), px(1)) }
                cell.addView(textView(names[i], 9f, LABEL, true).apply { letterSpacing = 0.08f })
                val v = textView("--", 13f, TEXT, true)
                valViews[i] = v
                cell.addView(v)
                cards[i] = cell
                line.addView(cell, lpw(0, WRAP, 1f))
            }
            stats.addView(line, lpw(MATCH, WRAP, mt = if (r == 0) 0 else px(4)))
        }
        run {
            val line = LinearLayout(ctx).apply { orientation = LinearLayout.HORIZONTAL }
            for ((k, nm) in listOf("BATERAI", "1% LOW").withIndex()) {
                val cell = LinearLayout(ctx).apply { orientation = LinearLayout.VERTICAL; setPadding(px(4), px(1), px(4), px(1)) }
                cell.addView(textView(nm, 9f, LABEL, true).apply { letterSpacing = 0.08f })
                val v = textView("--", 13f, TEXT, true)
                if (k == 0) panelBat = v else panelLow = v
                cell.addView(v)
                line.addView(cell, lpw(0, WRAP, 1f))
            }
            stats.addView(line, lpw(MATCH, WRAP, mt = px(4)))
        }
        gridRow = stats
        val head = LinearLayout(ctx).apply { orientation = LinearLayout.HORIZONTAL; gravity = Gravity.CENTER_VERTICAL }
        head.addView(wheelBox, lpw(px(70), px(70)))
        head.addView(stats, lpw(0, WRAP, 1f, px(8)))
        box.addView(head, lpw(MATCH, WRAP))

        // tombol ikon
        val (_, cRec) = roundTile("Rekam", RED, "\u25CF", { onRec?.invoke() })
        val (_, cFps) = roundTile("Rekam FPS", themeNeon(st), "\u2248", { toggleFpsLog() })
        val (_, cShot) = roundTile("Screenshot", 0xFF60A5FA.toInt(), "\u25A3", { onShot?.invoke() })
        val (_, cPause) = roundTile("Jeda", 0xFFF5A524.toInt(), "\u2016", { onPause?.invoke() })
        tileRec = cRec; tileFps = cFps; tileDnd = null
        val foot = LinearLayout(ctx).apply { orientation = LinearLayout.HORIZONTAL; gravity = Gravity.CENTER }
        for (c in listOf(cRec, cFps, cShot, cPause)) {
            (c.parent as? ViewGroup)?.removeView(c)
            foot.addView(c, lpw(px(36), px(36), 0f, px(6)).apply { marginEnd = px(6) })
        }
        footRow = foot
        box.addView(foot, lpw(MATCH, WRAP, mt = px(8)))

        // baris rekam (hanya saat merekam)
        val top = LinearLayout(ctx).apply { orientation = LinearLayout.HORIZONTAL; gravity = Gravity.CENTER_VERTICAL }
        top.addView(View(ctx).apply { background = GradientDrawable().apply { shape = GradientDrawable.OVAL; setColor(RED) } }, LinearLayout.LayoutParams(px(10), px(10)))
        top.addView(textView("00:00", 15f, TEXT, true).apply { tag = "timer" }, lpw(WRAP, WRAP, ms = px(6)))
        top.addView(textView("REC", 10f, REC_TAG, true).apply { letterSpacing = 0.12f }, lpw(WRAP, WRAP, ms = px(6)))
        top.addView(View(ctx), LinearLayout.LayoutParams(0, 1, 1f))
        top.addView(recButton(true), LinearLayout.LayoutParams(WRAP, px(34)))
        topRow = top
        box.addView(top, lpw(MATCH, WRAP, mt = px(8)))
        val recHint = textView("Profil terkunci selama merekam.", 10f, HINT, false)
        hintRec = recHint
        box.addView(recHint, lpw(MATCH, WRAP, mt = px(4)))

        // saklar mode
        buildOdRow()
        val msw = ModeSwitch()
        modeSw = msw
        segRow = msw
        box.addView(msw, lpw(MATCH, px(32), mt = px(8)))
        odSmall?.let { o -> (o.parent as? ViewGroup)?.removeView(o); o.textSize = 9f; box.addView(o, lpw(MATCH, WRAP, mt = px(4))); odStatusLine = o }

        val wf = prefs.flPanelW / 100f
        box.layoutParams = FrameLayout.LayoutParams((minOf(px(250), (sw * 0.5f).toInt()) * wf).toInt().coerceAtMost((sw * 0.94f).toInt()), FrameLayout.LayoutParams.WRAP_CONTENT)
        paintTiles()
        return box
    }

    private fun card(label: String, idx: Int): View {
        val box = LinearLayout(ctx).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(px(10), px(10), px(10), px(8))
            background = roundBg(CARD, pf(12), 0)
        }
        box.addView(textView(label, 10f, LABEL, true).apply { letterSpacing = 0.1f })
        val v = textView("--", 18f, TEXT, true)
        valViews[idx] = v
        box.addView(v, LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT).apply { topMargin = px(4) })
        val bar = BarView(barColor(idx))
        barViews[idx] = bar
        box.addView(bar, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, px(3)).apply { topMargin = px(4) })
        cards[idx] = box
        return box
    }

    private fun barColor(idx: Int): Int = when (idx) {
        0 -> CPU
        1 -> GPU
        2 -> RAM
        else -> TEMP
    }

    private fun buildOdRow(): View {
        val row = LinearLayout(ctx).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
            setPadding(px(6), 0, px(6), 0)
            minimumHeight = px(44)
            isClickable = true
            setOnClickListener {
                if (!odAvail && !odOn) Toast.makeText(ctx, "ℹ " + trn("Buka game terdaftar dulu, Puncak hanya untuk game"), Toast.LENGTH_SHORT).show()
                else onOvd?.invoke(!odOn)
            }
        }
        val fl = FlameView(OD_TEXT)
        odFlame = fl
        row.addView(fl, LinearLayout.LayoutParams(px(18), px(18)))
        val nm = textView("Puncak", 13f, OD_TEXT, true)
        odName = nm
        row.addView(nm, LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT).apply { marginStart = px(5) })
        val sm = textView("", 11f, HINT, true).apply { letterSpacing = 0.02f }
        odSmall = sm
        odRow = row
        applyOvd()
        return row
    }

    /** Status Overdrive dari modul. avail = ada game terdaftar yang aktif (syarat untuk menyalakan). */
    /** Beban Adapt dari modul (-1 = tidak beradaptasi). Roda orb dan panel berputar bila berubah. */
    /** Uji dari Alat: roda berputar seolah beban berubah (tanpa menunggu modul). */
    fun testLoad(l: Int) {
        adaptLoad = l
        for (o in orbs) o.setLoad(l)
        panelWheel?.setLoad(l)
    }

    fun setAdaptLoad(l: Int) {
        if (l == adaptLoad) return
        adaptLoad = l
        for (o in orbs) o.setLoad(l)
        panelWheel?.setLoad(l)
        for (t in loadTags) paintLoadTag(t)
    }

    fun setOvd(on: Boolean, level: String, avail: Boolean) {
        syncProbe(avail)
        if (on == odOn && level == odLevel && avail == odAvail) return
        val modeChanged = on != odOn
        odOn = on; odLevel = level; odAvail = avail
        if (modeChanged) { for (o in orbs) o.setPuncak(on); panelWheel?.setPuncak(on) }
        applyOvd()
        if (modeChanged) {
            val acc = accentColor()
            for (r in rings) { r.accent = acc; r.invalidate() }
            paintSeg()
        }
    }

    private fun applyOvd() {
        paintThinBtns()
        modeSw?.sync()
        val row = odRow
        if (row != null) {
            if (odOn) {
                row.background = GradientDrawable(GradientDrawable.Orientation.LEFT_RIGHT, intArrayOf(OD, OD_END)).apply { cornerRadius = pf(10) }
                odFlame?.color = Color.WHITE; odFlame?.invalidate()
                odName?.setTextColor(Color.WHITE)
                odSmall?.setTextColor(OD_TEXT)
                setText(odSmall, if (odLevel == "safe") trn("Puncak aktif, dibatasi karena panas") else if (odLevel == "mid") trn("Puncak aktif, diturunkan sedikit karena hangat") else trn("Puncak aktif sampai game ditutup"))
            } else {
                row.background = roundBg(0x1AFF4D5E, pf(10), 0x8CFF4D5E.toInt())
                odFlame?.color = OD_TEXT; odFlame?.invalidate()
                odName?.setTextColor(OD_TEXT)
                odSmall?.setTextColor(HINT)
                setText(odSmall, if (odAvail) trn("Puncak: tenaga penuh, turun sendiri kalau panas") else trn("Puncak butuh game yang sedang dibuka"))
            }
            row.alpha = if (!odOn && !odAvail) 0.6f else 1f
        }
        val edge = if (odOn) OD_GLOW else BORDER
        panelBox?.background = panelBg(if (recOn) 0x8CE5484D.toInt() else edge)
        pill?.background = if (prefs.flStyle >= 3) null else roundBg(panelColor(), pf(24), edge)
        thin?.background = roundBg(panelColor(), pf(26), edge)
    }

    private inner class FlameView(var color: Int) : View(ctx) {
        private val p = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
            strokeCap = Paint.Cap.ROUND
            strokeJoin = Paint.Join.ROUND
        }
        private val path = Path()
        override fun onDraw(c: Canvas) {
            val w = width.toFloat(); val h = height.toFloat()
            p.color = color
            p.strokeWidth = w * 0.09f
            path.reset()
            path.moveTo(0.50f * w, 0.06f * h)
            path.cubicTo(0.62f * w, 0.33f * h, 0.34f * w, 0.40f * h, 0.34f * w, 0.62f * h)
            path.cubicTo(0.34f * w, 0.80f * h, 0.66f * w, 0.80f * h, 0.66f * w, 0.62f * h)
            path.cubicTo(0.66f * w, 0.50f * h, 0.62f * w, 0.43f * h, 0.58f * w, 0.37f * h)
            path.cubicTo(0.82f * w, 0.48f * h, 0.90f * w, 0.62f * h, 0.90f * w, 0.70f * h)
            path.cubicTo(0.90f * w, 0.88f * h, 0.72f * w, 0.96f * h, 0.50f * w, 0.96f * h)
            path.cubicTo(0.28f * w, 0.96f * h, 0.10f * w, 0.88f * h, 0.10f * w, 0.70f * h)
            path.cubicTo(0.10f * w, 0.40f * h, 0.38f * w, 0.30f * h, 0.50f * w, 0.06f * h)
            c.drawPath(path, p)
        }
    }

    private fun paintSeg() {
        paintMenu()
        paintThinBtns()
        paintTiles()
        if (segButtons.size < 3) return
        val acc = accentColor()
        val chipCol = intArrayOf(P_ADAPT, P_ADAPT, P_ADAPT)
        for (i in 0 until 3) {
            val on = i == 0 && !odOn
            val b = segButtons[i]
            b.background = roundBg(if (on) chipCol[i] else Color.TRANSPARENT, pf(10), if (on) 0 else (chipCol[i] and 0x00FFFFFF) or 0x55000000)
            b.setTextColor(if (on) DARK else SEG_TEXT)
            b.alpha = if (recOn || odOn) 0.45f else 1f
        }
    }

    private fun applyRec() {
        paintMenu()
        segRow?.visibility = if (recOn) View.GONE else View.VISIBLE
        modeSw?.sync()
        odRow?.visibility = if (recOn) View.GONE else View.VISIBLE
        odStatusLine?.visibility = if (recOn) View.GONE else View.VISIBLE
        topRow?.visibility = if (recOn) View.VISIBLE else View.GONE
        footRow?.visibility = if (recOn) View.GONE else View.VISIBLE
        if (mode == MODE_PANEL && attached) anchorPanel()
        hintRec?.visibility = if (recOn) View.VISIBLE else View.GONE
        panelBox?.background = panelBg(if (recOn) 0x8CE5484D.toInt() else if (odOn) OD_GLOW else BORDER)
        if (recOn && recStart == 0L) recStart = SystemClock.elapsedRealtime()
        tickTimer()
    }

    private fun applyMetrics() {
        for (i in 0 until 4) {
            val on = when (i) {
                0 -> prefs.flMCpu
                1 -> prefs.flMGpu
                2 -> prefs.flMRam
                else -> prefs.flMTemp
            }
            cards[i]?.visibility = if (on) View.VISIBLE else View.GONE
            thinGroups[i]?.visibility = if (on) View.VISIBLE else View.GONE
        }
        thinBatGrp?.visibility = if (prefs.flMBatt) View.VISIBLE else View.GONE
        val fpsVis = if (prefs.flMFps) View.VISIBLE else View.GONE
        fpsPill?.visibility = fpsVis
        fpsPillLbl?.visibility = fpsVis
        fpsBig?.visibility = fpsVis
        fpsBigLbl?.visibility = fpsVis
        fpsThin?.visibility = fpsVis
        fpsThinLbl?.visibility = fpsVis
        // FPS dimatikan: pil ringkas hanya logo (cincin berwarna sesuai mode), padding dibuat simetris
        (pill as? LinearLayout)?.setPadding(px(8), 0, if (prefs.flMFps) px(16) else px(8), 0)
    }

    // ---------------- komponen gambar ----------------

    private inner class RingView(sizePx: Int, var accent: Int) : View(ctx) {
        private val p = Paint(Paint.ANTI_ALIAS_FLAG)
        private val path = Path()
        private val stroke = pf(2f)

        init {
            layoutParams = LinearLayout.LayoutParams(px(sizePx), px(sizePx))
        }

        override fun onDraw(canvas: Canvas) {
            val w = width.toFloat()
            val h = height.toFloat()
            p.style = Paint.Style.FILL
            p.color = Color.argb(46, Color.red(accent), Color.green(accent), Color.blue(accent))
            canvas.drawCircle(w / 2f, h / 2f, w / 2f, p)
            p.style = Paint.Style.STROKE
            p.strokeWidth = stroke
            p.color = accent
            canvas.drawCircle(w / 2f, h / 2f, w / 2f - stroke / 2f, p)
            val ic = w * 0.5f
            val s = ic / 24f
            canvas.save()
            canvas.translate((w - ic) / 2f, (h - ic) / 2f)
            canvas.scale(s, s)
            path.reset()
            path.moveTo(13f, 2f)
            path.lineTo(4f, 14f)
            path.lineTo(11f, 14f)
            path.lineTo(10f, 22f)
            path.lineTo(19f, 10f)
            path.lineTo(12f, 10f)
            path.close()
            p.style = Paint.Style.STROKE
            p.strokeWidth = 2.4f
            p.strokeJoin = Paint.Join.ROUND
            p.strokeCap = Paint.Cap.ROUND
            canvas.drawPath(path, p)
            canvas.restore()
        }
    }

    private inner class OrbView : AdaptWheelView(ctx, { false }) {
        var accent = accentColor()

        init {
            setPuncak(odOn)
            setLoad(adaptLoad, false)
        }

        fun setFps(v: Float) = setLow(v in 1f..29.5f)

        /** Hanya kedip skala saat mode berganti; roda sendiri diputar GPU, tidak digambar ulang per frame. */
        fun tick(now: Long) {
        }
    }

    /** Pilihan mode berbentuk saklar geser: Adapt di kiri, Puncak (merah) di kanan. */
    private inner class ModeSwitch : View(ctx) {
        private var pos = if (odOn) 1f else 0f
        private val p = Paint(Paint.ANTI_ALIAS_FLAG)
        private val rr = android.graphics.RectF()
        init { isClickable = true; setOnClickListener { markActive(); onToggle() } }
        private fun onToggle() {
            if (recOn) return
            if (!odOn && !odAvail) { Toast.makeText(ctx, "\u2139 " + trn("Buka game terdaftar dulu, Puncak hanya untuk game"), Toast.LENGTH_SHORT).show(); return }
            cycleMode()
        }
        private var fromPos = 0f; private var toPos = 0f; private var t0 = 0L; private var moving = false
        private val stepper = object : Runnable {
            override fun run() {
                val q = ((SystemClock.uptimeMillis() - t0) / 280f).coerceIn(0f, 1f)
                val t = q - 1f
                pos = (fromPos + (toPos - fromPos) * (t * t * (2.1f * t + 1.1f) + 1f)).coerceIn(0f, 1f)
                invalidate()
                if (q < 1f) postOnAnimation(this) else { pos = toPos; moving = false; invalidate() }
            }
        }
        fun sync() {
            alpha = if (recOn) 0.45f else if (!odOn && !odAvail) 0.75f else 1f
            val to = if (odOn) 1f else 0f
            if (to == toPos && (moving || to == pos)) { invalidate(); return }
            toPos = to; fromPos = pos; t0 = SystemClock.uptimeMillis()
            if (!moving) { moving = true; postOnAnimation(stepper) }
        }
        override fun onDraw(c: Canvas) {
            val w = width.toFloat(); val h = height.toFloat()
            p.style = Paint.Style.FILL; p.color = 0xFF10161E.toInt()
            rr.set(0f, 0f, w, h); c.drawRoundRect(rr, h / 2f, h / 2f, p)
            val tw = w / 2f - pf(3f)
            val x = pf(3f) + (w - 2f * pf(3f) - tw) * pos
            p.color = if (pos > 0.5f) OD else P_ADAPT
            rr.set(x, pf(3f), x + tw, h - pf(3f)); c.drawRoundRect(rr, h / 2f, h / 2f, p)
            p.textAlign = Paint.Align.CENTER; p.isFakeBoldText = true; p.textSize = pf(11f); p.letterSpacing = 0.08f
            val ty = h / 2f + pf(4f)
            p.color = if (pos < 0.5f) DARK else SEG_TEXT
            c.drawText("ADAPT", w * 0.25f, ty, p)
            p.color = if (pos > 0.5f) Color.WHITE else OD_TEXT
            c.drawText("PUNCAK", w * 0.75f, ty, p)
        }
    }

    /** Garis pindai neon yang menyapu panel saat muncul (tema gaming). */
    private inner class ScanView : View(ctx) {
        var pos = 0f
        private val p = Paint(Paint.ANTI_ALIAS_FLAG)
        override fun onDraw(canvas: Canvas) {
            val nc = themeNeon(prefs.flStyle)
            val y = pos * height
            val band = pf(70f)
            p.shader = android.graphics.LinearGradient(0f, y - band, 0f, y, intArrayOf(0x00000000, (nc and 0x00FFFFFF) or 0x44000000), null, android.graphics.Shader.TileMode.CLAMP)
            canvas.drawRect(0f, y - band, width.toFloat(), y, p)
            p.shader = null
            p.color = nc
            canvas.drawRect(0f, y - pf(1.5f), width.toFloat(), y + pf(1.5f), p)
        }
    }

    private inner class BarView(private val color: Int) : View(ctx) {
        var frac = 0f

        override fun onDraw(canvas: Canvas) {
            val r = height / 2f
            val p = Paint(Paint.ANTI_ALIAS_FLAG)
            p.color = 0x1FFFFFFF
            canvas.drawRoundRect(0f, 0f, width.toFloat(), height.toFloat(), r, r, p)
            if (frac > 0f) {
                p.color = color
                canvas.drawRoundRect(0f, 0f, width * frac.coerceIn(0f, 1f), height.toFloat(), r, r, p)
            }
        }
    }

    private inner class GraphView(private val color: Int) : View(ctx) {
        private val vals = FloatArray(30)
        private var n = 0
        private val p = Paint(Paint.ANTI_ALIAS_FLAG)
        private val path = Path()

        init {
            layoutParams = LinearLayout.LayoutParams(px(170), px(48))
        }

        fun add(fps: Float?) {
            if (fps == null) return
            for (i in 0 until vals.size - 1) vals[i] = vals[i + 1]
            vals[vals.size - 1] = fps
            if (n < vals.size) n++
            invalidate()
        }

        fun clear() {
            vals.fill(0f)
            n = 0
            invalidate()
        }

        override fun onDraw(canvas: Canvas) {
            p.style = Paint.Style.STROKE
            p.strokeWidth = pf(1f)
            p.color = 0x1AFFFFFF
            p.pathEffect = DashPathEffect(floatArrayOf(pf(3f), pf(4f)), 0f)
            canvas.drawLine(0f, pf(8f), width.toFloat(), pf(8f), p)
            p.pathEffect = null
            if (n < 2) return
            var mn = Float.MAX_VALUE
            var mx = -Float.MAX_VALUE
            for (i in vals.size - n until vals.size) {
                mn = min(mn, vals[i])
                mx = max(mx, vals[i])
            }
            if (mx - mn < 1f) mx = mn + 1f
            path.reset()
            for (i in 0 until n) {
                val v = vals[vals.size - n + i]
                val x = width * i / (n - 1f)
                val y = pf(6f) + (1f - (v - mn) / (mx - mn)) * (height - pf(12f))
                if (i == 0) path.moveTo(x, y) else path.lineTo(x, y)
            }
            p.color = color
            p.strokeWidth = pf(2f)
            p.strokeJoin = Paint.Join.ROUND
            p.strokeCap = Paint.Cap.ROUND
            canvas.drawPath(path, p)
        }
    }
}
