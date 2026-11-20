package com.example.vela

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import androidx.core.app.NotificationManagerCompat
import io.flutter.plugin.common.MethodChannel

class OfferActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val id = intent.getStringExtra("id") ?: return
        val cancelling = intent.action == "com.example.vela.CANCEL_TRANSFER"
        val engine = (context.applicationContext as VelaApplication).engine
        if (engine == null) {
            if (!cancelling) {
                NotificationManagerCompat.from(context).cancel(ReceivingService.OFFER_ID)
            }
            return
        }
        val background = MethodChannel(engine.dartExecutor.binaryMessenger, BACKGROUND_CHANNEL)
        if (cancelling) {
            background.invokeMethod("cancelTransfer", id)
        } else {
            val accepted = intent.getBooleanExtra("accepted", false)
            background.invokeMethod("offerDecision", mapOf("id" to id, "accepted" to accepted))
        }
    }
}
