package com.hsin

import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioTrack
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.sin
import kotlin.math.tanh

/**
 * Suara tema balap/game-space, disintesis sendiri (tanpa file): bass agresif + digital tajam.
 * Dirender ke PCM sekali per jenis lalu disimpan; dinormalkan + dijenuhkan lembut supaya KERAS
 * (tanpa headset pun terdengar) dan diputar lewat volume media. Hanya berbunyi kalau Prefs.soundOn.
 */
object SoundFx {
    private const val SR = 44100
    private const val GR = 0.9f   // agresif
    private const val DG = 0.95f  // digital
    private val rnd = java.util.Random(11)
    private val cache = HashMap<String, ShortArray>()

    private class Buf(secs: Float) { val d = FloatArray((secs * SR).toInt() + SR / 8) }

    private fun curve(k: Float, x: Float) = (1f + k) * x / (1f + k * abs(x))

    private fun env(t: Float, dur: Float, vol: Float, att: Float): Float {
        val a = min(att, dur / 4f)
        return if (t < a) 0.0001f * (vol / 0.0001f).pow(t / a)
        else vol * (0.0001f / vol).pow(((t - a) / (dur - a)).coerceIn(0f, 1f))
    }

    private fun wave(type: Int, p: Float): Float {
        val x = p - floor(p)
        return when (type) { 0 -> sin(2f * PI.toFloat() * x); 1 -> if (x < 0.5f) 1f else -1f; 2 -> 2f * x - 1f; else -> 4f * abs(x - 0.5f) - 1f }
    }

    private fun osc(b: Buf, type: String, f1: Float, f2: Float, dur: Float, vol: Float, t0: Float = 0f, d: Float = 0f) {
        val ty = when (type) { "sine" -> 0; "square" -> 1; "sawtooth" -> 2; else -> 3 }
        val s0 = (t0 * SR).toInt(); val n = (dur * SR).toInt()
        var ph = 0f
        val r = max(f2, 1f) / f1
        for (i in 0 until n) {
            val t = i.toFloat() / SR
            val f = f1 * r.pow(t / dur)
            ph += f / SR
            var s = wave(ty, ph) * env(t, dur, vol, 0.015f)
            if (d > 0f) s = curve(d * GR + 0.5f, s)
            val k = s0 + i
            if (k < b.d.size) b.d[k] += s
        }
    }

    /** Biquad RBJ: 0 lowpass, 1 highpass, 2 bandpass. */
    private class Bq { var x1 = 0f; var x2 = 0f; var y1 = 0f; var y2 = 0f; var b0 = 0f; var b1 = 0f; var b2 = 0f; var a1 = 0f; var a2 = 0f
        fun set(type: Int, f: Float, q: Float) {
            val fc = f.coerceIn(20f, SR / 2.2f); val w = 2f * PI.toFloat() * fc / SR
            val al = sin(w) / (2f * max(q, 0.1f)); val c = cos(w); val a0 = 1f + al
            when (type) {
                0 -> { b0 = (1 - c) / 2; b1 = 1 - c; b2 = (1 - c) / 2 }
                1 -> { b0 = (1 + c) / 2; b1 = -(1 + c); b2 = (1 + c) / 2 }
                else -> { b0 = al; b1 = 0f; b2 = -al }
            }
            a1 = -2f * c / a0; a2 = (1f - al) / a0; b0 /= a0; b1 /= a0; b2 /= a0
        }
        fun p(x: Float): Float { val y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2; x2 = x1; x1 = x; y2 = y1; y1 = y; return y }
    }

    private fun noise(b: Buf, dur: Float, vol: Float, type: String, f1: Float, f2: Float, q: Float, t0: Float = 0f) {
        val ty = when (type) { "lowpass" -> 0; "highpass" -> 1; else -> 2 }
        val s0 = (t0 * SR).toInt(); val n = (dur * SR).toInt()
        val bq = Bq(); val r = max(f2, 20f) / f1
        for (i in 0 until n) {
            val t = i.toFloat() / SR
            if (i % 16 == 0) bq.set(ty, f1 * r.pow(t / dur), q)
            val g = vol * (0.0001f / vol).pow(t / dur)
            val k = s0 + i
            if (k < b.d.size) b.d[k] += bq.p(rnd.nextFloat() * 2f - 1f) * g
        }
    }

