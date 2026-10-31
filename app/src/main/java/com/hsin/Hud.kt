package com.hsin

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.PixelFormat
import android.graphics.RectF
import android.graphics.Typeface
import android.net.Uri
import android.os.Build
import android.os.IBinder
import android.provider.Settings
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import java.io.BufferedReader
import java.io.InputStreamReader
import kotlin.concurrent.thread

/** Floating FPS untuk game. Tidak memakai ValueAnimator: animasinya jalan sendiri lewat jam frame. */
object Hud {
    @Volatile var running = false
    @Volatile var fpsNow = -1f

    fun canDraw(ctx: Context): Boolean = Settings.canDrawOverlays(ctx)

    fun permissionIntent(ctx: Context): Intent =
        Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, Uri.parse("package:" + ctx.packageName)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)

    fun start(ctx: Context, pkg: String) {
        val i = Intent(ctx, HudService::class.java).putExtra("pkg", pkg)
        try {
            if (Build.VERSION.SDK_INT >= 26) ctx.startForegroundService(i) else ctx.startService(i)
        } catch (e: Exception) {
            // abaikan: jendela floating tidak wajib
        }
    }

    fun stop(ctx: Context) {
        try { ctx.stopService(Intent(ctx, HudService::class.java)) } catch (e: Exception) { }
    }
}

class HudService : Service() {
    private var wm: WindowManager? = null
    private var view: HudView? = null
    private var lp: WindowManager.LayoutParams? = null
    @Volatile private var proc: Process? = null
    @Volatile private var gen = 0
    private var pkg = ""

    override fun onBind(i: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val p = intent?.getStringExtra("pkg").orEmpty()
        startFg()
        if (!Hud.canDraw(this)) { stopSelf(); return START_NOT_STICKY }
        if (p.isNotEmpty()) pkg = p
        if (pkg.isEmpty()) { stopSelf(); return START_NOT_STICKY }
        attach()
        stream()
        return START_NOT_STICKY
    }

