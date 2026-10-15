import 'dart:typed_data';

/// Установленное на устройстве приложение, которое можно запустить
/// (приходит с нативной стороны — MainActivity.loadInstalledApps).
class AppInfo {
  const AppInfo({
    required this.packageName,
    required this.label,
    required this.icon,
  });

  final String packageName;
  final String label;

  /// Иконка приложения в PNG.
  final Uint8List icon;

  factory AppInfo.fromMap(Map<Object?, Object?> map) {
    return AppInfo(
      packageName: map['packageName']! as String,
      label: map['label']! as String,
      icon: map['icon']! as Uint8List,
    );
  }
}
