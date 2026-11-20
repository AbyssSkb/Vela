package com.example.vela

import android.app.Activity
import android.app.AlertDialog
import android.app.NotificationManager
import android.content.ClipData
import android.content.ComponentName
import android.content.ContentResolver
import android.content.Context
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.DocumentsContract
import android.widget.Toast
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import androidx.core.content.IntentCompat

internal val shareDeviceId = Regex("[0-9a-f]{64}")

internal fun Intent.isShare(): Boolean =
    action == Intent.ACTION_SEND || action == Intent.ACTION_SEND_MULTIPLE

internal fun Intent.sharedUris(): List<Uri> {
    val streams = runCatching {
        if (action == Intent.ACTION_SEND_MULTIPLE) {
            val extras: List<*>? =
                IntentCompat.getParcelableArrayListExtra(this, Intent.EXTRA_STREAM, Uri::class.java)
            extras.orEmpty().filterIsInstance<Uri>()
        } else {
            listOfNotNull(IntentCompat.getParcelableExtra(this, Intent.EXTRA_STREAM, Uri::class.java))
        }
    }.getOrDefault(emptyList())
    val clipUris = clipData?.let { clip ->
        (0 until clip.itemCount).mapNotNull { clip.getItemAt(it).uri }
    }.orEmpty()
    val uris = (streams + clipUris + listOfNotNull(data)).filter { it.scheme == "content" }.distinct()
    return if (action == Intent.ACTION_SEND) uris.take(1) else uris
}

internal fun Intent.sharedText(): String? {
    val multiple = action == Intent.ACTION_SEND_MULTIPLE
    val items = if (multiple) {
        runCatching {
            val texts: List<*>? = getCharSequenceArrayListExtra(Intent.EXTRA_TEXT)
            texts.orEmpty().filterIsInstance<CharSequence>()
        }.getOrDefault(emptyList())
    } else emptyList()
    return items.filter { it.isNotEmpty() }.joinToString("\n")
        .takeIf { it.isNotEmpty() }
        ?: runCatching { getCharSequenceExtra(Intent.EXTRA_TEXT)?.toString() }.getOrNull()
        ?.takeIf { it.isNotEmpty() }
        ?: clipData?.let { clip ->
            val count = if (multiple) clip.itemCount else minOf(clip.itemCount, 1)
            (0 until count).mapNotNull { clip.getItemAt(it).text?.takeIf { text -> text.isNotEmpty() } }
                .joinToString("\n").takeIf { it.isNotEmpty() }
        }
}

internal fun Intent.shareShortcut(): String? =
    runCatching { getStringExtra(Intent.EXTRA_SHORTCUT_ID) }.getOrNull()
        ?.takeIf { it.length in 1..64 }

internal fun Intent.sharePayload(): Map<String, Any>? {
    if (!isShare()) return null
    val uris = sharedUris()
    if (uris.size > 100) return null
    if (uris.isNotEmpty()) return mapOf("uris" to uris.map(Uri::toString))
    return sharedText()?.let { mapOf("text" to it) }
}

internal fun Intent.withExternalFileViewer(context: Context): Intent {
    if (resolveActivity(context.packageManager)?.packageName != context.packageName) return this

    val target = ComponentName(context.packageName, "com.example.vela.SendWithVela")
    return Intent.createChooser(this, null)
        .putExtra(Intent.EXTRA_EXCLUDE_COMPONENTS, arrayOf(target))
        .addFlags(flags and Intent.FLAG_ACTIVITY_NEW_TASK)
}

class ShareActivity : Activity() {
    private var directSend: (() -> Unit)? = null

