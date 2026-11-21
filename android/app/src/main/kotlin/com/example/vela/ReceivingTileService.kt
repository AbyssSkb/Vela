package com.example.vela

import android.content.Intent
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import androidx.annotation.RequiresApi
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.MethodChannel

@RequiresApi(Build.VERSION_CODES.N)
class ReceivingTileService : TileService() {
    companion object {
        private var listening: ReceivingTileService? = null

        fun refresh() {
            listening?.updateTile()
        }
    }

    override fun onStartListening() {
        super.onStartListening()
        listening = this
        updateTile()
    }

    override fun onStopListening() {
        if (listening === this) listening = null
        super.onStopListening()
    }

    override fun onDestroy() {
        if (listening === this) listening = null
        super.onDestroy()
    }

    override fun onClick() {
        super.onClick()
        val service = Intent(this, ReceivingService::class.java)
        val previous = ReceivingService.isEnabled(this)
        val enabled = !ReceivingService.running
        ReceivingService.setEnabled(this, enabled)
        try {
            if (enabled) ContextCompat.startForegroundService(this, service)
            else stopService(service)
        } catch (error: RuntimeException) {
            ReceivingService.setEnabled(this, previous)
            android.util.Log.w("Vela", "Could not change background reception from the tile", error)
        }
        (application as VelaApplication).engine?.let {
            MethodChannel(it.dartExecutor.binaryMessenger, BACKGROUND_CHANNEL)
                .invokeMethod("backgroundPreferenceChanged", null)
        }
        updateTile()
    }

    private fun updateTile() {
        val app = application as VelaApplication
        val ready = ReceivingService.ready(app)
        qsTile?.apply {
            state = if (ready) Tile.STATE_ACTIVE else Tile.STATE_INACTIVE
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                subtitle = getString(when {
                    ready -> R.string.background_tile_ready
                    !ReceivingService.running -> R.string.background_tile_off
                    app.networkBlocked -> R.string.background_network_blocked
                    else -> R.string.background_tile_unready
                })
            }
            this.updateTile()
        }
    }
}
