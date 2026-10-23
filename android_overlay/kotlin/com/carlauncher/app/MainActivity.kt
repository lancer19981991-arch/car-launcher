package com.carlauncher.app

import android.app.ActivityOptions
import android.app.admin.DevicePolicyManager
import android.app.role.RoleManager
import android.content.ActivityNotFoundException
import android.content.ComponentName
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Rect
import android.graphics.drawable.Drawable
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.view.View
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.util.concurrent.Executors

/**
 * Единственная Activity лаунчера. Кроме стандартного запуска Flutter,
 * отвечает на вызовы из Dart (канал "car_launcher/native") за всё,
 * что требует настоящих системных API: роль лаунчера по умолчанию,
 * киоск-режим (lock task), список приложений и запуск приложений
 * в свободных окнах с заданными координатами.
 *
 * Здесь намеренно нет работы с android.uid.system/WRITE_SETTINGS и т.п. —
 * такие права даёт только подпись платформенным ключом устройства.
 * Всё ниже — официальные публичные Android API, доступные любому
 * обычному приложению (для Device Owner — см. README).
 */
class MainActivity : FlutterActivity() {

    private val channelName = "car_launcher/native"

    private var channel: MethodChannel? = null

    private val widgetSupport by lazy { WidgetSupport(this) }

    /** Ожидающий ответ Flutter на настройку виджета (bindWidget). */
    private var pendingConfigure: Pair<Int, MethodChannel.Result>? = null

    override fun onStart() {
        super.onStart()
        widgetSupport.startListening()
    }

    override fun onStop() {
        super.onStop()
        widgetSupport.stopListening()
    }

