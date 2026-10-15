import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/app_info.dart';
import '../models/preset.dart';
import '../services/native_bridge.dart';
import '../services/preset_service.dart';
import '../widgets/clock_widget.dart';
import '../widgets/preset_grid.dart';
import '../widgets/wallpaper_background.dart';
import 'app_picker_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  /// Установленные приложения по имени пакета — нужны, чтобы показать
  /// на плитке настоящую иконку и название назначенного приложения.
  Map<String, AppInfo> _apps = const {};
  bool _appsLoaded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadApps();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Возврат на домашний экран из другого приложения — хороший момент
  // обновить список: пока пользователь был там, что-то могли установить
  // или удалить.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _loadApps();
  }

  Future<void> _loadApps() async {
    try {
      final list = await NativeBridge.getInstalledApps();
      if (!mounted) return;
      setState(() {
        _apps = {for (final app in list) app.packageName: app};
        _appsLoaded = true;
      });
    } catch (_) {
      // Оставляем прежний список — плитки покажут подсказки вместо иконок.
    }
  }

  Future<void> _pickApp(PresetSlot slot) async {
    final presets = context.read<PresetService>();
    final app = await Navigator.of(context).push<AppInfo>(
      MaterialPageRoute(
        builder: (_) => AppPickerScreen(title: 'Пресет «${slot.hint}»'),
      ),
    );
    if (app == null) return;
    await presets.assign(slot.id, app.packageName);
    if (!mounted) return;
    setState(() => _apps = {..._apps, app.packageName: app});
  }

  Future<void> _onTap(PresetSlot slot) async {
    final pkg = context.read<PresetService>().packageFor(slot.id);
    if (pkg == null) {
      await _pickApp(slot);
      return;
    }
    final launched = await NativeBridge.launchApp(pkg);
    if (launched || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Приложение не найдено — выберите другое')),
    );
    await _pickApp(slot);
  }

  void _onLongPress(PresetSlot slot) {
    final presets = context.read<PresetService>();
    final assigned = presets.packageFor(slot.id) != null;
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.apps_rounded),
              title: Text(assigned ? 'Выбрать другое приложение' : 'Выбрать приложение'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _pickApp(slot);
              },
            ),
            if (assigned)
              ListTile(
                leading: const Icon(Icons.clear_rounded),
                title: const Text('Очистить пресет'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  presets.clear(slot.id);
                },
              ),
          ],
        ),
      ),
    );
  }

  PresetTileData _tileFor(PresetSlot slot, PresetService presets, ThemeData theme) {
    final pkg = presets.packageFor(slot.id);
    final app = pkg == null ? null : _apps[pkg];

    if (app != null) {
      return PresetTileData(
        title: app.label,
        icon: Image.memory(app.icon, width: 40, height: 40, gaplessPlayback: true),
        onTap: () => _onTap(slot),
        onLongPress: () => _onLongPress(slot),
      );
    }

    final String? subtitle;
    if (pkg == null) {
      subtitle = 'Нажмите, чтобы выбрать';
    } else if (_appsLoaded) {
      subtitle = 'Приложение удалено';
    } else {
      subtitle = null; // список ещё грузится
    }

    return PresetTileData(
      title: slot.hint,
      subtitle: subtitle,
      icon: Icon(slot.icon, size: 28, color: theme.colorScheme.primary),
      onTap: () => _onTap(slot),
      onLongPress: () => _onLongPress(slot),
    );
  }

  @override
  Widget build(BuildContext context) {
    final presets = context.watch<PresetService>();
    final theme = Theme.of(context);
    final tiles = [for (final slot in kPresetSlots) _tileFor(slot, presets, theme)];

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
                    // способ вернуть её, если пользователь её закрыл.
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
                        MaterialPageRoute(builder: (_) => const SettingsScreen()),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Text('Пресеты', style: theme.textTheme.titleMedium),
                Text(
                  'Удерживайте пресет, чтобы сменить приложение',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: SingleChildScrollView(
                    child: PresetGrid(tiles: tiles),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
