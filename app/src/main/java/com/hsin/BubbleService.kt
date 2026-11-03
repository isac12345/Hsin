package com.hsin

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.SharedPreferences
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.provider.Settings
import android.widget.Toast
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

/**
 * Notifikasi ongoing (profil aktif) + SATU overlay floating (FloatingOverlay):
 * ringkas, penuh, merekam, dan bar tipis. Tidak ada bubble/HUD terpisah lagi.
 */
class BubbleService : Service() {
    companion object {
        const val CH = "hsin_mode"
        const val NID = 7
        const val ACT_SET = "com.hsin.SET_PROFILE"
        const val ACT_SHOW = "com.hsin.SHOW_BUBBLE"
        const val ACT_FPSLOG = "com.hsin.FPS_LOG"
        const val EXTRA_P = "profile"

        private const val WANT = "/data/adb/hsin/.bubble_want"

        /** Penanda untuk watchdog modul: "floating harus hidup". Dihapus saat pengguna mematikannya. */
        private fun mark(on: Boolean) {
            kotlin.concurrent.thread(isDaemon = true) {
                Root.execBlocking(if (on) "mkdir -p /data/adb/hsin; : > $WANT" else "rm -f $WANT", 8_000L)
            }
        }

        fun start(ctx: android.content.Context) {
            mark(true)
            ContextCompat.startForegroundService(ctx, Intent(ctx, BubbleService::class.java))
        }

        fun stop(ctx: android.content.Context) {
            mark(false)
            ctx.stopService(Intent(ctx, BubbleService::class.java))
        }
    }

    private lateinit var prefs: Prefs
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private var floating: FloatingOverlay? = null
    private var profile = "none"
    private var tempC = 0f
    private var batt = -1
    private var gamePkg = ""
    private var hudPkg = ""
    private var recOn = false
    private var ovdOn = false
    private var lastFps = 0
    private var protectedFor = ""
    private var flJob: Job? = null

