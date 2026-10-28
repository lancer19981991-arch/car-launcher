package com.carlauncher.app

import android.annotation.SuppressLint
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothSocket
import android.os.Handler
import android.os.Looper
import java.io.IOException
import java.util.UUID

/**
 * Связь с OBD-адаптером ELM327 по Bluetooth (классический SPP).
 *
 * Опрашивает по кругу напряжение сети (команда адаптера ATRV — работает и
 * на заглушённом двигателе) и температуру охлаждающей жидкости (PID 01 05).
 * Работает только пока лаунчер на экране: ELM327 держит одно подключение,
 * и Car Scanner / CVTz должны иметь возможность его занять.
 * При обрыве сам переподключается через несколько секунд.
 */
class ObdClient(private val onUpdate: (Map<String, Any?>) -> Unit) {

    private val main = Handler(Looper.getMainLooper())

    /** MAC-адрес адаптера; null — OBD выключен. */
    @Volatile private var address: String? = null

    /** Лаунчер на экране. */
    @Volatile private var active = false

    /** Номер «поколения» потока: смена — сигнал старому потоку остановиться. */
    @Volatile private var gen = 0

    @Volatile private var socket: BluetoothSocket? = null

    fun setAddress(a: String?) {
        address = a?.takeIf { it.isNotBlank() }
        restart()
    }

    fun resume() {
        active = true
        restart()
    }

    fun pause() {
        active = false
        stopThread()
        emit("paused", null)
    }

    private fun restart() {
        stopThread()
        val a = address
        if (a == null) {
            emit("off", null)
            return
        }
        if (!active) return
        val my = gen
        Thread({ run(my, a) }, "obd").start()
    }

    private fun stopThread() {
        gen++
        closeSocket()
    }

    private fun closeSocket() {
        try {
            socket?.close()
        } catch (e: Throwable) {
        }
        socket = null
    }

    private fun alive(my: Int) = my == gen

    private fun run(my: Int, addr: String) {
        while (alive(my)) {
            try {
                connectAndPoll(my, addr)
            } catch (e: Throwable) {
                if (alive(my)) emit("error", e.message ?: e.toString())
            }
            closeSocket()
            // Пауза перед новой попыткой (адаптер мог быть занят другим приложением).
            var waited = 0
            while (alive(my) && waited < 5000) {
                Thread.sleep(200)
                waited += 200
            }
        }
    }

    @SuppressLint("MissingPermission")
    private fun connectAndPoll(my: Int, addr: String) {
        val bt = BluetoothAdapter.getDefaultAdapter() ?: throw IOException("Bluetooth недоступен на устройстве")
        if (!bt.isEnabled) throw IOException("Bluetooth выключен")
        val dev = bt.getRemoteDevice(addr)
        emit("connecting", null)
        try {
            bt.cancelDiscovery()
        } catch (e: Throwable) {
        }
        val s = openSocket(dev)
        socket = s
        if (!alive(my)) return
        val io = Elm(s)

        // Инициализация как в CVTz у пользователя. Протокол машины известен
        // (Teana J32: ISO 15765-4 CAN 11 бит 500k) — ATSP6, без автопоиска.
        io.cmd("ATZ", 4000)
        for (c in listOf("ATE0", "ATM0", "ATL0", "ATS0", "ATH0", "ATAT1", "ATST32", "ATAL", "ATSP6")) {
            io.cmd(c)
        }
        emit("connected", null)

        var voltage: Double? = null
        var coolant: Int? = null
        var cvt: CvtReading? = null
        var round = 0
        while (alive(my)) {
            voltage = parseVoltage(io.cmd("ATRV")) ?: voltage
            val c = io.cmd("0105", 5000)
            coolant = parsePid(c, "4105")?.let { it - 40 }
            // Вариатор — каждый второй круг (~3 с): запрос длинный.
            if (round % 2 == 0 && coolant != null) cvt = readCvt(io)
            round++
            if (!alive(my)) break
            emit(
                "connected",
                null,
                mapOf(
                    "voltage" to voltage,
                    "coolant" to coolant,
                    // Двигатель не отвечает (заглушён / зажигание выключено).
                    "ecuSilent" to (coolant == null),
                    "cvtTemp" to cvt?.temp,
                    "cvtBytes" to cvt?.bytes,
                    "cvtNote" to cvt?.note,
                ),
            )
            Thread.sleep(1500)
        }
    }

    /** Ответ блока вариатора: байты данных 2101 и посчитанная температура. */
    private class CvtReading(val bytes: List<Int>?, val temp: Double?, val note: String?)

    /**
     * Вариатор Nissan (блок 7E1, ответ 7E9): открыть диагностический сеанс
     * 10C0, запросить 2101 (длинный ответ из нескольких кадров), закрыть
     * сеанс и вернуть адаптер к обычным запросам (7DF).
     * Температура — байт AD (30-й) по формуле из Torque-файла для Murano Z51;
     * для JF011E у Teana надо сверить с CVTz.
     */
    private fun readCvt(io: Elm): CvtReading {
        try {
            for (c in listOf("ATSH7E1", "ATCRA7E9", "ATFCSH7E1", "ATFCSD300000", "ATFCSM1")) io.cmd(c)
            io.cmd("10C0", 3000)
            val r = io.cmd("2101", 5000)
            io.cmd("1081", 3000)
            val bytes = parseMultiFrame(r, "6101")
                ?: return CvtReading(null, null, "Вариатор ответил: ${r.replace('\r', ' ').take(60)}")
            val ad = bytes.getOrNull(29)
            val temp = ad?.let { cvtTemp(it) }
            return CvtReading(bytes, temp, if (ad == null) "Ответ короче ожидаемого (${bytes.size} байт)" else null)
        } catch (e: IOException) {
            throw e
        } catch (e: Throwable) {
            return CvtReading(null, null, "Ошибка разбора: ${e.message}")
        } finally {
            // Назад к обычным запросам OBD (функциональный адрес 7DF).
            for (c in listOf("ATAR", "ATFCSM0", "ATSH7DF")) io.cmd(c)
        }
    }

