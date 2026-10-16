import 'dart:typed_data';

/// Виджет рабочего стола, доступный на устройстве (провайдер AppWidget).
class WidgetProvider {
  const WidgetProvider({
    required this.provider,
    required this.label,
    required this.appLabel,
    required this.icon,
  });

  /// ComponentName провайдера в виде строки (для привязки).
  final String provider;

  /// Название виджета.
  final String label;

  /// Название приложения, которому принадлежит виджет.
  final String appLabel;

  /// Иконка в PNG (может быть пустой).
  final Uint8List icon;

  factory WidgetProvider.fromMap(Map<Object?, Object?> m) => WidgetProvider(
        provider: m['provider']! as String,
        label: (m['label'] as String?) ?? '',
        appLabel: (m['appLabel'] as String?) ?? '',
        icon: (m['icon'] as Uint8List?) ?? Uint8List(0),
      );
}
