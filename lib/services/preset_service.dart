import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/layout_preset.dart';
import '../models/preset.dart';
import '../models/window_rect.dart';

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

  // ---------- сохранённые пресеты (раскладка + содержимое окон) ----------

  static const _kSavedKey = 'layout_presets_v1';

  List<LayoutPreset> get savedPresets => LayoutPreset.decodeList(_prefs.getString(_kSavedKey));

  Future<void> _writeSaved(List<LayoutPreset> list) async {
    await _prefs.setString(_kSavedKey, LayoutPreset.encodeList(list));
    notifyListeners();
  }

  /// Снимок текущего состояния под именем [name].
  LayoutPreset snapshot(String name, List<WindowRect> layout, Offset pill) {
    final slots = <String, SlotContent>{};
    for (final r in layout) {
      final widgetId = widgetFor(r.slotId);
      final pkg = packageFor(r.slotId);
      if (widgetId != null) {
        slots[r.slotId] = SlotContent.widget(widgetId, widgetLabelFor(r.slotId));
      } else if (pkg != null) {
        slots[r.slotId] = SlotContent.app(pkg);
      }
    }
    return LayoutPreset(name: name, layout: [...layout], pill: pill, slots: slots);
  }

  /// Добавить пресет или заменить пресет с индексом [index].
  /// Возвращает id виджетов, которые больше нигде не нужны.
  Future<List<int>> savePreset(LayoutPreset preset, {int? index}) async {
    final list = savedPresets;
    final old = index != null && index >= 0 && index < list.length ? list[index] : null;
    if (old != null) {
      list[index!] = preset;
    } else {
      list.add(preset);
    }
    await _writeSaved(list);
    return old == null ? const [] : _unused(old.widgetIds);
  }

  Future<void> renamePreset(int index, String name) async {
    final list = savedPresets;
    if (index < 0 || index >= list.length) return;
    list[index] = list[index].copyWith(name: name);
    await _writeSaved(list);
  }

  /// Удалить пресет. Возвращает id виджетов, которые больше нигде не нужны.
  Future<List<int>> deletePreset(int index) async {
    final list = savedPresets;
    if (index < 0 || index >= list.length) return const [];
    final removed = list.removeAt(index);
    await _writeSaved(list);
    return _unused(removed.widgetIds);
  }

  /// Расставить содержимое окон из пресета. Раскладку и пилюлю ставит
  /// SettingsService. Возвращает id виджетов, которые больше нигде не нужны.
  Future<List<int>> applyContents(LayoutPreset preset) async {
    final before = [for (final s in kWindowSlots) widgetFor(s.id)].whereType<int>().toList();
    for (final s in kWindowSlots) {
      final c = preset.slots[s.id];
      await _prefs.remove(_appKey(s.id));
      await _prefs.remove(_widgetKey(s.id));
      await _prefs.remove(_widgetLabelKey(s.id));
      if (c?.packageName != null) {
        await _prefs.setString(_appKey(s.id), c!.packageName!);
      } else if (c?.widgetId != null) {
        await _prefs.setInt(_widgetKey(s.id), c!.widgetId!);
        if (c.widgetLabel != null) await _prefs.setString(_widgetLabelKey(s.id), c.widgetLabel!);
      }
    }
    notifyListeners();
    return _unused(before);
  }

  /// Виджет ещё нужен: стоит в окне сейчас или в каком-то пресете.
  /// Такой виджет нельзя удалять из системы — пресет перестанет работать.
  bool widgetInUse(int id) =>
      kWindowSlots.any((s) => widgetFor(s.id) == id) ||
      savedPresets.any((p) => p.widgetIds.contains(id));

  List<int> _unused(Iterable<int> ids) => ids.toSet().where((id) => !widgetInUse(id)).toList();
}
