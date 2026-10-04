package com.hsin

import android.app.Application
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.net.Uri
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.graphics.ImageBitmap
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

class HsinVm(app: Application) : AndroidViewModel(app) {
    private val ctx: Context = app.applicationContext
    val store = Store(ctx)

    // ---- state utama ----
    var setup by mutableStateOf(Setup.Loading)
    var device by mutableStateOf<DeviceInfo?>(null)
    var cats by mutableStateOf<List<Category>>(emptyList())
    var live by mutableStateOf<Live?>(null)
    val pending = mutableStateMapOf<String, String>()
    var busy by mutableStateOf(false)
    var refreshing by mutableStateOf(false)
    var message by mutableStateOf<String?>(null)
    var lastApply by mutableStateOf("Terakhir diterapkan: belum ada")
    var failures by mutableStateOf<List<Pair<String, String>>>(emptyList())

    // ---- navigasi ----
    var tab by mutableIntStateOf(0)
    var openCat by mutableStateOf<String?>(null)
    var customOpen by mutableStateOf(false)

    // ---- tampilan ----
    var theme by mutableIntStateOf(store.theme)
    var cardAlpha by mutableStateOf(store.cardAlpha)
    var bannerBmp by mutableStateOf<ImageBitmap?>(null)
    var wallBmp by mutableStateOf<ImageBitmap?>(null)
    var presets by mutableStateOf(store.presets)

    // ---- monitor ----
    var paused by mutableStateOf(false)
    var monitorMode by mutableIntStateOf(0) // 0 live, 1 log
    var logWhich by mutableIntStateOf(0) // 0 boot, 1 apply
    var logLines by mutableStateOf<List<String>>(emptyList())
    val hCpuTemp = mutableStateListOf<Float>()
    val hCpuMhz = mutableStateListOf<Float>()
    val hGpuMhz = mutableStateListOf<Float>()
    val hRamGb = mutableStateListOf<Float>()

    private var foreground = false
    private var loading = false
    private var monitorJob: Job? = null

    init {
        loadImages()
        loadAll()
        startMonitor()
    }

    // ================= helper turunan =================
    val allKnobs: List<Knob> get() = cats.flatMap { it.knobs }
    val supportedCount: Int get() = allKnobs.count { it.type != "locked" }
    val changedCount: Int get() = allKnobs.count { it.type != "locked" && it.cur != it.def }

    fun valueOf(k: Knob): String = pending[k.key] ?: k.cur

    val pendingList: List<Pair<String, String>>
        get() {
            val out = ArrayList<Pair<String, String>>()
            for (k in allKnobs) {
                val v = pending[k.key] ?: continue
                if (v != k.cur) out.add(Pair(k.key, v))
            }
            return out
        }

    fun setPending(k: Knob, v: String) {
        if (v == k.cur) pending.remove(k.key) else pending[k.key] = v
    }

    private fun valid(k: Knob, v: String): Boolean = when (k.type) {
        "choice" -> v in k.options
        "range" -> v.toIntOrNull()?.let { it in k.min..k.max } ?: false
        else -> false
    }

    // ================= muat data =================
    fun onForeground(f: Boolean) {
        foreground = f
        if (f && setup != Setup.Loading) loadAll(silent = true)
    }

    fun loadAll(silent: Boolean = false) {
        if (loading) return
        loading = true
        viewModelScope.launch(Dispatchers.IO) {
            if (!silent) withContext(Dispatchers.Main) { setup = Setup.Loading }
            withContext(Dispatchers.Main) { refreshing = true }
            val root = Shell.hasRoot()
            if (!root) {
                withContext(Dispatchers.Main) { setup = Setup.NoRoot; refreshing = false }
                loading = false
                return@launch
            }
            if (!Repo.ping()) {
                withContext(Dispatchers.Main) { setup = Setup.NoModule; refreshing = false }
                loading = false
                return@launch
            }
            val dev = Repo.device()
            val c = Repo.knobs()
            val st = Repo.status()
            withContext(Dispatchers.Main) {
                if (dev != null) device = dev
                if (c != null) {
                    cats = c
                    val keep = HashMap<String, String>()
                    for (k in c.flatMap { it.knobs }) {
                        val v = pending[k.key]
                        if (v != null && v != k.cur && k.type != "locked") keep[k.key] = v
                    }
                    pending.clear()
                    pending.putAll(keep)
                }
                if (st != null) live = st
                setup = Setup.Ready
                refreshing = false
            }
            loading = false
        }
    }

