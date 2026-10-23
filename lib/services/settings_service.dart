import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/weather_place.dart';
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
  static const _kKeepInLauncherKey = 'keep_windows_in_launcher';
  static const _kBorderColorKey = 'window_border_color';
  static const _kBorderWidthKey = 'window_border_width';
  static const _kCornerRadiusKey = 'window_corner_radius';
  static const _kGlowKey = 'window_glow';
  static const _kWeatherOnKey = 'weather_enabled';
  static const _kWeatherCityKey = 'weather_city';

  /// Показывать погоду в пилюле.
  bool get weatherEnabled => _prefs.getBool(_kWeatherOnKey) ?? true;

  Future<void> setWeatherEnabled(bool v) async {
    await _prefs.setBool(_kWeatherOnKey, v);
    notifyListeners();
  }

  /// Город для погоды; null — по местоположению устройства.
  WeatherPlace? get weatherCity {
    final raw = _prefs.getString(_kWeatherCityKey);
    if (raw == null) return null;
    try {
      return WeatherPlace.fromJson(jsonDecode(raw));
    } catch (_) {
      return null;
    }
  }

  Future<void> setWeatherCity(WeatherPlace? p) async {
    if (p == null) {
      await _prefs.remove(_kWeatherCityKey);
    } else {
      await _prefs.setString(_kWeatherCityKey, jsonEncode(p.toJson()));
    }
    notifyListeners();
  }

  /// Скругление углов окон (лог. px).
  double get windowCornerRadius => (_prefs.getDouble(_kCornerRadiusKey) ?? 16.0).clamp(0.0, 40.0);

  Future<void> setWindowCornerRadius(double v) async {
    await _prefs.setDouble(_kCornerRadiusKey, v.clamp(0.0, 40.0));
    notifyListeners();
  }

  /// Сила свечения вокруг контура: 0 — нет, 1 — максимум.
  double get windowGlow => (_prefs.getDouble(_kGlowKey) ?? 0.5).clamp(0.0, 1.0);

  Future<void> setWindowGlow(double v) async {
    await _prefs.setDouble(_kGlowKey, v.clamp(0.0, 1.0));
    notifyListeners();
  }

  /// Цвета подсветки контура окон на выбор.
  static const List<Color> borderColors = [
    Color(0xFFFFFFFF), // белый
    Color(0xFFB0BEC5), // серебристый
    Color(0xFF80D8FF), // ледяной
    Color(0xFF40C4FF), // небесный
    Color(0xFF00E5FF), // бирюзовый
    Color(0xFF1DE9B6), // аквамарин
    Color(0xFF2979FF), // синий
    Color(0xFF3D5AFE), // индиго
    Color(0xFF651FFF), // сине-фиолетовый
    Color(0xFFD500F9), // фиолетовый
    Color(0xFFE040FB), // сиреневый
    Color(0xFFFF4081), // малиновый
    Color(0xFFF50057), // розовый
    Color(0xFFFF1744), // красный
    Color(0xFFFF6E40), // коралловый
    Color(0xFFFF9100), // оранжевый
    Color(0xFFFFC400), // янтарный
    Color(0xFFFFEA00), // жёлтый
    Color(0xFFC6FF00), // лайм
    Color(0xFF76FF03), // салатовый
    Color(0xFF00E676), // зелёный
    Color(0xFF69F0AE), // мятный
  ];

  /// Цвет подсветки контура окон; null — подсветки нет (по умолчанию).
  Color? get windowBorderColor {
    final v = _prefs.getInt(_kBorderColorKey);
    return v == null ? null : Color(v);
  }

  Future<void> setWindowBorderColor(Color? c) async {
    if (c == null) {
      await _prefs.remove(_kBorderColorKey);
    } else {
      await _prefs.setInt(_kBorderColorKey, c.toARGB32());
    }
    notifyListeners();
  }

  /// Толщина контура (лог. px).
  double get windowBorderWidth => (_prefs.getDouble(_kBorderWidthKey) ?? 3.0).clamp(1.0, 8.0);

  Future<void> setWindowBorderWidth(double v) async {
    await _prefs.setDouble(_kBorderWidthKey, v.clamp(1.0, 8.0));
    notifyListeners();
  }

  /// Не перезапускать окна при открытии настроек/меню/выбора приложения
  /// (только прятать). По умолчанию выключено — так стабильнее.
  bool get keepWindowsInLauncher => _prefs.getBool(_kKeepInLauncherKey) ?? false;

  Future<void> setKeepWindowsInLauncher(bool v) async {
    await _prefs.setBool(_kKeepInLauncherKey, v);
    notifyListeners();
  }

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
