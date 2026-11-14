package com.carlauncher.app

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.ServiceConnection
import android.os.Binder
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.Parcel

/**
 * Данные CAN-декодера магнитолы FYT (у пользователя sprd ums512, приложения
 * com.syu.*). Главная служба com.syu.ms раздаёт их через свой «toolkit»:
 * IRemoteToolkit.getRemoteModule(7 = CANBUS) → IRemoteModule.register(callback,
 * код, 1) → IModuleCallback.update(код, int[], float[], String[]) при каждом
 * изменении. AIDL-файлов нет — пишем Binder-транзакции руками (описание —
 * из открытых разборов прошивки FYT; коды дверей у разных машин могут
 * отличаться, поэтому подписываемся на широкий диапазон и всё отдаём наверх).
 */
class FytCanbus(
    private val context: Context,
    private val onUpdate: (code: Int, ints: IntArray?, flts: FloatArray?, strs: Array<String?>?) -> Unit,
    private val onState: (String) -> Unit,
) {
    companion object {
        private const val TOOLKIT = "com.syu.ipc.IRemoteToolkit"
        private const val MODULE = "com.syu.ipc.IRemoteModule"
        private const val CALLBACK = "com.syu.ipc.IModuleCallback"
        const val MODULE_CANBUS = 7
        private const val MAX_CODE = 300
    }

    private val main = Handler(Looper.getMainLooper())
    private var module: IBinder? = null
    private var bound = false
    var state = "не подключено"
        private set

    /** Последние значения по коду — для экрана разведки. */
    val last = HashMap<Int, IntArray?>()

    private val callback = object : Binder() {
        override fun onTransact(code: Int, data: Parcel, reply: Parcel?, flags: Int): Boolean {
            if (code == INTERFACE_TRANSACTION) {
                reply?.writeString(CALLBACK)
                return true
            }
            if (code == FIRST_CALL_TRANSACTION) {
                return try {
                    data.enforceInterface(CALLBACK)
                    val c = data.readInt()
                    val ints = data.createIntArray()
                    val flts = data.createFloatArray()
                    val strs = data.createStringArray()
                    main.post {
                        last[c] = ints
                        onUpdate(c, ints, flts, strs)
                    }
                    true
                } catch (e: Throwable) {
                    false
                }
            }
            return super.onTransact(code, data, reply, flags)
        }
    }

    private val conn = object : ServiceConnection {
        override fun onServiceConnected(name: ComponentName?, service: IBinder?) {
            Thread {
                try {
                    val m = getModule(service ?: return@Thread, MODULE_CANBUS)
                    if (m == null) {
                        setState("модуль CANBUS не найден")
                        return@Thread
                    }
                    module = m
                    var ok = 0
                    for (c in 0..MAX_CODE) if (register(m, c)) ok++
                    setState("подключено к com.syu.ms (коды 0–$MAX_CODE: $ok)")
                } catch (e: Throwable) {
                    setState("ошибка: ${e.message ?: e}")
                }
            }.start()
        }

        override fun onServiceDisconnected(name: ComponentName?) {
            module = null
            setState("связь со службой потеряна — переподключение")
        }
    }

    private fun setState(s: String) {
        main.post {
            state = s
            onState(s)
        }
    }

    fun start() {
        if (bound) return
        try {
            val i = Intent().setClassName("com.syu.ms", "app.ToolkitService")
            bound = context.bindService(i, conn, Context.BIND_AUTO_CREATE)
            setState(if (bound) "подключение к com.syu.ms…" else "служба com.syu.ms не найдена (магнитола не FYT?)")
        } catch (e: Throwable) {
            setState("нет доступа к com.syu.ms: ${e.message ?: e}")
        }
    }

    fun stop() {
        val m = module
        if (m != null) for (c in 0..MAX_CODE) unregister(m, c)
        if (bound) {
            try {
                context.unbindService(conn)
            } catch (e: Throwable) {
            }
        }
        bound = false
        module = null
    }

    private fun getModule(toolkit: IBinder, code: Int): IBinder? {
        val data = Parcel.obtain()
        val reply = Parcel.obtain()
        return try {
            data.writeInterfaceToken(TOOLKIT)
            data.writeInt(code)
            toolkit.transact(IBinder.FIRST_CALL_TRANSACTION, data, reply, 0)
            reply.readException()
            reply.readStrongBinder()
        } finally {
            data.recycle()
            reply.recycle()
        }
    }

    private fun register(m: IBinder, code: Int): Boolean {
        val data = Parcel.obtain()
        return try {
            data.writeInterfaceToken(MODULE)
            data.writeStrongBinder(callback)
            data.writeInt(code)
            data.writeInt(1)
            m.transact(IBinder.FIRST_CALL_TRANSACTION + 2, data, null, IBinder.FLAG_ONEWAY)
        } catch (e: Throwable) {
            false
        } finally {
            data.recycle()
        }
    }

    private fun unregister(m: IBinder, code: Int) {
        val data = Parcel.obtain()
        try {
            data.writeInterfaceToken(MODULE)
            data.writeStrongBinder(callback)
            data.writeInt(code)
            m.transact(IBinder.FIRST_CALL_TRANSACTION + 3, data, null, IBinder.FLAG_ONEWAY)
        } catch (e: Throwable) {
        } finally {
            data.recycle()
        }
    }
}
