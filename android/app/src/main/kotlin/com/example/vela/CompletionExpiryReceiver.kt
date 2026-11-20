package com.example.vela

import android.app.NotificationManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class CompletionExpiryReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        context.getSystemService(NotificationManager::class.java)
            .cancel(TAG, intent.getIntExtra("id", -1))
    }

    companion object {
        const val TAG = "received-result"
    }
}