    private fun startFg() {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= 26) nm.createNotificationChannel(NotificationChannel("hsin_hud", "HSIN floating", NotificationManager.IMPORTANCE_MIN))
        val b = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this, "hsin_hud") else Notification.Builder(this)
        val n = b.setContentTitle("HSIN floating aktif").setSmallIcon(android.R.drawable.ic_menu_info_details).setOngoing(true).build()
        try {
            if (Build.VERSION.SDK_INT >= 34) startForeground(7, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE) else startForeground(7, n)
        } catch (e: Exception) {
            // tanpa notifikasi foreground, sistem bisa mematikan service; tetap lanjut
        }
    }

    private fun attach() {
        if (view != null) { view?.pkgLabel = pkg; return }
        val w = getSystemService(Context.WINDOW_SERVICE) as WindowManager
        wm = w
        val v = HudView(this)
        v.pkgLabel = pkg
        v.onMode = { m -> thread { Repo.modeSet(m); v.post { v.mode = m } } }
        v.onClose = { stopSelf() }
        v.onRecStop = { csv -> saveCsv(csv) }
        val type = WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        val p = WindowManager.LayoutParams(
            WindowManager.LayoutParams.WRAP_CONTENT, WindowManager.LayoutParams.WRAP_CONTENT, type,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
            PixelFormat.TRANSLUCENT
        )
        p.gravity = Gravity.TOP or Gravity.START
        p.x = 24; p.y = 90
        lp = p
        v.onMove = { dx, dy -> p.x += dx; p.y += dy; try { w.updateViewLayout(v, p) } catch (e: Exception) { } }
        try { w.addView(v, p); view = v } catch (e: Exception) { stopSelf() }
        thread { val m = Repo.modeGet(); v.post { v.mode = m } }
    }

    private fun stream() {
        val my = ++gen
        try { proc?.destroyForcibly() } catch (e: Exception) { }
        Hud.running = true
        val target = pkg
        thread(isDaemon = true) {
            var prevTs = ""
            var cpuT = 0L
            var cpuI = 0L
            try {
                val p = ProcessBuilder("su", "-c", "sh /data/adb/modules/hsin/core/hud.sh --loop '$target'").redirectErrorStream(true).start()
                proc = p
                val br = BufferedReader(InputStreamReader(p.inputStream))
                val block = ArrayList<String>(32)
                while (my == gen) {
                    val line = br.readLine() ?: break
                    if (line != "--") { if (block.size < 32) block.add(line); continue }
                    val m = HashMap<String, String>()
                    for (l in block) { val i = l.indexOf('='); if (i > 0) m[l.substring(0, i)] = l.substring(i + 1).trim() }
                    block.clear()
                    // FPS dihitung di sini (shell ROM 32-bit tidak bisa menghitung timestamp 14 digit)
                    var fps = -1f
                    val lat = m["lat"].orEmpty()
                    if (lat.isNotEmpty()) {
                        val arr = ArrayList<Long>(80)
                        for (t in lat.split(' ')) { val x = t.toLongOrNull() ?: continue; if (x > 0L) arr.add(x) }
                        if (arr.size >= 3) {
                            arr.sort()
                            val last = arr[arr.size - 1]
                            val ts = last.toString()
                            if (ts == prevTs) fps = 0f else {
                                val lo = last - 1_000_000_000L
                                var first = last; var n = 0
                                for (x in arr) if (x >= lo) { n++; if (x < first) first = x }
                                val span = last - first
                                if (n > 1 && span > 0L) { val f = ((n - 1) * 1_000_000_000.0 / span).toFloat(); if (f.isFinite() && f <= 480f) fps = f }
                            }
                            prevTs = ts
                        }
                    } else {
                        val x10 = m["fps_x10"]?.toIntOrNull()
                        if (x10 != null && x10 in 0..2400) fps = x10 / 10f
                    }
                    var cpu = -1
                    val parts = m["cpu"].orEmpty().split(Regex("\\s+")).filter { it.isNotEmpty() }
                    if (parts.size >= 9 && parts[0] == "cpu") {
                        val v = parts.drop(1).take(8).map { it.toLongOrNull() ?: 0L }
                        val total = v.sum(); val idle = v[3] + v[4]
                        val dt = total - cpuT; val di = idle - cpuI
                        if (cpuT > 0L && dt > 0L) cpu = (((dt - di) * 100) / dt).toInt().coerceIn(0, 100)
                        cpuT = total; cpuI = idle
                    }
                    val gpu = m["gpu"]?.toIntOrNull()?.coerceIn(0, 100) ?: -1
                    val gmhz = m["gpu_freq"]?.toIntOrNull() ?: -1
                    val soc = (m["soc_mc"]?.toIntOrNull() ?: 0) / 1000
                    val bat = (m["temp_mc"]?.toIntOrNull() ?: 0) / 1000
                    val temp = if (soc in 1..105) soc else if (bat in 1..105) bat else -1
                    Hud.fpsNow = fps
                    view?.post { view?.feed(fps, cpu, gpu, gmhz, temp) }
                }
            } catch (e: Exception) {
                // aliran berhenti
            } finally {
                try { proc?.destroyForcibly() } catch (e: Exception) { }
            }
        }
    }

    private fun saveCsv(csv: String) {
        thread {
            try {
                val name = "Hsin_fps_" + pkg.replace('.', '_') + "_" + System.currentTimeMillis() / 1000 + ".csv"
                val p = ProcessBuilder("su", "-c", "cat > '/sdcard/Download/$name'").redirectErrorStream(true).start()
                p.outputStream.use { it.write(csv.toByteArray()) }
                p.waitFor()
            } catch (e: Exception) {
                // gagal simpan
            }
        }
    }

    override fun onDestroy() {
        gen++
        Hud.running = false
        try { proc?.destroyForcibly() } catch (e: Exception) { }
        view?.stopRec()
        try { if (view != null) wm?.removeView(view) } catch (e: Exception) { }
        view = null
        super.onDestroy()
    }
}

/** Satu View digambar manual. Ciut (logo + FPS) -> ketuk -> panel; ketuk lagi -> ciut. */
class HudView(ctx: Context) : View(ctx) {
    var pkgLabel = ""
    var mode = "bawaan"
    var onMode: (String) -> Unit = {}
    var onClose: () -> Unit = {}
    var onMove: (Int, Int) -> Unit = { _, _ -> }
    var onRecStop: (String) -> Unit = {}

