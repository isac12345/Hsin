package com.hsin

import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioTrack
import kotlin.math.PI
import kotlin.math.sin

/** Suara sintesis kecil (tanpa file). Hanya berbunyi kalau Prefs.soundOn. */
object SoundFx {
    private fun tone(freqs: List<Pair<Int, Int>>, vol: Int) {
        Thread {
            try {
                val sr = 22050
                val total = freqs.sumOf { it.second } * sr / 1000
                val buf = ShortArray(total)
                var pos = 0
                for ((f, ms) in freqs) {
                    val n = ms * sr / 1000
                    for (i in 0 until n) {
                        val env = minOf(1f, i / 200f, (n - i) / 400f).coerceAtLeast(0f)
                        buf[pos++] = (sin(2.0 * PI * f * i / sr) * env * vol / 100.0 * 9000).toInt().toShort()
                    }
                }
                val t = AudioTrack.Builder()
                    .setAudioAttributes(AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_ASSISTANCE_SONIFICATION).setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION).build())
                    .setAudioFormat(AudioFormat.Builder().setEncoding(AudioFormat.ENCODING_PCM_16BIT).setSampleRate(sr).setChannelMask(AudioFormat.CHANNEL_OUT_MONO).build())
                    .setBufferSizeInBytes(buf.size * 2).setTransferMode(AudioTrack.MODE_STATIC).build()
                t.write(buf, 0, buf.size)
                t.play()
                Thread.sleep((total * 1000L / sr) + 150)
                t.release()
            } catch (_: Throwable) { }
        }.start()
    }

    fun play(p: Prefs, kind: String) {
        if (!p.soundOn) return
        val v = p.soundVol
        when (kind) {
            "tab" -> tone(listOf(900 to 40), v)
            "click" -> tone(listOf(700 to 30), v)
            "battery" -> tone(listOf(440 to 80, 520 to 80), v)
            "balanced" -> tone(listOf(520 to 80, 660 to 80), v)
            "performance" -> tone(listOf(600 to 70, 800 to 70, 1000 to 70), v)
            "overdrive" -> tone(listOf(500 to 60, 750 to 60, 1000 to 60, 1400 to 120), v)
            "ritual" -> tone(listOf(400 to 90, 600 to 90, 900 to 140), v)
            "good" -> tone(listOf(660 to 90, 880 to 130), v)
            "bad" -> tone(listOf(300 to 140, 220 to 180), v)
        }
    }
}
