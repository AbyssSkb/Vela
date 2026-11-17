package com.example.vela

import android.app.Notification
import android.app.NotificationManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build

class CompletionExpiryReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (Build.VERSION.SDK_INT < 36) return
        val id = intent.getIntExtra("id", -1)
        val manager = context.getSystemService(NotificationManager::class.java)
        val current =
            manager.activeNotifications.firstOrNull { it.id == id && it.tag == TAG } ?: return
        val normal =
            Notification.Builder.recoverBuilder(context, current.notification)
                .setOngoing(false)
                .setAutoCancel(true)
                .setOnlyAlertOnce(true)
                .build()
        manager.notify(TAG, id, normal)
    }

    companion object {
        const val TAG = "received-result"
    }
}