    /** Разные адаптеры и прошивки любят разные способы подключения. */
    @SuppressLint("MissingPermission")
    private fun openSocket(dev: BluetoothDevice): BluetoothSocket {
        var last: Throwable? = null
        val attempts = listOf<() -> BluetoothSocket>(
            { dev.createRfcommSocketToServiceRecord(SPP) },
            { dev.createInsecureRfcommSocketToServiceRecord(SPP) },
            { dev.javaClass.getMethod("createRfcommSocket", Int::class.javaPrimitiveType).invoke(dev, 1) as BluetoothSocket },
        )
        for (make in attempts) {
            var s: BluetoothSocket? = null
            try {
                s = make()
                s.connect()
                return s
            } catch (e: Throwable) {
                last = e
                try {
                    s?.close()
                } catch (x: Throwable) {
                }
            }
        }
        throw IOException("Не удалось подключиться к адаптеру (занят другим приложением или выключен?): ${last?.message ?: last}")
    }

    /** Обмен командами с ELM327: команда + \r, ответ — до приглашения «>». */
    private class Elm(s: BluetoothSocket) {
        private val input = s.inputStream
        private val output = s.outputStream

        fun cmd(c: String, timeoutMs: Long = 2500): String {
            // Выкинуть остатки прошлых ответов.
            while (input.available() > 0) input.read()
            output.write("$c\r".toByteArray())
            output.flush()
            val sb = StringBuilder()
            val deadline = System.currentTimeMillis() + timeoutMs
            while (System.currentTimeMillis() < deadline) {
                if (input.available() > 0) {
                    val ch = input.read()
                    if (ch < 0) throw IOException("Адаптер отключился")
                    if (ch == '>'.code) return sb.toString().trim()
                    sb.append(ch.toChar())
                } else {
                    Thread.sleep(10)
                }
            }
            throw IOException("Адаптер не ответил на $c")
        }
    }

    private fun emit(state: String, message: String?, values: Map<String, Any?> = emptyMap()) {
        val m = HashMap<String, Any?>(values)
        m["state"] = state
        m["message"] = message
        main.post { onUpdate(m) }
    }

    /** Сопряжённые устройства — для выбора адаптера в настройках. */
    @SuppressLint("MissingPermission")
    fun pairedDevices(): List<Map<String, String>> {
        val bt = BluetoothAdapter.getDefaultAdapter() ?: return emptyList()
        return try {
            bt.bondedDevices.map { mapOf("name" to (it.name ?: it.address), "address" to it.address) }
        } catch (e: Throwable) {
            emptyList()
        }
    }

    companion object {
        private val SPP: UUID = UUID.fromString("00001101-0000-1000-8000-00805F9B34FB")

        /** «12.6V» → 12.6 */
        fun parseVoltage(r: String): Double? =
            Regex("""(\d{1,2}[.,]\d)\s*V""", RegexOption.IGNORE_CASE).find(r)
                ?.groupValues?.get(1)?.replace(',', '.')?.toDoubleOrNull()

        /** Температура вариатора по байту AD (многочлен из Torque-файла). */
        fun cvtTemp(ad: Int): Double {
            val x = ad.toDouble()
            return 0.000000002344 * Math.pow(x, 5.0) - 0.000001387 * Math.pow(x, 4.0) +
                0.0003193 * Math.pow(x, 3.0) - 0.03501 * x * x + 2.302 * x - 36.6
        }

        /**
         * Длинный ответ ELM327 (ATH0, ATS0, ATCAF1): первая строка — длина,
         * дальше «0:6101…», «1:…» и т.д. Склеиваем, ищем заголовок и
         * возвращаем байты данных после него (A, B, C… как в Torque).
         */
        fun parseMultiFrame(r: String, header: String): List<Int>? {
            val sb = StringBuilder()
            for (raw in r.split('\r', '\n')) {
                val line = raw.trim().replace(" ", "").uppercase()
                if (line.isEmpty()) continue
                val colon = line.indexOf(':')
                if (colon in 1..2) {
                    sb.append(line.substring(colon + 1))
                } else if (line.length <= 3 && sb.isEmpty() && line.all { it.isDigit() || it in 'A'..'F' }) {
                    continue // длина ответа
                } else {
                    sb.append(line)
                }
            }
            val all = sb.toString()
            val i = all.indexOf(header)
            if (i < 0) return null
            val data = all.substring(i + header.length)
            return (0 until data.length / 2).mapNotNull { data.substring(it * 2, it * 2 + 2).toIntOrNull(16) }
        }

        /** Первый байт данных после заголовка ответа (например «4105» + «7B»). */
        fun parsePid(r: String, header: String): Int? {
            val clean = r.replace(" ", "").replace("\r", "").replace("\n", "").uppercase()
            val i = clean.indexOf(header)
            if (i < 0 || clean.length < i + header.length + 2) return null
            return clean.substring(i + header.length, i + header.length + 2).toIntOrNull(16)
        }
    }
}
