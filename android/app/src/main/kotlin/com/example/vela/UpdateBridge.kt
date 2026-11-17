package com.example.vela

import android.app.Activity
import android.content.ClipData
import android.content.Intent
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.nio.file.Files
import java.security.MessageDigest
import java.util.concurrent.Executors

internal data class UpdateIdentity(
    val packageName: String,
    val version: Long,
    val signers: Set<String>,
)

internal fun validateUpdateIdentity(installed: UpdateIdentity, candidate: UpdateIdentity) {
    require(candidate.packageName == installed.packageName) { "Update belongs to another app" }
    require(candidate.version > installed.version) { "Update is not newer than the installed app" }
    require(installed.signers.isNotEmpty() && candidate.signers == installed.signers) {
        "Update signing certificate does not match the installed app"
    }
}

class UpdateBridge(private val context: VelaApplication) {
    private var busy = true
    private var preparing = false
    private var pendingInstall: MethodChannel.Result? = null
    private var channel: MethodChannel? = null
    private val executor = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    private fun directory(): File =
        File(context.cacheDir, "vela-updates").also {
            check(it.isDirectory || it.mkdirs()) { "Cannot create update cache" }
        }.canonicalFile

    @Suppress("DEPRECATION")
    private fun identity(info: PackageInfo): UpdateIdentity {
        val signatures =
            if (Build.VERSION.SDK_INT >= 28) info.signingInfo?.apkContentsSigners
            else info.signatures
        val digest = MessageDigest.getInstance("SHA-256")
        return UpdateIdentity(
            info.packageName,
            if (Build.VERSION.SDK_INT >= 28) info.longVersionCode else info.versionCode.toLong(),
            signatures.orEmpty().map { signature ->
                digest.digest(signature.toByteArray()).joinToString("") { "%02x".format(it) }
            }.toSet(),
        )
    }

    @Suppress("DEPRECATION")
    private fun installed(): PackageInfo =
        context.packageManager.getPackageInfo(context.packageName, signingFlags())

    @Suppress("DEPRECATION")
    private fun signingFlags(): Int =
        if (Build.VERSION.SDK_INT >= 28) PackageManager.GET_SIGNING_CERTIFICATES
        else PackageManager.GET_SIGNATURES

    @Suppress("DEPRECATION")
    private fun verifiedPackage(path: String, expectedHash: String): File {
        val source = File(path)
        val file = source.canonicalFile
        require(file.parentFile == directory() && file.extension == "apk" && file.isFile) {
            "Update must be an APK in Vela's update cache"
        }
        require(Build.VERSION.SDK_INT < 26 || !Files.isSymbolicLink(source.toPath())) {
            "Update cannot be a symbolic link"
        }
        require(expectedHash.matches(Regex("[a-f0-9]{64}"))) { "Invalid update checksum" }
        val digest = MessageDigest.getInstance("SHA-256")
        file.inputStream().use { input ->
            val buffer = ByteArray(64 * 1024)
            while (true) {
                val read = input.read(buffer)
                if (read < 0) break
                digest.update(buffer, 0, read)
            }
        }
        val actualHash = digest.digest().joinToString("") { "%02x".format(it) }
        require(actualHash == expectedHash) { "Update checksum does not match" }
        val archive =
            context.packageManager.getPackageArchiveInfo(file.path, signingFlags())
                ?: throw IllegalArgumentException("Cannot read update package")
        validateUpdateIdentity(identity(installed()), identity(archive))
        return file
    }

    @Suppress("DEPRECATION")
    private fun launchInstaller(file: File, result: MethodChannel.Result) {
        check(!busy) { "Finish transfers and pairing before installing an update" }
        val activity = context.currentActivity
        if (activity == null) {
            preparing = false
            result.error("activity", "Open Vela to install the update", null)
            return
        }
        if (Build.VERSION.SDK_INT >= 26 && !context.packageManager.canRequestPackageInstalls()) {
            activity.startActivity(
                Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:${context.packageName}"))
            )
            preparing = false
            result.error("unknown_sources", "Allow Vela to install updates, then try again", null)
            return
        }
        val uri = FileProvider.getUriForFile(context, "${context.packageName}.provider", file)
        val intent = Intent(Intent.ACTION_INSTALL_PACKAGE).apply {
            data = uri
            putExtra(Intent.EXTRA_RETURN_RESULT, true)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            clipData = ClipData.newRawUri("Vela update", uri)
        }
        val updates = channel ?: error("Update channel is not initialized")
        updates.invokeMethod(
            "prepareInstall",
            null,
            object : MethodChannel.Result {
                override fun success(approved: Any?) {
                    if (approved != true) {
                        preparing = false
                        result.error("busy", "Update installation was not approved", null)
                        return
                    }
                    try {
                        val current = context.currentActivity
                            ?: throw IllegalStateException("Open Vela to install the update")
                        pendingInstall = result
                        current.startActivityForResult(intent, 7190)
                    } catch (e: Exception) {
                        pendingInstall = null
                        preparing = false
                        result.error("install_failed", e.message, null)
                    }
                }

                override fun error(code: String, message: String?, details: Any?) {
                    preparing = false
                    result.error(code, message, details)
                }

                override fun notImplemented() {
                    preparing = false
                    result.error("install_failed", "Update shutdown handler is unavailable", null)
                }
            },
        )
    }

    private fun install(path: String, expectedHash: String, result: MethodChannel.Result) {
        if (busy || preparing) {
            result.error("busy", "Finish transfers and pairing before installing an update", null)
            return
        }
        preparing = true
        executor.execute {
            try {
                val file = verifiedPackage(path, expectedHash)
                main.post {
                    try {
                        launchInstaller(file, result)
                    } catch (e: Exception) {
                        preparing = false
                        result.error("invalid_update", e.message, null)
                    }
                }
            } catch (e: Exception) {
                main.post {
                    preparing = false
                    result.error("invalid_update", e.message, null)
                }
            }
        }
    }

    fun onActivityResult(requestCode: Int, resultCode: Int): Boolean {
        if (requestCode != 7190) return false
        val result = pendingInstall
        pendingInstall = null
        preparing = false
        if (resultCode == Activity.RESULT_OK) result?.success(null)
        else result?.error("cancelled", "Update installation was cancelled or failed", null)
        return true
    }

    fun install(messenger: BinaryMessenger) {
        channel = MethodChannel(messenger, "vela/update").also {
            it.setMethodCallHandler(::handle)
        }
    }

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "configure" -> result.success(null)
                "info" -> {
                    val info = installed()
                    val abi = Build.SUPPORTED_ABIS.firstOrNull().orEmpty()
                    val arch = when (abi) {
                        "arm64-v8a" -> "arm64"
                        "x86_64" -> "x64"
                        "armeabi-v7a" -> "arm"
                        else -> abi
                    }
                    result.success(mapOf("arch" to arch, "version" to info.versionName, "build" to identity(info).version))
                }
                "getUpdateDirectory" -> result.success(directory().path)
                "canInstall" -> result.success(Build.VERSION.SDK_INT < 26 || context.packageManager.canRequestPackageInstalls())
                "setBusy" -> {
                    busy = call.argument<Boolean>("busy") != false
                    result.success(null)
                }
                "installDownloaded" -> install(
                    requireNotNull(call.argument<String>("path")),
                    requireNotNull(call.argument<String>("sha256")),
                    result,
                )
                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            result.error("invalid_update", e.message ?: "Cannot install the update", null)
        }
    }
}