    fun loadImages() {
        viewModelScope.launch(Dispatchers.IO) {
            val b = Images.load(ctx, Images.BANNER, 1400) ?: Images.loadDefaultBanner(ctx)
            val w = Images.load(ctx, Images.WALL, 1600)
            withContext(Dispatchers.Main) { bannerBmp = b; wallBmp = w }
        }
    }

    // ================= knob =================
    fun applyPending() {
        if (busy) return
        val list = pendingList
        if (list.isEmpty()) { message = "Tidak ada perubahan untuk diterapkan"; return }
        busy = true
        viewModelScope.launch(Dispatchers.IO) {
            val r = Repo.setMany(list)
            val c = Repo.knobs()
            val st = Repo.status()
            withContext(Dispatchers.Main) {
                for (k in r.okKeys) pending.remove(k)
                if (c != null) cats = c
                if (st != null) live = st
                lastApply = if (r.error.isNotEmpty()) "Gagal: ${r.error}"
                else "Terakhir diterapkan: ${r.ok} knob, ${r.fail} gagal"
                if (r.fail > 0 || r.error.isNotEmpty()) {
                    failures = if (r.failures.isEmpty()) listOf(Pair("modul", r.error)) else r.failures
                } else {
                    message = "${r.ok} knob diterapkan"
                }
                busy = false
            }
        }
    }

    fun discardPending() { pending.clear() }

    fun restoreDefaults() {
        if (busy) return
        busy = true
        viewModelScope.launch(Dispatchers.IO) {
            val r = Repo.restore()
            val c = Repo.knobs()
            val st = Repo.status()
            withContext(Dispatchers.Main) {
                pending.clear()
                if (c != null) cats = c
                if (st != null) live = st
                lastApply = if (r.error.isNotEmpty()) "Gagal: ${r.error}" else "Dipulihkan ke bawaan: ${r.ok} knob, ${r.fail} gagal"
                message = lastApply
                busy = false
            }
        }
    }

    fun disableSafeMode() {
        viewModelScope.launch(Dispatchers.IO) {
            val ok = Repo.guardReset()
            val st = Repo.status()
            withContext(Dispatchers.Main) {
                if (st != null) live = st
                message = if (ok) "Mode aman dimatikan" else "Gagal mematikan mode aman"
            }
        }
    }

    // ================= preset =================
    fun savePreset(name: String) {
        val m = LinkedHashMap<String, String>()
        for (k in allKnobs) {
            if (k.type == "locked") continue
            val v = pending[k.key] ?: k.cur
            if (v != k.def) m[k.key] = v
        }
        if (m.isEmpty()) { message = "Belum ada knob yang diubah dari bawaan"; return }
        val nm = name.trim().ifEmpty { "Preset ${presets.size + 1}" }.take(24)
        presets = presets + Preset(nm, m)
        store.presets = presets
        message = "Preset \"$nm\" disimpan (${m.size} knob)"
    }

    fun loadPreset(p: Preset) {
        var n = 0
        for (k in allKnobs) {
            if (k.type == "locked") continue
            val want = p.values[k.key] ?: k.def
            if (!valid(k, want)) continue
            if (want != k.cur) { pending[k.key] = want; n++ } else pending.remove(k.key)
        }
        if (n == 0) {
            message = "Preset sudah sama dengan kondisi sekarang"
        } else {
            openCat = null
            tab = 1
            message = "$n knob siap diterapkan, tekan Terapkan"
        }
    }

