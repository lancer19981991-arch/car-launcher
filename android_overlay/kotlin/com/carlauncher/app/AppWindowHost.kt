package com.carlauncher.app

import android.annotation.SuppressLint
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Handler
import android.os.Looper
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.ViewConfiguration
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextClock
import android.widget.TextView

/**
 * Встраивание ЖИВЫХ окон чужих приложений в экран лаунчера — так же,
 * как это делает CarCar.
 *
 * Это возможно только для системного приложения (APK подписан
 * платформенным ключом прошивки + sharedUserId=android.uid.system).
 * Механизм — android.app.ActivityView: скрытый системный класс, который
 * создаёт виртуальный дисплей, запускает на нём activity другого
 * приложения и показывает её поверхность внутри обычного View, передавая
 * туда касания. В публичный SDK он не входит, поэтому вызывается через
 * рефлексию. На Android 12+ ActivityView удалён; этот код рассчитан на
 * Android 10/11 (где он есть) — на целевой магнитоле пользователя.
 *
 * Окна кладутся в прозрачный оверлей ПОВЕРХ FlutterView: Flutter рисует
 * док и рамки-подложки, а живые окна — нативные View в точных
 * координатах, которые присылает Flutter. Так мы не боремся с
 * композитингом Flutter PlatformView.
 */
