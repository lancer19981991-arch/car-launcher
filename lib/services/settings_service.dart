import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/window_rect.dart';

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
  static const _kBottomReserveKey = 'bottom_reserve';
  static const _kTopReserveKey = 'top_reserve';
  static const _kLayoutKey = 'window_layout_v1';
  static const _kPillKey = 'pill_align';
  static const _kKeepBgKey = 'keep_windows_bg';

  /// Не закрывать приложения в окнах, когда лаунчер уходит в фон.
  /// Ключ читается и нативной стороной (MainActivity.onPause).
  bool get keepWindowsInBackground => _prefs.getBool(_kKeepBgKey) ?? false;

  Future<void> setKeepWindowsInBackground(bool v) async {
    await _prefs.setBool(_kKeepBgKey, v);
    notifyListeners();
  }

  /// Положение «пилюли» с часами: доли свободного места по X и Y
  /// (0 — левый/верхний край, 1 — правый/нижний). По умолчанию — правый
  /// верхний угол.
  Offset get pillAlign {
    final raw = _prefs.getString(_kPillKey);
    if (raw != null) {
      final parts = raw.split(',');
      if (parts.length == 2) {
        final x = double.tryParse(parts[0]);
        final y = double.tryParse(parts[1]);
        if (x != null && y != null) return Offset(x.clamp(0.0, 1.0), y.clamp(0.0, 1.0));
      }
    }
    return const Offset(1, 0);
  }

  Future<void> setPillAlign(Offset a) async {
    await _prefs.setString(_kPillKey, '${a.dx.clamp(0.0, 1.0)},${a.dy.clamp(0.0, 1.0)}');
    notifyListeners();
  }

  /// Раскладка окон: где стоит и какого размера каждое окно.
  /// Если свободной раскладки ещё нет — строим её из прежних настроек
  /// (окна стопкой, верхнее крупнее), чтобы у пользователя ничего не
  /// поменялось после обновления.
  List<WindowRect> get windowLayout {
    final saved = WindowRect.decodeList(_prefs.getString(_kLayoutKey));
    if (saved != null) return saved;
    return defaultLayout(windowCount, windowWeights);
  }

  Future<void> setWindowLayout(List<WindowRect> layout) async {
    await _prefs.setString(_kLayoutKey, WindowRect.encodeList(layout));
    notifyListeners();
  }

  Future<void> resetWindowLayout() async {
    await _prefs.remove(_kLayoutKey);
    await _prefs.remove(_kWeightsKey);
    await _prefs.remove(_kWindowCountKey);
    notifyListeners();
  }

  /// Окна стопкой по вертикали во всю ширину, высоты по весам.
  static List<WindowRect> defaultLayout(int count, List<double> weights) {
    final ids = ['window_1', 'window_2', 'window_3'];
    final ws = weights.take(count).toList();
    final total = ws.fold<double>(0, (a, b) => a + b);
    var y = 0.0;
    final out = <WindowRect>[];
    for (var i = 0; i < count; i++) {
      final h = ws[i] / total;
      out.add(WindowRect(slotId: ids[i], x: 0, y: y, w: 1, h: h));
      y += h;
    }
    return out;
  }

  /// Запас снизу (лог. px): чтобы окна не заезжали под климат-панель.
  double get bottomReserve => (_prefs.getDouble(_kBottomReserveKey) ?? 150.0).clamp(0.0, 400.0);

  Future<void> setBottomReserve(double v) async {
    await _prefs.setDouble(_kBottomReserveKey, v.clamp(0.0, 400.0));
    notifyListeners();
  }

  /// Запас сверху (лог. px): под системный статус-бар, если он есть.
  double get topReserve => (_prefs.getDouble(_kTopReserveKey) ?? 0.0).clamp(0.0, 200.0);

  Future<void> setTopReserve(double v) async {
    await _prefs.setDouble(_kTopReserveKey, v.clamp(0.0, 200.0));
    notifyListeners();
  }

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
