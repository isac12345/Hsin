package com.hsin

import android.animation.Animator
import android.animation.AnimatorListenerAdapter
import android.animation.ObjectAnimator
import android.animation.ValueAnimator
import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.view.View
import android.view.animation.DecelerateInterpolator
import android.view.animation.LinearInterpolator

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
    }

    private val p = Paint(Paint.ANTI_ALIAS_FLAG)
    private var load = -1
    private var puncak = false
    private var low = false
    private var flash = 0f
    private var spin: Animator? = null
    private var cont: ObjectAnimator? = null
    private var flashAnim: ValueAnimator? = null

    init { setLayerType(LAYER_TYPE_HARDWARE, null) }

    fun setPuncak(on: Boolean) {
        if (on == puncak) return
        puncak = on
        if (on) { stopAnims() }
        invalidate()
    }

    fun setLow(v: Boolean) { if (v != low) { low = v; invalidate() } }

    /** load: -1 = tidak beradaptasi. animate=false untuk pemasangan awal (tanpa putaran). */
    fun setLoad(n: Int, animate: Boolean = true) {
        val l = n.coerceIn(-1, 3)
        if (l == load) return
        val old = load
        load = l
        stopAnims()
        invalidate()
        if (l < 0 || puncak) return
        if (!animate || reduce()) { if (l == 3 && !reduce()) startCont(); return }
        val delta = (if (l >= old) 1f else -1f) * DEG[l]
        val a = ObjectAnimator.ofFloat(this, ROTATION, rotation, rotation + delta)
        a.duration = DUR[l]
        a.interpolator = DecelerateInterpolator(1.6f)
        a.addListener(object : AnimatorListenerAdapter() {
            private var cancelled = false
            override fun onAnimationCancel(an: Animator) { cancelled = true }
            override fun onAnimationEnd(an: Animator) {
                if (cancelled) return
                lock()
                if (load == 3) startCont()
            }
        })
        spin = a
        a.start()
    }

    private fun lock() {
        val f = ValueAnimator.ofFloat(0f, 1f, 0f)
        f.duration = 450L
        f.addUpdateListener { flash = it.animatedValue as Float; invalidate() }
        f.addListener(object : AnimatorListenerAdapter() { override fun onAnimationEnd(an: Animator) { flash = 0f; invalidate() } })
        flashAnim = f
        f.start()
    }

    private fun startCont() {
        cont?.cancel()
        val a = ObjectAnimator.ofFloat(this, ROTATION, rotation, rotation + 360f)
        a.duration = 7000L
        a.interpolator = LinearInterpolator()
        a.repeatCount = ValueAnimator.INFINITE
        cont = a
        if (isAttachedToWindow) a.start()
    }

    private fun stopAnims() {
        spin?.cancel(); spin = null
        cont?.cancel(); cont = null
        flashAnim?.cancel(); flashAnim = null
        flash = 0f
    }

    override fun onDetachedFromWindow() { cont?.pause(); super.onDetachedFromWindow() }
    override fun onAttachedToWindow() { super.onAttachedToWindow(); cont?.let { if (it.isPaused) it.resume() else if (!it.isStarted) it.start() } }

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
