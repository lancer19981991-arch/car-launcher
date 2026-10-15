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

/// Три окна на главном экране — в каждом своё приложение,
/// открытое свободным окном поверх этой области.
const List<PresetSlot> kWindowSlots = [
  PresetSlot(id: 'window_1', hint: 'Окно 1', icon: Icons.web_asset_rounded),
  PresetSlot(id: 'window_2', hint: 'Окно 2', icon: Icons.web_asset_rounded),
  PresetSlot(id: 'window_3', hint: 'Окно 3', icon: Icons.web_asset_rounded),
];

/// Ярлыки в доке слева.
const List<PresetSlot> kPresetSlots = [
  PresetSlot(id: 'nav', hint: 'Навигация', icon: Icons.navigation_rounded),
  PresetSlot(id: 'music', hint: 'Музыка', icon: Icons.library_music_rounded),
  PresetSlot(id: 'phone', hint: 'Телефон', icon: Icons.call_rounded),
  PresetSlot(id: 'camera', hint: 'Камера', icon: Icons.videocam_rounded),
  PresetSlot(id: 'radio', hint: 'Радио', icon: Icons.radio_rounded),
  PresetSlot(id: 'video', hint: 'Видео', icon: Icons.ondemand_video_rounded),
  PresetSlot(id: 'weather', hint: 'Погода', icon: Icons.wb_sunny_rounded),
  PresetSlot(id: 'browser', hint: 'Браузер', icon: Icons.public_rounded),
];
