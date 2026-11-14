package com.hsin

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.view.View
import android.view.animation.Interpolator

/**
 * Roda Adapt HSIN (desain asli): cincin tipis dengan 8 bulatan di luar, bagian tengah kosong untuk angka FPS.
 * Digambar statis, lalu hanya DIPUTAR lewat properti rotasi pada layer hardware (GPU), jadi hampir tanpa beban CPU.
 * Beban 0..3: putaran 180/270/360/540 derajat, emas makin pekat, bulatan menyala 2/4/6/8, kilat cincin saat mengunci.
 * Beban 3 berputar pelan terus selama masih beban 3. Puncak: merah, diam.
 */
open class AdaptWheelView(ctx: Context, private val reduce: () -> Boolean) : View(ctx) {
    companion object {
        val DEG = floatArrayOf(180f, 270f, 360f, 540f)
        val DUR = longArrayOf(700L, 900L, 1100L, 1500L)
        val GOLD = floatArrayOf(0.25f, 0.5f, 0.75f, 1f)
        private val SILVER = intArrayOf(215, 222, 230)
        private val GOLDC = intArrayOf(232, 184, 74)
        private const val PUN = 0xFFFF4D5E.toInt()
        /** Langkah ratchet per beban: sama dengan jumlah klik di SoundFx (tiap 45 derajat satu klik). */
        val STEPS = intArrayOf(4, 6, 8, 12)
    }

    /** Putaran bergerak per langkah 45 derajat (klik demi klik), makin lambat di akhir. Waktu klik sama dengan SoundFx. */
    class Ratchet(private val n: Int) : Interpolator {
        override fun getInterpolation(t: Float): Float {
            val outer = 1f - Math.pow((1f - t).toDouble(), 2.2).toFloat()
            val x = outer * n
            val i = Math.floor(x.toDouble()).toInt().coerceAtMost(n - 1)
            val f = x - i
            return (i + f * f * (3f - 2f * f)) / n
        }
    }

    private val p = Paint(Paint.ANTI_ALIAS_FLAG)
    private var load = -1
    private var puncak = false
    private var low = false
    private var flash = 0f

    // Animasi pakai jam sendiri (uptimeMillis), bukan Animator: Animator mengikuti skala animasi sistem (0 di banyak HP) dan jadi instan.
    private var spinning = false
    private var sFrom = 0f; private var sDelta = 0f; private var sT0 = 0L; private var sDur = 1L; private var sSteps = 4
    private var contOn = false
    private var cBase = 0f; private var cT0 = 0L
    private var flashing = false; private var fT0 = 0L
    private var appearing = false; private var aT0 = 0L; private var aBase = 0f
    private var running = false
    private var lastCont = 0L

    private val driver = object : Runnable {
        override fun run() {
            running = false
            if (!isAttachedToWindow) return
            val now = android.os.SystemClock.uptimeMillis()
            var keep = false
            var angle = rotation
            if (spinning) {
                val q = ((now - sT0).toFloat() / sDur).coerceIn(0f, 1f)
                angle = sFrom + sDelta * Ratchet(sSteps).getInterpolation(q)
                if (q >= 1f) {
                    spinning = false
                    flashing = true; fT0 = now
                    if (load == 3 && !puncak && !reduce()) { contOn = true; cT0 = now; cBase = angle }
                } else keep = true
            }
            if (contOn && !spinning) {
                if (now - lastCont >= 30L) { lastCont = now; angle = cBase + 360f * (((now - cT0) % 7000L) / 7000f) } else angle = rotation
                keep = true
            }
            if (appearing) {
                val q = ((now - aT0).toFloat() / 600f).coerceIn(0f, 1f)
                val t = q - 1f
                val sc = 0.4f + 0.6f * (t * t * (2.2f * t + 1.2f) + 1f)
                scaleX = sc; scaleY = sc; alpha = (sc / 0.7f).coerceIn(0f, 1f)
                if (!spinning && !contOn) angle = aBase - 270f * (1f - Ratchet(6).getInterpolation(q))
                if (q >= 1f) { appearing = false; scaleX = 1f; scaleY = 1f; alpha = 1f; if (!contOn && !spinning) angle = aBase } else keep = true
            }
            if (flashing) {
                val q = ((now - fT0) / 450f).coerceIn(0f, 1f)
                flash = Math.sin(Math.PI * q).toFloat()
                invalidate()
                if (q >= 1f) { flashing = false; flash = 0f; invalidate() } else keep = true
            }
            if (angle != rotation) rotation = angle
            if (keep) kick()
        }
    }

