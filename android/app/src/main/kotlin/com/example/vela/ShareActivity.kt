package com.example.vela

import android.app.Activity
import android.content.ClipData
import android.content.Intent
import android.net.Uri
import android.os.Bundle

class ShareActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val grants =
            intent.flags and
                (Intent.FLAG_GRANT_READ_URI_PERMISSION or
                    Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                    Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION or
                    Intent.FLAG_GRANT_PREFIX_URI_PERMISSION)
        val forward =
            Intent(intent)
                .setClass(this, MainActivity::class.java)
                .setFlags(
                    grants or
                        Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_ACTIVITY_CLEAR_TOP or
                        Intent.FLAG_ACTIVITY_SINGLE_TOP
                )
        if (forward.clipData == null) {
            @Suppress("DEPRECATION")
            val uris =
                if (intent.action == Intent.ACTION_SEND_MULTIPLE)
                    intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM).orEmpty()
                else listOfNotNull(intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM))
            if (uris.isNotEmpty())
                forward.clipData =
                    ClipData.newRawUri("Vela", uris.first()).apply {
                        uris.drop(1).forEach { addItem(ClipData.Item(it)) }
                    }
        }
        startActivity(forward)
        finish()
    }
}
