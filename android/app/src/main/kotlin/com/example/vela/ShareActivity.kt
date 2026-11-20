package com.example.vela

import android.app.Activity
import android.content.ClipData
import android.content.ComponentName
import android.content.ContentResolver
import android.content.Context
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.net.Uri
import android.os.Bundle
import android.provider.DocumentsContract
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

internal fun Intent.sharedDevice(): String? =
    runCatching { getStringExtra(Intent.EXTRA_SHORTCUT_ID) }.getOrNull()
        ?.takeIf(shareDeviceId::matches)

internal fun Intent.withExternalFileViewer(context: Context): Intent {
    if (resolveActivity(context.packageManager)?.packageName != context.packageName) return this

    val target = ComponentName(context.packageName, "com.example.vela.SendWithVela")
    return Intent.createChooser(this, null)
        .putExtra(Intent.EXTRA_EXCLUDE_COMPONENTS, arrayOf(target))
        .addFlags(flags and Intent.FLAG_ACTIVITY_NEW_TASK)
}

class ShareActivity : Activity() {
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
        val forward =
            Intent(if (isShare) intent.action else Intent.ACTION_SEND)
                .setClass(this, MainActivity::class.java)
                .setType(type)
                .putExtra(Intent.EXTRA_SHORTCUT_ID, if (isShare) intent.sharedDevice() else null)
                .setFlags(
                    Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_ACTIVITY_CLEAR_TOP or
                        Intent.FLAG_ACTIVITY_SINGLE_TOP
                )
        if (isShare && applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE != 0) {
            forward.putExtra(
                "driver-test",
                runCatching { intent.getBooleanExtra("driver-test", false) }.getOrDefault(false),
            )
        }
        if (uris.isNotEmpty()) {
            forward.clipData = ClipData.newRawUri("Vela", uris.first()).apply {
                uris.drop(1).forEach { addItem(ClipData.Item(it)) }
            }
            forward.addFlags(intent.flags and Intent.FLAG_GRANT_READ_URI_PERMISSION)
        } else {
            forward.putExtra(Intent.EXTRA_TEXT, text)
        }
        try {
            startActivity(forward)
        } catch (_: SecurityException) {
            // Some senders mark URIs as grantable even when their provider disallows grants.
            forward.setFlags(forward.flags and Intent.FLAG_GRANT_READ_URI_PERMISSION.inv())
            startActivity(forward)
        } finally {
            finish()
        }
    }
}

private fun String?.isDirectoryMimeType(): Boolean =
    this == DocumentsContract.Document.MIME_TYPE_DIR ||
        this?.startsWith(ContentResolver.CURSOR_DIR_BASE_TYPE + "/") == true
