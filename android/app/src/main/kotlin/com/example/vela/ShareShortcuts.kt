package com.example.vela

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.ShortcutInfo
import android.content.pm.ShortcutManager
import android.graphics.drawable.Icon
import android.os.Build

internal fun publishShareShortcuts(context: Context, names: Map<String, String>) {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return
    val manager = context.getSystemService(ShortcutManager::class.java)
    val targets = names.entries.filter { shareDeviceId.matches(it.key) && it.value.isNotBlank() }
        .take(manager.maxShortcutCountPerActivity)
    val current = manager.dynamicShortcuts.sortedBy { it.rank }
    if (current.map { it.id to it.shortLabel.toString() } == targets.map { it.toPair() }) return

    val ids = targets.map { it.key }.toSet()
    manager.removeDynamicShortcuts(current.map { it.id }.filterNot(ids::contains))
    if (targets.isEmpty()) return

    val activity = ComponentName(context, MainActivity::class.java)
    val shortcuts = targets.mapIndexed { rank, (id, name) ->
        ShortcutInfo.Builder(context, id)
            .setActivity(activity)
            .setShortLabel(name)
            .setRank(rank)
            .setCategories(setOf("com.example.vela.SHARE_DEVICE"))
            .setIcon(Icon.createWithResource(context, R.drawable.app_icon))
            .setIntent(Intent(Intent.ACTION_MAIN).setComponent(activity))
            .build()
    }
    check(manager.setDynamicShortcuts(shortcuts)) { "Sharing shortcuts are temporarily rate limited" }
}
