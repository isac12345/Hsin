package com.hsin

import android.content.Intent
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService

/** Tile Quick Settings: satu ketuk membuka HSIN dan menjalankan ritual luncur untuk game terakhir. */
class LastGameTileService : TileService() {
    private fun last(): String = Prefs(applicationContext).lastGame

    override fun onStartListening() {
        super.onStartListening()
        val t = qsTile ?: return
        val pkg = last()
        t.label = trn("Game terakhir")
        if (pkg.isEmpty()) {
            t.state = Tile.STATE_UNAVAILABLE
            if (android.os.Build.VERSION.SDK_INT >= 29) t.subtitle = trn("Belum ada")
        } else {
            t.state = Tile.STATE_INACTIVE
            val name = try { packageManager.getApplicationLabel(packageManager.getApplicationInfo(pkg, 0)).toString() } catch (_: Exception) { pkg }
            if (android.os.Build.VERSION.SDK_INT >= 29) t.subtitle = name
        }
        t.updateTile()
    }

    @Suppress("DEPRECATION")
    override fun onClick() {
        super.onClick()
        val pkg = last()
        if (pkg.isEmpty()) return
        val i = Intent(this, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            .putExtra("ritual", pkg)
        startActivityAndCollapse(i)
    }
}
