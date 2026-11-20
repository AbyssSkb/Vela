package com.example.vela

import android.app.ActivityManager
import android.app.ApplicationStartInfo
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.provider.Settings
import android.util.Log

class BootReceiver : BroadcastReceiver() {
    companion object {
        internal const val EXTRA_BOOT_COUNT = "vela.startup_boot_count"

        private fun history(context: Context) =
            context.getSharedPreferences("receiving_boot", Context.MODE_PRIVATE)

        private fun bootCount(context: Context): Int? =
            runCatching {
                Settings.Global.getInt(context.contentResolver, Settings.Global.BOOT_COUNT, -1)
            }.getOrNull()?.takeIf { it >= 0 }

        internal fun recordRecovered(context: Context, boot: Int) {
            runCatching { history(context).edit().putInt("recovered", boot).apply() }
                .onFailure { Log.w("Vela", "Could not save boot recovery status", it) }
        }

        internal fun recoveryStatus(context: Context): String? {
            val boot = bootCount(context) ?: return null
            val saved = history(context)
            return when (boot) {
                saved.getInt("recovered", -1) -> "restored"
                saved.getInt("broadcast", -1) -> "broadcast"
                else -> null
            }
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (
            intent.action != Intent.ACTION_BOOT_COMPLETED ||
                !context
                    .getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                    .getBoolean("flutter.background_receive_default", false)
        )
            return
        val service = Intent(context, ReceivingService::class.java)
        runCatching {
            bootCount(context)?.let { boot ->
                history(context).edit().putInt("broadcast", boot).apply()
                if (startedBeforeOpeningVela(context)) service.putExtra(EXTRA_BOOT_COUNT, boot)
            }
        }.onFailure { Log.w("Vela", "Could not record boot recovery status", it) }
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
                context.startForegroundService(service)
            else context.startService(service)
        } catch (e: Exception) {
            Log.e("Vela", "Could not start background receiving after boot", e)
        }
    }

    private fun startedBeforeOpeningVela(context: Context): Boolean {
        val app = context.applicationContext as VelaApplication
        if (app.engine != null || app.currentActivity != null) return false
        val manager = context.getSystemService(ActivityManager::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P && manager.isBackgroundRestricted)
            return false
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.VANILLA_ICE_CREAM) return true
        // Android can replay a boot broadcast after the user opens a force-stopped app.
        val start = manager.getHistoricalProcessStartReasons(1).firstOrNull() ?: return false
        return !start.wasForceStopped() &&
            (start.reason == ApplicationStartInfo.START_REASON_BOOT_COMPLETE ||
                start.reason == ApplicationStartInfo.START_REASON_BROADCAST)
    }
}
