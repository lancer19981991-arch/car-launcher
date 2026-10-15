package com.carlauncher.app

import android.app.Activity
import android.content.Intent
import android.graphics.Color
import android.os.Handler
import android.os.Looper
import android.view.View
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
class AppWindowHost(private val activity: Activity) {

    private val handler = Handler(Looper.getMainLooper())

    /** Оверлей-контейнер поверх FlutterView, в нём лежат окна. */
    private var overlay: FrameLayout? = null

    /** slotId -> состояние одного окна. */
    private val windows = HashMap<String, WindowEntry>()

    private class WindowEntry(
        val view: View,
        var packageName: String,
        var started: Boolean = false,
    )

    private val activityViewClass: Class<*>? = try {
        Class.forName("android.app.ActivityView")
    } catch (e: Throwable) {
        null
    }

    /** Доступно ли встраивание живых окон на этом устройстве/подписи. */
    fun isAvailable(): Boolean = activityViewClass != null && isSystemApp()

    /** Приложение установлено как системное (есть флаг FLAG_SYSTEM). */
    fun isSystemApp(): Boolean {
        val flags = activity.applicationInfo.flags
        return (flags and android.content.pm.ApplicationInfo.FLAG_SYSTEM) != 0
    }

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
                applyBounds(existing.view, spec)
            }
        }
        return true
    }

    private fun addWindow(overlay: FrameLayout, spec: WindowSpec) {
        val view = try {
            activityViewClass!!
                .getConstructor(android.content.Context::class.java)
                .newInstance(activity) as View
        } catch (e: Throwable) {
            // Нет подходящего конструктора — встраивание недоступно.
            return
        }

        val lp = FrameLayout.LayoutParams(spec.width, spec.height)
        lp.leftMargin = spec.left
        lp.topMargin = spec.top
        overlay.addView(view, lp)

        val entry = WindowEntry(view, spec.packageName)
        windows[spec.slotId] = entry

        // ActivityView должен быть прикреплён и измерен до startActivity.
        // Колбэка готовности не используем (StateCallback — абстрактный
        // класс, через рефлексию не подклассить), поэтому запускаем с
        // небольшой задержкой и несколькими повторами.
        view.post { startInto(entry, attempt = 0) }
    }

    private fun startInto(entry: WindowEntry, attempt: Int) {
        if (entry.started) return
        if (!windows.containsValue(entry)) return // окно уже убрали
        val intent = activity.packageManager.getLaunchIntentForPackage(entry.packageName)
        if (intent == null) return
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        val ok = try {
            val m = activityViewClass!!.getMethod("startActivity", Intent::class.java)
            m.invoke(entry.view, intent)
            true
        } catch (e: Throwable) {
            false
        }
        if (ok) {
            entry.started = true
        } else if (attempt < 5) {
            // Виртуальный дисплей ещё не готов — повторим.
            handler.postDelayed({ startInto(entry, attempt + 1) }, 250L)
        }
    }

    private fun applyBounds(view: View, spec: WindowSpec) {
        val lp = view.layoutParams as? FrameLayout.LayoutParams ?: return
        if (lp.leftMargin == spec.left && lp.topMargin == spec.top &&
            lp.width == spec.width && lp.height == spec.height
        ) {
            return
        }
        lp.leftMargin = spec.left
        lp.topMargin = spec.top
        lp.width = spec.width
        lp.height = spec.height
        view.layoutParams = lp
    }

    private fun removeWindow(slotId: String) {
        val entry = windows.remove(slotId) ?: return
        try {
            activityViewClass?.getMethod("release")?.invoke(entry.view)
        } catch (e: Throwable) {
            // ignore
        }
        overlay?.removeView(entry.view)
    }

    /** Убрать все живые окна (например, при уходе лаунчера в фон). */
    fun clear() {
        for (id in windows.keys.toList()) removeWindow(id)
    }
}