    private val d = ctx.resources.displayMetrics.density
    private val gold = Color.parseColor("#E8B95A")
    private val bg = Color.parseColor("#E6141416")
    private val p = Paint(Paint.ANTI_ALIAS_FLAG)
    private val rect = RectF()
    private var fps = -1f; private var cpu = -1; private var gpu = -1; private var gmhz = -1; private var temp = -1
    private var open = false
    private var ex = 0f              // 0 ciut .. 1 panel (jam sendiri, bukan ValueAnimator)
    private var exT0 = 0L
    private var exFrom = 0f
    private var anim = false
    private var rec = false
    private var recT0 = 0L
    private val csv = StringBuilder()
    private val modes = listOf("hemat" to "Hemat", "bawaan" to "Bawaan", "seimbang" to "Seimbang", "boost" to "Boost")
    private var downX = 0f; private var downY = 0f; private var lastX = 0f; private var lastY = 0f; private var moved = false
    private val wPill get() = (84 * d).toInt()
    private val hPill get() = (40 * d).toInt()
    private val wPanel get() = (260 * d).toInt()
    private val hPanel get() = (178 * d).toInt()

    init { p.typeface = Typeface.MONOSPACE }

    fun feed(f: Float, c: Int, g: Int, gm: Int, t: Int) {
        fps = f; cpu = c; gpu = g; gmhz = gm; temp = t
        if (rec) {
            val sec = (System.currentTimeMillis() - recT0) / 1000
            if (csv.length < 400_000 && f >= 0f) csv.append(sec).append(',').append(pkgLabel).append(',').append(String.format(java.util.Locale.US, "%.1f", f))
                .append(',').append(c).append(',').append(g).append(',').append(t).append(',').append(mode).append('\n')
        }
        invalidate()
    }

    fun stopRec() {
        if (!rec) return
        rec = false
        if (csv.length > 40) onRecStop("t_detik,paket,fps,cpu_persen,gpu_persen,suhu_c,mode\n$csv")
        csv.setLength(0)
    }

    private fun toggle() {
        exFrom = ex
        exT0 = System.nanoTime()
        open = !open
        if (!anim) { anim = true; postOnAnimation(tick) }
    }

    private val tick = object : Runnable {
        override fun run() {
            val k = ((System.nanoTime() - exT0) / 1e6f / 260f).coerceIn(0f, 1f)
            val e = 1f - (1f - k) * (1f - k) * (1f - k)
            val target = if (open) 1f else 0f
            ex = exFrom + (target - exFrom) * e
            requestLayout(); invalidate()
            if (k < 1f) postOnAnimation(this) else anim = false
        }
    }

    override fun onMeasure(wm: Int, hm: Int) {
        val w = wPill + ((wPanel - wPill) * ex).toInt()
        val h = hPill + ((hPanel - hPill) * ex).toInt()
        setMeasuredDimension(w, h)
    }

