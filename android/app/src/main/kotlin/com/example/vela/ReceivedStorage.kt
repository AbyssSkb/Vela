package com.example.vela

import android.content.ContentValues
import android.content.Context
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.DocumentsContract
import android.provider.MediaStore
import android.provider.OpenableColumns
import android.webkit.MimeTypeMap
import java.io.File
import java.util.concurrent.atomic.AtomicBoolean

class ReceivedStorage(private val context: Context) {
    private val resolver = context.contentResolver
    private val prefs = context.getSharedPreferences("vela_received_storage", Context.MODE_PRIVATE)
    val tree: Uri?
        get() = prefs.getString("tree", null)?.let(Uri::parse)

    fun location(): Map<String, Any> {
        val selected = tree ?: return mapOf("isDefault" to true, "displayPath" to "")
        if (
            resolver.persistedUriPermissions.none {
                it.uri == selected && it.isReadPermission && it.isWritePermission
            }
        )
            error("Folder permission is unavailable")
        val id = DocumentsContract.getTreeDocumentId(selected)
        return mapOf("isDefault" to false, "displayPath" to id.substringAfter(':', id))
    }

    fun setTree(uri: Uri) {
        prefs.edit().putString("tree", uri.toString()).apply()
    }

    fun reset() {
        prefs.edit().remove("tree").apply()
    }

    fun delete(uri: Uri): Boolean =
        if (DocumentsContract.isDocumentUri(context, uri))
            DocumentsContract.deleteDocument(resolver, uri)
        else resolver.delete(uri, null, null) > 0

    private fun mime(name: String): String =
        MimeTypeMap.getSingleton()
            .getMimeTypeFromExtension(name.substringAfterLast('.', "").lowercase())
            ?: "application/octet-stream"

    private fun displayName(uri: Uri, fallback: String): String =
        try {
            resolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use {
                if (it.moveToFirst()) it.getString(0) else null
            } ?: fallback
        } catch (_: Exception) {
            fallback
        }

    fun save(paths: List<String>, cancelled: AtomicBoolean): List<Map<String, String>> {
        val createdUris = mutableListOf<Uri>()
        val createdFiles = mutableListOf<File>()
        val results = mutableListOf<Map<String, String>>()
        val selectedTree = tree
        try {
            val parent =
                selectedTree?.let {
                    DocumentsContract.buildDocumentUriUsingTree(
                        it,
                        DocumentsContract.getTreeDocumentId(it),
                    )
                }
            val folderLabel =
                parent?.let {
                    val id = DocumentsContract.getDocumentId(it)
                    displayName(it, id.substringAfter(':', id))
                }
            for (path in paths) {
                if (cancelled.get()) error("save cancelled")
                val source = File(path)
                val name = source.name
                val uri: Uri?
                val file: File?
                if (parent != null) {
                    uri =
                        DocumentsContract.createDocument(resolver, parent, mime(name), name)
                            ?: error("Cannot create file")
                    createdUris.add(uri)
                    file = null
                } else if (Build.VERSION.SDK_INT >= 29) {
                    val values =
                        ContentValues().apply {
                            put(MediaStore.Downloads.DISPLAY_NAME, name)
                            put(MediaStore.Downloads.MIME_TYPE, mime(name))
                            put(
                                MediaStore.Downloads.RELATIVE_PATH,
                                Environment.DIRECTORY_DOWNLOADS + "/",
                            )
                            put(MediaStore.Downloads.IS_PENDING, 1)
                        }
                    uri =
                        resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
                            ?: error("Cannot create download")
                    createdUris.add(uri)
                    file = null
                } else {
                    @Suppress("DEPRECATION")
                    val directory =
                        Environment.getExternalStoragePublicDirectory(
                            Environment.DIRECTORY_DOWNLOADS
                        )
                    if (!directory.exists() && !directory.mkdirs()) error("Cannot open Downloads")
                    val stem = source.nameWithoutExtension
                    val extension = source.extension.let { if (it.isEmpty()) "" else ".$it" }
                    var candidate = File(directory, name)
                    var suffix = 1
                    while (!candidate.createNewFile()) {
                        candidate = File(directory, "$stem (${suffix++})$extension")
                    }
                    createdFiles.add(candidate)
                    file = candidate
                    uri = null
                }
                val output =
                    if (uri != null) resolver.openOutputStream(uri) else file!!.outputStream()
                (output ?: error("Cannot write file")).use { destination ->
                    source.inputStream().use { input ->
                        val buffer = ByteArray(64 * 1024)
                        while (true) {
                            if (cancelled.get()) error("save cancelled")
                            val count = input.read(buffer)
                            if (count < 0) break
                            destination.write(buffer, 0, count)
                        }
                    }
                }
                if (cancelled.get()) error("save cancelled")
                results.add(
                    buildMap {
                        put("path", uri?.toString() ?: file!!.absolutePath)
                        put("name", uri?.let { displayName(it, name) } ?: file!!.name)
                        if (folderLabel != null) put("folderLabel", folderLabel)
                    }
                )
            }
            if (selectedTree == null && Build.VERSION.SDK_INT >= 29) {
                for (uri in createdUris) {
                    if (cancelled.get()) error("save cancelled")
                    if (
                        resolver.update(
                            uri,
                            ContentValues().apply { put(MediaStore.Downloads.IS_PENDING, 0) },
                            null,
                            null,
                        ) != 1
                    )
                        error("Cannot publish download")
                }
            }
            if (cancelled.get()) error("save cancelled")
            for (index in results.indices) {
                val saved = results[index]
                val path = saved.getValue("path")
                if (path.startsWith("content:")) {
                    results[index] =
                        saved + ("name" to displayName(Uri.parse(path), saved.getValue("name")))
                }
            }
            if (createdFiles.isNotEmpty())
                MediaScannerConnection.scanFile(
                    context,
                    createdFiles.map { it.absolutePath }.toTypedArray(),
                    null,
                    null,
                )
            return results
        } catch (e: Exception) {
            for (uri in createdUris) try {
                delete(uri)
            } catch (_: Exception) {}
            for (file in createdFiles) file.delete()
            throw e
        }
    }
}
