import 'package:flutter/foundation.dart';

import 'native_bridge.dart';

/// Двери, багажник и капот — от CAN-декодера магнитолы FYT (служба
/// com.syu.ms, модуль CANBUS). Коды по умолчанию — как в разборе прошивки
/// FYT: 0 капот, 1 ПЛ, 2 ПП, 3 ЗЛ, 4 ЗП, 5 багажник (значение ≠ 0 —
/// открыто). У другой машины коды могут отличаться — их видно на экране
/// разведки, там же журнал всех сообщений шины.
class DoorsService extends ChangeNotifier {
  DoorsService() {
    NativeBridge.onCanbus = _onUpdate;
    NativeBridge.onCanbusState = (s) {
      state = s;
      notifyListeners();
    };
    NativeBridge.ensureIncomingHandler();
    _loadSnapshot();
  }

  static const parts = ['hood', 'fl', 'fr', 'rl', 'rr', 'trunk'];
  static const codes = {'hood': 0, 'fl': 1, 'fr': 2, 'rl': 3, 'rr': 4, 'trunk': 5};
  static const names = {
    'hood': 'капот',
    'fl': 'передняя левая',
    'fr': 'передняя правая',
    'rl': 'задняя левая',
    'rr': 'задняя правая',
    'trunk': 'багажник',
  };

  String state = 'не подключено';

  /// Последние значения по коду CAN.
  final Map<int, List<int>> values = {};

  /// Журнал сообщений шины (новые в конце) — для разведки.
  final List<({DateTime time, int code, List<int> ints})> events = [];

  /// Когда код менялся последний раз — для подсветки в таблице разведки.
  final Map<int, DateTime> changedAt = {};

  /// Тест анимации без машины: принудительно открытые части.
  final Set<String> simulated = {};

  Future<void> _loadSnapshot() async {
    final snap = await NativeBridge.canbusSnapshot();
    if (snap == null) return;
    state = '${snap['state'] ?? state}';
    final v = snap['values'];
    if (v is Map) {
      for (final e in v.entries) {
        final code = int.tryParse('${e.key}');
        final ints = e.value;
        if (code != null && ints is List) values[code] = ints.whereType<num>().map((x) => x.toInt()).toList();
      }
    }
    notifyListeners();
  }

  void _onUpdate(Map<Object?, Object?> m) {
    final code = m['code'];
    if (code is! int) return;
    final raw = m['ints'];
    final ints = raw is List ? raw.whereType<num>().map((x) => x.toInt()).toList() : <int>[];
    final prev = values[code];
    values[code] = ints;
    if (prev == null || !listEquals(prev, ints)) {
      events.add((time: DateTime.now(), code: code, ints: ints));
      if (prev != null) changedAt[code] = DateTime.now();
      if (events.length > 500) events.removeRange(0, events.length - 500);
    }
    notifyListeners();
  }

  bool isOpen(String part) {
    if (simulated.contains(part)) return true;
    final v = values[codes[part]];
    return v != null && v.isNotEmpty && v.first != 0;
  }

  /// Подпись под машиной: что открыто.
  String? get label {
    final open = parts.where(isOpen).toList();
    if (open.isEmpty) return null;
    final doors = open.where((p) => p != 'hood' && p != 'trunk').toList();
    final bits = <String>[];
    if (doors.length == 1) {
      bits.add(doors.first == 'fl' ? 'Открыта водительская дверь' : 'Открыта ${names[doors.first]} дверь');
    } else if (doors.length > 1) {
      bits.add('Открыты ${doors.length} ${doors.length < 5 ? 'двери' : 'дверей'}');
    }
    if (open.contains('trunk')) bits.add(bits.isEmpty ? 'Открыт багажник' : 'багажник');
    if (open.contains('hood')) bits.add(bits.isEmpty ? 'Открыт капот' : 'капот');
    return bits.join(', ');
  }

  void toggleSimulated(String part) {
    simulated.contains(part) ? simulated.remove(part) : simulated.add(part);
    notifyListeners();
  }
}
