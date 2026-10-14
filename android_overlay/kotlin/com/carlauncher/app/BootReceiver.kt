package com.carlauncher.app

import android.app.admin.DevicePolicyManager
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent

/**
 * После перезагрузки заново объявляет этот пакет единственным разрешённым
 * в lock task mode — ТОЛЬКО если приложение зарегистрировано как
 * Device Owner и администратор ранее включал киоск-режим.
 *
 * Важно: этот receiver НЕ запускает Activity и не нужен для самого
 * автозапуска лаунчера — Android и так открывает домашний экран
 * (HOME) сразу после загрузки, это встроенное поведение системы,
 * а не что-то, что требует boot-ресивера или особых прав.
 */
class BootReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED) return

        val dpm = context.getSystemService(DevicePolicyManager::class.java) ?: return
        val admin = ComponentName(context, DeviceOwnerReceiver::class.java)

        if (dpm.isDeviceOwnerApp(context.packageName)) {
            dpm.setLockTaskPackages(admin, arrayOf(context.packageName))
        }
    }
}
