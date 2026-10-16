import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Что назначено каждому окну: приложение (имя пакета) или виджет
/// рабочего стола (id + название). Одно исключает другое. Данные лежат
/// в SharedPreferences и переживают перезапуск устройства.
class PresetService extends ChangeNotifier {
  PresetService._(this._prefs);

  static Future<PresetService> load() async {
    final prefs = await SharedPreferences.getInstance();
    return PresetService._(prefs);
  }

  final SharedPreferences _prefs;

  static String _appKey(String slotId) => 'preset_app_$slotId';
  static String _widgetKey(String slotId) => 'preset_widget_$slotId';
  static String _widgetLabelKey(String slotId) => 'preset_widget_label_$slotId';

  /// Пакет приложения, назначенного окну, или null.
  String? packageFor(String slotId) => _prefs.getString(_appKey(slotId));

  /// Id виджета, назначенного окну, или null.
  int? widgetFor(String slotId) => _prefs.getInt(_widgetKey(slotId));

  String? widgetLabelFor(String slotId) => _prefs.getString(_widgetLabelKey(slotId));

  /// Назначить приложение (виджет окна при этом снимается).
  Future<void> assign(String slotId, String packageName) async {
    await _prefs.setString(_appKey(slotId), packageName);
    await _prefs.remove(_widgetKey(slotId));
    await _prefs.remove(_widgetLabelKey(slotId));
    notifyListeners();
  }

  /// Назначить виджет (приложение окна при этом снимается).
  Future<void> assignWidget(String slotId, int widgetId, String label) async {
    await _prefs.setInt(_widgetKey(slotId), widgetId);
    await _prefs.setString(_widgetLabelKey(slotId), label);
    await _prefs.remove(_appKey(slotId));
    notifyListeners();
  }

  Future<void> clear(String slotId) async {
    await _prefs.remove(_appKey(slotId));
    await _prefs.remove(_widgetKey(slotId));
    await _prefs.remove(_widgetLabelKey(slotId));
    notifyListeners();
  }
}
