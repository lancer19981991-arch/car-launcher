import 'dart:convert';

import 'package:flutter/painting.dart';

import 'window_rect.dart';

/// Что стоит в одном окне пресета: приложение ИЛИ виджет.
class SlotContent {
  const SlotContent.app(String this.packageName)
      : widgetId = null,
        widgetLabel = null;

  const SlotContent.widget(int this.widgetId, this.widgetLabel) : packageName = null;

  final String? packageName;
  final int? widgetId;
  final String? widgetLabel;

  Map<String, Object> toJson() => packageName != null
      ? {'app': packageName!}
      : {'widget': widgetId!, if (widgetLabel != null) 'label': widgetLabel!};

  static SlotContent? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final app = raw['app'];
    if (app is String) return SlotContent.app(app);
    final widget = raw['widget'];
    final label = raw['label'];
    if (widget is int) return SlotContent.widget(widget, label is String ? label : null);
    return null;
  }
}

/// Сохранённый пресет: раскладка окон, положение пилюли и содержимое
/// каждого окна. Пользователь переключается между пресетами из меню
/// пилюли (например, «Город» / «Трасса»).
class LayoutPreset {
  const LayoutPreset({
    required this.name,
    required this.layout,
    required this.pill,
    required this.slots,
  });

  final String name;
  final List<WindowRect> layout;
  final Offset pill;
  final Map<String, SlotContent> slots;

  LayoutPreset copyWith({String? name}) =>
      LayoutPreset(name: name ?? this.name, layout: layout, pill: pill, slots: slots);

  Iterable<int> get widgetIds => slots.values.map((s) => s.widgetId).whereType<int>();

  Map<String, Object> toJson() => {
        'name': name,
        'layout': [for (final r in layout) r.toJson()],
        'pill': [pill.dx, pill.dy],
        'slots': {for (final e in slots.entries) e.key: e.value.toJson()},
      };

  static LayoutPreset? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final name = raw['name'];
    final rawLayout = raw['layout'];
    if (name is! String || rawLayout is! List) return null;
    final layout = rawLayout.map(WindowRect.fromJson).whereType<WindowRect>().toList();
    var pill = const Offset(1, 0);
    final rawPill = raw['pill'];
    if (rawPill is List && rawPill.length == 2 && rawPill[0] is num && rawPill[1] is num) {
      pill = Offset(
        (rawPill[0] as num).toDouble().clamp(0.0, 1.0),
        (rawPill[1] as num).toDouble().clamp(0.0, 1.0),
      );
    }
    final slots = <String, SlotContent>{};
    final rawSlots = raw['slots'];
    if (rawSlots is Map) {
      for (final e in rawSlots.entries) {
        final c = SlotContent.fromJson(e.value);
        if (e.key is String && c != null) slots[e.key as String] = c;
      }
    }
    return LayoutPreset(name: name, layout: layout, pill: pill, slots: slots);
  }

  static String encodeList(List<LayoutPreset> list) =>
      jsonEncode([for (final p in list) p.toJson()]);

  static List<LayoutPreset> decodeList(String? raw) {
    if (raw == null) return [];
    try {
      final data = jsonDecode(raw);
      if (data is! List) return [];
      return data.map(LayoutPreset.fromJson).whereType<LayoutPreset>().toList();
    } catch (_) {
      return [];
    }
  }
}
