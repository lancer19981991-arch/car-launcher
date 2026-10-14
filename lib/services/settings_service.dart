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

  final SharedPreferences _prefs;
  late ThemeMode _themeMode;

  ThemeMode get themeMode => _themeMode;

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
