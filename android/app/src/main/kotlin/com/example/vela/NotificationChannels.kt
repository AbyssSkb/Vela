package com.example.vela

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.os.Build

object NotificationChannels {
    const val PROGRESS = "transfers"
    const val TRANSFER_ID = 33
    const val RESULTS = "transfer_results"

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
