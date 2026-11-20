package com.example.vela

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.graphics.Color
import android.net.Uri
import android.os.Build
import android.os.SystemClock
import android.webkit.MimeTypeMap
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.FileProvider
import androidx.core.graphics.drawable.IconCompat
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

internal const val ACTION_VIEW_RECEIVED_BATCH = "com.example.vela.VIEW_RECEIVED_BATCH"
private const val COMPLETION_TIMEOUT_MS = 30_000L

class BackgroundBridge(context: Context, private val isVisible: () -> Boolean) {
    private val context = context.applicationContext

    fun handle(call: MethodCall, result: MethodChannel.Result): Boolean {
        when (call.method) {
            "isVisible" -> result.success(isVisible())
            "nodeStarting" -> {
                (context as VelaApplication).nodeReady = false
                ReceivingService.markStarting()
                result.success(null)
            }
            "nodeReady" -> {
                (context as VelaApplication).nodeReady = true
                ReceivingService.markReady(call.argument<String>("message"))
                result.success(null)
            }
            "nodeFailed" -> {
                (context as VelaApplication).nodeReady = false
                ReceivingService.markFailed()
                ShareTransferService.failPending()
                result.success(null)
            }
            "offer" -> {
                NotificationChannels.ensure(context)
                val pending =
                    PendingIntent.getActivity(
                        context,
                        1,
                        Intent(context, MainActivity::class.java)
                            .addFlags(
                                Intent.FLAG_ACTIVITY_NEW_TASK or
                                    Intent.FLAG_ACTIVITY_SINGLE_TOP or
                                    Intent.FLAG_ACTIVITY_CLEAR_TOP
                            ),
                        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
                    )
                val builder =
                    NotificationCompat.Builder(context, ReceivingService.OFFERS)
                        .setSmallIcon(R.drawable.ic_stat_vela)
                        .setColor(Color.rgb(91, 91, 198))
                        .setContentTitle(call.argument<String>("title") ?: "Vela")
                        .setContentText(call.argument<String>("message") ?: "Incoming transfer")
                        .setStyle(
                            NotificationCompat.BigTextStyle()
                                .bigText(call.argument<String>("message") ?: "Incoming transfer")
                        )
                        .setContentIntent(pending)
                        .setShowWhen(false)
                        .setPriority(NotificationCompat.PRIORITY_HIGH)
                val id = call.argument<String>("id")
                if (id != null) {
                    fun action(accepted: Boolean): PendingIntent {
                        val intent =
                            Intent(context, OfferActionReceiver::class.java)
                                .setData(Uri.parse("vela://offer/$id/$accepted"))
                                .putExtra("id", id)
                                .putExtra("accepted", accepted)
                        return PendingIntent.getBroadcast(
                            context,
                            0,
                            intent,
                            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
                        )
                    }
                    builder
                        .setOngoing(true)
                        .setRequestPromotedOngoing(true)
                        .setShortCriticalText(call.argument<String>("shortText"))
                        .addAction(0, call.argument<String>("reject") ?: "Decline", action(false))
                        .addAction(0, call.argument<String>("accept") ?: "Accept", action(true))
                } else builder.setAutoCancel(true)
                try {
                    NotificationManagerCompat.from(context)
                        .notify(ReceivingService.OFFER_ID, builder.build())
                    result.success(null)
                } catch (e: SecurityException) {
                    result.error("notification", e.message, null)
                }
            }
            "clearOffer" -> {
                NotificationManagerCompat.from(context).cancel(ReceivingService.OFFER_ID)
                result.success(null)
            }
            "transfer" -> {
                NotificationChannels.ensure(context)
                val pending =
                    PendingIntent.getActivity(
                        context,
                        2,
                        Intent(context, MainActivity::class.java)
                            .addFlags(
                                Intent.FLAG_ACTIVITY_NEW_TASK or
                                    Intent.FLAG_ACTIVITY_SINGLE_TOP or
                                    Intent.FLAG_ACTIVITY_CLEAR_TOP
                            ),
                        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
                    )
                val progress = call.argument<Int>("progress")
                val builder =
                    NotificationCompat.Builder(context, NotificationChannels.PROGRESS)
                        .setSmallIcon(R.drawable.ic_stat_vela)
                        .setColor(Color.rgb(91, 91, 198))
                        .setContentTitle(call.argument<String>("title") ?: "Vela")
                        .setContentIntent(pending)
                        .setShowWhen(false)
                        .setCategory(NotificationCompat.CATEGORY_PROGRESS)
                        .setOngoing(true)
                        .setOnlyAlertOnce(true)
                        .setSilent(true)
                        .setRequestPromotedOngoing(true)
                val transferId = call.argument<String>("id")
                if (transferId != null && call.argument<Boolean>("cancelling") != true) {
                    val cancelIntent =
                        Intent(context, OfferActionReceiver::class.java)
                            .setAction("com.example.vela.CANCEL_TRANSFER")
                            .setData(Uri.parse("vela://transfer/$transferId"))
                            .putExtra("id", transferId)
                    val cancel =
                        PendingIntent.getBroadcast(
                            context,
                            0,
                            cancelIntent,
                            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
                        )
                    builder.addAction(0, call.argument<String>("cancel") ?: "Cancel", cancel)
                }
                if (Build.VERSION.SDK_INT >= 36) {
                    val style =
                        NotificationCompat.ProgressStyle()
                            .setProgressIndeterminate(progress == null)
                            .addProgressSegment(
                                NotificationCompat.ProgressStyle.Segment(100)
                                    .setColor(Color.rgb(91, 91, 198))
                            )
                    fun deviceIcon(type: String?): IconCompat? =
                        when (type) {
                            "mobile" ->
                                IconCompat.createWithResource(context, R.drawable.ic_transfer_phone)
                            "desktop" ->
                                IconCompat.createWithResource(
                                    context,
                                    R.drawable.ic_transfer_computer,
                                )
                            else -> null
                        }
                    deviceIcon(call.argument<String>("sourceType"))?.let {
                        style.setProgressStartIcon(it)
                    }
                    deviceIcon(call.argument<String>("destinationType"))?.let {
                        style.setProgressEndIcon(it)
                    }
                    if (progress != null) style.setProgress(progress.coerceIn(0, 100))
                    builder.setStyle(style)
                    builder.setShortCriticalText(call.argument<String>("shortText"))
                } else builder.setProgress(100, progress ?: 0, progress == null)
                try {
                    NotificationManagerCompat.from(context)
                        .notify(NotificationChannels.TRANSFER_ID, builder.build())
                } catch (_: SecurityException) {}
                result.success(null)
            }
            "clearTransfer" -> {
                NotificationManagerCompat.from(context).cancel(NotificationChannels.TRANSFER_ID)
                result.success(null)
            }
            "finishTransfer" -> {
                val testNotification =
                    context.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE != 0 &&
                        call.argument<Boolean>("test") == true
                if (isVisible() && !testNotification) {
                    NotificationManagerCompat.from(context).cancel(NotificationChannels.TRANSFER_ID)
                    result.success(null)
                    return true
                }
                NotificationChannels.ensure(context)
                val notificationId = (System.currentTimeMillis() and 0x7fffffff).toInt()
                val batchId = call.argument<String>("batchId")
                val launch =
                    Intent(context, MainActivity::class.java)
                        .addFlags(
                            Intent.FLAG_ACTIVITY_NEW_TASK or
                                Intent.FLAG_ACTIVITY_SINGLE_TOP or
                                Intent.FLAG_ACTIVITY_CLEAR_TOP
                        )
                if (batchId != null) {
                    launch.setAction(ACTION_VIEW_RECEIVED_BATCH).putExtra("batchId", batchId)
                }
                val pending =
                    PendingIntent.getActivity(
                        context,
                        notificationId,
                        launch,
                        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
                    )
                val message = call.argument<String>("text") ?: ""
                val completed = call.argument<Boolean>("completed") == true
                val promote =
                    completed &&
                        Build.VERSION.SDK_INT >= 36 &&
                        NotificationManagerCompat.from(context).canPostPromotedNotifications()
                val builder =
                    NotificationCompat.Builder(context, NotificationChannels.RESULTS)
                        .setSmallIcon(R.drawable.ic_stat_vela)
                        .setColor(Color.rgb(91, 91, 198))
                        .setContentTitle(call.argument<String>("title") ?: "Vela")
                        .setContentText(if (completed) null else message)
                        .setStyle(NotificationCompat.BigTextStyle().bigText(message))
                        .setContentIntent(pending)
                        .setShowWhen(false)
                        .setAutoCancel(true)
                        .setOnlyAlertOnce(true)
                        .setTimeoutAfter(if (completed) COMPLETION_TIMEOUT_MS else 0L)
                if (batchId != null) {
                    builder.addAction(0, call.argument<String>("open") ?: "View batch", pending)
                }
                if (promote)
                    builder
                        .setOngoing(true)
                        .setRequestPromotedOngoing(true)
                        .setShortCriticalText(call.argument<String>("shortText"))
                val previewPath = call.argument<String>("previewTextPath")
                if (previewPath != null) {
                    val view =
                        Intent(context, MainActivity::class.java)
                            .setAction("com.example.vela.VIEW_TEXT")
                            .putExtra("path", previewPath)
                            .addFlags(
                                Intent.FLAG_ACTIVITY_NEW_TASK or
                                    Intent.FLAG_ACTIVITY_SINGLE_TOP or
                                    Intent.FLAG_ACTIVITY_CLEAR_TOP
                            )
                    val preview =
                        PendingIntent.getActivity(
                            context,
                            notificationId,
                            view,
                            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
                        )
                    builder.addAction(0, call.argument<String>("open") ?: "View", preview)
                }
                val path = call.argument<String>("path")
                val url = call.argument<String>("url")?.let(Uri::parse)
                if (
                    url != null &&
                        url.scheme in listOf("http", "https") &&
                        !url.host.isNullOrBlank()
                ) {
                    val view =
                        Intent(Intent.ACTION_VIEW, url).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    val open =
                        PendingIntent.getActivity(
                            context,
                            notificationId,
                            view,
                            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
                        )
                    builder.addAction(0, call.argument<String>("open") ?: "Open", open)
                }
                if (path != null) {
                    try {
                        val uri =
                            if (path.startsWith("content:")) Uri.parse(path)
                            else
                                FileProvider.getUriForFile(
                                    context,
                                    "${context.packageName}.provider",
                                    File(path),
                                )
                        val extension =
                            call.argument<String>("name")?.substringAfterLast('.', "")?.lowercase()
                        val type =
                            context.contentResolver.getType(uri)
                                ?: MimeTypeMap.getSingleton().getMimeTypeFromExtension(extension)
                                ?: "application/octet-stream"
                        val view =
                            Intent(Intent.ACTION_VIEW)
                                .setDataAndType(uri, type)
                                .addFlags(
                                    Intent.FLAG_GRANT_READ_URI_PERMISSION or
                                        Intent.FLAG_ACTIVITY_NEW_TASK
                                )
                                .withExternalFileViewer(context)
                        val open =
                            PendingIntent.getActivity(
                                context,
                                notificationId,
                                view,
                                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
                            )
                        builder.addAction(0, call.argument<String>("open") ?: "Open", open)
                    } catch (e: Exception) {
                        android.util.Log.w("Vela", "Cannot create open action", e)
                    }
                }
                NotificationManagerCompat.from(context).cancel(NotificationChannels.TRANSFER_ID)
                try {
                    NotificationManagerCompat.from(context)
                        .notify(CompletionExpiryReceiver.TAG, notificationId, builder.build())
                    if (completed && Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
                        val expiry =
                            Intent(context, CompletionExpiryReceiver::class.java)
                                .setData(Uri.parse("vela://result/$notificationId"))
                                .putExtra("id", notificationId)
                        val alarm =
                            PendingIntent.getBroadcast(
                                context,
                                notificationId,
                                expiry,
                                PendingIntent.FLAG_ONE_SHOT or PendingIntent.FLAG_IMMUTABLE,
                            )
                        context.getSystemService(AlarmManager::class.java).setExact(
                            AlarmManager.ELAPSED_REALTIME,
                            SystemClock.elapsedRealtime() + COMPLETION_TIMEOUT_MS,
                            alarm,
                        )
                    }
                } catch (_: SecurityException) {}
                result.success(null)
            }
            else -> return false
        }
        return true
    }
}
