import 'dart:async';

import 'package:flutter/foundation.dart';

import 'native_bridge.dart';
import 'settings_service.dart';

/// Пакет-«пустышка»: в окне не приложение, а встроенная панель шин.
const String kTpmsPanel = '@tpms';

/// Состояние одного колеса — как его присылает TPMS-приложение
/// (TPMS_USB_MG_Uni и совместимые, broadcast `TPMS_APP_STATE_SEND`).
class TireState {
  const TireState({
    required this.tire,
    required this.pressureRaw,
    required this.temperature,
    required this.unit,
    required this.lowPower,
    required this.leakage,
    required this.noSignal,
    required this.at,
    required this.raw,
  });

  /// Номер колеса, как прислало приложение.
  final int tire;

  /// Давление «как есть» (по виду — кПа: 213 → 2.13 бар).
  final int? pressureRaw;
  final int? temperature;

  /// Единица давления, выбранная в TPMS-приложении (Bar / kPa / Psi …).
  final String unit;
  final bool lowPower;
  final bool leakage;
  final bool noSignal;
  final DateTime at;

  /// Все поля сообщения — для диагностики.
  final Map<String, Object?> raw;

  bool get alarm => leakage || noSignal || lowPower;

  /// Давление для показа в выбранных единицах.
  String get pressureText {
    final p = pressureRaw;
    if (p == null) return '—';
    final u = unit.toLowerCase();
    if (u.contains('psi')) return (p * 0.145038).toStringAsFixed(1).replaceAll('.', ',');
    if (u.contains('kpa')) return '$p';
    // Бар (по умолчанию): кПа / 100. Запятая — как в TPMS-приложении.
    return (p / 100).toStringAsFixed(2).replaceAll('.', ',');
  }

  String get unitShort {
    final u = unit.toLowerCase();
    if (u.contains('psi')) return 'psi';
    if (u.contains('kpa')) return 'кПа';
    return 'бар';
  }

  static TireState? fromMap(Map<Object?, Object?> m) {
    int? toInt(Object? v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}');
    bool toBool(Object? v) => v == true || v == 1 || v == 'true';
    final tire = toInt(m['tires']);
    if (tire == null) return null;
    return TireState(
      tire: tire,
      pressureRaw: toInt(m['airpressure']),
      temperature: toInt(m['temperature']),
      unit: '${m['presunit'] ?? 'Bar'}',
      lowPower: toBool(m['lowpower']),
      leakage: toBool(m['leakage']),
      noSignal: toBool(m['nosignal']),
      at: DateTime.now(),
      raw: {for (final e in m.entries) '${e.key}': e.value},
    );
  }
}

/// Данные шин, пойманные нативной стороной из broadcast TPMS-приложения.
class TpmsService extends ChangeNotifier {
  TpmsService(this._settings) {
    NativeBridge.onTpms = _onMessage;
    NativeBridge.ensureIncomingHandler();
    _loadCached();
    _settings.addListener(_sendWatchdog);
    _sendWatchdog();
    // Раз в 30 с перерисовать «сколько секунд назад» и потерю связи.
    _tick = Timer.periodic(const Duration(seconds: 30), (_) => notifyListeners());
  }

  final SettingsService _settings;
  String? _wdSent;

  /// Настройки сторожа — нативной стороне (она и следит, и перезапускает).
  void _sendWatchdog() {
    final on = _settings.tpmsWatchdogEnabled && _settings.tpmsWatchdogPkg != null;
    final pkg = on ? _settings.tpmsWatchdogPkg : null;
    final usb = on ? _settings.tpmsWatchdogUsb : null;
    final min = _settings.tpmsWatchdogMinutes;
    final key = '$pkg|$usb|$min';
    if (key == _wdSent) return;
    _wdSent = key;
    NativeBridge.tpmsWatchdog(pkg: pkg, usb: usb, minutes: min);
  }

  final Map<int, TireState> _tires = {};
  Timer? _tick;

  /// Последнее состояние по номеру колеса.
  Map<int, TireState> get tires => Map.unmodifiable(_tires);

  /// Когда пришло последнее сообщение.
  DateTime? get lastAt =>
      _tires.values.isEmpty ? null : _tires.values.map((t) => t.at).reduce((a, b) => a.isAfter(b) ? a : b);

  /// Названия мест — в порядке [byPosition].
  static const positionNames = ['Перед-лево', 'Перед-право', 'Зад-лево', 'Зад-право'];

  /// Четыре колеса по местам: ПЛ, ПП, ЗЛ, ЗП. [map] — номер колеса для
  /// каждого места, выбранный пользователем (null — автоматически: четыре
  /// наименьших номера по порядку, считая с 0 или с 1).
  List<TireState?> byPosition(List<int?> map) {
    final keys = _tires.keys.toList()..sort();
    final base = keys.isEmpty ? 0 : (keys.first >= 1 ? 1 : 0);
    return [
      for (var i = 0; i < 4; i++) _tires[(i < map.length ? map[i] : null) ?? base + i],
    ];
  }

  Future<void> _loadCached() async {
    for (final m in await NativeBridge.getTpmsState()) {
      final t = TireState.fromMap(m);
      if (t != null) _tires[t.tire] = t;
    }
    notifyListeners();
  }

  void _onMessage(Map<Object?, Object?> m) {
    final t = TireState.fromMap(m);
    if (t == null) return;
    _tires[t.tire] = t;
    notifyListeners();
  }

  @override
  void dispose() {
    _tick?.cancel();
    NativeBridge.onTpms = null;
    _settings.removeListener(_sendWatchdog);
    super.dispose();
  }
}
