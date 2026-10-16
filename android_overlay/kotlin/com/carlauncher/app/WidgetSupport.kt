package com.carlauncher.app

import android.app.Activity
import android.appwidget.AppWidgetHost
import android.appwidget.AppWidgetHostView
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProviderInfo
import android.content.ComponentName
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.Drawable
import android.os.Bundle
import java.io.ByteArrayOutputStream

/**
 * Виджеты рабочего стола (AppWidget) в окнах лаунчера.
 *
 * Лаунчер — хост виджетов, как обычный рабочий стол. Так как он
 * работает с системным UID, привязка виджета (bindAppWidgetIdIfAllowed)
 * проходит без диалога подтверждения. Вид виджета — обычный View
 * (AppWidgetHostView), он кладётся в тот же оверлей, что и живые окна.
 */
class WidgetSupport(private val activity: Activity) {

    companion object {
        private const val HOST_ID = 0x0CA4
        const val REQUEST_CONFIGURE = 7341
    }

    val manager: AppWidgetManager = AppWidgetManager.getInstance(activity)
    val host: AppWidgetHost = AppWidgetHost(activity, HOST_ID)

    fun startListening() {
        try {
            host.startListening()
        } catch (_: Throwable) {
        }
    }

    fun stopListening() {
        try {
            host.stopListening()
        } catch (_: Throwable) {
        }
    }

    /** Все виджеты, установленные на устройстве. */
    fun listProviders(): List<Map<String, Any>> {
        val pm = activity.packageManager
        val density = activity.resources.displayMetrics.densityDpi
        return manager.installedProviders.map { info ->
            val appLabel = try {
                pm.getApplicationLabel(pm.getApplicationInfo(info.provider.packageName, 0)).toString()
            } catch (_: Throwable) {
                info.provider.packageName
            }
            val icon = try {
                info.loadIcon(activity, density)
            } catch (_: Throwable) {
                null
            }
            mapOf(
                "provider" to info.provider.flattenToString(),
                "label" to info.loadLabel(pm),
                "appLabel" to appLabel,
                "icon" to (icon?.let { drawableToPng(it) } ?: ByteArray(0)),
            )
        }.sortedWith(compareBy({ (it["appLabel"] as String).lowercase() }, { (it["label"] as String).lowercase() }))
    }

    /** Результат привязки: id виджета и нужна ли его настройка. */
    data class BindResult(val widgetId: Int, val needsConfigure: Boolean)

    /** Выделить id и привязать виджет. null — если система не разрешила. */
    fun bind(providerFlat: String): BindResult? {
        val provider = ComponentName.unflattenFromString(providerFlat) ?: return null
        val id = host.allocateAppWidgetId()
        val ok = try {
            manager.bindAppWidgetIdIfAllowed(id, provider)
        } catch (_: Throwable) {
            false
        }
        if (!ok) {
            host.deleteAppWidgetId(id)
            return null
        }
        val info = manager.getAppWidgetInfo(id)
        return BindResult(id, info?.configure != null)
    }

    /** Открыть экран настройки виджета (ответ придёт в onActivityResult). */
    fun startConfigure(widgetId: Int): Boolean = try {
        host.startAppWidgetConfigureActivityForResult(activity, widgetId, 0, REQUEST_CONFIGURE, null)
        true
    } catch (_: Throwable) {
        false
    }

    fun delete(widgetId: Int) {
        try {
            host.deleteAppWidgetId(widgetId)
        } catch (_: Throwable) {
        }
    }

    /** Создать вид виджета. null — если виджет уже не существует. */
    fun createView(widgetId: Int): AppWidgetHostView? {
        val info: AppWidgetProviderInfo = manager.getAppWidgetInfo(widgetId) ?: return null
        return try {
            host.createView(activity.applicationContext, widgetId, info)
        } catch (_: Throwable) {
            null
        }
    }

    /** Сообщить виджету его реальный размер (в dp), чтобы он правильно сверстался. */
    @Suppress("DEPRECATION")
    fun updateSize(view: AppWidgetHostView, widthPx: Int, heightPx: Int) {
        val d = activity.resources.displayMetrics.density
        val w = (widthPx / d).toInt()
        val h = (heightPx / d).toInt()
        try {
            view.updateAppWidgetSize(Bundle(), w, h, w, h)
        } catch (_: Throwable) {
        }
    }

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
}
