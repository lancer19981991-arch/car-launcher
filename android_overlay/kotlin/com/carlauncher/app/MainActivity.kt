package com.carlauncher.app

import android.app.ActivityOptions
import android.app.admin.DevicePolicyManager
import android.app.role.RoleManager
import android.content.ActivityNotFoundException
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Rect
import android.graphics.drawable.Drawable
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
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

    /** OBD-адаптер ELM327: данные уходят во Flutter как onObd. */
    private val obd by lazy {
        ObdClient { m -> channel?.invokeMethod("onObd", m) }
    }

    override fun onStart() {
        super.onStart()
        widgetSupport.startListening()
        obd.resume()
        // Лаунчер снова на экране (в т.ч. после сна) — всё ли из автозапуска живо.
        scheduleAutostartCheck(4000L)
        launcherVisibleSince = SystemClock.elapsedRealtime()
        mainHandler.removeCallbacks(tpmsWatchdog)
        mainHandler.postDelayed(tpmsWatchdog, 20_000L)
    }

    override fun onStop() {
        super.onStop()
        widgetSupport.stopListening()
        // Отпускаем адаптер — им могут пользоваться Car Scanner / CVTz.
        obd.pause()
        launcherVisibleSince = -1L
        mainHandler.removeCallbacks(tpmsWatchdog)
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
                    "getTpmsState" -> result.success(tpmsLast.values.toList())
                    "tpmsWatchdog" -> {
                        wdPkg = call.argument<String>("pkg")?.takeIf { it.isNotBlank() }
                        wdUsb = call.argument<String>("usb")?.takeIf { it.isNotBlank() }
                        wdThresholdMs = ((call.argument<Int>("minutes") ?: 3).coerceIn(1, 30)) * 60_000L
                        result.success(null)
                    }
                    "tpmsRestartNow" -> {
                        restartTpms()
                        result.success(wdPkg != null)
                    }
                    "usbDevices" -> result.success(usbDevices())
                    "runAutostart" -> {
                        val pkgs = call.argument<List<String>>("packages") ?: emptyList()
                        val force = call.argument<Boolean>("force") ?: false
                        result.success(runAutostart(pkgs, force))
                    }
                    "obdSetAddress" -> {
                        obd.setAddress(call.argument<String>("address"))
                        result.success(null)
                    }
                    "obdPairedDevices" -> result.success(obd.pairedDevices())
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
                                densityDpi = (m["densityDpi"] as? Int) ?: 0,
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

    /**
     * Данные шин от TPMS-приложения (TPMS_USB_MG_Uni и совместимые): оно
     * рассылает broadcast TPMS_APP_STATE_SEND по каждому колесу. Ловим всё
     * время жизни лаунчера (не только на экране), последнее по колесу
     * храним — Flutter заберёт при старте.
     */
    private val tpmsLast = LinkedHashMap<Int, Map<String, Any?>>()

    private val tpmsReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            val extras = intent.extras ?: return
            val m = HashMap<String, Any?>()
            for (k in extras.keySet()) {
                @Suppress("DEPRECATION")
                val v = extras.get(k)
                // Через канал проходят только простые типы.
                m[k] = when (v) {
                    null, is Boolean, is Int, is Long, is Double, is String -> v
                    is Float -> v.toDouble()
                    is Short -> v.toInt()
                    is Byte -> v.toInt()
                    else -> v.toString()
                }
            }
            val tire = (m["tires"] as? Number)?.toInt() ?: return
            tpmsLast[tire] = m
            tpmsLastAt = SystemClock.elapsedRealtime()
            wdFailedRestarts = 0
            channel?.invokeMethod("onTpms", m)
        }
    }

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        try {
            registerReceiver(tpmsReceiver, IntentFilter("TPMS_APP_STATE_SEND"))
            registerReceiver(screenOnReceiver, IntentFilter(android.content.Intent.ACTION_SCREEN_ON))
        } catch (e: Throwable) {
            // не критично — без TPMS-данных
        }
    }

    /**
     * Свой автозапуск: прошивка разрешает в автозагрузку только одно
     * приложение (у пользователя это лаунчер), поэтому остальное (TPMS)
     * держит запущенным лаунчер. Проверка — когда лаунчер появляется на
     * экране и когда включается экран (выход из глубокого сна: магнитола
     * не перезагружается, а прошивка закрывает приложения). Запускаются
     * только те, чьего процесса нет. Приложение открывается (так стартует
     * его фоновая служба), затем лаунчер возвращается на экран.
     */
    private var autostartPkgs: List<String> = emptyList()
    private var lastAutostartRun = -60_000L

    private val autostartCheck = Runnable {
        if (autostartPkgs.isEmpty()) return@Runnable
        // Не чаще раза в 30 с — пока приложение поднимается, не дёргать снова.
        if (SystemClock.elapsedRealtime() - lastAutostartRun < 30_000L) return@Runnable
        val running = runningPackages() ?: return@Runnable
        val missing = autostartPkgs.filter { it !in running }
        if (missing.isNotEmpty()) launchAndReturn(missing, 300L)
    }

    private fun scheduleAutostartCheck(delayMs: Long) {
        mainHandler.removeCallbacks(autostartCheck)
        if (autostartPkgs.isNotEmpty()) mainHandler.postDelayed(autostartCheck, delayMs)
    }

    /** Пакеты с живым процессом (системному UID видны все); null — не узнать. */
    private fun runningPackages(): Set<String>? = try {
        val am = getSystemService(ACTIVITY_SERVICE) as android.app.ActivityManager
        am.runningAppProcesses?.flatMap { p -> p.pkgList?.toList() ?: listOf(p.processName) }?.toSet()
    } catch (e: Throwable) {
        null
    }

    private val screenOnReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            scheduleAutostartCheck(5000L)
        }
    }

    // ---------- сторож TPMS ----------
    //
    // TPMS_USB иногда теряет связь с USB-приёмником или датчиками (пишет
    // ошибку, помогает перезайти в приложение, а лучше всего — переподключить
    // приёмник). Если данных нет дольше порога, а лаунчер на экране:
    // закрыть TPMS, по желанию сбросить USB-приёмник (как вынуть-вставить)
    // и открыть TPMS заново, вернув лаунчер.

    /** Пакет TPMS-приложения; null — сторож выключен. */
    private var wdPkg: String? = null

    /** Ключ USB-приёмника «vid:pid» для сброса; null — не сбрасывать. */
    private var wdUsb: String? = null
    private var wdThresholdMs = 3 * 60_000L
    private var tpmsLastAt = 0L
    private var lastTpmsRestart = -3_600_000L
    private var launcherVisibleSince = -1L
    private var wdFailedRestarts = 0

    private val tpmsWatchdog: Runnable = Runnable {
        mainHandler.postDelayed(tpmsWatchdog, 20_000L)
        if (wdPkg == null || launcherVisibleSince < 0) return@Runnable
        val now = SystemClock.elapsedRealtime()
        // Отсчёт — от последних данных, перезапуска или появления лаунчера
        // (после сна приложению надо дать время подняться).
        val since = maxOf(tpmsLastAt, lastTpmsRestart, launcherVisibleSince)
        // Если перезапуски подряд не помогают (например, машина стоит и
        // датчики спят) — ждать дольше: 3 → 6 → 12 … до 30 мин.
        val wait = (wdThresholdMs shl minOf(wdFailedRestarts, 4)).coerceAtMost(30 * 60_000L)
        if (now - since > wait) {
            if (lastTpmsRestart > tpmsLastAt) wdFailedRestarts++
            restartTpms()
        }
    }

    private fun restartTpms() {
        val pkg = wdPkg ?: return
        lastTpmsRestart = SystemClock.elapsedRealtime()
        try {
            val am = getSystemService(ACTIVITY_SERVICE) as android.app.ActivityManager
            am.javaClass.getMethod("forceStopPackage", String::class.java).invoke(am, pkg)
        } catch (e: Throwable) {
        }
        wdUsb?.let { resetUsb(it) }
        // Дать приёмнику переподключиться, затем открыть TPMS и вернуться.
        mainHandler.postDelayed({ launchAndReturn(listOf(pkg), 0L) }, 3000L)
    }

    private fun usbKey(d: android.hardware.usb.UsbDevice) =
        String.format("%04x:%04x", d.vendorId, d.productId)

    /** USB-устройства — для выбора приёмника TPMS в настройках. */
    private fun usbDevices(): List<Map<String, String>> = try {
        val um = getSystemService(USB_SERVICE) as android.hardware.usb.UsbManager
        um.deviceList.values.map { d ->
            val name = try {
                listOfNotNull(d.manufacturerName, d.productName).joinToString(" ").ifBlank { d.deviceName }
            } catch (e: Throwable) {
                d.deviceName
            }
            mapOf("key" to usbKey(d), "name" to name)
        }
    } catch (e: Throwable) {
        emptyList()
    }

    /** Программный «вынуть-вставить»: сброс порта USB (скрытый API, системный UID). */
    private fun resetUsb(key: String) {
        try {
            val um = getSystemService(USB_SERVICE) as android.hardware.usb.UsbManager
            val dev = um.deviceList.values.firstOrNull { usbKey(it) == key } ?: return
            try {
                um.javaClass.getMethod("grantPermission", android.hardware.usb.UsbDevice::class.java).invoke(um, dev)
            } catch (e: Throwable) {
            }
            val conn = um.openDevice(dev) ?: return
            try {
                conn.javaClass.getMethod("resetDevice").invoke(conn)
            } finally {
                conn.close()
            }
        } catch (e: Throwable) {
        }
    }

    /** Flutter передаёт список; [force] — открыть всё сейчас («Проверить сейчас»). */
    private fun runAutostart(pkgs: List<String>, force: Boolean): Boolean {
        autostartPkgs = pkgs
        if (pkgs.isEmpty()) return false
        if (force) {
            launchAndReturn(pkgs, 300L)
        } else {
            scheduleAutostartCheck(4000L)
        }
        return true
    }

    private fun launchAndReturn(pkgs: List<String>, firstDelay: Long) {
        lastAutostartRun = SystemClock.elapsedRealtime()
        var delay = firstDelay
        for (pkg in pkgs) {
            mainHandler.postDelayed({
                try {
                    packageManager.getLaunchIntentForPackage(pkg)?.let {
                        it.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        startActivity(it)
                    }
                } catch (e: Throwable) {
                    // приложение удалено — пропускаем
                }
            }, delay)
            delay += 3000L
        }
        // Вернуть лаунчер на экран, когда всё запущено.
        mainHandler.postDelayed({
            try {
                startActivity(
                    Intent(this, MainActivity::class.java)
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT),
                )
            } catch (e: Throwable) {
            }
        }, delay)
    }

    override fun onDestroy() {
        try {
            unregisterReceiver(tpmsReceiver)
            unregisterReceiver(screenOnReceiver)
        } catch (e: Throwable) {
        }
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