    fun deletePreset(p: Preset) {
        presets = presets.filter { it !== p }
        store.presets = presets
    }

    // ================= tampilan =================
    fun setTheme(t: Int) { theme = t; store.theme = t }
    fun setCardAlpha(a: Float) { cardAlpha = a; store.cardAlpha = a }

    fun setImage(uri: Uri, banner: Boolean) {
        viewModelScope.launch(Dispatchers.IO) {
            val name = if (banner) Images.BANNER else Images.WALL
            val ok = Images.saveFrom(ctx, uri, name, if (banner) 1400 else 1600)
            val bmp = if (ok) Images.load(ctx, name, if (banner) 1400 else 1600) else null
            withContext(Dispatchers.Main) {
                if (!ok || bmp == null) {
                    message = "Gambar tidak bisa dibaca"
                } else if (banner) {
                    bannerBmp = bmp
                } else {
                    wallBmp = bmp
                }
            }
        }
    }

    fun resetImage(banner: Boolean) {
        viewModelScope.launch(Dispatchers.IO) {
            Images.delete(ctx, if (banner) Images.BANNER else Images.WALL)
            val b = if (banner) Images.loadDefaultBanner(ctx) else null
            withContext(Dispatchers.Main) {
                if (banner) bannerBmp = b else wallBmp = null
            }
        }
    }

    // ================= monitor & log =================
    private fun push(list: MutableList<Float>, v: Float) {
        list.add(v)
        while (list.size > 30) list.removeAt(0)
    }

    private fun startMonitor() {
        monitorJob?.cancel()
        monitorJob = viewModelScope.launch(Dispatchers.IO) {
            while (isActive) {
                if (foreground && tab == 2 && monitorMode == 0 && !paused && setup == Setup.Ready && !customOpen) {
                    val st = Repo.status()
                    if (st != null) {
                        withContext(Dispatchers.Main) {
                            live = st
                            if (st.cpuTemp > 0) push(hCpuTemp, st.cpuTemp.toFloat())
                            if (st.cpuKhz > 0) push(hCpuMhz, st.cpuKhz / 1000f)
                            if (st.gpuHz > 0) push(hGpuMhz, st.gpuHz / 1000000f)
                            if (st.ramUsedKb > 0) push(hRamGb, st.ramUsedKb / 1048576f)
                        }
                    }
                }
                delay(2000)
            }
        }
    }

    fun loadLogs() {
        viewModelScope.launch(Dispatchers.IO) {
            val lines = Repo.logs(if (logWhich == 0) "boot" else "apply", 80)
            withContext(Dispatchers.Main) { logLines = lines }
        }
    }

    fun copyReport() {
        viewModelScope.launch(Dispatchers.IO) {
            val d = device
            val st = live
            val sb = StringBuilder()
            sb.append("HSIN v5.0.0\n")
            if (d != null) sb.append("Device: ${d.brand} ${d.model} | ${d.soc} | kernel ${d.kernel} | android ${d.android}\n")
            if (st != null) sb.append("CPU ${st.cpuKhz / 1000} MHz | GPU ${st.gpuHz / 1000000} MHz | suhu ${st.cpuTemp} C | safe_mode ${st.safeMode}\n")
            sb.append("Knob diubah: $changedCount dari $supportedCount\n")
            sb.append("\n--- boot.log ---\n").append(Repo.logs("boot", 60).joinToString("\n"))
            sb.append("\n\n--- apply.log ---\n").append(Repo.logs("apply", 60).joinToString("\n"))
            withContext(Dispatchers.Main) {
                val cm = ctx.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                cm.setPrimaryClip(ClipData.newPlainText("HSIN", sb.toString()))
                message = "Laporan disalin"
            }
        }
    }
}
