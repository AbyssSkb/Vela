package com.example.vela

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.ShortcutInfo
import android.content.pm.ShortcutManager
import android.graphics.drawable.Icon
import android.os.Build
import java.util.UUID
import org.json.JSONArray
import org.json.JSONObject

internal data class ShareDevice(val peer: String, val name: String, val shortcut: String)

private fun shareTargets(context: Context) =
    context.getSharedPreferences("share_targets", Context.MODE_PRIVATE)

internal fun shareDevices(context: Context): List<ShareDevice> =
    runCatching {
        val stored = JSONArray(shareTargets(context).getString("devices", "[]"))
        List(stored.length()) { index ->
            val device = stored.getJSONObject(index)
            ShareDevice(device.getString("peer"), device.getString("name"), device.getString("shortcut"))
        }
    }.getOrDefault(emptyList())

internal fun publishShareShortcuts(context: Context, names: Map<String, String>) {
    val previous = shareDevices(context)
    val shortcutsByPeer = previous.associate { it.peer to it.shortcut }
    val devices = names.entries.filter { shareDeviceId.matches(it.key) && it.value.isNotBlank() }
        .map { (peer, name) ->
            // The selected shortcut goes through an exported activity. A peer ID is public.
            ShareDevice(peer, name, shortcutsByPeer[peer] ?: UUID.randomUUID().toString())
        }
    if (devices != previous) {
        val stored = JSONArray()
        devices.forEach {
            stored.put(JSONObject().put("peer", it.peer).put("name", it.name).put("shortcut", it.shortcut))
        }
        shareTargets(context).edit().putString("devices", stored.toString()).apply()
    }
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return
    val manager = context.getSystemService(ShortcutManager::class.java)
    val targets = devices.take(manager.maxShortcutCountPerActivity)
    val current = manager.dynamicShortcuts.sortedBy { it.rank }
    if (current.map { it.id to it.shortLabel.toString() } ==
        targets.map { it.shortcut to it.name }) return

    val ids = targets.map { it.shortcut }.toSet()
    manager.removeDynamicShortcuts(current.map { it.id }.filterNot(ids::contains))
    if (targets.isEmpty()) return

    val activity = ComponentName(context, MainActivity::class.java)
    val shortcuts = targets.mapIndexed { rank, device ->
        ShortcutInfo.Builder(context, device.shortcut)
            .setActivity(activity)
            .setShortLabel(device.name)
            .setRank(rank)
            .setCategories(setOf("com.example.vela.SHARE_DEVICE"))
            .setIcon(Icon.createWithResource(context, R.drawable.app_icon))
            .setIntent(Intent(Intent.ACTION_MAIN).setComponent(activity))
            .build()
    }
    check(manager.setDynamicShortcuts(shortcuts)) { "Sharing shortcuts are temporarily rate limited" }
}
