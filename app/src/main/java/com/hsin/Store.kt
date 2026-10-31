package com.hsin

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

class Store(ctx: Context) {
    private val sp = ctx.getSharedPreferences("hsin_prefs", Context.MODE_PRIVATE)

    var theme: Int // 0 Carbon, 1 Terminal, 2 Paper, 3 Blueprint
        get() = sp.getInt("theme_v5", 0).coerceIn(0, 3)
        set(v) { sp.edit().putInt("theme_v5", v).apply() }

    var monitorMs: Int
        get() = sp.getInt("monitor_ms", 2000)
        set(v) { sp.edit().putInt("monitor_ms", v).apply() }

    var games: List<GameProfile>
        get() {
            val raw = sp.getString("games", "[]") ?: "[]"
            val out = ArrayList<GameProfile>()
            try {
                val arr = JSONArray(raw)
                for (i in 0 until arr.length()) {
                    val o = arr.getJSONObject(i)
                    val vals = o.getJSONObject("values")
                    val m = LinkedHashMap<String, String>()
                    val it = vals.keys()
                    while (it.hasNext()) {
                        val k = it.next()
                        m[k] = vals.getString(k)
                    }
                    out.add(GameProfile(o.getString("pkg"), o.optString("label", o.getString("pkg")), m))
                }
            } catch (e: Exception) {
                // data rusak: abaikan
            }
            return out
        }
        set(list) {
            val arr = JSONArray()
            for (g in list) {
                val o = JSONObject()
                o.put("pkg", g.pkg)
                o.put("label", g.label)
                val v = JSONObject()
                for ((k, x) in g.values) v.put(k, x)
                o.put("values", v)
                arr.put(o)
            }
            sp.edit().putString("games", arr.toString()).apply()
        }

    var cardAlpha: Float
        get() = sp.getFloat("card_alpha_v5", 0.72f)
        set(v) { sp.edit().putFloat("card_alpha_v5", v).apply() }

    var presets: List<Preset>
        get() {
            val raw = sp.getString("presets", "[]") ?: "[]"
            val out = ArrayList<Preset>()
            try {
                val arr = JSONArray(raw)
                for (i in 0 until arr.length()) {
                    val o = arr.getJSONObject(i)
                    val vals = o.getJSONObject("values")
                    val m = LinkedHashMap<String, String>()
                    val it = vals.keys()
                    while (it.hasNext()) {
                        val k = it.next()
                        m[k] = vals.getString(k)
                    }
                    out.add(Preset(o.getString("name"), m))
                }
            } catch (e: Exception) {
                // data rusak: abaikan
            }
            return out
        }
        set(list) {
            val arr = JSONArray()
            for (p in list) {
                val o = JSONObject()
                o.put("name", p.name)
                val v = JSONObject()
                for ((k, x) in p.values) v.put(k, x)
                o.put("values", v)
                arr.put(o)
            }
            sp.edit().putString("presets", arr.toString()).apply()
        }

    /** Mode dan resolusi per game: pkg -> "mode:res" (mode: global|hemat|bawaan|seimbang|boost). */
    var gameCfg: Map<String, Pair<String, Int>>
        get() {
            val out = LinkedHashMap<String, Pair<String, Int>>()
            try {
                val o = JSONObject(sp.getString("game_cfg_v6", "{}") ?: "{}")
                val it = o.keys()
                while (it.hasNext()) {
                    val k = it.next()
                    val v = o.getString(k).split(":")
                    out[k] = Pair(v.getOrElse(0) { "global" }, (v.getOrNull(1)?.toIntOrNull() ?: 100).coerceIn(50, 100))
                }
            } catch (e: Exception) {
                // data rusak: abaikan
            }
            return out
        }
        set(m) {
            val o = JSONObject()
            for ((k, v) in m) o.put(k, v.first + ":" + v.second)
            sp.edit().putString("game_cfg_v6", o.toString()).apply()
        }

    var dndGame: Boolean
        get() = sp.getBoolean("dnd_game", true)
        set(v) { sp.edit().putBoolean("dnd_game", v).apply() }

    var hudOn: Boolean
        get() = sp.getBoolean("hud_on", true)
        set(v) { sp.edit().putBoolean("hud_on", v).apply() }

    var lastGame: String
        get() = sp.getString("last_game", "") ?: ""
        set(v) { sp.edit().putString("last_game", v).apply() }
}
