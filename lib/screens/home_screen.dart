import 'package:flutter/material.dart';

import '../models/preset.dart';
import '../services/native_bridge.dart';
import '../widgets/clock_widget.dart';
import '../widgets/preset_grid.dart';
import '../widgets/wallpaper_background.dart';
import 'settings_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final presets = _demoPresets(context);

    return Scaffold(
      body: WallpaperBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Expanded(child: ClockWidget()),
                    // Медиаплеер живёт в соседней панели (MediaPaneActivity).
                    // Она открывается автоматически при старте; эта кнопка —
                    // способ вернуть её, если пользователь её закрыл или
                    // устройство не поддерживает показ окон рядом
                    // (см. README, раздел "Activity Embedding").
                    IconButton.filledTonal(
                      iconSize: 26,
                      icon: const Icon(Icons.graphic_eq_rounded),
                      onPressed: NativeBridge.openMediaPane,
                    ),
                    const SizedBox(width: 12),
                    IconButton.filledTonal(
                      iconSize: 26,
                      icon: const Icon(Icons.settings_rounded),
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const SettingsScreen(),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Text(
                  'Пресеты',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: SingleChildScrollView(
                    child: PresetGrid(presets: presets),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Демонстрационный набор пресетов. Замените [CarPreset.action] на
  /// реальный запуск приложения/сценария через NativeBridge.
  List<CarPreset> _demoPresets(BuildContext context) {
    void notify(String label) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(label), duration: const Duration(seconds: 1)),
      );
    }

    return [
      CarPreset(
        title: 'Навигация',
        icon: Icons.navigation_rounded,
        action: () => notify('Открыть навигацию'),
      ),
      CarPreset(
        title: 'Музыка',
        icon: Icons.library_music_rounded,
        action: () => notify('Открыть музыку'),
      ),
      CarPreset(
        title: 'Телефон',
        icon: Icons.call_rounded,
        action: () => notify('Открыть телефон'),
      ),
      CarPreset(
        title: 'Камера',
        icon: Icons.videocam_rounded,
        action: () => notify('Открыть камеру заднего вида'),
      ),
      CarPreset(
        title: 'Климат',
        icon: Icons.ac_unit_rounded,
        action: () => notify('Открыть климат-контроль'),
      ),
      CarPreset(
        title: 'Bluetooth',
        icon: Icons.bluetooth_rounded,
        action: () => notify('Открыть Bluetooth'),
      ),
      CarPreset(
        title: 'Погода',
        icon: Icons.wb_sunny_rounded,
        action: () => notify('Открыть погоду'),
      ),
      CarPreset(
        title: 'Ещё',
        icon: Icons.apps_rounded,
        action: () => notify('Все приложения'),
      ),
    ];
  }
}
