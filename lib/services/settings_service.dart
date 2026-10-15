import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Хранит пользовательские настройки лаунчера на устройстве
/// (тема, выбранный вариант фона и т.п.) через SharedPreferences.
class SettingsService extends ChangeNotifier {
  SettingsService._(this._prefs) {
    _themeMode = _readThemeMode();
  }

  static Future<SettingsService> load() async {
    final prefs = await SharedPreferences.getInstance();
    return SettingsService._(prefs);
  }

  static const _kThemeModeKey = 'theme_mode';
  static const _kWindowCountKey = 'window_count';
  static const _kWeightsKey = 'window_weights';

  final SharedPreferences _prefs;
  late ThemeMode _themeMode;

  ThemeMode get themeMode => _themeMode;

  /// Сколько окон показывать (1..3).
  int get windowCount {
    final v = _prefs.getInt(_kWindowCountKey) ?? 3;
    return v.clamp(1, 3);
  }

  Future<void> setWindowCount(int count) async {
    await _prefs.setInt(_kWindowCountKey, count.clamp(1, 3));
    notifyListeners();
  }

  /// Вес (доля высоты) каждого из трёх окон. По умолчанию верхнее
  /// (навигация) крупнее. Список всегда длины 3.
  List<double> get windowWeights {
    final raw = _prefs.getStringList(_kWeightsKey);
    if (raw == null || raw.length != 3) return const [2.0, 1.0, 1.0];
    final parsed = raw.map((e) => double.tryParse(e) ?? 1.0).toList();
    // Защита от нулей/отрицательных.
    return [for (final w in parsed) w < 0.3 ? 0.3 : w];
  }

  Future<void> setWindowWeights(List<double> weights) async {
    final clamped = [for (final w in weights) (w < 0.3 ? 0.3 : w)];
    await _prefs.setStringList(
      _kWeightsKey,
      [for (final w in clamped) w.toStringAsFixed(3)],
    );
    notifyListeners();
  }

  ThemeMode _readThemeMode() {
    final stored = _prefs.getString(_kThemeModeKey);
    switch (stored) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    await _prefs.setString(_kThemeModeKey, mode.name);
    notifyListeners();
  }
}
