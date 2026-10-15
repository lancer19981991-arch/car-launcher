import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/app_info.dart';
import '../models/freeform_status.dart';
import '../models/live_windows_status.dart';
import '../models/preset.dart';
import '../services/native_bridge.dart';
import '../services/preset_service.dart';
import '../services/settings_service.dart';
import '../widgets/dock_clock.dart';
import '../widgets/wallpaper_background.dart';
import 'app_picker_screen.dart';
import 'settings_screen.dart';

/// Главный экран: тонкая верхняя полоса (часы + кнопки) и область окон.
/// В каждом окне открывается своё приложение: живым окном (системный
/// режим) или свободным окном (запасной режим).
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  Map<String, AppInfo> _apps = const {};
  bool _appsLoaded = false;

  FreeformStatus? _freeform;
  LiveWindowsStatus? _live;
  bool get _liveMode => _live?.available == true;

  /// Ключи областей окон — по ним считаются координаты для запуска.
  final List<GlobalKey> _windowKeys =
      List.generate(kWindowSlots.length, (_) => GlobalKey());

  static bool _autoLayoutDone = false;
  bool _layingOut = false;
  bool _editing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    NativeBridge.onWindowLongPress = _onLiveWindowLongPress;
    NativeBridge.ensureIncomingHandler();
    _init();
  }

  @override
  void dispose() {
    NativeBridge.onWindowLongPress = null;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadApps();
      _loadFreeformStatus();
      _loadLiveStatus().then((_) {
        if (_liveMode && !_editing) {
          WidgetsBinding.instance.addPostFrameCallback((_) => _syncLiveWindows());
        }
      });
    }
  }

  int get _count => context.read<SettingsService>().windowCount;

  Future<void> _init() async {
    await Future.wait([_loadApps(), _loadFreeformStatus(), _loadLiveStatus()]);
    if (!mounted || _autoLayoutDone) return;
    _autoLayoutDone = true;
    if (_liveMode) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _syncLiveWindows());
      return;
    }
    if (_freeform?.supported != true) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => _layoutAllWindows());
  }

  Future<void> _loadApps() async {
    try {
      final list = await NativeBridge.getInstalledApps();
      if (!mounted) return;
      setState(() {
        _apps = {for (final app in list) app.packageName: app};
        _appsLoaded = true;
      });
    } catch (_) {}
  }

  Future<void> _loadFreeformStatus() async {
    try {
      final status = await NativeBridge.getFreeformStatus();
      if (mounted) setState(() => _freeform = status);
    } catch (_) {}
  }

  Future<void> _loadLiveStatus() async {
    try {
      final status = await NativeBridge.liveWindowsAvailable();
      if (mounted) setState(() => _live = status);
    } catch (_) {}
  }

  // ---------- живые окна ----------

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

  Future<void> _syncLiveWindows() async {
    if (!_liveMode || _editing) return;
    final presets = context.read<PresetService>();
    final specs = <AppWindowSpec>[];
    for (var i = 0; i < _count; i++) {
      final pkg = presets.packageFor(kWindowSlots[i].id);
      if (pkg == null) continue;
      final bounds = _windowBoundsPx(i);
      if (bounds == null) continue;
      specs.add(AppWindowSpec(slotId: kWindowSlots[i].id, packageName: pkg, boundsPx: bounds));
    }
    try {
      await NativeBridge.syncAppWindows(specs);
    } catch (_) {}
  }

  /// Временно убрать живые окна (они перекрывают Flutter-экраны), выполнить
  /// действие (выбор приложения, настройки) и вернуть окна.
  Future<void> _withWindowsHidden(Future<void> Function() action) async {
    if (_liveMode) {
      try {
        await NativeBridge.clearAppWindows();
      } catch (_) {}
    }
    await action();
    if (_liveMode && mounted && !_editing) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _syncLiveWindows());
    }
  }

  void _onLiveWindowLongPress(String slotId) {
    final slot = kWindowSlots.firstWhere((s) => s.id == slotId, orElse: () => kWindowSlots.first);
    _withWindowsHidden(() => _pickApp(slot));
  }

  // ---------- назначение ----------

  Future<void> _pickApp(PresetSlot slot) async {
    final presets = context.read<PresetService>();
    final app = await Navigator.of(context).push<AppInfo>(
      MaterialPageRoute(builder: (_) => AppPickerScreen(title: '«${slot.hint}»: выбор приложения')),
    );
    if (app == null) return;
    await presets.assign(slot.id, app.packageName);
    if (!mounted) return;
    setState(() => _apps = {..._apps, app.packageName: app});
  }

  void _showSlotMenu(PresetSlot slot) {
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
                _withWindowsHidden(() => _pickApp(slot));
              },
            ),
            if (assigned)
              ListTile(
                leading: const Icon(Icons.clear_rounded),
                title: const Text('Очистить окно'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  presets.clear(slot.id);
                  if (_liveMode && !_editing) {
                    WidgetsBinding.instance.addPostFrameCallback((_) => _syncLiveWindows());
                  }
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

  // ---------- свободные окна (запасной режим) ----------

  Future<bool> _openWindow(int index, {bool pickIfEmpty = true}) async {
    final slot = kWindowSlots[index];
    final pkg = context.read<PresetService>().packageFor(slot.id);
    if (pkg == null) {
      if (pickIfEmpty) await _withWindowsHidden(() => _pickApp(slot));
      return true;
    }
    if (_liveMode && !_editing) {
      await _syncLiveWindows();
      return true;
    }
    final bounds = _windowBoundsPx(index);
    if (bounds == null) return false;
    final ok = await NativeBridge.launchAppInBounds(pkg, bounds);
    if (!ok && mounted && pickIfEmpty) {
      _appMissing();
      await _withWindowsHidden(() => _pickApp(slot));
    }
    return ok;
  }

  Future<void> _layoutAllWindows() async {
    if (_layingOut) return;
    final presets = context.read<PresetService>();
    final anyAssigned =
        List.generate(_count, (i) => kWindowSlots[i].id).any((id) => presets.packageFor(id) != null);
    if (!anyAssigned) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Сначала назначьте приложения окнам — нажмите на окно')),
      );
      return;
    }
    setState(() => _layingOut = true);
    try {
      if (_liveMode) {
        await _syncLiveWindows();
      } else {
        for (var i = 0; i < _count; i++) {
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
      setState(() => _editing = false);
      WidgetsBinding.instance.addPostFrameCallback((_) => _syncLiveWindows());
    } else {
      setState(() => _editing = true);
      try {
        await NativeBridge.clearAppWindows();
      } catch (_) {}
    }
  }

  Future<void> _openSettings() =>
      _withWindowsHidden(() => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const SettingsScreen()),
          ));

  void _showFreeformHelp() {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Как включить свободные окна'),
        content: const SingleChildScrollView(
          child: Text(
            'Без свободных окон приложения открываются на весь экран.\n\n'
            '1. Настройки → О системе → 7 раз нажмите «Номер сборки» '
            '(режим разработчика).\n'
            '2. Настройки → Для разработчиков: включите «Окна произвольной '
            'формы» и «Изменение размера в многооконном режиме».\n'
            '3. Перезагрузите устройство.\n\n'
            'Если этих пунктов нет — прошивка свободные окна не поддерживает.',
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
              await NativeBridge.openDeveloperSettings();
            },
            child: const Text('Открыть настройки'),
          ),
        ],
      ),
    );
  }

  // ---------- построение ----------

  @override
  Widget build(BuildContext context) {
    context.watch<PresetService>();
    final settings = context.watch<SettingsService>();
    final size = MediaQuery.sizeOf(context);
    final portrait = size.height >= size.width;

    return Scaffold(
      body: WallpaperBackground(
        // SafeArea только снизу/по бокам — верх отдаём под статус-бар.
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildTopBar(),
                _buildHints(),
                const SizedBox(height: 8),
                Expanded(child: _buildWindows(settings, portrait)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: theme.cardTheme.color,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        children: [
          const DockClock(),
          const Spacer(),
          if (_liveMode)
            FilledButton.icon(
              onPressed: _toggleEditing,
              icon: Icon(_editing ? Icons.check_rounded : Icons.edit_rounded, size: 18),
              label: Text(_editing ? 'Готово' : 'Изменить'),
            )
          else
            FilledButton.icon(
              onPressed: _layingOut ? null : _layoutAllWindows,
              icon: _layingOut
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.dashboard_rounded, size: 18),
              label: const Text('Разложить'),
            ),
          const SizedBox(width: 8),
          IconButton.filledTonal(
            tooltip: 'Настройки',
            icon: const Icon(Icons.settings_rounded),
            onPressed: _openSettings,
          ),
        ],
      ),
    );
  }

  Widget _buildHints() {
    final theme = Theme.of(context);
    final hintStyle = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
    );
    final showFreeformWarning = !_liveMode && _freeform != null && !_freeform!.supported;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_editing) ...[
          const SizedBox(height: 6),
          Text('Правка: нажмите окно — выбрать приложение, тяните разделитель — размер. Затем «Готово».',
              style: hintStyle),
        ] else if (_liveMode) ...[
          const SizedBox(height: 6),
          Text('Долгое нажатие на окно — сменить приложение.', style: hintStyle),
        ],
        if (_live != null && (!_live!.available || _live!.lastError != null)) ...[
          const SizedBox(height: 6),
          Text(_live!.diagnostics, style: theme.textTheme.labelSmall),
        ],
        if (showFreeformWarning) ...[
          const SizedBox(height: 6),
          Card(
            color: theme.colorScheme.errorContainer,
            margin: EdgeInsets.zero,
            child: ListTile(
              dense: true,
              leading: Icon(Icons.warning_amber_rounded, color: theme.colorScheme.onErrorContainer),
              title: Text('Свободные окна выключены — приложения открываются на весь экран',
                  style: TextStyle(color: theme.colorScheme.onErrorContainer, fontSize: 12)),
              trailing: TextButton(onPressed: _showFreeformHelp, child: const Text('Как включить')),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildWindows(SettingsService settings, bool portrait) {
    final count = settings.windowCount;
    final weights = settings.windowWeights;

    return LayoutBuilder(
      builder: (context, constraints) {
        final extent = portrait ? constraints.maxHeight : constraints.maxWidth;
        final children = <Widget>[];
        for (var i = 0; i < count; i++) {
          if (i > 0) {
            children.add(_divider(i, settings, extent, portrait));
          }
          final flex = (weights[i] * 1000).round().clamp(300, 100000);
          children.add(Expanded(flex: flex, child: _buildWindowCard(i)));
        }
        return portrait
            ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children)
            : Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
      },
    );
  }

  /// Разделитель между окнами. В режиме правки — перетаскиваемый (меняет
  /// пропорции соседних окон). Вне правки — просто отступ.
  Widget _divider(int rightIndex, SettingsService settings, double extent, bool portrait) {
    const gap = 10.0;
    if (!_editing) return SizedBox(width: portrait ? null : gap, height: portrait ? gap : null);

    final theme = Theme.of(context);
    final handle = Container(
      width: portrait ? double.infinity : 18,
      height: portrait ? 18 : double.infinity,
      alignment: Alignment.center,
      child: Container(
        width: portrait ? 44 : 4,
        height: portrait ? 4 : 44,
        decoration: BoxDecoration(
          color: theme.colorScheme.primary,
          borderRadius: BorderRadius.circular(3),
        ),
      ),
    );

    void drag(double delta) {
      final weights = [...settings.windowWeights];
      final left = rightIndex - 1;
      final right = rightIndex;
      // Перевод смещения в пикселях в доли веса.
      final totalWeight = weights.take(settings.windowCount).reduce((a, b) => a + b);
      final perPx = extent <= 0 ? 0 : totalWeight / extent;
      final d = delta * perPx;
      weights[left] = (weights[left] + d).clamp(0.3, 100.0);
      weights[right] = (weights[right] - d).clamp(0.3, 100.0);
      settings.setWindowWeights(weights);
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragUpdate: portrait ? (d) => drag(d.delta.dy) : null,
      onHorizontalDragUpdate: portrait ? null : (d) => drag(d.delta.dx),
      child: MouseRegion(
        cursor: portrait ? SystemMouseCursors.resizeRow : SystemMouseCursors.resizeColumn,
        child: handle,
      ),
    );
  }

  Widget _appIcon(PresetSlot slot, double size) {
    final pkg = context.read<PresetService>().packageFor(slot.id);
    final app = pkg == null ? null : _apps[pkg];
    if (app != null) {
      return Image.memory(app.icon, width: size, height: size, gaplessPlayback: true);
    }
    return Icon(Icons.add_rounded, size: size * 0.7, color: Theme.of(context).colorScheme.primary);
  }

  Widget _buildWindowCard(int index) {
    final theme = Theme.of(context);
    final presets = context.read<PresetService>();
    final slot = kWindowSlots[index];
    final pkg = presets.packageFor(slot.id);
    final app = pkg == null ? null : _apps[pkg];
    final missing = pkg != null && _appsLoaded && app == null;

    final String title;
    final String subtitle;
    if (pkg == null) {
      title = slot.hint;
      subtitle = 'Нажмите, чтобы выбрать приложение';
    } else if (missing) {
      title = slot.hint;
      subtitle = 'Приложение удалено';
    } else {
      title = app?.label ?? slot.hint;
      subtitle = _liveMode ? 'Живое окно' : 'Нажмите, чтобы открыть в окне';
    }

    return Card(
      key: _windowKeys[index],
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          if (_liveMode) {
            _withWindowsHidden(() => _pickApp(slot));
          } else {
            _openWindow(index);
          }
        },
        onLongPress: () => _showSlotMenu(slot),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(width: 64, height: 64, child: Center(child: _appIcon(slot, 64))),
              const SizedBox(height: 10),
              Text(title,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium),
              const SizedBox(height: 2),
              Text(subtitle,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  )),
            ],
          ),
        ),
      ),
    );
  }
}
