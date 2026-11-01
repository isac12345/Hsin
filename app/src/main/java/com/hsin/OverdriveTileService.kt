package com.hsin

import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import android.widget.Toast
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch

/**
 * Quick Settings tile Overdrive: tap untuk menyalakan/mematikan.
 * Mati (abu-abu) bila tidak ada game terdaftar yang sedang aktif; menyala bila Overdrive aktif.
 */
class OverdriveTileService : TileService() {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)

    override fun onStartListening() {
        super.onStartListening()
        scope.launch { render(Hsin.status()) }
    }

    override fun onClick() {
        super.onClick()
        scope.launch {
            val s = Hsin.status()
            if (s == null) {
                Toast.makeText(applicationContext, "Modul HSIN tidak terbaca", Toast.LENGTH_SHORT).show()
                return@launch
            }
            if (s.ovd) {
                Hsin.ovdStop()
            } else if (s.gamePkg.isEmpty()) {
                Toast.makeText(applicationContext, "Buka game terdaftar dulu, Puncak hanya untuk game", Toast.LENGTH_LONG).show()
            } else {
                val r = Hsin.ovdStart()
                if (!r.ok) {
                    val msg = r.out.lines().firstOrNull { it.startsWith("ERROR") }?.removePrefix("ERROR:")?.trim() ?: "Puncak gagal"
                    Toast.makeText(applicationContext, msg, Toast.LENGTH_LONG).show()
                }
            }
            render(Hsin.status())
        }
    }

    private fun render(s: Status?) {
        val t = qsTile ?: return
        t.label = "Puncak"
        t.state = when {
            s == null -> Tile.STATE_UNAVAILABLE
            s.ovd -> Tile.STATE_ACTIVE
            else -> Tile.STATE_INACTIVE
        }
        if (android.os.Build.VERSION.SDK_INT >= 29) {
            t.subtitle = when {
                s == null -> "Modul tidak terbaca"
                s.ovd && s.ovdLevel == "safe" -> "Aktif, mode aman (panas)"
                s.ovd && s.ovdLevel == "mid" -> "Aktif, turun sedikit (panas)"
                s.ovd -> "Aktif"
                s.gamePkg.isEmpty() -> "Butuh game aktif"
                else -> "Mati"
            }
        }
        t.updateTile()
    }

    override fun onDestroy() {
        scope.cancel()
        super.onDestroy()
    }
}
