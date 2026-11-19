package com.example.vela

import android.app.Activity
import android.content.ClipData
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.net.Uri
import android.os.Bundle
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

internal fun Intent.sharedText(): String? =
    runCatching { getCharSequenceExtra(Intent.EXTRA_TEXT)?.toString() }.getOrNull()
        ?.takeIf { it.isNotEmpty() }
        ?: clipData?.takeIf { it.itemCount > 0 }?.getItemAt(0)?.text?.toString()
            ?.takeIf { it.isNotEmpty() }

internal fun Intent.sharedDevice(): String? =
    runCatching { getStringExtra(Intent.EXTRA_SHORTCUT_ID) }.getOrNull()
        ?.takeIf(shareDeviceId::matches)

class ShareActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (!intent.isShare()) {
            finish()
            return
        }
        val forward =
            Intent(intent.action)
                .setClass(this, MainActivity::class.java)
                .setType(intent.type)
                .putExtra(Intent.EXTRA_SHORTCUT_ID, intent.sharedDevice())
                .setFlags(
                    Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_ACTIVITY_CLEAR_TOP or
                        Intent.FLAG_ACTIVITY_SINGLE_TOP
                )
        if (applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE != 0) {
            forward.putExtra(
                "driver-test",
                runCatching { intent.getBooleanExtra("driver-test", false) }.getOrDefault(false),
            )
        }
        val uris = intent.sharedUris()
        if (uris.isNotEmpty()) {
            forward.clipData = ClipData.newRawUri("Vela", uris.first()).apply {
                uris.drop(1).forEach { addItem(ClipData.Item(it)) }
            }
            forward.addFlags(intent.flags and Intent.FLAG_GRANT_READ_URI_PERMISSION)
        } else {
            forward.putExtra(Intent.EXTRA_TEXT, intent.sharedText())
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