    override fun onPostResume() {
        super.onPostResume()
        val send = directSend
        directSend = null
        send?.invoke()
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val isShare = intent.isShare()
        val document = intent.data?.takeIf {
            intent.action == Intent.ACTION_VIEW && it.scheme == "content"
        }
        val type = if (document == null) intent.type else
            runCatching { intent.resolveType(contentResolver) }.getOrNull()
        val uris = when {
            isShare -> intent.sharedUris()
            document != null && !type.isDirectoryMimeType() -> listOf(document)
            else -> emptyList()
        }
        val text = if (uris.isNotEmpty()) null else when {
            isShare -> intent.sharedText()
            intent.action == Intent.ACTION_PROCESS_TEXT ->
                runCatching { intent.getCharSequenceExtra(Intent.EXTRA_PROCESS_TEXT)?.toString() }
                    .getOrNull()?.takeIf { it.isNotEmpty() }
            else -> null
        }
        if (uris.isEmpty() && text == null) {
            finish()
            return
        }
        if (uris.size > 100) {
            Toast.makeText(this, R.string.too_many_shared_files, Toast.LENGTH_LONG).show()
            finish()
            return
        }
        fun shareIntent(destination: Class<*>) =
            Intent(if (isShare) intent.action else Intent.ACTION_SEND)
                .setClass(this, destination)
                .setType(type)
                .apply {
                    if (uris.isNotEmpty()) {
                        clipData = ClipData.newRawUri("Vela", uris.first()).apply {
                            uris.drop(1).forEach { addItem(ClipData.Item(it)) }
                        }
                        addFlags(intent.flags and Intent.FLAG_GRANT_READ_URI_PERMISSION)
                    } else {
                        putExtra(Intent.EXTRA_TEXT, text)
                    }
                }
        val shortcut = if (isShare) intent.shareShortcut() else null
        val devices = shareDevices(this)
        val debugging =
            applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE != 0 &&
                runCatching { intent.getBooleanExtra("driver-test", false) }.getOrDefault(false)
        fun openVela(device: ShareDevice? = null) {
            val forward = shareIntent(MainActivity::class.java)
                .putExtra(Intent.EXTRA_SHORTCUT_ID, device?.shortcut ?: shortcut)
                .putExtra("driver-test", debugging)
                .addFlags(
                    Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_ACTIVITY_CLEAR_TOP or
                        Intent.FLAG_ACTIVITY_SINGLE_TOP
                )
            try {
                startActivity(forward)
            } catch (_: SecurityException) {
                // Some providers reject an explicit grant even when the URI is otherwise readable.
                forward.setFlags(forward.flags and Intent.FLAG_GRANT_READ_URI_PERMISSION.inv())
                startActivity(forward)
            } finally {
                finish()
            }
        }
        fun send(device: ShareDevice) {
            if (canShowShareProgress()) {
                val request = shareIntent(ShareTransferService::class.java)
                    .putExtra(ShareTransferService.EXTRA_PEER, device.peer)
                try {
                    ContextCompat.startForegroundService(this, request)
                    finish()
                    return
                } catch (_: SecurityException) {
                    // The foreground flow can use a readable URI without a transferable grant.
                } catch (_: IllegalStateException) {
                    // Some devices restrict foreground service starts even from a visible share.
                }
            }
            openVela(device)
        }
        val selected = devices.firstOrNull { it.shortcut == shortcut }
        when {
            selected != null -> directSend = { send(selected) }
            devices.isEmpty() || debugging -> openVela()
            else -> AlertDialog.Builder(this)
                .setTitle(R.string.share_choose_device)
                .setItems(devices.map { it.name }.toTypedArray()) { _, index -> send(devices[index]) }
                .setNegativeButton(android.R.string.cancel) { _, _ -> finish() }
                .setOnCancelListener { finish() }
                .show()
                .window?.setBackgroundDrawableResource(R.drawable.share_dialog_background)
        }
    }

    private fun canShowShareProgress(): Boolean {
        if (!NotificationManagerCompat.from(this).areNotificationsEnabled()) return false
        return Build.VERSION.SDK_INT < Build.VERSION_CODES.O ||
            getSystemService(NotificationManager::class.java)
                .getNotificationChannel(NotificationChannels.PROGRESS)?.importance !=
                NotificationManager.IMPORTANCE_NONE
    }
}

private fun String?.isDirectoryMimeType(): Boolean =
    this == DocumentsContract.Document.MIME_TYPE_DIR ||
        this?.startsWith(ContentResolver.CURSOR_DIR_BASE_TYPE + "/") == true
