package com.example.vela

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log

class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (
            intent.action != Intent.ACTION_BOOT_COMPLETED ||
                !context
                    .getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                    .getBoolean("flutter.background_receive_default", false)
        )
            return
        try {
            val service = Intent(context, ReceivingService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
                context.startForegroundService(service)
            else context.startService(service)
        } catch (e: Exception) {
            Log.e("Vela", "Could not start background receiving after boot", e)
        }
    }
}
