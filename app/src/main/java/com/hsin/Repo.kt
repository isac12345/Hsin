package com.hsin

import org.json.JSONObject

object Repo {
    private fun obj(vararg a: String): JSONObject? {
        val out = Shell.action(*a).second
        val i = out.indexOf('{')
        val j = out.lastIndexOf('}')
        if (i < 0 || j <= i) return null
        return try {
            JSONObject(out.substring(i, j + 1))
        } catch (e: Exception) {
            null
        }
    }

    fun ping(): Boolean = Shell.action("ping").second.contains("pong")

    fun device(): DeviceInfo? {
        val o = obj("device") ?: return null
        return DeviceInfo(
            model = o.optString("model"),
            brand = o.optString("brand"),
            soc = o.optString("soc"),
            kernel = o.optString("kernel"),
            android = o.optString("android"),
            module = o.optString("module")
        )
    }

    fun status(): Live? {
        val o = obj("status") ?: return null
        val pols = ArrayList<Policy>()
        val pa = o.optJSONArray("policies")
        if (pa != null) {
            for (i in 0 until pa.length()) {
                val p = pa.optJSONObject(i) ?: continue
                pols.add(
                    Policy(
                        p.optInt("id"), p.optLong("cur"), p.optLong("min"),
                        p.optLong("max"), p.optLong("hw"), p.optString("gov")
                    )
                )
            }
        }
        return Live(
            cpuKhz = o.optLong("cpu_khz"),
            cores = o.optInt("cores"),
            policies = pols,
            gpuHz = o.optLong("gpu_hz"),
            gpuMaxHz = o.optLong("gpu_max_hz"),
            gpuGov = o.optString("gpu_gov"),
            cpuTemp = o.optInt("cpu_temp", -1),
            gpuTemp = o.optInt("gpu_temp", -1),
            tempMax = o.optInt("temp_max", -1),
            batPct = o.optInt("bat_pct", -1),
            batTemp = o.optInt("bat_temp", -1),
            charging = o.optInt("bat_charging") == 1,
            ramTotalKb = o.optLong("ram_total_kb"),
            ramUsedKb = o.optLong("ram_used_kb"),
            swapTotalKb = o.optLong("swap_total_kb"),
            swapUsedKb = o.optLong("swap_used_kb"),
            loadX100 = o.optInt("load_x100"),
            cpuTotal = o.optLong("cpu_total"),
            cpuIdle = o.optLong("cpu_idle"),
            safeMode = o.optInt("safe_mode") == 1,
            thermalTrip = o.optInt("thermal_trip") == 1,
            gameMode = o.optInt("game_mode") == 1,
            gameActive = o.optString("game_active"),
            overrides = o.optInt("overrides")
        )
    }

    fun knobs(): List<Category>? {
        val o = obj("knobs") ?: return null
        val arr = o.optJSONArray("categories") ?: return null
        val res = ArrayList<Category>()
        for (i in 0 until arr.length()) {
            val c = arr.optJSONObject(i) ?: continue
            val ks = c.optJSONArray("knobs") ?: continue
            val list = ArrayList<Knob>()
            for (j in 0 until ks.length()) {
                val k = ks.optJSONObject(j) ?: continue
                val opts = ArrayList<String>()
                val oa = k.optJSONArray("options")
                if (oa != null) {
                    for (n in 0 until oa.length()) opts.add(oa.optString(n))
                }
                list.add(
                    Knob(
                        key = k.optString("key"),
                        label = k.optString("label"),
                        type = k.optString("type"),
                        unit = k.optString("unit"),
                        options = opts,
                        min = k.optInt("min"),
                        max = k.optInt("max"),
                        step = k.optInt("step", 1).coerceAtLeast(1),
                        cur = k.optString("cur"),
                        def = k.optString("def"),
                        reason = k.optString("reason")
                    )
                )
            }
            if (list.isNotEmpty()) res.add(Category(c.optString("id"), c.optString("title"), list))
        }
        return res
    }

    private fun result(o: JSONObject?): ApplyResult {
        if (o == null) return ApplyResult(0, 0, emptySet(), emptyList(), "Tidak ada jawaban dari modul")
        val okKeys = HashSet<String>()
        val fails = ArrayList<Pair<String, String>>()
        val arr = o.optJSONArray("results")
        if (arr != null) {
            for (i in 0 until arr.length()) {
                val r = arr.optJSONObject(i) ?: continue
                val key = r.optString("key")
                if (r.optInt("ok") == 1) okKeys.add(key) else fails.add(Pair(key, r.optString("msg")))
            }
        }
        return ApplyResult(o.optInt("ok"), o.optInt("fail"), okKeys, fails, o.optString("error"))
    }

    fun setMany(pairs: List<Pair<String, String>>): ApplyResult {
        val args = ArrayList<String>()
        args.add("set-many")
        for (p in pairs) args.add(p.first + "=" + p.second)
        return result(obj(*args.toTypedArray()))
    }

    fun restore(): ApplyResult = result(obj("restore"))

    fun guardReset(): Boolean = obj("guard-reset")?.optInt("ok") == 1

    fun conflicts(): List<String> {
        val o = obj("conflicts") ?: return emptyList()
        val a = o.optJSONArray("list") ?: return emptyList()
        val out = ArrayList<String>()
        for (i in 0 until a.length()) {
            val n = a.optString(i)
            if (n.isNotBlank()) out.add(n)
        }
        return out
    }

    fun thermalGet(): ThermalCfg? {
        val o = obj("thermal-get") ?: return null
        return ThermalCfg(o.optInt("on") == 1, o.optInt("limit", 90), o.optInt("trip") == 1)
    }

    fun thermalSet(on: Boolean, limit: Int): Boolean =
        obj("thermal-set", if (on) "1" else "0", limit.toString())?.optInt("ok") == 1

    fun thermalAck(): ApplyResult = result(obj("thermal-ack"))

    fun gameMode(on: Boolean): Boolean = obj("game-mode", if (on) "1" else "0")?.optInt("ok") == 1

    fun gameSet(pkg: String, values: Map<String, String>): ApplyResult {
        val args = ArrayList<String>()
        args.add("game-set")
        args.add(pkg)
        for ((k, v) in values) args.add("$k=$v")
        return result(obj(*args.toTypedArray()))
    }

    fun gameDel(pkg: String): Boolean = obj("game-del", pkg)?.optInt("ok") == 1

    fun logs(which: String, n: Int): List<String> {
        val out = Shell.action("logs", which, n.toString()).second
        if (out.isBlank()) return emptyList()
        return out.lines().filter { it.isNotBlank() }
    }
}
