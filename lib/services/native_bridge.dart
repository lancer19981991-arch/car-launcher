import 'dart:ui' show Rect;

import 'package:flutter/services.dart';

import '../models/app_info.dart';
import '../models/freeform_status.dart';

/// Канал связи с нативной (Kotlin) стороной — android/.../MainActivity.kt.
///
/// Всё, что требует настоящих системных прав (роль лаунчера по умолчанию,
/// device owner, lock task / kiosk-режим), решается на нативной стороне
/// через официальные Android API, а не через фейковые "system" permissions.
class NativeBridge {
  NativeBridge._();

  static const MethodChannel _channel = MethodChannel('car_launcher/native');

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
