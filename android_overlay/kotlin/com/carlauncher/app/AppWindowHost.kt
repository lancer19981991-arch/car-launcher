package com.carlauncher.app

import android.annotation.SuppressLint
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.os.Handler
import android.os.Looper
import android.view.MotionEvent
import android.view.View
import android.view.ViewConfiguration
import android.view.ViewGroup
import android.widget.FrameLayout

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
    private val onLongPress: (slotId: String) -> Unit = {},
) {

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

        override fun onInterceptTouchEvent(ev: MotionEvent): Boolean {
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
            // Никогда не перехватываем — касания идут в живое окно.
            return false
        }
    }

    /** Оверлей-контейнер поверх FlutterView, в нём лежат окна. */
    private var overlay: FrameLayout? = null

    /** slotId -> состояние одного окна. */
    private val windows = HashMap<String, WindowEntry>()

    private class WindowEntry(
        /** Контейнер в оверлее (ловит долгое нажатие). */
        val frame: FrameLayout,
        /** Сам ActivityView с живым приложением. */
        val activityView: View,
        var packageName: String,
        var started: Boolean = false,
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
    )

    /**
     * Синхронизировать живые окна с тем, что просит Flutter.
     * Возвращает true, если встраивание доступно и применено;
     * false — если устройство/подпись не поддерживают (вызывающая
     * сторона тогда откатывается на свободные окна).
     */
    fun sync(specs: List<WindowSpec>): Boolean {
        if (!isAvailable()) return false
        val overlay = ensureOverlay()

        val wanted = specs.associateBy { it.slotId }

        // Убрать окна, которых больше нет или сменилось приложение.
        val toRemove = windows.keys.filter { id ->
            val spec = wanted[id]
            spec == null || spec.packageName != windows[id]?.packageName
        }
        for (id in toRemove) removeWindow(id)

        // Создать/переместить нужные.
        for (spec in specs) {
            val existing = windows[spec.slotId]
            if (existing == null) {
                addWindow(overlay, spec)
            } else {
                applyBounds(existing.frame, spec)
            }
        }
        return true
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

        val entry = WindowEntry(frame, activityView, spec.packageName)
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
        val ok = try {
            val m = activityViewClass!!.getMethod("startActivity", Intent::class.java)
            m.invoke(entry.activityView, intent)
            true
        } catch (e: Throwable) {
            lastError = "startActivity в окне (попытка $attempt): ${e.cause ?: e}"
            false
        }
        if (ok) {
            entry.started = true
            lastError = null
        } else if (attempt < 5) {
            // Виртуальный дисплей ещё не готов — повторим.
            handler.postDelayed({ startInto(entry, attempt + 1) }, 250L)
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
        try {
            activityViewClass?.getMethod("release")?.invoke(entry.activityView)
        } catch (e: Throwable) {
            // ignore
        }
        overlay?.removeView(entry.frame)
    }

    /** Убрать все живые окна (например, при уходе лаунчера в фон). */
    fun clear() {
        for (id in windows.keys.toList()) removeWindow(id)
    }
}