    override fun onDraw(c: Canvas) {
        val w = width.toFloat(); val h = height.toFloat()
        val r = (20 * d) + (-6 * d) * ex
        p.style = Paint.Style.FILL; p.color = bg
        rect.set(0f, 0f, w, h); c.drawRoundRect(rect, r, r, p)
        p.style = Paint.Style.STROKE; p.strokeWidth = 1.2f * d; p.color = gold
        rect.set(1f, 1f, w - 1f, h - 1f); c.drawRoundRect(rect, r, r, p)
        p.style = Paint.Style.FILL
        val fpsTxt = if (fps < 0f) "--" else fps.toInt().toString()
        val idle = fps in 0f..0.5f
        // pil
        p.color = gold; p.textSize = 18 * d; p.typeface = Typeface.create(Typeface.MONOSPACE, Typeface.BOLD)
        c.drawText(fpsTxt, 12 * d, 26 * d, p)
        p.color = Color.argb(170, 255, 255, 255); p.textSize = 9 * d; p.typeface = Typeface.MONOSPACE
        c.drawText(if (idle) "IDLE" else "FPS", 12 * d + p.measureText("00 ") + 18 * d, 26 * d, p)
        if (rec) { p.color = Color.parseColor("#E5484D"); c.drawCircle(w - 12 * d, 12 * d, 3.5f * d, p) }
        if (ex < 0.4f) return
        val a = (((ex - 0.4f) / 0.6f) * 255).toInt().coerceIn(0, 255)
        p.textSize = 11 * d
        fun line(y: Float, k: String, v: String) {
            p.color = Color.argb(a * 6 / 10, 255, 255, 255); c.drawText(k, 14 * d, y, p)
            p.color = Color.argb(a, 255, 255, 255); c.drawText(v, 80 * d, y, p)
        }
        line(50 * d, "CPU", if (cpu >= 0) "$cpu%" else "--")
        line(66 * d, "GPU", if (gpu >= 0) "$gpu%" else if (gmhz > 0) "$gmhz MHz" else "--")
        line(82 * d, "SUHU", if (temp > 0) "$temp°C" else "--")
        line(98 * d, "MODE", modes.firstOrNull { it.first == mode }?.second ?: mode)
        // tombol mode
        val bw = (wPanel - 28 * d) / 4f
        for ((i, m) in modes.withIndex()) {
            val l = 14 * d + bw * i
            rect.set(l + 2 * d, 110 * d, l + bw - 2 * d, 136 * d)
            p.style = Paint.Style.FILL
            p.color = if (m.first == mode) Color.argb(a, 232, 185, 90) else Color.argb(a * 2 / 10, 255, 255, 255)
            c.drawRoundRect(rect, 8 * d, 8 * d, p)
            p.color = if (m.first == mode) Color.argb(a, 20, 20, 22) else Color.argb(a, 255, 255, 255)
            p.textSize = 8.5f * d
            c.drawText(m.second.take(7), rect.left + (rect.width() - p.measureText(m.second.take(7))) / 2f, rect.centerY() + 3 * d, p)
        }
        // tombol rekam + tutup
        rect.set(16 * d, 144 * d, 126 * d, 168 * d)
        p.color = if (rec) Color.argb(a, 229, 72, 77) else Color.argb(a * 2 / 10, 255, 255, 255)
        c.drawRoundRect(rect, 12 * d, 12 * d, p)
        p.color = Color.argb(a, 255, 255, 255); p.textSize = 9.5f * d
        val rt = if (rec) "BERHENTI REKAM" else "REKAM FPS"
        c.drawText(rt, rect.left + (rect.width() - p.measureText(rt)) / 2f, rect.centerY() + 3 * d, p)
        rect.set(134 * d, 144 * d, wPanel - 16 * d, 168 * d)
        p.color = Color.argb(a * 2 / 10, 255, 255, 255)
        c.drawRoundRect(rect, 12 * d, 12 * d, p)
        p.color = Color.argb(a, 255, 255, 255)
        val xt = "TUTUP"
        c.drawText(xt, rect.left + (rect.width() - p.measureText(xt)) / 2f, rect.centerY() + 3 * d, p)
    }

    override fun onTouchEvent(e: MotionEvent): Boolean {
        when (e.actionMasked) {
            MotionEvent.ACTION_DOWN -> { downX = e.rawX; downY = e.rawY; lastX = downX; lastY = downY; moved = false }
            MotionEvent.ACTION_MOVE -> {
                if (Math.abs(e.rawX - downX) > 8 * d || Math.abs(e.rawY - downY) > 8 * d) moved = true
                if (moved) { onMove((e.rawX - lastX).toInt(), (e.rawY - lastY).toInt()) }
                lastX = e.rawX; lastY = e.rawY
            }
            MotionEvent.ACTION_UP -> if (!moved) tap(e.x, e.y)
        }
        return true
    }

    private fun tap(x: Float, y: Float) {
        if (!open || ex < 0.9f) { toggle(); return }
        if (y < 40 * d) { toggle(); return }
        if (y in (110 * d)..(138 * d)) {
            val bw = (wPanel - 28 * d) / 4f
            val i = ((x - 14 * d) / bw).toInt()
            if (i in 0..3 && modes[i].first != mode) { mode = modes[i].first; onMode(mode); invalidate() }
            return
        }
        if (y >= 142 * d) {
            if (x < 130 * d) {
                if (rec) stopRec() else { rec = true; recT0 = System.currentTimeMillis(); csv.setLength(0) }
                invalidate()
            } else { stopRec(); onClose() }
        }
    }
}