class AppWindowHost(
    private val activity: Activity,
    private val widgets: WidgetSupport,
    private val onLongPress: (slotId: String) -> Unit = {},
    private val onPillTap: () -> Unit = {},
) {

    /** Подсветка контура окон: цвет ARGB, толщина и скругление (px экрана). */
    data class BorderSpec(val color: Int, val width: Int, val radius: Int = 0)

    /** Текущая подсветка; null — без контура. */
    private var border: BorderSpec? = null

    /** Нарисовать контур вокруг окна (содержимое сдвигается внутрь). */
    private fun styleFrame(frame: FrameLayout) {
        val b = border
        if (b == null || b.width <= 0) {
            frame.background = null
            frame.setPadding(0, 0, 0, 0)
            frame.clipToOutline = false
            frame.getChildAt(0)?.let { setInnerCornerRadius(it, 0f) }
            return
        }
        val radius = maxOf(b.radius, b.width).toFloat()
        frame.background = GradientDrawable().apply {
            setColor(Color.TRANSPARENT)
            setStroke(b.width, b.color)
            cornerRadius = radius
        }
        frame.setPadding(b.width, b.width, b.width, b.width)
        // Обычные View (виджеты) обрезаются по скруглённому контуру рамки.
        frame.clipToOutline = true
        // Поверхность живого приложения так не обрезается — скругляем её
        // скрытым API (есть на Android 10/11), внутренний радиус меньше.
        frame.getChildAt(0)?.let { setInnerCornerRadius(it, maxOf(radius - b.width, 0f)) }
    }

    /** Скругление углов поверхности ActivityView (скрытый API, по возможности). */
    private fun setInnerCornerRadius(view: View, r: Float) {
        if (view !is ViewGroup && view !is android.view.SurfaceView) return
        try {
            view.javaClass.getMethod("setCornerRadius", java.lang.Float.TYPE).invoke(view, r)
            return
        } catch (e: Throwable) {
            // нет у этого класса — пробуем SurfaceView внутри
        }
        if (view is ViewGroup) {
            for (i in 0 until view.childCount) {
                val c = view.getChildAt(i)
                if (c is android.view.SurfaceView) {
                    try {
                        c.javaClass.getMethod("setCornerRadius", java.lang.Float.TYPE).invoke(c, r)
                    } catch (e: Throwable) {
                        // скрытого метода нет — останутся прямые углы внутри рамки
                    }
                }
            }
        }
    }

    /** Положение и размер «пилюли» с часами (px экрана). */
    data class PillSpec(
        val left: Int,
        val top: Int,
        val width: Int,
        val height: Int,
        /** Погода рядом с часами, например «☁ +5°»; null — не показывать. */
        val weather: String? = null,
    )

    /** Текст погоды в пилюле. */
    private var pillWeather: TextView? = null

    /** Пилюля с часами и шестерёнкой — лежит ПОВЕРХ живых окон. */
    private var pill: LinearLayout? = null

    private fun ensurePill(overlay: FrameLayout): LinearLayout {
        pill?.let { return it }
        val density = activity.resources.displayMetrics.density
        val ll = LinearLayout(activity).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
            background = GradientDrawable().apply {
                cornerRadius = 20f * density
                setColor(0x59000000) // чёрный ~35% — почти прозрачный
            }
            setOnClickListener { onPillTap() }
        }
        val clock = TextClock(activity).apply {
            format24Hour = "HH:mm"
            format12Hour = "HH:mm"
            setTextColor(Color.WHITE)
            textSize = 18f
            setTypeface(typeface, Typeface.BOLD)
            setShadowLayer(4f, 0f, 1f, Color.BLACK)
        }
        val gear = ImageView(activity).apply {
            setImageResource(android.R.drawable.ic_menu_preferences)
            setColorFilter(Color.WHITE)
        }
        val weather = TextView(activity).apply {
            setTextColor(Color.WHITE)
            textSize = 16f
            setTypeface(typeface, Typeface.BOLD)
            setShadowLayer(4f, 0f, 1f, Color.BLACK)
            maxLines = 1
            visibility = View.GONE
        }
        ll.addView(clock)
        ll.addView(
            weather,
            LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT,
                LinearLayout.LayoutParams.WRAP_CONTENT,
            ).apply { leftMargin = (8 * density).toInt() },
        )
        pillWeather = weather
        ll.addView(
            gear,
            LinearLayout.LayoutParams((20 * density).toInt(), (20 * density).toInt()).apply {
                leftMargin = (6 * density).toInt()
            },
        )
        overlay.addView(ll, FrameLayout.LayoutParams(0, 0))
        pill = ll
        return ll
    }

    private fun syncPill(overlay: FrameLayout, spec: PillSpec?) {
        if (spec == null) {
            pill?.let { overlay.removeView(it) }
            pill = null
            pillWeather = null
            return
        }
        val p = ensurePill(overlay)
        pillWeather?.let {
            if (spec.weather.isNullOrEmpty()) {
                it.visibility = View.GONE
            } else {
                it.text = spec.weather
                it.visibility = View.VISIBLE
            }
        }
        val lp = p.layoutParams as FrameLayout.LayoutParams
        lp.leftMargin = spec.left
        lp.topMargin = spec.top
        lp.width = spec.width
        lp.height = spec.height
        p.layoutParams = lp
        p.bringToFront() // всегда поверх окон
    }

    private val handler = Handler(Looper.getMainLooper())

    /**
     * Контейнер поверх одного живого окна. Ловит ДОЛГОЕ нажатие (для
     * смены приложения), но обычные касания пропускает в приложение:
     * onInterceptTouchEvent всегда видит DOWN/UP, даже когда возвращает
     * false, поэтому таймер долгого нажатия работает, а само событие
     * уходит в ActivityView под контейнером.
     */
    @SuppressLint("ViewConstructor")
    private inner class WindowFrame(context: Context, val slotId: String) : FrameLayout(context) {
        private val longPressMs = ViewConfiguration.getLongPressTimeout().toLong()
        private val slop = ViewConfiguration.get(context).scaledTouchSlop
        private var downX = 0f
        private var downY = 0f
        private var fired = false
        private val longPressRunnable = Runnable {
            fired = true
            onLongPress(slotId)
        }

        // Отслеживаем касание в dispatchTouchEvent: так долгое нажатие
        // работает и над некликабельными частями виджета, где дочерний
        // вид не забирает касание и onInterceptTouchEvent не видит UP.
        override fun dispatchTouchEvent(ev: MotionEvent): Boolean {
            when (ev.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    fired = false
                    downX = ev.x
                    downY = ev.y
                    handler.postDelayed(longPressRunnable, longPressMs)
                }
                MotionEvent.ACTION_MOVE -> {
                    if (kotlin.math.abs(ev.x - downX) > slop ||
                        kotlin.math.abs(ev.y - downY) > slop
                    ) {
                        handler.removeCallbacks(longPressRunnable)
                    }
                }
                MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                    handler.removeCallbacks(longPressRunnable)
                }
            }
            // Касания всегда идут в окно/виджет; DOWN подтверждаем сами,
            // чтобы получить UP и отменить долгое нажатие.
            val handled = super.dispatchTouchEvent(ev)
            return handled || ev.actionMasked == MotionEvent.ACTION_DOWN
        }
    }

    /** Оверлей-контейнер поверх FlutterView, в нём лежат окна. */
    private var overlay: FrameLayout? = null

    /** slotId -> состояние одного окна. */
    private val windows = HashMap<String, WindowEntry>()

    private class WindowEntry(
        /** Контейнер в оверлее (ловит долгое нажатие). */
        val frame: FrameLayout,
        /** ActivityView с живым приложением или вид виджета. */
        val activityView: View,
        var packageName: String,
        /** 0 — приложение; иначе id виджета. */
        val widgetId: Int = 0,
        var started: Boolean = false,
        /** Желаемая плотность (0 — как у экрана) и уже применённая. */
        var densityDpi: Int = 0,
        var appliedDensity: Int = 0,
    )

    /** Последняя ошибка встраивания — для диагностики на экране. */
    var lastError: String? = null
        private set

    private val activityViewClass: Class<*>? = try {
        Class.forName("android.app.ActivityView")
    } catch (e: Throwable) {
        lastError = "ActivityView не найден: $e"
        null
    }

    /** Найден ли класс ActivityView на этой прошивке. */
    fun activityViewAvailable(): Boolean = activityViewClass != null

    /**
     * Работает ли процесс под системным UID (1000). Именно это — а не
     * флаг FLAG_SYSTEM (он только у приложений из раздела /system) —
     * признак того, что sharedUserId=android.uid.system сработал и у нас
     * есть системные права для встраивания живых окон.
     */
    fun hasSystemUid(): Boolean =
        android.os.Process.myUid() == android.os.Process.SYSTEM_UID

    fun currentUid(): Int = android.os.Process.myUid()

    /** Доступно ли встраивание живых окон на этом устройстве/подписи. */
    fun isAvailable(): Boolean = activityViewClass != null && hasSystemUid()

    private fun ensureOverlay(): FrameLayout {
        overlay?.let { return it }
        val content = activity.findViewById<ViewGroup>(android.R.id.content)
        val fl = FrameLayout(activity)
        fl.setBackgroundColor(Color.TRANSPARENT)
        // Поверх FlutterView, на весь контент.
        content.addView(
            fl,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT,
            ),
        )
        overlay = fl
        return fl
    }

    /**
     * Описание одного окна от Flutter: какое приложение и где (px).
     */
    data class WindowSpec(
        val slotId: String,
        val packageName: String,
        val left: Int,
        val top: Int,
        val width: Int,
        val height: Int,
        /** 0 — в окне приложение; иначе — виджет с этим id. */
        val widgetId: Int = 0,
        /** Плотность виртуального дисплея (масштаб приложения); 0 — как есть. */
        val densityDpi: Int = 0,
    )

    /**
     * Синхронизировать живые окна с тем, что просит Flutter.
     * Возвращает true, если встраивание доступно и применено;
     * false — если устройство/подпись не поддерживают (вызывающая
     * сторона тогда откатывается на свободные окна).
     */
    fun sync(specs: List<WindowSpec>, pillSpec: PillSpec? = null, borderSpec: BorderSpec? = null): Boolean {
        if (!isAvailable()) return false
        val overlay = ensureOverlay()
        overlay.visibility = View.VISIBLE
        if (borderSpec != border) {
            border = borderSpec
            for (entry in windows.values) styleFrame(entry.frame)
        }
        try {
            syncWindows(overlay, specs)
        } finally {
            // Пилюля добавляется/поднимается после окон — она всегда сверху.
            syncPill(overlay, pillSpec)
        }
        return true
    }

    private fun syncWindows(overlay: FrameLayout, specs: List<WindowSpec>) {

        val wanted = specs.associateBy { it.slotId }

        // Убрать окна, которых больше нет или сменилось приложение.
        val toRemove = windows.keys.filter { id ->
            val spec = wanted[id]
            val entry = windows[id]
            spec == null || spec.packageName != entry?.packageName || spec.widgetId != entry?.widgetId
        }
        for (id in toRemove) removeWindow(id)

        // Создать/переместить нужные.
        for (spec in specs) {
            val existing = windows[spec.slotId]
            if (existing == null) {
                if (spec.widgetId != 0) addWidget(overlay, spec) else addWindow(overlay, spec)
            } else {
                applyBounds(existing.frame, spec)
                if (existing.widgetId == 0) {
                    existing.densityDpi = spec.densityDpi
                    applyDensity(existing) // ничего не делает, если уже применено
                }
                if (existing.widgetId != 0) {
                    (existing.activityView as? android.appwidget.AppWidgetHostView)
                        ?.let { widgets.updateSize(it, spec.width, spec.height) }
                }
            }
        }
    }

    /** Окно с виджетом рабочего стола вместо живого приложения. */
    private fun addWidget(overlay: FrameLayout, spec: WindowSpec) {
        val view = widgets.createView(spec.widgetId)
        if (view == null) {
            lastError = "Виджет ${spec.widgetId} не найден (удалён?)"
            return
        }
        val frame = WindowFrame(activity, spec.slotId)
        frame.addView(
            view,
            FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT),
        )
        val lp = FrameLayout.LayoutParams(spec.width, spec.height)
        lp.leftMargin = spec.left
        lp.topMargin = spec.top
        overlay.addView(frame, lp)
        styleFrame(frame)
        widgets.updateSize(view, spec.width, spec.height)
        windows[spec.slotId] = WindowEntry(frame, view, spec.packageName, widgetId = spec.widgetId, started = true)
    }

    private fun addWindow(overlay: FrameLayout, spec: WindowSpec) {
        val activityView = try {
            activityViewClass!!
                .getConstructor(Context::class.java)
                .newInstance(activity) as View
        } catch (e: Throwable) {
            // Нет подходящего конструктора — встраивание недоступно.
            lastError = "Конструктор ActivityView: $e"
            return
        }

        // Оборачиваем ActivityView в контейнер, который ловит долгое
        // нажатие (смена приложения), пропуская обычные касания внутрь.
        val frame = WindowFrame(activity, spec.slotId)
        frame.addView(
            activityView,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT,
            ),
        )

        val lp = FrameLayout.LayoutParams(spec.width, spec.height)
        lp.leftMargin = spec.left
        lp.topMargin = spec.top
        overlay.addView(frame, lp)
        styleFrame(frame)

        val entry = WindowEntry(frame, activityView, spec.packageName, densityDpi = spec.densityDpi)
        windows[spec.slotId] = entry

        // ActivityView должен быть прикреплён и измерен до startActivity.
        // Колбэка готовности не используем (StateCallback — абстрактный
        // класс, через рефлексию не подклассить), поэтому запускаем с
        // небольшой задержкой и несколькими повторами.
        activityView.post { startInto(entry, attempt = 0) }
    }

    private fun startInto(entry: WindowEntry, attempt: Int) {
        if (entry.started) return
        if (!windows.containsValue(entry)) return // окно уже убрали
        val intent = activity.packageManager.getLaunchIntentForPackage(entry.packageName)
        if (intent == null) return
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        // Масштаб ставим до запуска — приложение сразу откроется с ним.
        applyDensity(entry)
        val ok = try {
            val m = activityViewClass!!.getMethod("startActivity", Intent::class.java)
            m.invoke(entry.activityView, intent)
            true
        } catch (e: Throwable) {
            lastError = "startActivity в окне (попытка $attempt): ${e.cause ?: e}"
            false
        }
        if (ok) {
            // Если дисплей был ещё не готов до запуска — применим масштаб чуть позже.
            if (entry.appliedDensity != entry.densityDpi) {
                handler.postDelayed({ if (windows.containsValue(entry)) applyDensity(entry) }, 300L)
            }
            entry.started = true
            lastError = null
        } else if (attempt < 5) {
            // Виртуальный дисплей ещё не готов — повторим.
            handler.postDelayed({ startInto(entry, attempt + 1) }, 250L)
        }
    }

    /** id виртуального дисплея окна (скрытый API) или -1. */
    private fun virtualDisplayId(view: View): Int {
        try {
            val id = view.javaClass.getMethod("getVirtualDisplayId").invoke(view) as? Int
            if (id != null && id > 0) return id
        } catch (e: Throwable) {
            // нет метода — пробуем поле
        }
        return try {
            val f = activityViewClass!!.getDeclaredField("mVirtualDisplay")
            f.isAccessible = true
            (f.get(view) as? android.hardware.display.VirtualDisplay)?.display?.displayId ?: -1
        } catch (e: Throwable) {
            -1
        }
    }

    /**
     * Масштаб приложения: меняем плотность (dpi) виртуального дисплея окна,
     * как `wm density N -d <id>`. Приложение само перерисуется мельче или
     * крупнее, касания при этом остаются точными. Нужен системный UID.
     */
    private fun applyDensity(entry: WindowEntry) {
        if (entry.densityDpi == entry.appliedDensity) return
        val displayId = virtualDisplayId(entry.activityView)
        if (displayId <= 0) return // дисплея ещё нет — применится при запуске
        try {
            val wm = Class.forName("android.view.WindowManagerGlobal")
                .getMethod("getWindowManagerService").invoke(null)
            val user = Class.forName("android.os.UserHandle").getMethod("myUserId").invoke(null) as Int
            val iwm = Class.forName("android.view.IWindowManager")
            if (entry.densityDpi > 0) {
                iwm.getMethod(
                    "setForcedDisplayDensityForUser",
                    Int::class.javaPrimitiveType, Int::class.javaPrimitiveType, Int::class.javaPrimitiveType,
                ).invoke(wm, displayId, entry.densityDpi, user)
            } else {
                iwm.getMethod(
                    "clearForcedDisplayDensityForUser",
                    Int::class.javaPrimitiveType, Int::class.javaPrimitiveType,
                ).invoke(wm, displayId, user)
            }
            entry.appliedDensity = entry.densityDpi
        } catch (e: Throwable) {
            lastError = "Масштаб окна: ${e.cause ?: e}"
        }
    }

    private fun applyBounds(frame: FrameLayout, spec: WindowSpec) {
        val lp = frame.layoutParams as? FrameLayout.LayoutParams ?: return
        if (lp.leftMargin == spec.left && lp.topMargin == spec.top &&
            lp.width == spec.width && lp.height == spec.height
        ) {
            return
        }
        lp.leftMargin = spec.left
        lp.topMargin = spec.top
        lp.width = spec.width
        lp.height = spec.height
        frame.layoutParams = lp
    }

    private fun removeWindow(slotId: String) {
        val entry = windows.remove(slotId) ?: return
        if (entry.widgetId == 0) {
            try {
                activityViewClass?.getMethod("release")?.invoke(entry.activityView)
            } catch (e: Throwable) {
                // ignore
            }
        }
        // У виджета id не удаляем — он живёт, пока назначен окну.
        overlay?.removeView(entry.frame)
    }

    /**
     * Спрятать окна, не уничтожая их: приложения внутри остаются
     * запущенными и не перезапускаются. Следующий sync() покажет их снова.
     */
    fun hide() {
        overlay?.visibility = View.GONE
    }

    /** Уничтожить все живые окна и пилюлю. */
    fun clear() {
        for (id in windows.keys.toList()) removeWindow(id)
        pill?.let { overlay?.removeView(it) }
        pill = null
        pillWeather = null
    }
}
