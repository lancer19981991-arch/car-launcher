package com.carlauncher.app

import android.content.Context
import android.net.Uri
import java.io.BufferedReader
import java.io.InputStreamReader

/**
 * Разведка: откуда брать состояние дверей. Магнитола сама показывает
 * открытые двери (в ней CAN-декодер), но как прошивка передаёт эти данные —
 * зависит от модели. Пока идёт запись, пользователь открывает и закрывает
 * дверь; сравниваем «до/после» системные настройки и свойства и ловим
 * строки журнала (logcat) про двери/CAN. Отчёт — текстом, пользователь
 * присылает его файлом.
 */
class DoorProbe(private val context: Context) {

    private var settingsBefore: Map<String, String> = emptyMap()
    private var propsBefore: Map<String, String> = emptyMap()
    private var logProcess: Process? = null
    private val logLines = ArrayList<String>()
    private var startedAt = 0L

    fun start() {
        stopLog()
        settingsBefore = readSettings()
        propsBefore = readProps()
        synchronized(logLines) { logLines.clear() }
        startedAt = System.currentTimeMillis()
        try {
            // Только новые строки с момента старта.
            val p = Runtime.getRuntime().exec(arrayOf("logcat", "-v", "time", "-T", "1"))
            logProcess = p
            Thread {
                try {
                    BufferedReader(InputStreamReader(p.inputStream)).useLines { lines ->
                        for (l in lines) {
                            synchronized(logLines) {
                                logLines.add(l)
                                if (logLines.size > 20000) logLines.subList(0, 5000).clear()
                            }
                        }
                    }
                } catch (e: Throwable) {
                }
            }.start()
        } catch (e: Throwable) {
            synchronized(logLines) { logLines.add("logcat недоступен: $e") }
        }
    }

    fun stop(): String {
        Thread.sleep(300) // дочитать последние строки журнала
        stopLog()
        val sb = StringBuilder()
        val secs = (System.currentTimeMillis() - startedAt) / 1000
        sb.append("=== Отчёт разведки дверей ===\n")
        sb.append("Модель: ${android.os.Build.MANUFACTURER} ${android.os.Build.MODEL} / ${android.os.Build.DEVICE}, ")
        sb.append("Android ${android.os.Build.VERSION.RELEASE}, прошивка ${android.os.Build.DISPLAY}\n")
        sb.append("Запись: $secs с\n\n")

        sb.append("--- Изменились настройки (system/global/secure) ---\n")
        val after = readSettings()
        diff(settingsBefore, after, sb)

        sb.append("\n--- Изменились свойства (getprop) ---\n")
        diff(propsBefore, readProps(), sb)

        val lines = synchronized(logLines) { ArrayList(logLines) }
        val keys = listOf("door", "дверь", "canbus", "can_", "canbox", "carinfo", "car_info", "trunk", "hood", "mcu")
        val hits = lines.filter { l -> val low = l.lowercase(); keys.any { low.contains(it) } }
        sb.append("\n--- Журнал: строки про двери/CAN (${hits.size} из ${lines.size}) ---\n")
        for (l in hits.takeLast(300)) sb.append(l).append('\n')

        // Какие «теги» писали в журнал во время записи — подсказка, кто
        // обрабатывает CAN, даже если слова «door» нет.
        val tags = HashMap<String, Int>()
        val tagRe = Regex("""^\S+\s+\S+\s+[VDIWEF]/([^(]+)\(""")
        for (l in lines) tagRe.find(l)?.groupValues?.get(1)?.trim()?.let { tags[it] = (tags[it] ?: 0) + 1 }
        sb.append("\n--- Самые активные теги журнала ---\n")
        for ((t, n) in tags.entries.sortedByDescending { it.value }.take(40)) sb.append("$n  $t\n")

        sb.append("\n--- Приложения, похожие на CAN/MCU/машину ---\n")
        val pkgRe = Regex("can|mcu|vehicle|carinfo|syu|microntek|fyt|ts\\.|hct|autochips|car\\.|carservice|decoder", RegexOption.IGNORE_CASE)
        try {
            for (pi in context.packageManager.getInstalledPackages(0).sortedBy { it.packageName }) {
                if (pkgRe.containsMatchIn(pi.packageName)) sb.append(pi.packageName).append('\n')
            }
        } catch (e: Throwable) {
            sb.append("не удалось: $e\n")
        }
        return sb.toString()
    }

    private fun stopLog() {
        try {
            logProcess?.destroy()
        } catch (e: Throwable) {
        }
        logProcess = null
    }

    private fun diff(before: Map<String, String>, after: Map<String, String>, sb: StringBuilder) {
        var n = 0
        for (k in (before.keys + after.keys).toSortedSet()) {
            val a = before[k]
            val b = after[k]
            if (a != b) {
                sb.append("$k: ${a ?: "—"} → ${b ?: "—"}\n")
                n++
            }
        }
        if (n == 0) sb.append("ничего\n")
    }

    private fun readSettings(): Map<String, String> {
        val out = HashMap<String, String>()
        for (table in listOf("system", "global", "secure")) {
            try {
                context.contentResolver.query(Uri.parse("content://settings/$table"), arrayOf("name", "value"), null, null, null)
                    ?.use { c ->
                        while (c.moveToNext()) out["$table/${c.getString(0)}"] = c.getString(1) ?: ""
                    }
            } catch (e: Throwable) {
            }
        }
        return out
    }

    private fun readProps(): Map<String, String> {
        val out = HashMap<String, String>()
        try {
            val p = Runtime.getRuntime().exec("getprop")
            val re = Regex("""^\[(.+?)]: \[(.*)]$""")
            BufferedReader(InputStreamReader(p.inputStream)).useLines { lines ->
                for (l in lines) re.find(l)?.let { out[it.groupValues[1]] = it.groupValues[2] }
            }
        } catch (e: Throwable) {
        }
        return out
    }
}
