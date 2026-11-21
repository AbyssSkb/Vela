package com.example.vela

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.os.Build
import androidx.core.app.NotificationManagerCompat

object NotificationChannels {
    const val PROGRESS = "transfers"
    const val TRANSFER_ID = 33
    const val RESULTS = "transfer_results"
    const val SHOW_TRANSFERS = "showTransfers"
    const val SHOW_REQUESTS = "showRequests"
    const val SHOW_LIVE = "showLive"

    private fun preferences(context: Context) =
        context.getSharedPreferences("notifications", Context.MODE_PRIVATE)

    fun enabled(context: Context, category: String): Boolean =
        preferences(context).getBoolean(category, true)

    fun setEnabled(context: Context, category: String, enabled: Boolean): Boolean {
        val channel = when (category) {
            SHOW_TRANSFERS -> PROGRESS
            SHOW_REQUESTS -> ReceivingService.OFFERS
            SHOW_LIVE -> null
            else -> return false
        }
        preferences(context).edit().putBoolean(category, enabled).apply()
        if (enabled || channel == null) return true

        val manager = context.getSystemService(NotificationManager::class.java)
        if (category == SHOW_REQUESTS) manager.cancel(ReceivingService.OFFER_ID)
        else {
            manager.cancel(TRANSFER_ID)
            ShareTransferService.hideProgress()
            for (notification in manager.activeNotifications) {
                if (notification.tag == CompletionExpiryReceiver.TAG || notification.tag == "share") {
                    manager.cancel(notification.tag, notification.id)
                }
            }
        }
        return true
    }

    fun promote(context: Context): Boolean =
        Build.VERSION.SDK_INT >= 36 &&
            enabled(context, SHOW_LIVE) &&
            NotificationManagerCompat.from(context).canPostPromotedNotifications()

    fun ensure(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = context.getSystemService(NotificationManager::class.java)
        val progressBlocked =
            manager.getNotificationChannel(PROGRESS)?.importance ==
                NotificationManager.IMPORTANCE_NONE
        manager.createNotificationChannels(
            listOf(
                NotificationChannel(
                    ReceivingService.OFFERS,
                    context.getString(R.string.notification_requests),
                    NotificationManager.IMPORTANCE_HIGH,
                ),
                NotificationChannel(
                    PROGRESS,
                    context.getString(R.string.notification_progress),
                    NotificationManager.IMPORTANCE_LOW,
                ),
                NotificationChannel(
                    RESULTS,
                    context.getString(R.string.notification_results),
                    if (progressBlocked) NotificationManager.IMPORTANCE_NONE
                    else NotificationManager.IMPORTANCE_DEFAULT,
                ),
                NotificationChannel(
                    ReceivingService.CHANNEL,
                    context.getString(R.string.notification_service),
                    NotificationManager.IMPORTANCE_LOW,
                ),
            )
        )
    }
}
