package com.example.vela

import android.content.Context
import android.net.Uri
import android.provider.DocumentsContract
import android.provider.OpenableColumns
import android.webkit.MimeTypeMap
import java.io.File
import java.io.InputStream
import java.io.OutputStream
import java.util.UUID
import java.util.concurrent.atomic.AtomicBoolean

class FolderDocuments(private val context: Context, private val cancelled: AtomicBoolean) {
    private val resolver = context.contentResolver
    private var entries = 0
    private var bytes = 0L
    private val seen = mutableSetOf<String>()
    private val maxBytes = 16L * 1024 * 1024 * 1024

    private fun check() {
        if (cancelled.get()) error("folder operation cancelled")
    }

    private fun component(name: String): String {
        require(
            name.isNotEmpty() &&
                name != "." &&
                name != ".." &&
                name.none { it == '/' || it == '\\' || it == ':' || it.isISOControl() }
        ) {
            "Invalid folder item name"
        }
        return name
    }

    private fun item(depth: Int) {
        check()
        require(depth <= 64 && ++entries <= 10000) { "Folder limit exceeded" }
    }

    private fun transfer(input: InputStream, output: OutputStream) {
        val buffer = ByteArray(64 * 1024)
        while (true) {
            check()
            val count = input.read(buffer)
            if (count < 0) break
            bytes += count
            require(bytes <= maxBytes && context.cacheDir.usableSpace >= 256L * 1024 * 1024) {
                "Folder size or free space limit exceeded"
            }
            output.write(buffer, 0, count)
        }
    }

    private fun temporary(): File =
        File(context.cacheDir, "vela-folder/${UUID.randomUUID()}").apply {
            check(mkdirs()) { "Cannot create temporary folder" }
        }

    private fun name(uri: Uri): String =
        resolver
            .query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
            ?.use { if (it.moveToFirst()) it.getString(0) else null }
            ?.let(::component) ?: error("Cannot read folder name")

    fun stageTree(tree: Uri): Map<String, String> {
        val temp = temporary()
        try {
            val rootId = DocumentsContract.getTreeDocumentId(tree)
            val rootUri = DocumentsContract.buildDocumentUriUsingTree(tree, rootId)
            val root = File(temp, name(rootUri))
            check(root.mkdir()) { "Cannot create temporary folder" }
            fun copyTree(id: String, directory: File, depth: Int) {
                check()
                require(seen.add(id)) { "Repeated folder reference" }
                val children = DocumentsContract.buildChildDocumentsUriUsingTree(tree, id)
                val projection =
                    arrayOf(
                        DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                        DocumentsContract.Document.COLUMN_DISPLAY_NAME,
                        DocumentsContract.Document.COLUMN_MIME_TYPE,
                    )
                val cursor =
                    resolver.query(children, projection, null, null, null)
                        ?: error("Cannot read folder")
                cursor.use {
                    while (it.moveToNext()) {
                        item(depth)
                        val childId = it.getString(0) ?: error("Invalid folder item")
                        val childName =
                            component(it.getString(1) ?: error("Missing folder item name"))
                        val mime = it.getString(2) ?: error("Missing folder item type")
                        val child = File(directory, childName)
                        val uri = DocumentsContract.buildDocumentUriUsingTree(tree, childId)
                        if (mime == DocumentsContract.Document.MIME_TYPE_DIR) {
                            check(child.mkdir()) { "Duplicate folder item" }
                            copyTree(childId, child, depth + 1)
                        } else {
                            require(!mime.startsWith("vnd.android.document/")) {
                                "Virtual files are not supported"
                            }
                            check(child.createNewFile()) { "Duplicate folder item" }
                            (resolver.openInputStream(uri) ?: error("Cannot read folder item"))
                                .use { input ->
                                    child.outputStream().use { output -> transfer(input, output) }
                                }
                        }
                    }
                }
            }
            copyTree(rootId, root, 1)
            return mapOf("path" to root.absolutePath, "temporary" to temp.absolutePath)
        } catch (e: Exception) {
            temp.deleteRecursively()
            throw e
        }
    }

    fun stageFile(path: String): Map<String, String> {
        val temp = temporary()
        try {
            val uri = Uri.parse(path)
            val sourceName = if (uri.scheme == "content") name(uri) else component(File(path).name)
            val file = File(temp, sourceName)
            val input =
                if (uri.scheme == "content") resolver.openInputStream(uri)
                else File(path).inputStream()
            (input ?: error("Cannot read archive")).use { stream ->
                file.outputStream().use { transfer(stream, it) }
            }
            return mapOf("path" to file.absolutePath, "temporary" to temp.absolutePath)
        } catch (e: Exception) {
            temp.deleteRecursively()
            throw e
        }
    }

    fun saveTree(tree: Uri, source: String): String {
        val directory = File(source).canonicalFile
        val cache = context.cacheDir.canonicalPath + File.separator
        require(directory.path.startsWith(cache) && directory.isDirectory) {
            "Invalid source folder"
        }
        val parent =
            DocumentsContract.buildDocumentUriUsingTree(
                tree,
                DocumentsContract.getTreeDocumentId(tree),
            )
        var root: Uri? = null
        try {
            fun copyTree(folder: File, target: Uri, depth: Int) {
                for (child in folder.listFiles() ?: error("Cannot read folder")) {
                    item(depth)
                    require(child.canonicalPath == child.absolutePath) { "Invalid folder item" }
                    val mime =
                        if (child.isDirectory) DocumentsContract.Document.MIME_TYPE_DIR
                        else
                            MimeTypeMap.getSingleton()
                                .getMimeTypeFromExtension(child.extension.lowercase())
                                ?: "application/octet-stream"
                    val created =
                        DocumentsContract.createDocument(
                            resolver,
                            target,
                            mime,
                            component(child.name),
                        ) ?: error("Cannot create folder item")
                    if (child.isDirectory) copyTree(child, created, depth + 1)
                    else if (child.isFile)
                        (resolver.openOutputStream(created) ?: error("Cannot write folder item"))
                            .use { output ->
                                child.inputStream().use { input -> transfer(input, output) }
                            }
                    else error("Invalid folder item")
                }
            }
            check()
            root =
                DocumentsContract.createDocument(
                    resolver,
                    parent,
                    DocumentsContract.Document.MIME_TYPE_DIR,
                    component(directory.name),
                ) ?: error("Cannot create folder")
            copyTree(directory, root, 1)
            check()
            return root.toString()
        } catch (e: Exception) {
            root?.let {
                try {
                    DocumentsContract.deleteDocument(resolver, it)
                } catch (_: Exception) {}
            }
            throw e
        }
    }
}
