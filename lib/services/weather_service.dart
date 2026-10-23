import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/weather_place.dart';
import 'native_bridge.dart';
import 'settings_service.dart';

/// Текущая погода для пилюли: значок + температура. Источник — Open-Meteo
/// (бесплатно, без ключа). Место — выбранный в настройках город или
/// последнее известное местоположение устройства (GPS магнитолы).
class WeatherService extends ChangeNotifier {
  WeatherService(this._settings) {
    _settings.addListener(_onSettings);
    _lastKey = _settingsKey();
    if (_settings.weatherEnabled) refresh();
    _timer = Timer.periodic(const Duration(minutes: 20), (_) => refresh());
  }

  final SettingsService _settings;
  Timer? _timer;
  String? _lastKey;
  bool _loading = false;
  DateTime? _updatedAt;

  /// Текст для пилюли, например «☁ +5°»; null — показывать нечего.
  String? text;

  /// Что пошло не так (для настроек); null — всё хорошо.
  String? error;

  /// Название места, для которого показана погода.
  String? placeName;

  /// Что показывать в пилюле прямо сейчас.
  String? get pillText => _settings.weatherEnabled ? text : null;

  String _settingsKey() =>
      '${_settings.weatherEnabled}|${_settings.weatherCity?.lat}|${_settings.weatherCity?.lon}';

  void _onSettings() {
    final key = _settingsKey();
    if (key == _lastKey) return;
    _lastKey = key;
    text = null;
    notifyListeners();
    if (_settings.weatherEnabled) refresh();
  }

  /// Обновить, если данные старше 10 минут (при возврате на экран).
  void refreshIfStale() {
    final t = _updatedAt;
    if (t == null || DateTime.now().difference(t) > const Duration(minutes: 10)) refresh();
  }

  Future<void> refresh() async {
    if (!_settings.weatherEnabled || _loading) return;
    _loading = true;
    try {
      double lat, lon;
      final city = _settings.weatherCity;
      if (city != null) {
        lat = city.lat;
        lon = city.lon;
        placeName = city.name;
      } else {
        final loc = await NativeBridge.getLastLocation();
        if (loc == null) {
          error = 'Местоположение неизвестно — выберите город вручную';
          notifyListeners();
          return;
        }
        lat = loc.$1;
        lon = loc.$2;
        placeName = 'по местоположению';
      }
      final data = await _getJson(Uri.https('api.open-meteo.com', '/v1/forecast', {
        'latitude': lat.toStringAsFixed(3),
        'longitude': lon.toStringAsFixed(3),
        'current': 'temperature_2m,weather_code,is_day',
      }));
      final cur = (data as Map)['current'] as Map;
      final t = (cur['temperature_2m'] as num).round();
      final code = (cur['weather_code'] as num).toInt();
      final day = (cur['is_day'] as num?)?.toInt() != 0;
      text = '${_icon(code, day)} ${t > 0 ? '+' : ''}$t°';
      error = null;
      _updatedAt = DateTime.now();
    } catch (e) {
      // Старое значение оставляем — лучше чуть устаревшая погода, чем пусто.
      error = 'Не удалось получить погоду (нет интернета?)';
    } finally {
      _loading = false;
      notifyListeners();
      // Сразу после включения магнитолы сети/GPS ещё может не быть —
      // пока погоды нет, пробуем чаще.
      if (text == null) {
        _retry?.cancel();
        _retry = Timer(const Duration(minutes: 1), refresh);
      }
    }
  }

  Timer? _retry;

  /// Поиск города по названию.
  static Future<List<WeatherPlace>> searchCity(String query) async {
    final data = await _getJson(Uri.https('geocoding-api.open-meteo.com', '/v1/search', {
      'name': query,
      'count': '8',
      'language': 'ru',
    }));
    final results = (data as Map)['results'];
    if (results is! List) return const [];
    return [
      for (final r in results.whereType<Map>())
        if (r['latitude'] is num && r['longitude'] is num && r['name'] is String)
          WeatherPlace(
            name: r['name'] as String,
            region: [r['admin1'], r['country']].whereType<String>().join(', '),
            lat: (r['latitude'] as num).toDouble(),
            lon: (r['longitude'] as num).toDouble(),
          ),
    ];
  }

  static Future<Object?> _getJson(Uri uri) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      final req = await client.getUrl(uri);
      final res = await req.close().timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) throw HttpException('HTTP ${res.statusCode}');
      return jsonDecode(await res.transform(utf8.decoder).join());
    } finally {
      client.close();
    }
  }

  /// Значок по коду погоды WMO.
  static String _icon(int code, bool day) {
    if (code == 0) return day ? '☀' : '☾';
    if (code <= 2) return day ? '⛅' : '☁';
    if (code == 3) return '☁';
    if (code == 45 || code == 48) return '🌫';
    if (code >= 51 && code <= 67) return '🌧';
    if (code >= 71 && code <= 77) return '❄';
    if (code >= 80 && code <= 82) return '🌧';
    if (code == 85 || code == 86) return '❄';
    if (code >= 95) return '⛈';
    return '☁';
  }

  @override
  void dispose() {
    _timer?.cancel();
    _retry?.cancel();
    _settings.removeListener(_onSettings);
    super.dispose();
  }
}
