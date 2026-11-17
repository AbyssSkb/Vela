package com.example.vela

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import androidx.core.app.NotificationManagerCompat
import io.flutter.plugin.common.MethodChannel

class OfferActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val id = intent.getStringExtra("id") ?: return
        if (intent.action == "com.example.vela.CANCEL_TRANSFER") {
            val engine = (context.applicationContext as VelaApplication).engine ?: return
            MethodChannel(engine.dartExecutor.binaryMessenger, "vela/offer_actions")
                .invokeMethod("cancelTransfer", id)
            return
        }
        val accepted = intent.getBooleanExtra("accepted", false)
        val engine = (context.applicationContext as VelaApplication).engine
        if (engine == null) {
            NotificationManagerCompat.from(context).cancel(ReceivingService.OFFER_ID)
            return
        }
        MethodChannel(engine.dartExecutor.binaryMessenger, "vela/offer_actions")
            .invokeMethod("decision", mapOf("id" to id, "accepted" to accepted))
    }
}
