package com.example.vela

import android.app.Notification
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import androidx.core.app.NotificationCompat

class ReceivingService : Service() {
    private var wakeLock: PowerManager.WakeLock? = null
    private val handler = Handler(Looper.getMainLooper())
    private var engineRetryDelay = 1000L
    private val retryEngine = Runnable { startEngine() }
    private var message: String? = null
    private var readyMessage: String? = null

    companion object {
        const val CHANNEL = "receiving_service"
        const val OFFERS = "incoming_offers"
        const val SERVICE_ID = 31
        const val OFFER_ID = 32
        private const val ENABLED_KEY = "flutter.background_receive_default"
        @Volatile var running = false
            private set
        private var active: ReceivingService? = null

        fun isEnabled(context: Context): Boolean =
            preferences(context).getBoolean(ENABLED_KEY, true)

        fun setEnabled(context: Context, enabled: Boolean) {
            preferences(context).edit().putBoolean(ENABLED_KEY, enabled).apply()
        }

        private fun preferences(context: Context) =
            context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)

        fun ready(app: VelaApplication): Boolean =
            running && app.nodeReady && !app.networkBlocked

        fun markStarting() {
            active?.updateStatus(R.string.background_starting)
        }

        fun markReady(message: String?) {
            active?.let {
                if (message != null) it.readyMessage = message
                it.updateStatus(R.string.background_ready)
            }
        }

        fun markFailed() {
            active?.updateStatus(R.string.background_failed)
        }

        fun networkChanged(app: VelaApplication) {
            if (app.nodeReady) markReady(null)
        }
    }

    override fun onCreate() {
        super.onCreate()
        NotificationChannels.ensure(this)
        active = this
    }

    private fun startEngine() {
        try {
            (application as VelaApplication).startHeadlessEngine()
            engineRetryDelay = 1000L
        } catch (e: Exception) {
            android.util.Log.e("Vela", "Could not start background engine; retrying", e)
            (application as VelaApplication).nodeReady = false
            markFailed()
            handler.removeCallbacks(retryEngine)
            handler.postDelayed(retryEngine, engineRetryDelay)
            engineRetryDelay = (engineRetryDelay * 2).coerceAtMost(60000L)
        }
    }

    private fun updateStatus(status: Int) {
        val app = application as VelaApplication
        val display = when {
            app.networkBlocked && status == R.string.background_ready ->
                getString(R.string.background_network_blocked)
            status == R.string.background_ready ->
                readyMessage ?: getString(R.string.background_ready)
            else -> getString(status)
        }
        if (message != display) {
            showForeground(display)
            message = display
        }
        ReceivingTileService.refresh()
    }

    private fun showForeground(message: String) {
        val pending =
            PendingIntent.getActivity(
                this,
                0,
                Intent(this, MainActivity::class.java)
                    .addFlags(
                        Intent.FLAG_ACTIVITY_NEW_TASK or
                            Intent.FLAG_ACTIVITY_SINGLE_TOP or
                            Intent.FLAG_ACTIVITY_CLEAR_TOP
                    ),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        val notification: Notification =
            NotificationCompat.Builder(this, CHANNEL)
                .setSmallIcon(R.drawable.ic_stat_vela)
                .setContentTitle("Vela")
                .setContentText(message)
                .setContentIntent(pending)
                .setOngoing(true)
                .build()
        startForeground(SERVICE_ID, notification)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (!isEnabled(this)) {
            stopSelf(startId)
            return START_NOT_STICKY
        }
        val application = application as VelaApplication
        intent?.getStringExtra("message")?.let { readyMessage = it }
        running = true
        if (application.nodeReady) markReady(null) else markStarting()
        if (wakeLock == null) {
            wakeLock =
                getSystemService(PowerManager::class.java)
                    .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "$packageName:receiving")
                    .apply {
                        setReferenceCounted(false)
                        acquire()
                    }
        }
        handler.removeCallbacks(retryEngine)
        startEngine()
        return START_STICKY
    }

    override fun onDestroy() {
        handler.removeCallbacks(retryEngine)
        wakeLock?.let { if (it.isHeld) it.release() }
        wakeLock = null
        if (active === this) active = null
        running = false
        stopForeground(STOP_FOREGROUND_REMOVE)
        ReceivingTileService.refresh()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
