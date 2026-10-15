import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/app_info.dart';
import '../models/freeform_status.dart';
import '../models/live_windows_status.dart';
import '../models/preset.dart';
import '../services/native_bridge.dart';
import '../services/preset_service.dart';
import '../widgets/dock_clock.dart';
import '../widgets/wallpaper_background.dart';
import 'app_picker_screen.dart';
import 'settings_screen.dart';

/// Главный экран: слева док с часами и ярлыками, справа три области,
/// в каждой из которых открывается своё приложение свободным окном.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  /// Установленные приложения по имени пакета — для иконок и названий.
  Map<String, AppInfo> _apps = const {};
  bool _appsLoaded = false;

  FreeformStatus? _freeform;

  /// Доступно ли встраивание живых окон (системный режим, как CarCar).
  LiveWindowsStatus? _live;
  bool get _liveMode => _live?.available == true;

  /// Ключи областей окон — по ним считаются координаты для запуска.
  final List<GlobalKey> _windowKeys = List.generate(kWindowSlots.length, (_) => GlobalKey());

  /// Раскладывать окна автоматически только один раз за запуск лаунчера,
  /// а не при каждом возвращении на домашний экран.
  static bool _autoLayoutDone = false;
  bool _layingOut = false;

  /// Режим правки: в системном режиме живые окна перехватывают касания,
  /// поэтому для смены приложения их временно убирают и показывают карточки.
  bool _editing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadApps();
      _loadFreeformStatus();
      _loadLiveStatus().then((_) {
        // Вернулись на домашний экран — восстановить живые окна.
        if (_liveMode) {
          WidgetsBinding.instance.addPostFrameCallback((_) => _syncLiveWindows());
        }
      });
    }
  }

  Future<void> _init() async {
    await Future.wait([_loadApps(), _loadFreeformStatus(), _loadLiveStatus()]);
    if (!mounted || _autoLayoutDone) return;
    _autoLayoutDone = true;

    // Системный режим (как CarCar): встраиваем живые окна сразу.
    if (_liveMode) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _syncLiveWindows());
      return;
    }
    // Иначе — свободные окна, и только если устройство их поддерживает:
    // без этого три приложения открылись бы на весь экран друг поверх друга.
    if (_freeform?.supported != true) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => _layoutAllWindows());
  }

  Future<void> _loadLiveStatus() async {
    try {
      final status = await NativeBridge.liveWindowsAvailable();
      if (mounted) setState(() => _live = status);
    } catch (_) {
      // Останется null — считаем, что живых окон нет.
    }
  }

  /// Собрать живые окна для всех назначенных слотов и показать их.
  Future<void> _syncLiveWindows() async {
    if (!_liveMode || _editing) return;
    final presets = context.read<PresetService>();
    final specs = <AppWindowSpec>[];
    for (var i = 0; i < kWindowSlots.length; i++) {
      final pkg = presets.packageFor(kWindowSlots[i].id);
      if (pkg == null) continue;
      final bounds = _windowBoundsPx(i);
      if (bounds == null) continue;
      specs.add(AppWindowSpec(slotId: kWindowSlots[i].id, packageName: pkg, boundsPx: bounds));
    }
    try {
      await NativeBridge.syncAppWindows(specs);
    } catch (_) {
      // ignore — на следующем кадре попробуем снова
    }
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

  Future<void> _loadFreeformStatus() async {
    try {
      final status = await NativeBridge.getFreeformStatus();
      if (mounted) setState(() => _freeform = status);
    } catch (_) {
      // Статус останется неизвестным — баннер покажет предупреждение.
    }
  }

  // ---------- назначение приложений ----------

  Future<void> _pickApp(PresetSlot slot) async {
    final presets = context.read<PresetService>();
    final app = await Navigator.of(context).push<AppInfo>(
      MaterialPageRoute(builder: (_) => AppPickerScreen(title: '«${slot.hint}»: выбор приложения')),
    );
    if (app == null) return;
    await presets.assign(slot.id, app.packageName);
    if (!mounted) return;
    setState(() => _apps = {..._apps, app.packageName: app});
    // В системном режиме сразу показать живое окно для этого слота.
    if (_liveMode) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _syncLiveWindows());
    }
  }

  void _showSlotMenu(PresetSlot slot, {VoidCallback? onOpen}) {
    final presets = context.read<PresetService>();
    final assigned = presets.packageFor(slot.id) != null;
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (assigned && onOpen != null)
              ListTile(
                leading: const Icon(Icons.open_in_new_rounded),
                title: const Text('Открыть в окне'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  onOpen();
                },
              ),
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
                title: const Text('Очистить'),
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

  void _appMissing() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Приложение не найдено — выберите другое')),
    );
  }

  // ---------- док ----------

  Future<void> _onDockTap(PresetSlot slot) async {
    final pkg = context.read<PresetService>().packageFor(slot.id);
    if (pkg == null) return _pickApp(slot);
    final launched = await NativeBridge.launchApp(pkg);
    if (launched || !mounted) return;
    _appMissing();
    await _pickApp(slot);
  }

  // ---------- окна ----------

  /// Границы области окна в физических пикселях экрана лаунчера.
  Rect? _windowBoundsPx(int index) {
    final box = _windowKeys[index].currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final topLeft = box.localToGlobal(Offset.zero);
    return Rect.fromLTWH(
      topLeft.dx * dpr,
      topLeft.dy * dpr,
      box.size.width * dpr,
      box.size.height * dpr,
    );
  }

  /// true — окно открыто (или слот пуст и открывать нечего).
  Future<bool> _openWindow(int index, {bool pickIfEmpty = true}) async {
    final slot = kWindowSlots[index];
    final pkg = context.read<PresetService>().packageFor(slot.id);
    if (pkg == null) {
      if (pickIfEmpty) await _pickApp(slot);
      return true;
    }
    // В системном режиме окно рисуется живым оверлеем — просто пересобрать
    // (кроме режима правки, где живые окна временно убраны).
    if (_liveMode && !_editing) {
      await _syncLiveWindows();
      return true;
    }
    final bounds = _windowBoundsPx(index);
    if (bounds == null) return false;
    final ok = await NativeBridge.launchAppInBounds(pkg, bounds);
    if (!ok && mounted && pickIfEmpty) {
      _appMissing();
      await _pickApp(slot);
    }
    return ok;
  }

  Future<void> _layoutAllWindows() async {
    if (_layingOut) return;
    final presets = context.read<PresetService>();
    final anyAssigned = kWindowSlots.any((s) => presets.packageFor(s.id) != null);
    if (!anyAssigned) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Сначала назначьте приложения окнам — нажмите на окно')),
      );
      return;
    }
    setState(() => _layingOut = true);
    try {
      if (_liveMode) {
        // Системный режим: все живые окна одним вызовом.
        await _syncLiveWindows();
      } else {
        // Свободные окна: запускаем по очереди с паузой, чтобы система
        // успевала создать каждое окно.
        for (var i = 0; i < kWindowSlots.length; i++) {
          if (!mounted) return;
          await _openWindow(i, pickIfEmpty: false);
          await Future<void>.delayed(const Duration(milliseconds: 400));
        }
      }
    } finally {
      if (mounted) setState(() => _layingOut = false);
    }
  }

  Future<void> _toggleEditing() async {
    if (_editing) {
      // Завершаем правку — возвращаем живые окна.
      setState(() => _editing = false);
      WidgetsBinding.instance.addPostFrameCallback((_) => _syncLiveWindows());
    } else {
      // Входим в правку — убираем живые окна, чтобы открыть карточки.
      setState(() => _editing = true);
      try {
        await NativeBridge.clearAppWindows();
      } catch (_) {
        // ignore
      }
    }
  }

  void _showFreeformHelp() {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Как включить свободные окна'),
        content: const SingleChildScrollView(
          child: Text(
            'Без свободных окон приложения открываются на весь экран, '
            'а не в своих областях.\n\n'
            '1. Настройки → О системе (Об устройстве) → 7 раз нажмите '
            '«Номер сборки», чтобы включить режим разработчика.\n'
            '2. Настройки → Для разработчиков:\n'
            '   • включите «Окна произвольной формы» '
            '(Enable freeform windows);\n'
            '   • включите «Изменение размера в многооконном режиме» '
            '(Force activities to be resizable) — иначе часть приложений '
            'всё равно откроется на весь экран.\n'
            '3. Перезагрузите магнитолу.\n\n'
            'На некоторых прошивках этих пунктов нет — значит, прошивка '
            'не поддерживает свободные окна, и обычное приложение это не исправит.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Закрыть'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.of(dialogContext).pop();
              final opened = await NativeBridge.openDeveloperSettings();
              if (!opened && mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Раздел «Для разработчиков» недоступен — сначала выполните шаг 1'),
                  ),
                );
              }
            },
            child: const Text('Открыть настройки'),
          ),
        ],
      ),
    );
  }

  // ---------- построение ----------

  Widget _appIcon(PresetSlot slot, PresetService presets, double size) {
    final pkg = presets.packageFor(slot.id);
    final app = pkg == null ? null : _apps[pkg];
    if (app != null) {
      return Image.memory(app.icon, width: size, height: size, gaplessPlayback: true);
    }
    return Icon(slot.icon, size: size * 0.6, color: Theme.of(context).colorScheme.primary);
  }

  String? _missingNote(PresetSlot slot, PresetService presets) {
    final pkg = presets.packageFor(slot.id);
    if (pkg != null && _appsLoaded && !_apps.containsKey(pkg)) return 'Приложение удалено';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final presets = context.watch<PresetService>();
    return Scaffold(
      body: WallpaperBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildDock(presets),
                const SizedBox(width: 12),
                Expanded(child: _buildWindowsArea(presets)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDock(PresetService presets) {
    final theme = Theme.of(context);
    return Container(
      width: 92,
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: theme.cardTheme.color,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(
        children: [
          const DockClock(),
          const SizedBox(height: 12),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              itemCount: kPresetSlots.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final slot = kPresetSlots[index];
                final pkg = presets.packageFor(slot.id);
                final label = pkg != null ? (_apps[pkg]?.label ?? slot.hint) : slot.hint;
                return Tooltip(
                  message: pkg == null ? '$label — нажмите, чтобы выбрать' : label,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(18),
                    onTap: () => _onDockTap(slot),
                    onLongPress: () => _showSlotMenu(slot),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Column(
                        children: [
                          SizedBox(
                            width: 48,
                            height: 48,
                            child: Center(child: _appIcon(slot, presets, 48)),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelSmall,
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          IconButton.filledTonal(
            tooltip: 'Настройки',
            icon: const Icon(Icons.settings_rounded),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWindowsArea(PresetService presets) {
    final theme = Theme.of(context);
    final status = _freeform;
    final showFreeformWarning = !_liveMode && status != null && !status.supported;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                _liveMode
                    ? (_editing
                        ? 'Правка: нажмите на окно, чтобы выбрать приложение. Затем — «Готово».'
                        : 'Системный режим: приложения показываются живыми окнами. «Изменить окна» — чтобы сменить.')
                    : 'Нажмите на окно, чтобы открыть приложение. Удерживайте, чтобы сменить.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
            ),
            const SizedBox(width: 12),
            if (_liveMode)
              FilledButton.icon(
                onPressed: _toggleEditing,
                icon: Icon(_editing ? Icons.check_rounded : Icons.edit_rounded),
                label: Text(_editing ? 'Готово' : 'Изменить окна'),
              )
            else
              FilledButton.icon(
                onPressed: _layingOut ? null : _layoutAllWindows,
                icon: _layingOut
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.dashboard_rounded),
                label: const Text('Разложить окна'),
              ),
          ],
        ),
        if (showFreeformWarning) ...[
          const SizedBox(height: 8),
          Card(
            color: theme.colorScheme.errorContainer,
            margin: EdgeInsets.zero,
            child: ListTile(
              leading: Icon(Icons.warning_amber_rounded, color: theme.colorScheme.onErrorContainer),
              title: Text(
                'Свободные окна на этом устройстве выключены',
                style: TextStyle(color: theme.colorScheme.onErrorContainer),
              ),
              subtitle: Text(
                'Приложения будут открываться на весь экран, а не в своих окнах.',
                style: TextStyle(color: theme.colorScheme.onErrorContainer),
              ),
              trailing: TextButton(
                onPressed: _showFreeformHelp,
                child: const Text('Как включить'),
              ),
            ),
          ),
        ],
        const SizedBox(height: 12),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < kWindowSlots.length; i++) ...[
                if (i > 0) const SizedBox(width: 12),
                Expanded(child: _buildWindowSlot(i, presets)),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildWindowSlot(int index, PresetService presets) {
    final theme = Theme.of(context);
    final slot = kWindowSlots[index];
    final pkg = presets.packageFor(slot.id);
    final app = pkg == null ? null : _apps[pkg];
    final missing = _missingNote(slot, presets);

    final String title;
    final String subtitle;
    if (pkg == null) {
      title = slot.hint;
      subtitle = 'Нажмите, чтобы выбрать приложение';
    } else if (missing != null) {
      title = slot.hint;
      subtitle = missing;
    } else {
      title = app?.label ?? slot.hint;
      subtitle = 'Нажмите, чтобы открыть в окне';
    }

    return Card(
      key: _windowKeys[index],
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _openWindow(index),
        onLongPress: () => _showSlotMenu(slot, onOpen: () => _openWindow(index)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 72,
                height: 72,
                child: Center(
                  child: pkg == null
                      ? Icon(Icons.add_rounded, size: 48, color: theme.colorScheme.primary)
                      : _appIcon(slot, presets, 72),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                title,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
