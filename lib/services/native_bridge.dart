import 'package:flutter/services.dart';

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

  /// Открыть вторую панель (медиаплеер, MediaPaneActivity). Если на
  /// устройстве доступен Jetpack Activity Embedding, система покажет
  /// её рядом с главным экраном; иначе — как обычный полноэкранный
  /// экран поверх (см. README, раздел "Activity Embedding").
  static Future<void> openMediaPane() async {
    await _channel.invokeMethod('openMediaPane');
  }
}
