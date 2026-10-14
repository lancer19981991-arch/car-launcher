package com.carlauncher.app

import android.app.admin.DeviceAdminReceiver
import android.content.Context
import android.content.Intent

/**
 * Приёмник, обязательный для работы Device Owner API (см. README,
 * раздел "Device Owner"). Сам по себе не даёт никаких прав — он лишь
 * точка входа, которую требует android.app.admin.DevicePolicyManager.
 * Фактическая регистрация происходит ОДНОЙ командой adb на чистом,
 * ещё не настроенном устройстве — см. инструкцию в README.
 */
class DeviceOwnerReceiver : DeviceAdminReceiver() {

    override fun onEnabled(context: Context, intent: Intent) {
        super.onEnabled(context, intent)
    }

    override fun onDisabled(context: Context, intent: Intent) {
        super.onDisabled(context, intent)
    }
}