    private fun engine(b: Buf, f1: Float, f2: Float, dur: Float, vol: Float, t0: Float = 0f) {
        val s0 = (t0 * SR).toInt(); val n = (dur * SR).toInt()
        var pa = 0f; var pb = 0f; var pl = 0f
        val r = f2 / f1; val bq = Bq()
        for (i in 0 until n) {
            val t = i.toFloat() / SR
            val k = r.pow(t / dur); val f = f1 * k
            pa += f / SR; pb += f / 2f / SR; pl += f / 2f / SR
            val mod = 0.65f + 0.35f * sin(2f * PI.toFloat() * pl)
            val x = (wave(2, pa) + wave(1, pb)) * mod
            if (i % 16 == 0) bq.set(0, 600f * (2600f / 600f).pow(t / dur), 0.7f)
            var y = curve(8f * GR + 1f, bq.p(x))
            val e = if (t < 0.05f) 0.0001f * (vol / 0.0001f).pow(t / 0.05f) else if (t < dur * 0.8f) vol else vol * (0.0001f / vol).pow((t - dur * 0.8f) / (dur * 0.2f))
            y *= e
            val kk = s0 + i
            if (kk < b.d.size) b.d[kk] += y
        }
    }

    // ---- lapisan agresif
    private fun hit(b: Buf, t0: Float, v: Float = 0.6f) { osc(b, "sine", 130f, 32f, 0.28f, v, t0); noise(b, 0.08f, 0.35f, "lowpass", 3000f, 300f, 1f, t0); noise(b, 0.02f, 0.3f, "highpass", 5000f, 5000f, 1f, t0) }
    private fun blow(b: Buf, t0: Float = 0f) = noise(b, 0.45f, 0.35f, "bandpass", 6000f, 1800f, 0.8f, t0)
    private fun tire(b: Buf, dur: Float, t0: Float = 0f) = noise(b, dur, 0.25f, "bandpass", 2800f, 2300f, 10f, t0)
    private fun crackle(b: Buf, t0: Float, n: Int) { for (i in 0 until n) noise(b, 0.03f, 0.5f, "bandpass", 900f + rnd.nextFloat() * 1800f, 500f, 2f, t0 + rnd.nextFloat() * 0.5f) }
    private fun zap(b: Buf, a: Float, c: Float, dur: Float, v: Float, t0: Float = 0f) { osc(b, "sawtooth", a, c, dur, v, t0, 10f); osc(b, "sine", a * 1.5f, c * 1.5f, dur, v * 0.5f, t0) }
    // ---- lapisan digital
    private fun digi(b: Buf, notes: List<Float>, step: Float, dur: Float, v: Float, t0: Float = 0f) {
        notes.forEachIndexed { i, f -> osc(b, "square", f, f, dur, v * DG, t0 + i * step); osc(b, "sine", f * 2f, f * 2f, dur, v * 0.5f * DG, t0 + i * step) }
    }
    private fun glitch(b: Buf, t0: Float, n: Int, v: Float = 0.1f) { for (i in 0 until n) { val a = 800f + rnd.nextFloat() * 3500f; osc(b, "square", a, a * (0.6f + rnd.nextFloat() * 0.8f), 0.025f, v * DG, t0 + i * 0.035f) } }
    private fun sweep(b: Buf, a: Float, c: Float, dur: Float, v: Float, t0: Float = 0f) { osc(b, "triangle", a, c, dur, v * DG, t0); osc(b, "sine", a * 2f, c * 2f, dur, v * 0.6f * DG, t0) }
    private fun chime(b: Buf, t0: Float = 0f) { osc(b, "sine", 1319f, 1319f, 0.2f, 0.22f * DG, t0); osc(b, "sine", 1760f, 1760f, 0.35f, 0.22f * DG, t0 + 0.12f); osc(b, "sine", 3520f, 3520f, 0.3f, 0.06f * DG, t0 + 0.12f) }
    private fun click(b: Buf, t0: Float, v: Float = 0.4f) { noise(b, 0.03f, v, "highpass", 2500f, 2500f, 1f, t0); osc(b, "sine", 180f, 70f, 0.07f, v + 0.1f, t0) }

