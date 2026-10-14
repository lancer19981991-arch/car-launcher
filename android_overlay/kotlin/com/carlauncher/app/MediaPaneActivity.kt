package com.carlauncher.app

import android.content.Context
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor

/**
 * Вторая "панель" лаунчера — медиаплеер (lib/screens/media_pane_screen.dart).
 *
 * Это намеренно отдельная Activity, а не второй виджет внутри экрана
 * MainActivity: показать рядом можно только независимые Activity —
 * см. CarLauncherApplication (правило Activity Embedding) и README.
 *
 * Использует движок из общей FlutterEngineGroup — так оба окна лаунчера
 * делят GPU-контекст и изоляты вместо двух полностью независимых
 * инстансов Flutter-движка.
 */
class MediaPaneActivity : FlutterActivity() {

    override fun provideFlutterEngine(context: Context): FlutterEngine {
        val app = applicationContext as CarLauncherApplication
        return app.engineGroup.createAndRunEngine(
            context,
            DartExecutor.DartEntrypoint.createDefault(),
            "/media_pane",
        )
    }
}
