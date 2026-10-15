/// Поддерживает ли устройство свободные окна (freeform), в которых
/// лаунчер открывает приложения в заданных координатах.
class FreeformStatus {
  const FreeformStatus({
    required this.supported,
    required this.systemFeature,
    required this.developerSetting,
    required this.forceResizable,
    required this.sdk,
  });

  /// Итог: окна будут открываться в заданных границах.
  final bool supported;

  /// Прошивка заявляет поддержку свободных окон.
  final bool systemFeature;

  /// «Окна произвольной формы» в настройках разработчика.
  /// null — система не дала прочитать настройку.
  final bool? developerSetting;

  /// «Изменение размера в многооконном режиме» в настройках разработчика.
  /// null — система не дала прочитать настройку.
  final bool? forceResizable;

  final int sdk;

  factory FreeformStatus.fromMap(Map<Object?, Object?> map) {
    return FreeformStatus(
      supported: map['supported'] as bool? ?? false,
      systemFeature: map['systemFeature'] as bool? ?? false,
      developerSetting: map['developerSetting'] as bool?,
      forceResizable: map['forceResizable'] as bool?,
      sdk: map['sdk'] as int? ?? 0,
    );
  }
}