    private fun build(kind: String): Pair<Float, (Buf) -> Unit>? = when (kind) {
        "ignition" -> 2.4f to { b -> for (i in 0 until 4) osc(b, "square", 95f, 70f, 0.1f, 0.22f, i * 0.16f, 5f); engine(b, 70f, 110f, 0.4f, 0.5f, 0.7f); engine(b, 110f, 270f, 0.4f, 0.5f, 1.1f); engine(b, 270f, 90f, 0.5f, 0.45f, 1.5f); digi(b, listOf(880f, 1320f, 1760f, 2640f), 0.07f, 0.1f, 0.1f, 1.2f); hit(b, 1.1f, 0.5f) }
        "loading" -> 3.4f to { b -> engine(b, 60f, 330f, 3f, 0.35f); for (i in 0 until 14) osc(b, "square", 1800f + i * 60f, 1800f + i * 60f, 0.02f, 0.07f * DG, i * 0.21f); sweep(b, 1200f, 4200f, 0.5f, 0.1f, 2.5f); glitch(b, 2.9f, 4, 0.08f) }
        "loaded" -> 1.0f to { b -> blow(b); hit(b, 0.12f, 0.5f); digi(b, listOf(1320f, 1760f, 2640f), 0.06f, 0.1f, 0.12f, 0.14f); chime(b, 0.35f) }
        "launch" -> 1.4f to { b -> engine(b, 80f, 320f, 0.7f, 0.5f); tire(b, 0.5f, 0.45f); zap(b, 300f, 3000f, 0.5f, 0.12f, 0.3f); hit(b, 0.7f, 0.6f); glitch(b, 0.75f, 4, 0.1f) }
        "splash" -> 1.3f to { b -> sweep(b, 800f, 4500f, 0.6f, 0.12f); hit(b, 0.55f, 0.6f); chime(b, 0.55f); glitch(b, 0.8f, 5, 0.08f) }
        "tap" -> 0.2f to { b -> click(b, 0f, 0.5f); osc(b, "square", 3200f, 3200f, 0.03f, 0.1f * DG, 0.01f) }
        "tap2" -> 0.2f to { b -> digi(b, listOf(2000f, 2800f), 0.045f, 0.04f, 0.12f); click(b, 0f, 0.25f) }
        "on" -> 0.4f to { b -> hit(b, 0f, 0.35f); osc(b, "sawtooth", 100f, 190f, 0.15f, 0.28f, 0.03f, 6f); digi(b, listOf(1200f, 1800f), 0.06f, 0.07f, 0.12f, 0.04f) }
        "off" -> 0.4f to { b -> hit(b, 0f, 0.35f); osc(b, "sawtooth", 190f, 90f, 0.15f, 0.28f, 0.03f, 6f); digi(b, listOf(1800f, 1200f), 0.06f, 0.07f, 0.12f, 0.04f) }
        "open" -> 0.7f to { b -> sweep(b, 600f, 3400f, 0.3f, 0.14f); noise(b, 0.3f, 0.15f, "bandpass", 500f, 3000f, 1f); hit(b, 0.28f, 0.3f) }
        "close" -> 0.5f to { b -> blow(b); sweep(b, 3000f, 500f, 0.25f, 0.12f, 0.05f); click(b, 0.1f, 0.3f) }
        "swipe" -> 0.4f to { b -> noise(b, 0.2f, 0.3f, "bandpass", 800f, 3500f, 2f); sweep(b, 800f, 3000f, 0.15f, 0.08f) }
        "boost" -> 2.0f to { b -> noise(b, 1f, 0.4f, "bandpass", 2500f, 9000f, 0.8f); zap(b, 150f, 2600f, 1f, 0.2f); osc(b, "sine", 70f, 45f, 1f, 0.6f); hit(b, 0f, 0.7f); digi(b, listOf(1760f, 2200f, 2640f, 3520f), 0.05f, 0.06f, 0.1f, 0.8f); crackle(b, 0.95f, 3) }
        "clean" -> 1.2f to { b -> for (i in 0 until 9) { noise(b, 0.04f, 0.3f, "bandpass", 3000f, 2500f, 2f, i * 0.055f); osc(b, "square", 170f, 170f, 0.04f, 0.2f, i * 0.055f, 6f) }; glitch(b, 0.1f, 12, 0.09f); hit(b, 0.55f, 0.5f); sweep(b, 1000f, 3600f, 0.4f, 0.1f, 0.55f) }
        "cool" -> 1.3f to { b -> osc(b, "sawtooth", 1500f, 300f, 1f, 0.08f, 0f, 3f); noise(b, 1f, 0.2f, "bandpass", 3000f, 500f, 1.5f); sweep(b, 4000f, 1500f, 0.9f, 0.08f); digi(b, listOf(3520f, 2640f), 0.12f, 0.15f, 0.06f, 0.2f) }
        "perf" -> 1.8f to { b -> engine(b, 70f, 300f, 0.6f, 0.5f); for (i in 0 until 4) { osc(b, "sawtooth", 270f, 255f, 0.07f, 0.35f, 0.7f + i * 0.1f, 8f); osc(b, "sine", 90f, 80f, 0.07f, 0.4f, 0.7f + i * 0.1f) }; crackle(b, 1.05f, 4); digi(b, listOf(1320f, 1760f, 2200f), 0.04f, 0.05f, 0.1f, 0.65f); glitch(b, 1.1f, 6, 0.1f) }
        "done" -> 1.6f to { b -> listOf(220f, 277f, 330f, 440f).forEachIndexed { i, f -> osc(b, "sawtooth", f, f, 0.15f, 0.2f, i * 0.09f, 5f) }; listOf(220f, 330f, 440f).forEach { f -> osc(b, "sawtooth", f, f, 0.6f, 0.15f, 0.4f, 3f) }; hit(b, 0.4f, 0.6f); digi(b, listOf(1320f, 1760f, 2640f, 3520f), 0.06f, 0.12f, 0.1f, 0.45f); chime(b, 0.7f) }
        "boostoff" -> 1.0f to { b -> osc(b, "sawtooth", 270f, 60f, 0.6f, 0.35f, 0f, 7f); crackle(b, 0.1f, 5); digi(b, listOf(2640f, 1760f, 1320f), 0.05f, 0.07f, 0.09f); sweep(b, 3000f, 300f, 0.5f, 0.08f) }
        "notif" -> 0.7f to { b -> chime(b); hit(b, 0f, 0.25f); digi(b, listOf(2640f), 0f, 0.05f, 0.08f, 0.02f) }
        "hot" -> 1.6f to { b -> for (i in 0 until 3) { osc(b, "square", 700f, 1100f, 0.2f, 0.15f, i * 0.4f, 6f); osc(b, "square", 1100f, 700f, 0.2f, 0.15f, i * 0.4f + 0.2f, 6f) }; digi(b, listOf(3520f, 3520f, 3520f), 0.4f, 0.08f, 0.1f) }
        "fps" -> 1.0f to { b -> osc(b, "sawtooth", 140f, 60f, 0.5f, 0.35f, 0f, 8f); crackle(b, 0.1f, 5); glitch(b, 0f, 10, 0.1f) }
        "err" -> 1.2f to { b -> osc(b, "sawtooth", 110f, 100f, 0.3f, 0.3f, 0f, 12f); osc(b, "sawtooth", 110f, 100f, 0.3f, 0.3f, 0.38f, 12f); glitch(b, 0.7f, 6, 0.12f) }
        "ok" -> 1.0f to { b -> listOf(262f, 330f, 392f).forEach { f -> osc(b, "sawtooth", f, f, 0.5f, 0.15f, 0f, 3f) }; hit(b, 0f, 0.45f); digi(b, listOf(1320f, 1760f, 2640f), 0.07f, 0.1f, 0.1f, 0.1f); chime(b, 0.3f) }
        "adapt0" -> 0.3f to { b -> click(b, 0f, 0.35f); osc(b, "triangle", 330f, 500f, 0.12f, 0.3f * DG, 0.01f) }
        "adapt1" -> 0.45f to { b -> click(b, 0f, 0.4f); osc(b, "triangle", 440f, 660f, 0.14f, 0.3f * DG, 0.01f); osc(b, "sine", 880f, 880f, 0.2f, 0.12f * DG, 0.1f) }
        "adapt2" -> 0.6f to { b -> hit(b, 0f, 0.35f); osc(b, "triangle", 587f, 880f, 0.16f, 0.3f * DG, 0.01f); chime(b, 0.12f) }
        "adapt3" -> 0.9f to { b -> hit(b, 0f, 0.5f); sweep(b, 500f, 2400f, 0.35f, 0.12f); osc(b, "sawtooth", 784f, 1180f, 0.2f, 0.18f, 0.1f, 3f); crackle(b, 0.25f, 3); chime(b, 0.45f) }
        else -> null
    }