    @Deprecated("FlutterActivity still routes results here")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != WidgetSupport.REQUEST_CONFIGURE) return
        val pending = pendingConfigure ?: return
        pendingConfigure = null
        val (widgetId, result) = pending
        if (resultCode == RESULT_OK) {
            result.success(widgetId)
        } else {
            widgetSupport.delete(widgetId)
            result.success(null)
        }
    }

    private val appWindowHost by lazy {
        AppWindowHost(
            this,
            widgetSupport,
            onLongPress = { slotId ->
                // Долгое нажатие по живому окну — просим Flutter открыть выбор.
                runOnUiThread { channel?.invokeMethod("onWindowLongPress", slotId) }
            },
            onPillTap = {
                // Нажатие на пилюлю с часами — открыть меню во Flutter.
                runOnUiThread { channel?.invokeMethod("onPillTap", null) }
            },
        )
    }

    override fun onPause() {
        super.onPause()
        // Уходя в фон: по умолчанию окна уничтожаются — иначе приложение,
        // живущее в окне, при запуске из другого места может «открыться»
        // на спрятанном дисплее окна. По настройке — только прячем.
        val keep = getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE)
            .getBoolean("flutter.keep_windows_bg", false)
        if (keep) appWindowHost.hide() else appWindowHost.clear()
    }

    /**
     * Последнее известное местоположение (для погоды) — без включения GPS
     * и ожидания. Системному UID разрешение выдано всегда; в демо-сборке
     * без разрешения просто вернёт null (город выбирается вручную).
     */
    @android.annotation.SuppressLint("MissingPermission")
    private fun lastLocation(): Map<String, Double>? {
        val lm = getSystemService(LOCATION_SERVICE) as? android.location.LocationManager ?: return null
        var best: android.location.Location? = null
        val providers = try { lm.getProviders(false) } catch (e: Throwable) { emptyList<String>() }
        for (p in providers) {
            val loc = try { lm.getLastKnownLocation(p) } catch (e: Throwable) { null } ?: continue
            if (best == null || loc.time > best.time) best = loc
        }
        return best?.let { mapOf("lat" to it.latitude, "lon" to it.longitude) }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val ch = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
        channel = ch
        ch.setMethodCallHandler { call, result ->
                when (call.method) {
                    "isDefaultLauncher" -> result.success(isDefaultLauncher())
                    "getLastLocation" -> result.success(lastLocation())
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
                    "liveWindowsAvailable" -> result.success(
                        mapOf(
                            "available" to appWindowHost.isAvailable(),
                            "systemUid" to appWindowHost.hasSystemUid(),
                            "uid" to appWindowHost.currentUid(),
                            "activityViewFound" to appWindowHost.activityViewAvailable(),
                            "lastError" to appWindowHost.lastError,
                        ),
                    )
                    "syncAppWindows" -> {
                        val raw = call.argument<List<Map<String, Any>>>("windows") ?: emptyList()
                        val specs = raw.mapNotNull { m ->
                            val slotId = m["slotId"] as? String ?: return@mapNotNull null
                            val pkg = m["packageName"] as? String ?: return@mapNotNull null
                            AppWindowHost.WindowSpec(
                                slotId = slotId,
                                packageName = pkg,
                                left = (m["left"] as? Int) ?: 0,
                                top = (m["top"] as? Int) ?: 0,
                                width = (m["width"] as? Int) ?: 0,
                                height = (m["height"] as? Int) ?: 0,
                                widgetId = (m["widgetId"] as? Int) ?: 0,
                            )
                        }
                        val p = call.argument<Map<String, Any>>("pill")
                        val pill = p?.let {
                            AppWindowHost.PillSpec(
                                left = (it["left"] as? Int) ?: 0,
                                top = (it["top"] as? Int) ?: 0,
                                width = (it["width"] as? Int) ?: 0,
                                height = (it["height"] as? Int) ?: 0,
                                weather = it["weather"] as? String,
                            )
                        }
                        val b = call.argument<Map<String, Any>>("border")
                        val border = b?.let {
                            AppWindowHost.BorderSpec(
                                color = (it["color"] as? Number)?.toInt() ?: 0,
                                width = (it["width"] as? Number)?.toInt() ?: 0,
                                radius = (it["radius"] as? Number)?.toInt() ?: 0,
                            )
                        }
                        result.success(appWindowHost.sync(specs, pill, border))
                    }
                    "getWidgetProviders" -> {
                        backgroundExecutor.execute {
                            val list = try {
                                widgetSupport.listProviders()
                            } catch (e: Exception) {
                                mainHandler.post { result.error("WIDGETS_FAILED", e.message, null) }
                                return@execute
                            }
                            mainHandler.post { result.success(list) }
                        }
                    }
                    "bindWidget" -> {
                        val provider = call.argument<String>("provider")
                        val bound = provider?.let { widgetSupport.bind(it) }
                        when {
                            bound == null -> result.error("BIND_FAILED", "Система не разрешила добавить виджет", null)
                            bound.needsConfigure -> {
                                // Ответ вернём после экрана настройки виджета.
                                pendingConfigure?.second?.success(null)
                                pendingConfigure = bound.widgetId to result
                                if (!widgetSupport.startConfigure(bound.widgetId)) {
                                    pendingConfigure = null
                                    result.success(bound.widgetId) // без настройки
                                }
                            }
                            else -> result.success(bound.widgetId)
                        }
                    }
                    "deleteWidget" -> {
                        call.argument<Int>("widgetId")?.let { widgetSupport.delete(it) }
                        result.success(null)
                    }
                    "hideAppWindows" -> {
                        appWindowHost.hide()
                        result.success(null)
                    }
                    "clearAppWindows" -> {
                        appWindowHost.clear()
                        result.success(null)
                    }
                    "getFreeformStatus" -> result.success(freeformStatus())
                    "openDeveloperSettings" -> {
                        result.success(openDeveloperSettings())
                    }
                    "launchAppInBounds" -> {
                        val pkg = call.argument<String>("packageName")
                        val left = call.argument<Int>("left")
                        val top = call.argument<Int>("top")
                        val right = call.argument<Int>("right")
                        val bottom = call.argument<Int>("bottom")
                        if (pkg == null || left == null || top == null || right == null || bottom == null) {
                            result.error("BAD_ARGS", "packageName и границы окна обязательны", null)
                        } else {
                            result.success(launchAppInBounds(pkg, Rect(left, top, right, bottom)))
                        }
                    }
                    "getInstalledApps" -> {
                        // Чтение иконок может занять заметное время на
                        // устройствах с большим числом приложений — делаем
                        // это в фоне, а ответ отдаём на главном потоке
                        // (MethodChannel требует отвечать с него).
                        backgroundExecutor.execute {
                            val apps = try {
                                loadInstalledApps()
                            } catch (e: Exception) {
                                mainHandler.post {
                                    result.error("APPS_FAILED", e.message, null)
                                }
                                return@execute
                            }
                            mainHandler.post { result.success(apps) }
                        }
                    }
                    "launchApp" -> {
                        val pkg = call.argument<String>("packageName")
                        result.success(pkg != null && launchApp(pkg))
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private val backgroundExecutor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun onDestroy() {
        backgroundExecutor.shutdown()
        super.onDestroy()
    }

    /**
     * Все приложения, у которых есть значок в списке приложений
     * (intent MAIN + LAUNCHER), кроме самого лаунчера. Для видимости
     * чужих пакетов на Android 11+ в манифесте объявлен блок <queries>.
     */
    private fun loadInstalledApps(): List<Map<String, Any>> {
        val pm = packageManager
        val intent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        @Suppress("DEPRECATION")
        val activities = pm.queryIntentActivities(intent, 0)

        return activities
            .map { it.activityInfo }
            .filter { it.packageName != packageName }
            .distinctBy { it.packageName }
            .map { info ->
                mapOf(
                    "packageName" to info.packageName,
                    "label" to info.loadLabel(pm).toString(),
                    "icon" to drawableToPng(info.loadIcon(pm)),
                )
            }
            .sortedBy { (it["label"] as String).lowercase() }
    }

    /** Иконка в PNG. Рисуем через Canvas, т.к. это может быть не
     *  BitmapDrawable (адаптивные иконки Android 8+). */
    private fun drawableToPng(drawable: Drawable, sizePx: Int = 128): ByteArray {
        val bitmap = Bitmap.createBitmap(sizePx, sizePx, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        drawable.setBounds(0, 0, sizePx, sizePx)
        drawable.draw(canvas)
        val out = ByteArrayOutputStream()
        bitmap.compress(Bitmap.CompressFormat.PNG, 100, out)
        bitmap.recycle()
        return out.toByteArray()
    }

    /**
     * Запуск приложения в свободном окне с заданными границами.
     *
     * Границы приходят из Flutter в физических пикселях относительно
     * области лаунчера; сдвигаем их на положение этой области на экране.
     *
     * ActivityOptions.setLaunchBounds — публичный API: если устройство
     * поддерживает свободные окна (freeform), система откроет приложение
     * окном ровно в этих границах. Если не поддерживает — приложение
     * просто откроется на весь экран. Ничего сверх этого обычное
     * (не системное) приложение сделать не может.
     */
    private fun launchAppInBounds(pkg: String, bounds: Rect): Boolean {
        val intent = packageManager.getLaunchIntentForPackage(pkg) ?: return false
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)

        val origin = IntArray(2)
        findViewById<View>(android.R.id.content)?.getLocationOnScreen(origin)
        val screenBounds = Rect(bounds).apply { offset(origin[0], origin[1]) }

        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                val options = ActivityOptions.makeBasic().setLaunchBounds(screenBounds)
                startActivity(intent, options.toBundle())
            } else {
                startActivity(intent)
            }
            true
        } catch (e: ActivityNotFoundException) {
            false
        } catch (e: SecurityException) {
            false
        }
    }

    /**
     * Поддерживает ли устройство свободные окна. Значения настроек на
     * новых Android могут быть недоступны обычному приложению — тогда
     * в ответе null («неизвестно»), а не ошибка.
     */
    private fun freeformStatus(): Map<String, Any?> {
        val feature = packageManager.hasSystemFeature(PackageManager.FEATURE_FREEFORM_WINDOW_MANAGEMENT)
        val setting = readGlobalFlag("enable_freeform_support")
        val forceResizable = readGlobalFlag("force_resizable_activities")
        return mapOf(
            "supported" to (feature || setting == true),
            "systemFeature" to feature,
            "developerSetting" to setting,
            "forceResizable" to forceResizable,
            "sdk" to Build.VERSION.SDK_INT,
        )
    }

    private fun readGlobalFlag(key: String): Boolean? = try {
        Settings.Global.getInt(contentResolver, key, 0) != 0
    } catch (e: SecurityException) {
        null
    }

    /** Экран «Для разработчиков», где включаются свободные окна. */
    private fun openDeveloperSettings(): Boolean = try {
        startActivity(
            Intent(Settings.ACTION_APPLICATION_DEVELOPMENT_SETTINGS)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
        )
        true
    } catch (e: ActivityNotFoundException) {
        false
    }

    /** Запуск приложения по имени пакета. false — если приложение
     *  удалено или у него нет экрана запуска. */
    private fun launchApp(pkg: String): Boolean {
        val intent = packageManager.getLaunchIntentForPackage(pkg) ?: return false
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED)
        return try {
            startActivity(intent)
            true
        } catch (e: ActivityNotFoundException) {
            false
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
