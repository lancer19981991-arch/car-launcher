import 'dart:ui' show Rect;

import 'package:flutter/services.dart';

import '../models/app_info.dart';
import '../models/freeform_status.dart';
import '../models/live_windows_status.dart';
import '../models/widget_provider.dart';

/// Канал связи с нативной (Kotlin) стороной — android/.../MainActivity.kt.
///
/// Всё, что требует настоящих системных прав (роль лаунчера по умолчанию,
/// device owner, lock task / kiosk-режим), решается на нативной стороне
/// через официальные Android API, а не через фейковые "system" permissions.
/// Одно живое окно: какое приложение и в каких границах (px экрана).
class AppWindowSpec {
  const AppWindowSpec({
    required this.slotId,
    required this.packageName,
    required this.boundsPx,
    this.widgetId = 0,
  });

  final String slotId;
  final String packageName;
  final Rect boundsPx;

  /// 0 — в окне приложение; иначе id виджета рабочего стола.
  final int widgetId;

  Map<String, Object> toMap() => {
        'slotId': slotId,
        'packageName': packageName,
        'left': boundsPx.left.round(),
        'top': boundsPx.top.round(),
        'width': boundsPx.width.round(),
        'height': boundsPx.height.round(),
        'widgetId': widgetId,
      };
}

class NativeBridge {
  NativeBridge._();

  static const MethodChannel _channel = MethodChannel('car_launcher/native');

  /// Вызывается из нативной стороны при долгом нажатии на живое окно
  /// (slotId окна). Назначается экраном лаунчера.
  static void Function(String slotId)? onWindowLongPress;

  /// Нажатие на нативную пилюлю с часами (поверх живых окон).
  static void Function()? onPillTap;

  static bool _handlerSet = false;

  /// Подписаться на входящие вызовы из нативной стороны (один раз).
  static void ensureIncomingHandler() {
    if (_handlerSet) return;
    _handlerSet = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onWindowLongPress') {
        final slotId = call.arguments as String?;
        if (slotId != null) onWindowLongPress?.call(slotId);
      } else if (call.method == 'onPillTap') {
        onPillTap?.call();
      }
      return null;
    });
  }

  /// Является ли это приложение сейчас лаунчером по умолчанию (ролью HOME).
  static Future<bool> isDefaultLauncher() async {
    final result = await _channel.invokeMethod<bool>('isDefaultLauncher');
    return result ?? false;
  }

  /// Открыть системный диалог выбора лаунчера по умолчанию
  /// (RoleManager на Android 10+, иначе экран настроек "Домашнее приложение").
  static Future<void> requestDefaultLauncher() async {
    await _channel.invokeMethod('requestDefaultLauncher');
  }

  /// Зарегистрировано ли приложение как Device Owner
  /// (требуется для киоск-режима — см. README, раздел "Device Owner").
  static Future<bool> isDeviceOwner() async {
    final result = await _channel.invokeMethod<bool>('isDeviceOwner');
    return result ?? false;
  }

  /// Включить киоск-режим: lock task mode + (если Device Owner) скрытие
  /// статус-бара и блокировка выхода из приложения.
  static Future<bool> startKioskMode() async {
    final result = await _channel.invokeMethod<bool>('startKioskMode');
    return result ?? false;
  }

  /// Выключить киоск-режим.
  static Future<void> stopKioskMode() async {
    await _channel.invokeMethod('stopKioskMode');
  }

  /// Открыть приложение свободным окном в границах [boundsPx] —
  /// в физических пикселях относительно экрана лаунчера. Если устройство
  /// не поддерживает свободные окна, приложение откроется на весь экран.
  static Future<bool> launchAppInBounds(String packageName, Rect boundsPx) async {
    final ok = await _channel.invokeMethod<bool>('launchAppInBounds', {
      'packageName': packageName,
      'left': boundsPx.left.round(),
      'top': boundsPx.top.round(),
      'right': boundsPx.right.round(),
      'bottom': boundsPx.bottom.round(),
    });
    return ok ?? false;
  }

  /// Доступно ли встраивание живых окон приложений (системный режим,
  /// как у CarCar).
  static Future<LiveWindowsStatus> liveWindowsAvailable() async {
    final raw = await _channel.invokeMapMethod<Object?, Object?>('liveWindowsAvailable');
    return LiveWindowsStatus.fromMap(raw ?? const {});
  }

  /// Показать живые окна приложений в заданных областях (px экрана
  /// лаунчера). Возвращает true, если встраивание применено; false —
  /// если устройство/подпись его не поддерживают.
  static Future<bool> syncAppWindows(List<AppWindowSpec> windows, {Rect? pillPx}) async {
    final ok = await _channel.invokeMethod<bool>('syncAppWindows', {
      'windows': [for (final w in windows) w.toMap()],
      if (pillPx != null)
        'pill': {
          'left': pillPx.left.round(),
          'top': pillPx.top.round(),
          'width': pillPx.width.round(),
          'height': pillPx.height.round(),
        },
    });
    return ok ?? false;
  }

  /// Убрать все живые окна.
  static Future<void> clearAppWindows() async {
    await _channel.invokeMethod('clearAppWindows');
  }

  /// Все виджеты рабочего стола, установленные на устройстве.
  static Future<List<WidgetProvider>> getWidgetProviders() async {
    final raw = await _channel.invokeListMethod<Object?>('getWidgetProviders') ?? const [];
    return raw.map((e) => WidgetProvider.fromMap(e! as Map<Object?, Object?>)).toList();
  }

  /// Привязать виджет (и, если нужно, открыть его настройку).
  /// Возвращает id виджета; null — если настройку отменили.
  /// Бросает PlatformException, если система не разрешила.
  static Future<int?> bindWidget(String provider) =>
      _channel.invokeMethod<int>('bindWidget', {'provider': provider});

  static Future<void> deleteWidget(int widgetId) =>
      _channel.invokeMethod('deleteWidget', {'widgetId': widgetId});

  static Future<FreeformStatus> getFreeformStatus() async {
    final raw = await _channel.invokeMapMethod<Object?, Object?>('getFreeformStatus');
    return FreeformStatus.fromMap(raw ?? const {});
  }

  /// Открыть «Для разработчиков». false — если экран недоступен
  /// (режим разработчика ещё не включён).
  static Future<bool> openDeveloperSettings() async {
    final ok = await _channel.invokeMethod<bool>('openDeveloperSettings');
    return ok ?? false;
  }

  /// Все установленные приложения со значком в списке приложений
  /// (кроме самого лаунчера), отсортированы по названию.
  static Future<List<AppInfo>> getInstalledApps() async {
    final raw =
        await _channel.invokeListMethod<Object?>('getInstalledApps') ?? const [];
    return raw
        .map((e) => AppInfo.fromMap(e! as Map<Object?, Object?>))
        .toList();
  }

  /// Запустить приложение. false — если оно удалено или не запускается.
  static Future<bool> launchApp(String packageName) async {
    final ok = await _channel.invokeMethod<bool>(
      'launchApp',
      {'packageName': packageName},
    );
    return ok ?? false;
  }
}
