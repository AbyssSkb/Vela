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
    private var bootCount: Int? = null
    private val handler = Handler(Looper.getMainLooper())
    private var engineRetryDelay = 1000L
    private val retryEngine = Runnable { startEngine() }

    companion object {
        const val CHANNEL = "receiving_service"
        const val OFFERS = "incoming_offers"
        const val SERVICE_ID = 31
        const val OFFER_ID = 32
        @Volatile var running = false
        private var active: ReceivingService? = null

        fun markStarting() {
            active?.let { it.showForeground(it.getString(R.string.background_starting)) }
        }

        fun markReady(message: String?) {
            active?.let {
                it.showForeground(message ?: it.getString(R.string.background_ready))
                it.recordBootRecovery()
            }
        }

        fun markFailed() {
            active?.let { it.showForeground(it.getString(R.string.background_failed)) }
        }
    }

    private fun recordBootRecovery() {
        val boot = bootCount ?: return
        bootCount = null
        if ((application as VelaApplication).currentActivity == null) {
            BootReceiver.recordRecovered(this, boot)
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
        if (
            !getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                .getBoolean("flutter.background_receive_default", false)
        ) {
            stopSelf(startId)
            return START_NOT_STICKY
        }
        val application = application as VelaApplication
        intent?.getIntExtra(BootReceiver.EXTRA_BOOT_COUNT, -1)?.takeIf { it >= 0 }?.let {
            bootCount = it
        }
        val message =
            if (application.nodeReady)
                intent?.getStringExtra("message") ?: getString(R.string.background_ready)
            else getString(R.string.background_starting)
        showForeground(message)
        running = true
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
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