    private fun kick() { if (!running && isAttachedToWindow) { running = true; postOnAnimation(driver) } }

    init { setLayerType(LAYER_TYPE_HARDWARE, null) }

    fun setPuncak(on: Boolean) {
        if (on == puncak) return
        puncak = on
        if (on) stopAnims()
        invalidate()
    }

    fun setLow(v: Boolean) { if (v != low) { low = v; invalidate() } }

    /** load: -1 = tidak beradaptasi. animate=false untuk pemasangan awal (tanpa putaran). */
    fun setLoad(n: Int, animate: Boolean = true) {
        val l = n.coerceIn(-1, 3)
        if (l == load) return
        val old = load
        load = l
        val cur = rotation
        stopAnims()
        invalidate()
        if (l < 0 || puncak) return
        if (!animate) {
            if (l == 3 && !reduce()) { contOn = true; cT0 = android.os.SystemClock.uptimeMillis(); cBase = cur; kick() }
            return
        }
        if (reduce()) return
        sFrom = cur
        sDelta = (if (l >= old) 1f else -1f) * DEG[l]
        sDur = DUR[l]; sSteps = STEPS[l]
        sT0 = android.os.SystemClock.uptimeMillis()
        spinning = true
        kick()
    }

    private fun stopAnims() {
        spinning = false; contOn = false; flashing = false; appearing = false
        flash = 0f
        scaleX = 1f; scaleY = 1f; alpha = 1f
    }

    /** Muncul: roda membesar sambil berputar ratchet 270 derajat. */
    fun appear() {
        if (reduce()) return
        appearing = true
        aT0 = android.os.SystemClock.uptimeMillis()
        aBase = if (contOn) rotation else rotation
        scaleX = 0.4f; scaleY = 0.4f; alpha = 0f
        kick()
    }

    override fun onDetachedFromWindow() { running = false; super.onDetachedFromWindow() }
    override fun onAttachedToWindow() { super.onAttachedToWindow(); if (spinning || contOn || appearing || flashing) kick() }

    private fun base(): Int {
        if (puncak) return PUN
        val k = if (load < 0) 0f else GOLD[load]
        return Color.rgb(
            (SILVER[0] + (GOLDC[0] - SILVER[0]) * k).toInt(),
            (SILVER[1] + (GOLDC[1] - SILVER[1]) * k).toInt(),
            (SILVER[2] + (GOLDC[2] - SILVER[2]) * k).toInt()
        )
    }

    override fun onDraw(c: Canvas) {
        val cx = width / 2f
        val half = cx
        val r = half * 0.86f
        val col = base()
        val lit = if (puncak) 8 else if (load < 0) 0 else (load + 1) * 2
        val al = if (!puncak && load < 0) 115 else 255
        p.style = Paint.Style.FILL
        p.color = Color.argb(210, 10, 13, 18)
        c.drawCircle(cx, cx, r * 0.78f, p)
        p.style = Paint.Style.STROKE
        p.strokeCap = Paint.Cap.ROUND
        val ringCol = if (low && !puncak) 0xFFE5484D.toInt() else col
        if (flash > 0f) {
            p.strokeWidth = r * 0.16f
            p.color = Color.argb((90 * flash).toInt(), Color.red(ringCol), Color.green(ringCol), Color.blue(ringCol))
            c.drawCircle(cx, cx, r * 0.72f, p)
        }
        p.strokeWidth = r * (0.06f + 0.04f * flash)
        p.color = Color.argb(al, Color.red(ringCol), Color.green(ringCol), Color.blue(ringCol))
        c.drawCircle(cx, cx, r * 0.72f, p)
        val kr = r * 0.11f
        for (i in 0 until 8) {
            c.save()
            c.rotate(i * 45f, cx, cx)
            p.color = Color.argb(al, Color.red(col), Color.green(col), Color.blue(col))
            p.strokeWidth = r * 0.045f
            c.drawLine(cx, cx - r * 0.74f, cx, cx - r * 0.8f, p)
            p.style = Paint.Style.FILL
            p.color = Color.argb(if (i < lit) al else (al * 0.5f).toInt(), Color.red(col), Color.green(col), Color.blue(col))
            c.drawCircle(cx, cx - r * 0.9f, kr, p)
            p.style = Paint.Style.STROKE
            p.strokeWidth = r * 0.025f
            p.color = Color.argb((al * 0.8f).toInt(), 255, 255, 255)
            c.drawArc(cx - kr, cx - r * 0.9f - kr, cx + kr, cx - r * 0.9f + kr, 100f, 70f, false, p)
            c.restore()
        }
    }
}