    private fun alias(kind: String) = when (kind) {
        "tab" -> "tap2"; "click" -> "tap"; "battery" -> "cool"; "balanced" -> "on"; "adapt" -> "on"; "performance" -> "perf"
        "overdrive" -> "boost"; "ritual" -> "ignition"; "good" -> "ok"; "bad" -> "err"; else -> kind
    }

    private fun render(kind: String): ShortArray? {
        val (secs, f) = build(kind) ?: return null
        val b = Buf(secs); f(b)
        var peak = 0.0001f
        for (v in b.d) peak = max(peak, abs(v))
        val g = 1f / peak
        val drive = 2.4f; val nrm = tanh(drive)
        return ShortArray(b.d.size) { i -> (tanh(drive * b.d[i] * g * 0.9f) / nrm * 32000f).toInt().coerceIn(-32767, 32767).toShort() }
    }

    private val exec = java.util.concurrent.Executors.newSingleThreadExecutor { r -> Thread(r, "hsin-sfx").apply { isDaemon = true } }
    @Volatile private var track: AudioTrack? = null

    private fun ensureTrack(): AudioTrack? {
        track?.let { return it }
        return try {
            AudioTrack.Builder()
                .setAudioAttributes(AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_MEDIA).setContentType(AudioAttributes.CONTENT_TYPE_MUSIC).build())
                .setAudioFormat(AudioFormat.Builder().setEncoding(AudioFormat.ENCODING_PCM_16BIT).setSampleRate(SR).setChannelMask(AudioFormat.CHANNEL_OUT_MONO).build())
                .setBufferSizeInBytes(maxOf(AudioTrack.getMinBufferSize(SR, AudioFormat.CHANNEL_OUT_MONO, AudioFormat.ENCODING_PCM_16BIT), 8192))
                .setTransferMode(AudioTrack.MODE_STREAM).build().also { track = it }
        } catch (_: Throwable) { null }
    }

    /** Satu pemutar bersama, satu thread; PCM dibuat sekali lalu disimpan di memori. */
    fun play(p: Prefs, kind: String) {
        if (!p.soundOn) return
        val k = alias(kind)
        val vol = (p.soundVol / 100f).coerceIn(0.1f, 1f)
        try { track?.let { it.pause(); it.flush() } } catch (_: Throwable) { }
        exec.execute {
            try {
                val pcm = synchronized(cache) { cache[k] } ?: (render(k) ?: return@execute).also { synchronized(cache) { cache[k] = it } }
                val t = ensureTrack() ?: return@execute
                t.pause(); t.flush()
                t.setVolume(vol)
                t.play()
                t.write(pcm, 0, pcm.size)
            } catch (_: Throwable) { }
        }
    }
}
