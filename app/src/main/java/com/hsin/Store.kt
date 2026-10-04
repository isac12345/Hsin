package com.hsin

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

class Store(ctx: Context) {
    private val sp = ctx.getSharedPreferences("hsin_prefs", Context.MODE_PRIVATE)

    var theme: Int // 0 gelap, 1 terang, 2 ikut sistem
        get() = sp.getInt("theme", 0)
        set(v) { sp.edit().putInt("theme", v).apply() }

    var cardAlpha: Float
        get() = sp.getFloat("card_alpha", 0.55f)
        set(v) { sp.edit().putFloat("card_alpha", v).apply() }

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
}
