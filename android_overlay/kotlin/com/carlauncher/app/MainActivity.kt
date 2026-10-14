package com.carlauncher.app

import android.app.admin.DevicePolicyManager
import android.app.role.RoleManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel

/**
 * Главная (левая) панель лаунчера. Кроме стандартного запуска Flutter,
 * отвечает на вызовы из Dart (канал "car_launcher/native") за всё,
 * что требует настоящих системных API: роль лаунчера по умолчанию,
 * киоск-режим (lock task) и открытие второй панели (медиаплеера).
 *
 * Здесь намеренно нет работы с android.uid.system/WRITE_SETTINGS и т.п. —
 * такие права даёт только подпись платформенным ключом устройства.
 * Всё ниже — официальные публичные Android API, доступные любому
 * обычному приложению (для Device Owner — см. README).
 */
class MainActivity : FlutterActivity() {

    private val channelName = "car_launcher/native"

    // Движок берётся из общей FlutterEngineGroup приложения — см.
    // CarLauncherApplication и README, раздел "Activity Embedding".
    override fun provideFlutterEngine(context: Context): FlutterEngine {
        val app = applicationContext as CarLauncherApplication
        return app.engineGroup.createAndRunEngine(context, DartExecutor.DartEntrypoint.createDefault())
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Сразу открываем вторую панель (медиаплеер). Если на устройстве
        // есть androidx.window.extensions — система покажет её рядом
        // (Activity Embedding, правило в CarLauncherApplication). Если нет —
        // она просто откроется поверх как обычный полноэкранный экран,
        // и пользователь сможет вернуться назад кнопкой "Домой"/"Назад".
        if (savedInstanceState == null) {
            openMediaPane()
        }
    }

    private fun openMediaPane() {
        startActivity(Intent(this, MediaPaneActivity::class.java))
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isDefaultLauncher" -> result.success(isDefaultLauncher())
                    "requestDefaultLauncher" -> {
                        requestDefaultLauncher()
                        result.success(null)
                    }
                    "isDeviceOwner" -> result.success(isDeviceOwner())
                    "startKioskMode" -> result.success(startKioskMode())
                    "stopKioskMode" -> {
                        stopKioskMode()
                        result.success(null)
                    }
                    "openMediaPane" -> {
                        openMediaPane()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /** Является ли это приложение сейчас выбранным домашним экраном. */
    private fun isDefaultLauncher(): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val roleManager = getSystemService(RoleManager::class.java)
            if (roleManager != null && roleManager.isRoleAvailable(RoleManager.ROLE_HOME)) {
                return roleManager.isRoleHeld(RoleManager.ROLE_HOME)
            }
        }
        // Фолбэк для старых версий Android: сравниваем пакет текущего
        // обработчика intent-а HOME с нашим.
        val intent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME)
        val resolved = packageManager.resolveActivity(intent, PackageManager.MATCH_DEFAULT_ONLY)
        return resolved?.activityInfo?.packageName == packageName
    }

    /** Открывает системный диалог выбора лаунчера по умолчанию. */
    private fun requestDefaultLauncher() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val roleManager = getSystemService(RoleManager::class.java)
            if (roleManager != null && roleManager.isRoleAvailable(RoleManager.ROLE_HOME) &&
                !roleManager.isRoleHeld(RoleManager.ROLE_HOME)
            ) {
                startActivity(roleManager.createRequestRoleIntent(RoleManager.ROLE_HOME))
                return
            }
        }
        // Фолбэк: системный экран "Домашнее приложение" со списком лаунчеров.
        startActivity(Intent(Settings.ACTION_HOME_SETTINGS))
    }

    private fun devicePolicyManager(): DevicePolicyManager =
        getSystemService(DevicePolicyManager::class.java)

    private fun adminComponent(): ComponentName =
        ComponentName(this, DeviceOwnerReceiver::class.java)

    /** Зарегистрировано ли приложение как Device Owner (см. README). */
    private fun isDeviceOwner(): Boolean = devicePolicyManager().isDeviceOwnerApp(packageName)

    /**
     * Включает полноценный киоск-режим: блокирует экран "Недавние"/"Домой"
     * и сворачивание приложения. Требует Device Owner — без него доступен
     * только обычный startLockTask() без скрытия системных элементов,
     * который пользователь в любой момент может завершить системными
     * средствами (это осознанное ограничение Android, не баг).
     */
    private fun startKioskMode(): Boolean {
        return try {
            if (isDeviceOwner()) {
                val dpm = devicePolicyManager()
                val admin = adminComponent()
                dpm.setLockTaskPackages(admin, arrayOf(packageName))
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                    dpm.setStatusBarDisabled(admin, true)
                }
            }
            startLockTask()
            true
        } catch (e: SecurityException) {
            false
        } catch (e: IllegalStateException) {
            false
        }
    }

    private fun stopKioskMode() {
        try {
            if (isDeviceOwner() && Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                devicePolicyManager().setStatusBarDisabled(adminComponent(), false)
            }
        } catch (e: SecurityException) {
            // ignore — продолжаем снимать lock task в любом случае
        }
        stopLockTask()
    }
}
