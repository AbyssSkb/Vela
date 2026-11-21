package com.example.vela

import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.os.IBinder
import android.os.PowerManager
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import java.util.UUID

internal class ShareTransferService : Service() {
    private val app get() = application as VelaApplication
    private val requests = mutableSetOf<String>()
    private var lastStartId = 0
    private var wakeLock: PowerManager.WakeLock? = null

    companion object {
        const val EXTRA_PEER = "com.example.vela.SHARE_PEER"
        private var active: ShareTransferService? = null

        fun complete(id: String) {
            val service = active ?: return
            if (service.requests.remove(id) && service.requests.isEmpty()) {
                service.stopSelf(service.lastStartId)
            }
        }

        fun failPending() {
            active?.let {
                it.showFailure()
                it.stopSelf()
            }
        }

        fun hideProgress() {
            val service = active ?: return
            if (service.requests.isNotEmpty()) service.showForeground(showProgress = false)
        }
    }

    override fun onCreate() {
        super.onCreate()
        active = this
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        lastStartId = startId
        NotificationChannels.ensure(this)
        if (requests.isEmpty()) {
            try {
                showForeground(NotificationChannels.enabled(this, NotificationChannels.SHOW_TRANSFERS))
            } catch (_: IllegalStateException) {
                showFailure()
                stopSelf(startId)
                return START_NOT_STICKY
            }
        }
        val peer = intent?.getStringExtra(EXTRA_PEER)?.takeIf(shareDeviceId::matches)
        val payload = intent?.sharePayload()
        if (peer == null || payload == null) {
            showFailure()
            if (requests.isEmpty()) stopSelf(startId)
            return START_NOT_STICKY
        }
        val id = UUID.randomUUID().toString()
        requests.add(id)
        if (wakeLock == null) {
            wakeLock = getSystemService(PowerManager::class.java)
                .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "$packageName:share")
                .apply {
                    setReferenceCounted(false)
                    acquire()
                }
        }
        app.channels.enqueueConfirmedShare(
            payload + mapOf("preferredPeer" to peer, "serviceRequest" to id)
        )
        try {
            app.startHeadlessEngine()
        } catch (_: Exception) {
            showFailure()
            stopSelf()
        }
        return START_NOT_STICKY
    }

    private fun notification(channel: String) =
        NotificationCompat.Builder(this, channel)
            .setSmallIcon(R.drawable.ic_stat_vela)
            .setShowWhen(false)
            .setContentIntent(
                PendingIntent.getActivity(
                    this, 2, Intent(this, MainActivity::class.java)
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP),
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
                )
            )

    private fun showForeground(showProgress: Boolean) {
        val channel = if (showProgress) NotificationChannels.PROGRESS else ReceivingService.CHANNEL
        val builder = notification(channel).setOngoing(true).setOnlyAlertOnce(true)
        if (showProgress) {
            val connecting = getString(R.string.share_transfer_connecting)
            builder
                .setContentTitle(connecting)
                .setCategory(NotificationCompat.CATEGORY_PROGRESS)
                .setRequestPromotedOngoing(NotificationChannels.promote(this))
                .setShortCriticalText(connecting)
                .setProgress(100, 0, true)
        } else {
            builder.setContentTitle("Vela").setSilent(true)
        }
        startForeground(NotificationChannels.TRANSFER_ID, builder.build())
    }

    private fun showFailure() {
        if (!NotificationChannels.enabled(this, NotificationChannels.SHOW_TRANSFERS)) return
        try {
            NotificationManagerCompat.from(this).notify(
                "share",
                NotificationChannels.TRANSFER_ID,
                notification(NotificationChannels.RESULTS)
                    .setContentTitle("Vela")
                    .setContentText(getString(R.string.share_transfer_failed))
                    .setAutoCancel(true)
                    .build(),
            )
        } catch (_: SecurityException) {}
    }

    override fun onTimeout(startId: Int, fgsType: Int) {
        showFailure()
        stopSelf()
    }

    override fun onDestroy() {
        app.channels.discardConfirmedShares(requests)
        wakeLock?.let { if (it.isHeld) it.release() }
        wakeLock = null
        if (active === this) active = null
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
