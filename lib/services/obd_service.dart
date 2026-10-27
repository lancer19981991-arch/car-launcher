import 'package:flutter/foundation.dart';

import 'native_bridge.dart';
import 'settings_service.dart';

/// Пакет-«пустышка»: в окне встроенная панель приборов OBD.
const String kObdPanel = '@obd';

/// Данные с OBD-адаптера ELM327 (Bluetooth): напряжение сети и
/// температура двигателя. Подключение ведёт нативная сторона (ObdClient),
/// только пока лаунчер на экране.
class ObdService extends ChangeNotifier {
  ObdService(this._settings) {
    NativeBridge.onObd = _onUpdate;
    NativeBridge.ensureIncomingHandler();
    _settings.addListener(_apply);
    _apply();
  }

  final SettingsService _settings;
  String? _applied;

  /// off / connecting / connected / error / paused.
  String state = 'off';
  String? message;
  double? voltage;
  int? coolant;

  /// Блок двигателя не отвечает (зажигание выключено).
  bool ecuSilent = false;
  DateTime? lastAt;

  void _apply() {
    final addr = _settings.obdEnabled ? _settings.obdAddress : null;
    final key = addr ?? '';
    if (key == _applied) return;
    _applied = key;
    if (addr == null) {
      voltage = null;
      coolant = null;
    }
    NativeBridge.obdSetAddress(addr);
  }

  void _onUpdate(Map<Object?, Object?> m) {
    state = '${m['state'] ?? 'off'}';
    message = m['message'] as String?;
    if (m.containsKey('voltage')) {
      final v = m['voltage'];
      voltage = v is num ? v.toDouble() : voltage;
      final c = m['coolant'];
      coolant = c is num ? c.toInt() : null;
      ecuSilent = m['ecuSilent'] == true;
      lastAt = DateTime.now();
    }
    notifyListeners();
  }

  String get statusText {
    switch (state) {
      case 'connected':
        return ecuSilent ? 'Подключено, двигатель не отвечает (зажигание выкл.?)' : 'Подключено';
      case 'connecting':
        return 'Подключение к адаптеру…';
      case 'error':
        return message ?? 'Ошибка подключения';
      case 'paused':
        return 'Адаптер отпущен (лаунчер не на экране)';
      default:
        return 'Выключено';
    }
  }

  @override
  void dispose() {
    _settings.removeListener(_apply);
    NativeBridge.onObd = null;
    super.dispose();
  }
}
