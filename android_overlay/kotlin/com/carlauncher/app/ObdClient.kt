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

        io.cmd("ATZ", 4000)
        io.cmd("ATE0")
        io.cmd("ATL0")
        io.cmd("ATS0")
        io.cmd("ATH0")
        io.cmd("ATSP0")
        emit("connected", null)

        var voltage: Double? = null
        var coolant: Int? = null
        while (alive(my)) {
            voltage = parseVoltage(io.cmd("ATRV")) ?: voltage
            // Первый запрос PID может идти долго: адаптер ищет протокол.
            val c = io.cmd("0105", 8000)
            coolant = parsePid(c, "4105")?.let { it - 40 }
            if (!alive(my)) break
            emit(
                "connected",
                null,
                mapOf(
                    "voltage" to voltage,
                    "coolant" to coolant,
                    // Двигатель не отвечает (заглушён / зажигание выключено).
                    "ecuSilent" to (coolant == null),
                ),
            )
            Thread.sleep(1500)
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

        /** Первый байт данных после заголовка ответа (например «4105» + «7B»). */
        fun parsePid(r: String, header: String): Int? {
            val clean = r.replace(" ", "").replace("\r", "").replace("\n", "").uppercase()
            val i = clean.indexOf(header)
            if (i < 0 || clean.length < i + header.length + 2) return null
            return clean.substring(i + header.length, i + header.length + 2).toIntOrNull(16)
        }
    }
}
