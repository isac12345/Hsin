package com.hsin

import android.app.Activity
import android.os.Handler
import android.os.HandlerThread
import android.os.Looper
import android.os.SystemClock
import android.view.FrameMetrics
import android.view.Window

/**
 * Ukur kelancaran frame sungguhan (bukan RAM) lewat FrameMetrics. Hanya aktif di mode animasi Otomatis
 * dan hanya saat animasi menyala. Kalau dua jendela 90 frame berturut-turut punya >= 30% frame di atas 22 ms,
 * animasi dimatikan dan hasilnya diingat. Tidak membangunkan frame sendiri, jadi tanpa biaya saat layar diam.
 */
object PerfGuard {
    @Volatile var armed = false
    /** Tingkat ringan: beban sedang, jam animasi turun ke 30/dtk sebelum animasi dimatikan total. */
    @Volatile var soft = false
    @Volatile private var calm = 0
    var onDemote: (() -> Unit)? = null
    private val ring = LongArray(90)
    @Volatile private var n = 0
    @Volatile private var t0 = 0L
    @Volatile private var strikes = 0
    private var listener: Window.OnFrameMetricsAvailableListener? = null
    private var win: Window? = null
    private var thread: HandlerThread? = null

    fun attach(a: Activity) {
        if (android.os.Build.VERSION.SDK_INT < 24 || listener != null) return
        try {
            val th = HandlerThread("hsin-perf").also { it.start() }
            val l = Window.OnFrameMetricsAvailableListener { _, fm, _ ->
                if (!armed) return@OnFrameMetricsAvailableListener
                if (android.os.Build.VERSION.SDK_INT >= 26 && fm.getMetric(FrameMetrics.FIRST_DRAW_FRAME) == 1L) return@OnFrameMetricsAvailableListener
                feed(fm.getMetric(FrameMetrics.TOTAL_DURATION))
            }
            a.window.addOnFrameMetricsAvailableListener(l, Handler(th.looper))
            thread = th; listener = l; win = a.window
        } catch (_: Throwable) { listener = null }
    }

    fun detach() {
        try { listener?.let { win?.removeOnFrameMetricsAvailableListener(it) } } catch (_: Throwable) {}
        listener = null; win = null
        thread?.quitSafely(); thread = null
    }

    fun reset() { n = 0; strikes = 0; soft = false; calm = 0 }

    private fun feed(d: Long) {
        val now = SystemClock.elapsedRealtime()
        if (n == 0) t0 = now
        ring[n++] = d
        if (n < ring.size) return
        n = 0
        // jendela yang terlalu panjang berarti layar jarang bergerak: bukan beban animasi, abaikan
        if (now - t0 > 6000L) { strikes = 0; return }
        var slow = 0
        for (v in ring) if (v > 22_000_000L) slow++
        val pct = slow * 100 / ring.size
        if (pct >= 12) { soft = true; calm = 0 } else if (pct < 4 && soft) { if (++calm >= 3) { soft = false; calm = 0 } }
        if (pct >= 30) {
            strikes++
            if (strikes >= 2) { strikes = 0; armed = false; Handler(Looper.getMainLooper()).post { onDemote?.invoke() } }
        } else strikes = 0
    }
}
