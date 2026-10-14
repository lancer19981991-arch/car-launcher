package com.carlauncher.app

import android.app.Application
import android.content.ComponentName
import androidx.window.embedding.RuleController
import androidx.window.embedding.SplitAttributes
import androidx.window.embedding.SplitPairFilter
import androidx.window.embedding.SplitPairRule
import androidx.window.embedding.SplitRule
import io.flutter.embedding.engine.FlutterEngineGroup

/**
 * Application-класс лаунчера. Делает две вещи:
 *
 * 1. Держит общий [FlutterEngineGroup] — это рекомендованный Google/Flutter
 *    способ работать с несколькими одновременно видимыми Flutter-окнами
 *    (сплит-скрин, multi-window, PiP): движки в группе используют общий
 *    GPU-контекст и группу изолятов, что заметно дешевле двух независимых
 *    FlutterEngine. См. MainActivity и MediaPaneActivity.
 *
 * 2. Регистрирует правило Jetpack Activity Embedding (androidx.window):
 *    если MainActivity запускает MediaPaneActivity, и устройство
 *    предоставляет androidx.window.extensions (это делает производитель
 *    прошивки/OEM), система покажет обе Activity рядом половина-на-половину.
 *
 *    ВАЖНО: на устройствах БЕЗ extensions (многие бюджетные автомагнитолы
 *    на старых/кастомных прошивках их не поставляют) это правило тихо не
 *    применяется — MediaPaneActivity просто откроется как обычный
 *    полноэкранный экран поверх MainActivity. Это безопасный fallback,
 *    а не баг: проверить поддержку на вашем конкретном устройстве можно
 *    только тестом на нём (см. README, раздел "Activity Embedding").
 */
class CarLauncherApplication : Application() {

    lateinit var engineGroup: FlutterEngineGroup
        private set

    override fun onCreate() {
        super.onCreate()
        engineGroup = FlutterEngineGroup(this)
        setupActivityEmbeddingRules()
    }

    private fun setupActivityEmbeddingRules() {
        val filter = SplitPairFilter(
            ComponentName(this, MainActivity::class.java),
            ComponentName(this, MediaPaneActivity::class.java),
            null,
        )

        val rule = SplitPairRule.Builder(setOf(filter))
            .setDefaultSplitAttributes(
                SplitAttributes.Builder()
                    .setSplitType(SplitAttributes.SplitType.ratio(0.5f))
                    .build(),
            )
            // Если закроют основной экран — закрыть и медиа-панель.
            .setFinishPrimaryWithSecondary(SplitRule.FinishBehavior.NEVER)
            .setFinishSecondaryWithPrimary(SplitRule.FinishBehavior.ALWAYS)
            .setClearTop(true)
            .build()

        RuleController.getInstance(this).setRules(setOf(rule))
    }
}
