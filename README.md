# Car Launcher

Автомобильный лаунчер (Flutter): часы, сетка пресетов, настройки темы,
регистрация как лаунчер по умолчанию, опциональный киоск-режим через
Device Owner, и две панели на экране одновременно (главный экран +
медиаплеер) через Jetpack Activity Embedding.

## Сборка — автоматически, через GitHub Actions

При каждом push в `main` (а также вручную — вкладка **Actions** →
**Build Android APK** → **Run workflow**) собирается release APK.
Готовый файл появляется в разделе **Artifacts** завершённого запуска —
скачать можно прямо там, подписания собственным ключом для установки
на свой телефон достаточно (Android сам предложит debug-подпись, т.к.
отдельный release-ключ здесь не настроен — см. ниже).

Workflow (`.github/workflows/build-apk.yml`) делает это так: ставит
Flutter на сервере GitHub, генерирует свежий Android-скаффолд (`flutter
create`), накладывает поверх наш код (`lib/`, `android_overlay/`),
правит `pubspec.yaml` и `build.gradle` скриптом `scripts/patch_project.py`
и собирает APK. Генерация скаффолда на каждом запуске — осознанный
выбор: так Gradle-файлы всегда актуальны версии Flutter, которая
реально ставится в этом запуске, а не заморожены на момент написания
workflow.

## Структура репозитория

```
lib/                          — весь Dart/Flutter-код приложения
android_overlay/
  AndroidManifest.xml          — финальный манифест (роль HOME, 2 Activity)
  kotlin/com/carlauncher/app/  — Kotlin-код (MainActivity, MediaPaneActivity,
                                  CarLauncherApplication — Activity Embedding,
                                  BootReceiver, DeviceOwnerReceiver)
  res/xml/device_admin_receiver.xml
pubspec_extra.yaml             — дополнительные зависимости (мерджатся в pubspec.yaml)
scripts/patch_project.py       — скрипт слияния, запускается в workflow
.github/workflows/build-apk.yml
```

## Почему нет системных/`android.uid.system` прав

Права вроде `WRITE_SETTINGS`, `FORCE_STOP_PACKAGES`,
`sharedUserId="android.uid.system"` даёт не манифест, а подпись
платформенным ключом конкретной прошивки — такой ключ есть только у
производителя устройства. Вместо этого используются официальные
механизмы: роль лаунчера по умолчанию (`RoleManager`/HOME-intent,
без всяких прав) и опционально Device Owner (`DevicePolicyManager`)
для настоящего киоск-режима — регистрируется одной командой `adb` на
ещё не настроенном устройстве:

```bash
adb shell dpm set-device-owner com.carlauncher.app/.DeviceOwnerReceiver
```

## Две панели на экране (Jetpack Activity Embedding)

`MainActivity` при запуске сама открывает `MediaPaneActivity`.
`CarLauncherApplication.kt` регистрирует правило: если на устройстве
есть `androidx.window.extensions` (её поставляет производитель
прошивки), система покажет обе панели рядом, 50/50. Если библиотеки
нет — вторая панель просто откроется поверх как обычный полноэкранный
экран; ничего не ломается, но и панели рядом не будет. Проверить,
какой вариант на конкретном устройстве, можно только тестом на нём.

## Установка собранного APK

1. Скачайте `car-launcher-apk` из Artifacts завершённого workflow-рана.
2. На устройстве разрешите установку из неизвестных источников и
   установите APK обычным способом.
3. При первом нажатии кнопки «Домой» Android предложит выбрать
   лаунчер — выберите Car Launcher, либо используйте кнопку
   «Назначить» на экране настроек самого приложения.

APK подписан отладочным (debug) ключом Flutter по умолчанию — этого
достаточно для установки и личного использования, но не для публикации
в Google Play (там нужен ваш собственный release-ключ — за пределами
этой задачи).
