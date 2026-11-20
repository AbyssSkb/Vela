package com.example.vela

import android.Manifest
import android.app.DownloadManager
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import android.provider.OpenableColumns
import android.provider.Settings
import android.webkit.MimeTypeMap
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.UUID
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

class MainActivity : FlutterActivity() {
    private val executor = Executors.newSingleThreadExecutor()
    private var pendingStart: MethodChannel.Result? = null
    private var pendingExport: Pair<File, MethodChannel.Result>? = null
    private var exportPreparing = false
    private var pendingDirectory: MethodChannel.Result? = null
    private var pendingFolderPick: MethodChannel.Result? = null
    private var pendingSave: Pair<List<String>, MethodChannel.Result>? = null
    private val saveCancelled = AtomicBoolean(false)
    private val app get() = application as VelaApplication
    private val receivedStorage get() = app.channels.storage
    private var pendingMedia: MethodChannel.Result? = null
    private val mediaPicker = ActivityResultContracts.PickMultipleVisualMedia(100)
    private var serviceMessage: String? = null
    private val pendingShares = ArrayDeque<Map<String, Any>>()

    private fun inputFor(path: String) =
        if (path.startsWith("content:")) contentResolver.openInputStream(Uri.parse(path))
        else File(path).inputStream()

    private fun startSaving(paths: List<String>, result: MethodChannel.Result) {
        app.channels.saveReceived(paths, result)
    }

    override fun provideFlutterEngine(context: Context): FlutterEngine {
        return app.getOrCreateEngine()
    }

    override fun shouldDestroyEngineWithHost(): Boolean = false

