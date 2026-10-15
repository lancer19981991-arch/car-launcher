/// Можно ли встраивать живые окна приложений прямо в экран лаунчера
/// (как CarCar). Доступно только системному приложению на Android 10/11.
class LiveWindowsStatus {
  const LiveWindowsStatus({
    required this.available,
    required this.systemUid,
    required this.uid,
    required this.activityViewFound,
    this.lastError,
  });

  /// Встраивание работает: системный UID и ActivityView доступны.
  final bool available;

  /// Процесс работает под системным UID (sharedUserId сработал).
  final bool systemUid;

  /// Фактический UID процесса (1000 = system).
  final int uid;

  /// Класс android.app.ActivityView найден на этой прошивке.
  final bool activityViewFound;

  /// Последняя ошибка встраивания, если была.
  final String? lastError;

  factory LiveWindowsStatus.fromMap(Map<Object?, Object?> map) {
    return LiveWindowsStatus(
      available: map['available'] as bool? ?? false,
      systemUid: map['systemUid'] as bool? ?? false,
      uid: map['uid'] as int? ?? -1,
      activityViewFound: map['activityViewFound'] as bool? ?? false,
      lastError: map['lastError'] as String?,
    );
  }

  /// Короткая строка диагностики для экрана.
  String get diagnostics {
    final parts = [
      'UID=$uid${systemUid ? " (system)" : " (не system)"}',
      'ActivityView=${activityViewFound ? "есть" : "нет"}',
      if (lastError != null) 'ошибка: $lastError',
    ];
    return parts.join('  •  ');
  }
}
