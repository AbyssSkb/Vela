package com.example.vela

import android.Manifest
import android.app.ActivityManager
import android.app.NotificationManager
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.provider.OpenableColumns
import android.provider.Settings
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.FileProvider
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.UUID
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

class AppChannels(private val context: VelaApplication) {
    val storage = ReceivedStorage(context)
    private val executor = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private val cancelled = AtomicBoolean(false)
    private var saving = false
    private val background = BackgroundBridge(context) {
        context.currentActivity?.let { it.hasWindowFocus() && !it.isFinishing } == true
    }
    private var shareChannel: MethodChannel? = null
    private val folderCancelled = AtomicBoolean(false)
    private var folderBusy = false
    private val updates = UpdateBridge(context)

    fun onUpdateActivityResult(requestCode: Int, resultCode: Int): Boolean =
        updates.onActivityResult(requestCode, resultCode)

    fun saveReceived(paths: List<String>?, result: MethodChannel.Result) {
        if (paths.isNullOrEmpty() || paths.size > 100 || saving) {
            result.error("storage", "Invalid save request", null)
            return
        }
        try {
            val root = context.filesDir.canonicalPath + File.separator
            if (paths.any { !File(it).canonicalPath.startsWith(root) || !File(it).isFile }) {
                result.error("storage", "Invalid source", null)
                return
            }
            if (
                Build.VERSION.SDK_INT < 29 &&
                    storage.tree == null &&
                    context.checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) !=
                        PackageManager.PERMISSION_GRANTED
            ) {
                val activity = context.currentActivity
                if (activity == null) result.error("storage", "Storage permission required", null)
                else activity.requestSavePermission(paths, result)
                return
            }
        } catch (e: Exception) {
            result.error("storage", e.message, null)
            return
        }
        saving = true
        cancelled.set(false)
        executor.execute {
            try {
                val saved = storage.save(paths, cancelled)
                main.post {
                    saving = false
                    result.success(saved)
                }
            } catch (e: Exception) {
                main.post {
                    saving = false
                    result.error(if (cancelled.get()) "cancelled" else "storage", e.message, null)
                }
            }
        }
    }

    fun cancelSave() {
        cancelled.set(true)
        context.currentActivity?.cancelPendingSave()
    }

    fun writeClipboardFiles(paths: List<String>?, result: MethodChannel.Result) {
        try {
            require(!paths.isNullOrEmpty() && paths.size <= 100) { "Invalid clipboard files" }
            val uris =
                paths.map { path ->
                    if (path.startsWith("content:")) Uri.parse(path)
                    else
                        FileProvider.getUriForFile(
                            context,
                            "${context.packageName}.provider",
                            File(path),
                        )
                }
            val types =
                uris
                    .map { context.contentResolver.getType(it) ?: "application/octet-stream" }
                    .distinct()
                    .toTypedArray()
            val clip = ClipData("files", types, ClipData.Item(uris.first()))
            uris.drop(1).forEach { clip.addItem(ClipData.Item(it)) }
            (context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager)
                .setPrimaryClip(clip)
            result.success(null)
        } catch (e: Exception) {
            result.error("clipboard", e.message, null)
        }
    }

    fun shareAvailable() {
        shareChannel?.invokeMethod("available", null)
    }

    private fun withActivity(result: MethodChannel.Result, action: (MainActivity) -> Unit) {
        val activity = context.currentActivity
        if (activity == null) result.error("activity", "Open Vela to perform this action", null)
        else action(activity)
    }

    private fun handleBackground(call: MethodCall, result: MethodChannel.Result) {
        if (background.handle(call, result)) return
        when (call.method) {
            "stop" -> {
                context.stopService(Intent(context, ReceivingService::class.java))
                result.success(null)
            }
            "status" -> {
                NotificationChannels.ensure(context)
                val power = context.getSystemService(PowerManager::class.java)
                val activity = context.getSystemService(ActivityManager::class.java)
                val manager = context.getSystemService(NotificationManager::class.java)
                val offers =
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
                        manager.getNotificationChannel(ReceivingService.OFFERS)
                    else null
                fun channelEnabled(id: String) =
                    NotificationManagerCompat.from(context).areNotificationsEnabled() &&
                        (Build.VERSION.SDK_INT < 26 ||
                            manager.getNotificationChannel(id)?.importance !=
                                NotificationManager.IMPORTANCE_NONE)
                result.success(
                    mapOf(
                        "running" to ReceivingService.running,
                        "nodeReady" to context.nodeReady,
                        "notifications" to
                            (NotificationManagerCompat.from(context)
                                .areNotificationsEnabled() &&
                                (offers == null ||
                                    offers.importance !=
                                        NotificationManager.IMPORTANCE_NONE)),
                        "allNotifications" to
                            NotificationManagerCompat.from(context).areNotificationsEnabled(),
                        "requestNotifications" to channelEnabled(ReceivingService.OFFERS),
                        "progressNotifications" to
                            channelEnabled(NotificationChannels.PROGRESS),
                        "resultNotifications" to
                            channelEnabled(NotificationChannels.RESULTS),
                        "liveSupported" to (Build.VERSION.SDK_INT >= 36),
                        "liveAllowed" to
                            (Build.VERSION.SDK_INT >= 36 &&
                                NotificationManagerCompat.from(context)
                                    .canPostPromotedNotifications()),
                        "batteryExempt" to
                            (Build.VERSION.SDK_INT < 23 ||
                                power.isIgnoringBatteryOptimizations(context.packageName)),
                        "lowPowerStandbyEnabled" to
                            (if (Build.VERSION.SDK_INT >= 33) power.isLowPowerStandbyEnabled
                            else null),
                        "lowPowerStandbyExempt" to
                            (if (Build.VERSION.SDK_INT >= 34)
                                power.isExemptFromLowPowerStandby
                            else null),
                        "restricted" to
                            (Build.VERSION.SDK_INT >= 28 &&
                                activity.isBackgroundRestricted),
                        "manufacturer" to Build.MANUFACTURER,
                    )
                )
            }
            "resume" -> {
                val activity = context.currentActivity
                if (activity != null) {
                    activity.resumeBackgroundReceiving(call.argument<String>("message"), result)
                } else {
                    if (ReceivingService.running && context.nodeReady)
                        ReceivingService.markReady(call.argument<String>("message"))
                    result.success(ReceivingService.running)
                }
            }
            "start" -> withActivity(result) {
                it.requestBackgroundReceiving(call.argument<String>("message"), result)
            }
            "settings" -> withActivity(result) {
                it.openBackgroundSettings(call.argument<String>("section"), result)
            }
            else -> withActivity(result) { result.notImplemented() }
        }
    }

    private fun handleFiles(call: MethodCall, result: MethodChannel.Result) {
        if (call.method == "cancelFolder") {
            folderCancelled.set(true)
            result.success(null)
            return
        }
        if (call.method in listOf("stageFolder", "stageFolderArchive", "saveFolder")) {
            if (folderBusy) {
                result.error("folder", "Folder operation already in progress", null)
                return
            }
            val path = call.argument<String>("path")
            val tree = call.argument<String>("tree")
            if (
                (call.method == "stageFolder" && tree == null) ||
                    (call.method == "stageFolderArchive" && path == null) ||
                    (call.method == "saveFolder" && (path == null || tree == null))
            ) {
                result.error("folder", "Invalid folder request", null)
                return
            }
            folderBusy = true
            folderCancelled.set(false)
            executor.execute {
                try {
                    val folders = FolderDocuments(context, folderCancelled)
                    val value =
                        when (call.method) {
                            "stageFolder" -> folders.stageTree(Uri.parse(tree))
                            "stageFolderArchive" -> folders.stageFile(path!!)
                            else -> folders.saveTree(Uri.parse(tree), path!!)
                        }
                    main.post {
                        folderBusy = false
                        result.success(value)
                    }
                } catch (e: Exception) {
                    main.post {
                        folderBusy = false
                        result.error(
                            if (folderCancelled.get()) "cancelled" else "folder",
                            e.message,
                            null,
                        )
                    }
                }
            }
            return
        }
        if (call.method == "existsUri" || call.method == "deleteUri") {
            val value = call.argument<String>("path")
            if (value == null || !value.startsWith("content:")) {
                result.error("storage", "Invalid URI", null)
                return
            }
            executor.execute {
                try {
                    val uri = Uri.parse(value)
                    if (call.method == "existsUri") {
                        val exists =
                            context.contentResolver
                                .query(
                                    uri,
                                    arrayOf(OpenableColumns.DISPLAY_NAME),
                                    null,
                                    null,
                                    null,
                                )
                                ?.use { it.moveToFirst() } ?: false
                        main.post { result.success(exists) }
                    } else {
                        val deleted =
                            try {
                                storage.delete(uri)
                            } catch (e: java.io.FileNotFoundException) {
                                val cursor =
                                    context.contentResolver.query(
                                        uri,
                                        arrayOf(OpenableColumns.DISPLAY_NAME),
                                        null,
                                        null,
                                        null,
                                    ) ?: throw e
                                if (cursor.use { it.moveToFirst() }) throw e else true
                            }
                        if (!deleted) {
                            val cursor =
                                context.contentResolver.query(
                                    uri,
                                    arrayOf(OpenableColumns.DISPLAY_NAME),
                                    null,
                                    null,
                                    null,
                                ) ?: error("Cannot verify file deletion")
                            if (cursor.use { it.moveToFirst() }) error("Cannot delete file")
                        }
                        main.post { result.success(null) }
                    }
                } catch (e: Exception) {
                    main.post { result.error("storage", e.message, null) }
                }
            }
            return
        }
        withActivity(result) { it.handleFilesCall(call, result) }
    }

    private fun handleClipboard(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "writeText" -> {
                try {
                    val text = call.argument<String>("text") ?: error("Missing text")
                    val clipboard =
                        context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                    clipboard.setPrimaryClip(ClipData.newPlainText("text", text))
                    result.success(null)
                } catch (e: Exception) {
                    result.error("clipboard", e.message, null)
                }
            }
            "files" -> {
                val clipboard =
                    context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                val clip = clipboard.primaryClip
                result.success(
                    if (clip == null) emptyList<String>()
                    else
                        (0 until clip.itemCount).mapNotNull {
                            clip.getItemAt(it).uri?.toString()
                        }
                )
            }
            "materialize" -> {
                val value = call.argument<String>("uri")
                if (value == null) {
                    result.error("invalid", "Missing URI", null)
                    return
                }
                executor.execute {
                    try {
                        val uri = Uri.parse(value)
                        val name =
                            context.contentResolver
                                .query(
                                    uri,
                                    arrayOf(OpenableColumns.DISPLAY_NAME),
                                    null,
                                    null,
                                    null,
                                )
                                ?.use { cursor ->
                                    if (cursor.moveToFirst()) cursor.getString(0) else null
                                }
                                ?.substringAfterLast('/')
                                ?.substringAfterLast('\\')
                                ?.takeIf { it.isNotBlank() && it != "." && it != ".." }
                                ?: "clipboard-file"
                        val directory =
                            File(context.cacheDir, "clipboard/${UUID.randomUUID()}").apply {
                                mkdirs()
                            }
                        val file = File(directory, name)
                        context.contentResolver.openInputStream(uri)?.use { input ->
                            file.outputStream().use { output -> input.copyTo(output) }
                        } ?: error("Cannot read clipboard file")
                        main.post { result.success(file.absolutePath) }
                    } catch (e: Exception) {
                        main.post { result.error("clipboard", e.message, null) }
                    }
                }
            }
            "writeFile" ->
                writeClipboardFiles(
                    call.argument<String>("path")?.let { listOf(it) },
                    result,
                )
            "writeFiles" ->
                writeClipboardFiles(call.argument<List<String>>("paths"), result)
            else -> result.notImplemented()
        }
    }

    fun install(engine: FlutterEngine) {
        val messenger = engine.dartExecutor.binaryMessenger
        updates.install(messenger)
        MethodChannel(messenger, "vela/background").setMethodCallHandler(::handleBackground)
        MethodChannel(messenger, "vela/files").setMethodCallHandler(::handleFiles)
        MethodChannel(messenger, "vela/device").setMethodCallHandler { call, result ->
            if (call.method != "info") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val name =
                try {
                    Settings.Global.getString(context.contentResolver, Settings.Global.DEVICE_NAME)
                } catch (_: SecurityException) {
                    null
                }
            val type =
                if (context.resources.configuration.smallestScreenWidthDp >= 600) "tablet"
                else "mobile"
            result.success(
                mapOf("name" to (name?.takeIf { it.isNotBlank() } ?: Build.MODEL), "type" to type)
            )
        }
        MethodChannel(messenger, "vela/storage").setMethodCallHandler { call, result ->
            when (call.method) {
                "location" ->
                    try {
                        result.success(storage.location())
                    } catch (e: Exception) {
                        result.error("storage", e.message, null)
                    }
                "reset" -> {
                    storage.reset()
                    result.success(null)
                }
                "saveReceived" -> saveReceived(call.argument<List<String>>("paths"), result)
                "cancelSave" -> {
                    cancelSave()
                    result.success(null)
                }
                else -> withActivity(result) { it.handleStorageCall(call, result) }
            }
        }
        MethodChannel(messenger, "vela/clipboard").setMethodCallHandler(::handleClipboard)
        shareChannel = MethodChannel(messenger, "vela/share").also { channel ->
            channel.setMethodCallHandler { call, result ->
                val activity = context.currentActivity
                if (activity == null) result.success(null)
                else activity.handleShareCall(call, result)
            }
        }
    }
}