    private val prefListener = SharedPreferences.OnSharedPreferenceChangeListener { _, key ->
        if (key == null) return@OnSharedPreferenceChangeListener
        if (key == "fl_always") {
            rebuild()
        } else if (key == "fl_start_thin") {
            flJob?.cancel()
            flJob = scope.launch { delay(100); floating?.applyStartMode() }
        } else if (key.startsWith("fl_") && key != "fl_x_p" && key != "fl_y_p" && key != "fl_x_l" && key != "fl_y_l") {
            // slider mengirim puluhan perubahan per detik: gabungkan jadi satu rebuild setelah 150 ms tenang
            flJob?.cancel()
            flJob = scope.launch { delay(150); floating?.rebuild() }
        } else if (key.startsWith("bubble_") && key != "bubble_x" && key != "bubble_y") {
            rebuild()
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        prefs = Prefs(this)
        createChannel()
        val n = buildNotification()
        if (Build.VERSION.SDK_INT >= 34) startForeground(NID, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        else startForeground(NID, n)
        prefs.sp.registerOnSharedPreferenceChangeListener(prefListener)
        harden()
        screenOn = object : android.content.BroadcastReceiver() {
            override fun onReceive(c: android.content.Context?, i: Intent?) {
                // layar menyala / buka kunci: pasang floating lagi seketika, tanpa menunggu siklus 8 dtk
                rebuild()
            }
        }
        val flt = android.content.IntentFilter().apply {
            addAction(Intent.ACTION_SCREEN_ON); addAction(Intent.ACTION_USER_PRESENT)
        }
        ContextCompat.registerReceiver(this, screenOn, flt, ContextCompat.RECEIVER_NOT_EXPORTED)
        val f = FloatingOverlay(this, prefs)
        f.onProfile = { p -> setProfile(p) }
        f.onRec = { toggleRec() }
        f.onOvd = { on -> toggleOvd(on) }
        f.onSession = { st0 ->
            scope.launch {
                // profil yang dicatat = yang tertinggi antara profil aktif dan profil yang diatur untuk game itu
                // (profil aktif tetap "daily" selama game di ROM ini, padahal game memakai profil per-game)
                val rank = { p: String -> when (p) { "battery" -> 1; "balanced" -> 2; "performance" -> 3; else -> 0 } }
                val gp = try { Hsin.games().firstOrNull { it.pkg == st0.pkg }?.profile.orEmpty() } catch (_: Exception) { "" }
                val st = if (rank(gp) > rank(st0.profile)) st0.copy(profile = gp) else st0
                prefs.fpsSessions = listOf(st) + prefs.fpsSessions
                val mode = if (st.ovdPct >= 50) "Puncak" else profileLabel(st.profile)
                Toast.makeText(this@BubbleService, "Sesi selesai ($mode): rata-rata ${st.avg} FPS, 1% terendah ${st.low1} FPS", Toast.LENGTH_LONG).show()
            }
        }
        f.onHidden = { floating?.detach() }
        floating = f
        rebuild()
        scope.launch {
            while (isActive) {
                val pm = getSystemService(POWER_SERVICE) as android.os.PowerManager
                if (!pm.isInteractive) {
                    // layar mati: tidak perlu memanggil su; cukup segarkan notifikasi dari baterai sistem
                    // hentikan aliran HUD (proses su + dumpsys) selama layar mati
                    floating?.detach()
                    readBattery(); updateNotification()
                    var w = 0
                    while (isActive && !pm.isInteractive && w < 15) { delay(2000); w++ }
                    continue
                }
                val s = Hsin.status()
                if (s == null) {
                    // status gagal/lambat: floating tetap dipastikan ada (jangan hilang menunggu su)
                    if (orbAllowed()) floating?.setGame("auto")
                }
                if (s != null) {
                    profile = s.profile
                    tempC = s.tempC
                    batt = s.batt
                    gamePkg = s.gamePkg
                    ovdOn = s.ovd
                    if (gamePkg.isNotEmpty()) prefs.lastGame = gamePkg
                    hudPkg = s.hudPkg.ifEmpty { s.gamePkg }
                    // Lindungi proses ini dari pembunuh memori tiap kali game baru terdeteksi (satu panggilan su, bukan tiap siklus).
                    if (hudPkg.isNotEmpty() && hudPkg != protectedFor) {
                        protectedFor = hudPkg
                        protectSelf()
                    }
                    recOn = s.rec
                    floating?.setOvd(s.ovd, s.ovdLevel, s.gamePkg.isNotEmpty())
                    floating?.setSession(s.gamePkg)
                    floating?.setProfileState(profile, recOn)
                    if (!orbAllowed()) {
                        floating?.detach()
                    } else {
                        floating?.attach()
                        floating?.setGame("auto")
                    }
                }
                // baterai/suhu selalu dari sistem (tanpa su) supaya notifikasi tidak basi walau status gagal/lambat
                readBattery()
                updateNotification()
                delay(if (gamePkg.isNotEmpty()) 4000L else 6000L)
            }
        }
    }

    private var screenOn: android.content.BroadcastReceiver? = null

    /** Orb selalu tampil bila "Floating selalu tampil" aktif (bawaan); bila mati, hanya saat game berjalan atau merekam FPS. */
    private fun orbAllowed(): Boolean =
        !(prefs.bubbleHidden || (!prefs.bubbleOn && !prefs.hudOn) || !Settings.canDrawOverlays(this)) &&
            (prefs.flAlways || gamePkg.isNotEmpty() || FpsLog.on || recOn)

    /** Minta sistem jangan membekukan/membunuh service ini: whitelist hemat daya, bucket aktif, oom. Butuh root, gagal diam-diam. */
    private fun harden() {
        val pkg = packageName
        val pid = android.os.Process.myPid()
        scope.launch {
            Root.exec(
                "dumpsys deviceidle whitelist +$pkg >/dev/null 2>&1; " +
                    "cmd appops set $pkg RUN_ANY_IN_BACKGROUND allow >/dev/null 2>&1; " +
                    "cmd appops set $pkg RUN_IN_BACKGROUND allow >/dev/null 2>&1; " +
                    "am set-standby-bucket $pkg active >/dev/null 2>&1; " +
                    "[ -w /proc/$pid/oom_score_adj ] && echo -500 > /proc/$pid/oom_score_adj; true",
                10_000L,
            )
        }
    }

    /** Turunkan oom_score_adj proses ini (butuh root). Gagal diam-diam: hanya tambahan, bukan syarat jalan. */
    private fun protectSelf() {
        val pid = android.os.Process.myPid()
        scope.launch {
            Root.exec("[ -w /proc/$pid/oom_score_adj ] && echo -300 > /proc/$pid/oom_score_adj", 5_000L)
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACT_SET -> intent.getStringExtra(EXTRA_P)?.let {
                if (it == "puncak") {
                    if (gamePkg.isEmpty()) Toast.makeText(this, trn("Buka game dulu untuk mode Puncak"), Toast.LENGTH_SHORT).show()
                    else toggleOvd(!ovdOn)
                } else setProfile(it)
            }
            ACT_FPSLOG -> {
                // layar Performa di app: mulai/berhenti rekam data FPS; pastikan floating terpasang (aliran HUD)
                if (!FpsLog.on) { prefs.bubbleHidden = false; rebuild() }
                floating?.toggleFpsLog()
            }
            ACT_SHOW -> {
                prefs.bubbleHidden = false
                rebuild()
                floating?.setGame("auto")
            }
        }
        return START_STICKY
    }

    override fun onDestroy() {
        prefs.sp.unregisterOnSharedPreferenceChangeListener(prefListener)
        try { screenOn?.let { unregisterReceiver(it) } } catch (_: Exception) {}
        floating?.release()
        floating = null
        scope.cancel()
        super.onDestroy()
    }

    private fun rebuild() {
        updateNotification()
        if (!orbAllowed()) {
            floating?.detach()
            return
        }
        floating?.setProfileState(profile, recOn)
        floating?.attach()
        floating?.setGame("auto")
    }

    // ---------- profil ----------
    private fun setProfile(p: String) {
        if (p !in PROFILE_KEYS) return
        profile = p
        floating?.setProfileState(p, recOn)
        updateNotification()
        scope.launch {
            val r = Hsin.setProfile(p)
            Toast.makeText(
                this@BubbleService,
                if (r.ok) "Mode ${profileLabel(p)}" else "Gagal ganti mode",
                Toast.LENGTH_SHORT,
            ).show()
            Hsin.status()?.let {
                profile = it.profile
                tempC = it.tempC
                batt = it.batt
                gamePkg = it.gamePkg
            }
            floating?.setProfileState(profile, recOn)
            updateNotification()
        }
    }

    // ---------- rekam ----------
    private fun toggleOvd(on: Boolean) {
        scope.launch {
            val r = if (on) Hsin.ovdStart() else Hsin.ovdStop()
            if (on && !r.ok) {
                val msg = r.out.lines().firstOrNull { it.startsWith("ERROR") }?.removePrefix("ERROR:")?.trim() ?: "Puncak gagal"
                Toast.makeText(this@BubbleService, msg, Toast.LENGTH_LONG).show()
            }
            Hsin.status()?.let { ovdOn = it.ovd; floating?.setOvd(it.ovd, it.ovdLevel, it.gamePkg.isNotEmpty()); updateNotification() }
        }
    }

    private fun toggleRec() {
        val start = !recOn
        scope.launch {
            val r = if (start) Hsin.recStart() else Hsin.recStop()
            if (!r.ok) Toast.makeText(this@BubbleService, trn("Gagal mengakses rekaman"), Toast.LENGTH_SHORT).show()
            Hsin.status()?.let {
                recOn = it.rec
                profile = it.profile
            }
            floating?.setProfileState(profile, recOn)
            updateNotification()
        }
    }

    // ---------- notifikasi ----------
    private fun createChannel() {
        val nm = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        try { nm.deleteNotificationChannel("alpha_profile") } catch (_: Exception) {}
        val ch = NotificationChannel(CH, "HSIN", NotificationManager.IMPORTANCE_LOW)
        ch.setShowBadge(false)
        ch.setSound(null, null)
        ch.enableVibration(false)
        nm.createNotificationChannel(ch)
    }

    private fun modeNow(): String = if (ovdOn) "Puncak" else profileLabel(profile)

    private fun buildNotification(): Notification {
        val flags = PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        val hidden = prefs.bubbleHidden
        val content: PendingIntent = if (hidden) {
            PendingIntent.getService(this, 90, Intent(this, BubbleService::class.java).setAction(ACT_SHOW), flags)
        } else {
            PendingIntent.getActivity(
                this, 91,
                Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP),
                flags,
            )
        }
        val gameName = if (gamePkg.isNotEmpty()) {
            try { packageManager.getApplicationLabel(packageManager.getApplicationInfo(gamePkg, 0)).toString() } catch (_: Exception) { gamePkg }
        } else ""
        lastFps = floating?.lastFps ?: 0
        val text = buildString {
            if (gameName.isNotEmpty()) append(gameName) else append("Siaga")
            if (gameName.isNotEmpty() && lastFps > 0) append(" · ").append(lastFps).append(" FPS")
            if (tempC > 0f) append(" · %.0f°C".format(tempC))
            if (batt >= 0) append(" · ").append(batt).append("%")
        }
        val b = NotificationCompat.Builder(this, CH)
            .setSmallIcon(R.drawable.ic_stat_hsin)
            .setContentTitle("HSIN · Mode ${modeNow()}")
            .setContentText(if (hidden) "Orb disembunyikan · ketuk untuk memunculkan" else text)
            .setContentIntent(content)
            .setOngoing(true)
            .setShowWhen(false)
            .setOnlyAlertOnce(true)
            .setSilent(true)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setPriority(NotificationCompat.PRIORITY_LOW)
        val keys = PROFILE_KEYS + "puncak"
        val labels = PROFILE_LABELS + "Puncak"
        keys.forEachIndexed { i, k ->
            val active = if (k == "puncak") ovdOn else (!ovdOn && k == profile)
            val pi = PendingIntent.getService(
                this, 100 + i,
                Intent(this, BubbleService::class.java).setAction(ACT_SET).putExtra(EXTRA_P, k),
                flags,
            )
            b.addAction(0, (if (active) "● " else "") + labels[i], pi)
        }
        return b.build()
    }

    private fun readBattery() {
        try {
            val i = registerReceiver(null, android.content.IntentFilter(Intent.ACTION_BATTERY_CHANGED)) ?: return
            val lv = i.getIntExtra(android.os.BatteryManager.EXTRA_LEVEL, -1)
            val sc = i.getIntExtra(android.os.BatteryManager.EXTRA_SCALE, 100)
            if (lv >= 0 && sc > 0) batt = lv * 100 / sc
            val t = i.getIntExtra(android.os.BatteryManager.EXTRA_TEMPERATURE, -1)
            if (t > 0) tempC = t / 10f
        } catch (_: Exception) {}
    }

    private fun updateNotification() {
        val nm = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        nm.notify(NID, buildNotification())
    }
}
