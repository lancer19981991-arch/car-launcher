/// Можно ли встраивать живые окна приложений прямо в экран лаунчера
/// (как CarCar). Доступно только системному приложению на Android 10/11.
class LiveWindowsStatus {
  const LiveWindowsStatus({required this.available, required this.systemApp});

  /// Встраивание работает: приложение системное и ActivityView доступен.
  final bool available;

  /// APK установлен как системный (подписан платформенным ключом).
  final bool systemApp;

  factory LiveWindowsStatus.fromMap(Map<Object?, Object?> map) {
    return LiveWindowsStatus(
      available: map['available'] as bool? ?? false,
      systemApp: map['systemApp'] as bool? ?? false,
    );
  }
}
