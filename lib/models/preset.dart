import 'package:flutter/material.dart';

/// Слот быстрого запуска на главном экране.
///
/// Какое приложение открывает слот, выбирает сам пользователь
/// (долгое нажатие на пресет) — выбор хранится в PresetService.
/// [hint] и [icon] показываются, пока приложение не назначено.
class PresetSlot {
  const PresetSlot({
    required this.id,
    required this.hint,
    required this.icon,
  });

  /// Ключ для хранения выбора. Не менять у существующих слотов —
  /// иначе пользовательские назначения потеряются.
  final String id;
  final String hint;
  final IconData icon;
}

/// Окна на главном экране (до четырёх) — в каждом своё приложение.
/// Положение и размер каждого окна хранятся отдельно (WindowRect).
const List<PresetSlot> kWindowSlots = [
  PresetSlot(id: 'window_1', hint: 'Окно 1', icon: Icons.web_asset_rounded),
  PresetSlot(id: 'window_2', hint: 'Окно 2', icon: Icons.web_asset_rounded),
  PresetSlot(id: 'window_3', hint: 'Окно 3', icon: Icons.web_asset_rounded),
  PresetSlot(id: 'window_4', hint: 'Окно 4', icon: Icons.web_asset_rounded),
];

PresetSlot slotById(String id) =>
    kWindowSlots.firstWhere((s) => s.id == id, orElse: () => kWindowSlots.first);