    override fun onStart() {
        super.onStart()
        val enabled =
            getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                .getBoolean("flutter.background_receive_default", false)
        if (enabled && !ReceivingService.running) {
            try {
                val service = Intent(this, ReceivingService::class.java)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) startForegroundService(service)
                else startService(service)
            } catch (e: Exception) {
                android.util.Log.w("Vela", "Could not resume background service", e)
            }
        }
    }

    private fun startReceiving(result: MethodChannel.Result) {
        try {
            val service =
                Intent(this, ReceivingService::class.java).putExtra("message", serviceMessage)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) startForegroundService(service)
            else startService(service)
            result.success(true)
        } catch (e: Exception) {
            result.error("background", e.message, null)
        }
    }

    @Deprecated("Deprecated in Android")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (app.channels.onUpdateActivityResult(requestCode, resultCode)) return
        if (requestCode == 7106) {
            val result = pendingFolderPick ?: return
            pendingFolderPick = null
            val uri = data?.data
            if (resultCode != RESULT_OK || uri == null) result.success(null)
            else result.success(uri.toString())
            return
        }
        if (requestCode == 7105) {
            val result = pendingDirectory ?: return
            pendingDirectory = null
            val uri = data?.data
            if (resultCode != RESULT_OK || uri == null) {
                result.success(false)
                return
            }
            try {
                val flags =
                    (data?.flags ?: 0) and
                        (Intent.FLAG_GRANT_READ_URI_PERMISSION or
                            Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
                val requiredFlags =
                    Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
                if (flags != requiredFlags) error("Folder is not writable")
                contentResolver.takePersistableUriPermission(uri, flags)
                receivedStorage.setTree(uri)
                result.success(true)
            } catch (e: Exception) {
                result.error("storage", e.message, null)
            }
            return
        }
        if (requestCode == 7103) {
            val result = pendingMedia ?: return
            pendingMedia = null
            result.success(mediaPicker.parseResult(resultCode, data).map { it.toString() })
            return
        }
        if (requestCode != 7102) return
        val (file, result) = pendingExport ?: return
        pendingExport = null
        val uri = data?.data
        if (resultCode != RESULT_OK || uri == null) {
            file.parentFile?.deleteRecursively()
            result.success(false)
            return
        }
        executor.execute {
            try {
                contentResolver.openOutputStream(uri)?.use { output ->
                    file.inputStream().use { input -> input.copyTo(output) }
                } ?: error("Cannot write destination")
                runOnUiThread { result.success(true) }
            } catch (e: Exception) {
                runOnUiThread { result.error("export", e.message, null) }
            } finally {
                file.parentFile?.deleteRecursively()
            }
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 7101) {
            val result = pendingStart ?: return
            pendingStart = null
            if (grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED)
                startReceiving(result)
            else result.success(false)
        }
        if (requestCode == 7104) {
            val (paths, result) = pendingSave ?: return
            pendingSave = null
            if (
                grantResults.isNotEmpty() &&
                    grantResults.all { it == PackageManager.PERMISSION_GRANTED } &&
                    !saveCancelled.get()
            )
                startSaving(paths, result)
            else
                result.error(
                    if (saveCancelled.get()) "cancelled" else "storage",
                    "Storage access was not granted",
                    null,
                )
        }
    }

    override fun getDartEntrypointArgs(): List<String>? =
        if (
            applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE != 0 &&
                intent.getBooleanExtra("driver-test", false)
        )
            listOf("--driver-test")
        else null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        app.attachActivity(this)
    }

    fun requestBackgroundReceiving(message: String?, result: MethodChannel.Result) {
        serviceMessage = message
        if (
            Build.VERSION.SDK_INT >= 33 &&
                checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
                    PackageManager.PERMISSION_GRANTED
        ) {
            if (pendingStart != null)
                result.error("background", "Request already in progress", null)
            else {
                pendingStart = result
                requestPermissions(
                    arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                    7101,
                )
            }
        } else startReceiving(result)
    }

    fun resumeBackgroundReceiving(message: String?, result: MethodChannel.Result) {
        serviceMessage = message
        if (
            Build.VERSION.SDK_INT >= 33 &&
                checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
                    PackageManager.PERMISSION_GRANTED
        )
            result.success(false)
        else startReceiving(result)
    }

    fun openBackgroundSettings(section: String?, result: MethodChannel.Result) {
        NotificationChannels.ensure(this)
        val uri = Uri.fromParts("package", packageName, null)
        val appSettings = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, uri)
        val intent =
            when (section) {
                "notifications" ->
                    if (
                        Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
                            getSystemService(NotificationManager::class.java)
                                .getNotificationChannel(ReceivingService.OFFERS) !=
                                null
                    )
                        Intent(Settings.ACTION_CHANNEL_NOTIFICATION_SETTINGS)
                            .putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                            .putExtra(
                                Settings.EXTRA_CHANNEL_ID,
                                ReceivingService.OFFERS,
                            )
                    else
                        Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                            .putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                "notification_app" ->
                    Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                        .putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                "notification_progress",
                "notification_results",
                "notification_requests" ->
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
                        Intent(Settings.ACTION_CHANNEL_NOTIFICATION_SETTINGS)
                            .putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                            .putExtra(
                                Settings.EXTRA_CHANNEL_ID,
                                when (section) {
                                    "notification_progress" ->
                                        NotificationChannels.PROGRESS
                                    "notification_results" ->
                                        NotificationChannels.RESULTS
                                    else -> ReceivingService.OFFERS
                                },
                            )
                    else
                        Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                            .putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                "notification_live" ->
                    if (Build.VERSION.SDK_INT >= 36)
                        Intent(Settings.ACTION_APP_NOTIFICATION_PROMOTION_SETTINGS)
                            .putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                    else
                        Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                            .putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                "battery" -> appSettings
                "battery_exemption" ->
                    Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS, uri)
                "autostart" -> Intent(Settings.ACTION_SETTINGS)
                "guide" -> {
                    val guide =
                        if (resources.configuration.locales[0].language == "zh")
                            "user-guide.zh-CN.md#后台接收"
                        else "user-guide.md#receive-in-the-background"
                    Intent(
                        Intent.ACTION_VIEW,
                        Uri.parse("https://github.com/AbyssSkb/Vela/blob/main/docs/$guide"),
                    )
                }
                else -> appSettings
            }
        val fallbacks =
            when (section) {
                "battery_exemption" ->
                    listOf(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS), appSettings)
                "battery", "autostart", "guide" -> listOf(appSettings)
                else ->
                    listOf(
                        Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                            .putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                    )
            }
        var failure: Exception? = null
        for (settings in (listOf(intent) + fallbacks).distinctBy { it.action }) {
            try {
                startActivity(settings)
                result.success(null)
                return
            } catch (e: Exception) {
                failure = e
            }
        }
        result.error("settings", failure?.message, null)
    }

    fun handleFilesCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method == "pickFolder") {
            if (pendingFolderPick != null) {
                result.error("picker", "Selection already in progress", null)
                return
            }
            pendingFolderPick = result
            try {
                val flags =
                    Intent.FLAG_GRANT_READ_URI_PERMISSION or
                        if (call.argument<Boolean>("write") == true)
                            Intent.FLAG_GRANT_WRITE_URI_PERMISSION
                        else 0
                val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).addFlags(flags)
                @Suppress("DEPRECATION") startActivityForResult(intent, 7106)
            } catch (e: Exception) {
                pendingFolderPick = null
                result.error("picker", e.message, null)
            }
            return
        }
        if (call.method == "pickMedia") {
            if (pendingMedia != null) {
                result.error("picker", "Selection already in progress", null)
                return
            }
            pendingMedia = result
            try {
                val request =
                    PickVisualMediaRequest.Builder()
                        .setMediaType(ActivityResultContracts.PickVisualMedia.ImageAndVideo)
                        .build()
                @Suppress("DEPRECATION")
                startActivityForResult(mediaPicker.createIntent(this, request), 7103)
            } catch (e: Exception) {
                pendingMedia = null
                result.error("picker", e.message, null)
            }
            return
        }
        if (call.method == "openUrl") {
            val uri = Uri.parse(call.argument<String>("url") ?: "")
            if (uri.scheme !in listOf("http", "https") || uri.host.isNullOrBlank()) {
                result.error("url", "Invalid URL", null)
                return
            }
            try {
                startActivity(Intent(Intent.ACTION_VIEW, uri))
                result.success(null)
            } catch (e: Exception) {
                result.error("url", e.message, null)
            }
            return
        }
        if (call.method == "openPath") {
            try {
                val path = call.argument<String>("path") ?: error("Missing path")
                val uri =
                    if (path.startsWith("content:")) Uri.parse(path)
                    else
                        FileProvider.getUriForFile(
                            this,
                            "$packageName.provider",
                            File(path),
                        )
                val type = contentResolver.getType(uri) ?: "application/octet-stream"
                val intent =
                    Intent(Intent.ACTION_VIEW)
                        .setDataAndType(uri, type)
                        .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                startActivity(intent.withExternalFileViewer(this))
                result.success(null)
            } catch (e: android.content.ActivityNotFoundException) {
                result.error("no_app", e.message, null)
            } catch (e: Exception) {
                result.error("open", e.message, null)
            }
            return
        }
        if (call.method != "saveAs") {
            result.notImplemented()
            return
        }
        val path = call.argument<String>("path")
        val name =
            call
                .argument<String>("name")
                ?.substringAfterLast('/')
                ?.substringAfterLast('\\')
                ?.takeIf { it.isNotBlank() } ?: "file"
        if (path == null || pendingExport != null || exportPreparing) {
            result.error("export", "File unavailable", null)
            return
        }
        exportPreparing = true
        executor.execute {
            val directory = File(cacheDir, "exports/${UUID.randomUUID()}")
            val snapshot = File(directory, name)
            try {
                if (!directory.mkdirs()) error("Cannot prepare file")
                inputFor(path)?.use { input ->
                    snapshot.outputStream().use { output -> input.copyTo(output) }
                } ?: error("Cannot read file")
                runOnUiThread {
                    exportPreparing = false
                    val type =
                        MimeTypeMap.getSingleton()
                            .getMimeTypeFromExtension(snapshot.extension.lowercase())
                            ?: "application/octet-stream"
                    val intent =
                        Intent(Intent.ACTION_CREATE_DOCUMENT)
                            .addCategory(Intent.CATEGORY_OPENABLE)
                            .setType(type)
                            .putExtra(Intent.EXTRA_TITLE, name)
                    pendingExport = snapshot to result
                    try {
                        @Suppress("DEPRECATION") startActivityForResult(intent, 7102)
                    } catch (e: Exception) {
                        pendingExport = null
                        directory.deleteRecursively()
                        result.error("export", e.message, null)
                    }
                }
            } catch (e: Exception) {
                directory.deleteRecursively()
                runOnUiThread {
                    exportPreparing = false
                    result.error("export", e.message, null)
                }
            }
        }
    }

    fun handleStorageCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "openFolder" ->
                try {
                    val path = call.argument<String>("path")
                    val item = path?.takeIf { it.startsWith("content:") }?.let(Uri::parse)
                    val tree =
                        if (path == null) receivedStorage.tree
                        else
                            item?.takeIf {
                                android.provider.DocumentsContract.isTreeUri(it)
                            }
                    if (
                        item != null &&
                            tree == null &&
                            item.authority != MediaStore.AUTHORITY
                    )
                        error("Folder cannot be determined")
                    if (
                        path != null &&
                            item == null &&
                            !File(path)
                                .absolutePath
                                .startsWith(
                                    android.os.Environment
                                        .getExternalStoragePublicDirectory(
                                            android.os.Environment.DIRECTORY_DOWNLOADS
                                        )
                                        .absolutePath + "/"
                                )
                    )
                        error("Folder cannot be opened")
                    val intent =
                        if (tree == null) Intent(DownloadManager.ACTION_VIEW_DOWNLOADS)
                        else {
                            val folder =
                                android.provider.DocumentsContract
                                    .buildDocumentUriUsingTree(
                                        tree,
                                        android.provider.DocumentsContract
                                            .getTreeDocumentId(tree),
                                    )
                            Intent(Intent.ACTION_VIEW)
                                .setDataAndType(
                                    folder,
                                    android.provider.DocumentsContract.Document
                                        .MIME_TYPE_DIR,
                                )
                                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                .withExternalFileViewer(this)
                        }
                    startActivity(intent)
                    result.success(null)
                } catch (e: Exception) {
                    result.error("storage", e.message, null)
                }
            "choose" -> {
                if (pendingDirectory != null) {
                    result.error("storage", "Selection already in progress", null)
                    return
                }
                val intent =
                    Intent(Intent.ACTION_OPEN_DOCUMENT_TREE)
                        .addFlags(
                            Intent.FLAG_GRANT_READ_URI_PERMISSION or
                                Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                                Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION
                        )
                pendingDirectory = result
                try {
                    @Suppress("DEPRECATION") startActivityForResult(intent, 7105)
                } catch (e: Exception) {
                    pendingDirectory = null
                    result.error("storage", e.message, null)
                }
            }
            else -> result.notImplemented()
        }
    }

    fun requestSavePermission(paths: List<String>, result: MethodChannel.Result) {
        if (pendingSave != null) {
            result.error("storage", "Save already in progress", null)
            return
        }
        if (!hasWindowFocus()) {
            result.error("storage", "Storage permission required", null)
            return
        }
        saveCancelled.set(false)
        pendingSave = paths to result
        requestPermissions(
            arrayOf(
                Manifest.permission.READ_EXTERNAL_STORAGE,
                Manifest.permission.WRITE_EXTERNAL_STORAGE,
            ),
            7104,
        )
    }

    fun cancelPendingSave() {
        saveCancelled.set(true)
    }

    fun handleShareCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method == "takeReceivedBatch") {
            val batchIntent = intent
            if (batchIntent?.action != ACTION_VIEW_RECEIVED_BATCH) {
                result.success(null)
                return
            }
            batchIntent.action = null
            val batchId = batchIntent.getStringExtra("batchId")
            result.success(
                batchId?.takeIf { it.length in 1..20 && it.all { char -> char in '0'..'9' } }
            )
            return
        }
        if (call.method == "takeTextPreview") {
            val previewIntent = intent
            if (previewIntent?.action != "com.example.vela.VIEW_TEXT") {
                result.success(null)
                return
            }
            previewIntent.action = null
            try {
                val path = previewIntent.getStringExtra("path") ?: error("Missing text")
                val file = File(path).canonicalFile
                val root = File(filesDir, "Vela").canonicalPath + File.separator
                if (
                    !file.path.startsWith(root) ||
                        !file.isFile ||
                        file.extension != "txt"
                )
                    error("Invalid text")
                result.success(file.path)
            } catch (e: Exception) {
                result.error("preview", e.message, null)
            }
            return
        }
        if (call.method != "take") {
            result.notImplemented()
            return
        }
        enqueueShare()
        result.success(pendingShares.removeFirstOrNull())
    }

    private fun enqueueShare() {
        val sharedIntent = intent ?: return
        if (!sharedIntent.isShare()) return
        val payload = sharedIntent.sharePayload()
        sharedIntent.action = null
        if (payload == null) return
        val shortcut = sharedIntent.shareShortcut()
        val device = shareDevices(this).firstOrNull { it.shortcut == shortcut }
        if (device != null) {
            app.channels.enqueueConfirmedShare(payload + ("preferredPeer" to device.peer))
        } else {
            val legacy = shortcut?.takeIf(shareDeviceId::matches)
            pendingShares.addLast(
                if (legacy == null) payload else payload + ("preferredPeer" to legacy)
            )
        }
    }

    override fun onNewIntent(intent: Intent) {
        enqueueShare()
        super.onNewIntent(intent)
        setIntent(intent)
        notifyPendingShare()
    }

    override fun onPostResume() {
        super.onPostResume()
        notifyPendingShare()
    }

    private fun notifyPendingShare() {
        enqueueShare()
        if (
            pendingShares.isNotEmpty() ||
                intent?.action == "com.example.vela.VIEW_TEXT" ||
                intent?.action == ACTION_VIEW_RECEIVED_BATCH
        )
            app.channels.shareAvailable()
    }

    override fun onDestroy() {
        app.detachActivity(this)
        executor.shutdown()
        super.onDestroy()
    }
}
