import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Хранит, какое приложение (имя пакета) назначено на каждый пресет.
/// Данные лежат в SharedPreferences и переживают перезапуск устройства.
class PresetService extends ChangeNotifier {
  PresetService._(this._prefs);

  static Future<PresetService> load() async {
    final prefs = await SharedPreferences.getInstance();
    return PresetService._(prefs);
  }

  final SharedPreferences _prefs;

  static String _key(String slotId) => 'preset_app_$slotId';

  /// Пакет приложения, назначенного на слот, или null.
  String? packageFor(String slotId) => _prefs.getString(_key(slotId));

  Future<void> assign(String slotId, String packageName) async {
    await _prefs.setString(_key(slotId), packageName);
    notifyListeners();
  }

  Future<void> clear(String slotId) async {
    await _prefs.remove(_key(slotId));
    notifyListeners();
  }
}
