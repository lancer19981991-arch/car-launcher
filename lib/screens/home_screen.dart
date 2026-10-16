import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/app_info.dart';
import '../models/freeform_status.dart';
import '../models/live_windows_status.dart';
import '../models/preset.dart';
import '../models/window_rect.dart';
import '../services/native_bridge.dart';
import '../services/preset_service.dart';
import '../services/settings_service.dart';
import '../widgets/dock_clock.dart';
import '../widgets/wallpaper_background.dart';
import 'app_picker_screen.dart';
import 'settings_screen.dart';

/// Главный экран: тонкая верхняя полоса и холст с окнами. Каждое окно
/// стоит в своих координатах (свободная раскладка), в нём своё
/// приложение: живым окном (системный режим) или свободным окном
/// (запасной режим). В режиме «Изменить» окна двигаются, тянутся за
/// уголок по ширине и высоте, добавляются и удаляются.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  static const double _gap = 4; // отступ внутри каждой ячейки окна
  static const int _maxWindows = 4;

  Map<String, AppInfo> _apps = const {};
  bool _appsLoaded = false;

  FreeformStatus? _freeform;
  LiveWindowsStatus? _live;
  bool get _liveMode => _live?.available == true;

  /// Ключи окон по slotId — по ним считаются координаты для запуска.
  final Map<String, GlobalKey> _keys = {for (final s in kWindowSlots) s.id: GlobalKey()};

  static bool _autoLayoutDone = false;
  bool _layingOut = false;
  bool _editing = false;

  /// Черновик раскладки, пока идёт правка (сохраняется по окончании жеста).
  List<WindowRect>? _draft;

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
        if (_liveMode && !_editing) _scheduleSync();
      });
    }
  }

  List<WindowRect> get _layout => _draft ?? context.read<SettingsService>().windowLayout;

  void _scheduleSync() =>
      WidgetsBinding.instance.addPostFrameCallback((_) => _syncLiveWindows());

  Future<void> _init() async {
    await Future.wait([_loadApps(), _loadFreeformStatus(), _loadLiveStatus()]);
    if (!mounted || _autoLayoutDone) return;
    _autoLayoutDone = true;
    if (_liveMode) {
      _scheduleSync();
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

  /// Границы окна в физических пикселях экрана лаунчера.
  Rect? _boundsPx(String slotId) {
    final box = _keys[slotId]?.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final topLeft = box.localToGlobal(Offset.zero);
    return Rect.fromLTWH(topLeft.dx * dpr, topLeft.dy * dpr, box.size.width * dpr, box.size.height * dpr);
  }

  Future<void> _syncLiveWindows() async {
    if (!_liveMode || _editing || !mounted) return;
    final presets = context.read<PresetService>();
    final specs = <AppWindowSpec>[];
    for (final r in _layout) {
      final pkg = presets.packageFor(r.slotId);
      if (pkg == null) continue;
      final bounds = _boundsPx(r.slotId);
      if (bounds == null) continue;
      specs.add(AppWindowSpec(slotId: r.slotId, packageName: pkg, boundsPx: bounds));
    }
    try {
      await NativeBridge.syncAppWindows(specs);
    } catch (_) {}
  }

  /// Живые окна — нативные View поверх Flutter, они перекрыли бы экраны
  /// выбора и настроек. Убираем их на время действия и возвращаем.
  Future<void> _withWindowsHidden(Future<void> Function() action) async {
    if (_liveMode) {
      try {
        await NativeBridge.clearAppWindows();
      } catch (_) {}
    }
    await action();
    if (_liveMode && mounted && !_editing) _scheduleSync();
  }

  void _onLiveWindowLongPress(String slotId) {
    _withWindowsHidden(() => _pickApp(slotById(slotId)));
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

  void _appMissing() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Приложение не найдено — выберите другое')),
    );
  }

  // ---------- свободные окна (запасной режим) ----------

  Future<bool> _openWindow(String slotId, {bool pickIfEmpty = true}) async {
    final slot = slotById(slotId);
    final pkg = context.read<PresetService>().packageFor(slotId);
    if (pkg == null) {
      if (pickIfEmpty) await _withWindowsHidden(() => _pickApp(slot));
      return true;
    }
    if (_liveMode && !_editing) {
      await _syncLiveWindows();
      return true;
    }
    final bounds = _boundsPx(slotId);
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
    final ids = _layout.map((r) => r.slotId).toList();
    if (!ids.any((id) => presets.packageFor(id) != null)) {
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
        for (final id in ids) {
          if (!mounted) return;
          await _openWindow(id, pickIfEmpty: false);
          await Future<void>.delayed(const Duration(milliseconds: 400));
        }
      }
    } finally {
      if (mounted) setState(() => _layingOut = false);
    }
  }

  // ---------- правка раскладки ----------

  Future<void> _toggleEditing() async {
    final settings = context.read<SettingsService>();
    if (_editing) {
      final draft = _draft;
      setState(() {
        _editing = false;
        _draft = null;
      });
      if (draft != null) await settings.setWindowLayout(draft);
      _scheduleSync();
    } else {
      setState(() {
        _editing = true;
        _draft = [...settings.windowLayout];
      });
      try {
        await NativeBridge.clearAppWindows();
      } catch (_) {}
    }
  }

  void _updateDraft(String slotId, WindowRect Function(WindowRect r) change, {bool toFront = false}) {
    final draft = _draft;
    if (draft == null) return;
    final i = draft.indexWhere((r) => r.slotId == slotId);
    if (i < 0) return;
    setState(() {
      final updated = change(draft[i]).clamped();
      if (toFront) {
        draft.removeAt(i);
        draft.add(updated);
      } else {
        draft[i] = updated;
      }
    });
  }

  void _snapDraft(String slotId) => _updateDraft(slotId, (r) => r.snapped());

  void _addWindow() {
    final draft = _draft;
    if (draft == null || draft.length >= _maxWindows) return;
    final used = draft.map((r) => r.slotId).toSet();
    final free = kWindowSlots.firstWhere((s) => !used.contains(s.id));
    setState(() => draft.add(WindowRect(slotId: free.id, x: 0.2, y: 0.3, w: 0.6, h: 0.3)));
  }

  void _removeWindow(String slotId) {
    final draft = _draft;
    if (draft == null) return;
    setState(() => draft.removeWhere((r) => r.slotId == slotId));
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
            '1. Настройки → О системе → 7 раз нажмите «Номер сборки».\n'
            '2. Для разработчиков: «Окна произвольной формы» и «Изменение '
            'размера в многооконном режиме».\n'
            '3. Перезагрузите устройство.',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Закрыть')),
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
    context.watch<SettingsService>();
    final showFreeformWarning = !_liveMode && _freeform != null && !_freeform!.supported;

    return Scaffold(
      body: WallpaperBackground(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(6, 4, 6, 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildTopBar(),
              if (showFreeformWarning) Padding(padding: const EdgeInsets.only(top: 4), child: _freeformWarning()),
              const SizedBox(height: 4),
              Expanded(child: _buildCanvas()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _freeformWarning() {
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.errorContainer,
      margin: EdgeInsets.zero,
      child: ListTile(
        dense: true,
        visualDensity: VisualDensity.compact,
        leading: Icon(Icons.warning_amber_rounded, color: theme.colorScheme.onErrorContainer),
        title: Text('Свободные окна выключены — приложения открываются на весь экран',
            style: TextStyle(color: theme.colorScheme.onErrorContainer, fontSize: 11)),
        trailing: TextButton(onPressed: _showFreeformHelp, child: const Text('Как включить')),
      ),
    );
  }

  static final ButtonStyle _compactBtn = FilledButton.styleFrom(
    visualDensity: VisualDensity.compact,
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
  );

  Widget _buildTopBar() {
    final theme = Theme.of(context);
    final canAdd = _editing && (_draft?.length ?? 0) < _maxWindows;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      decoration: BoxDecoration(color: theme.cardTheme.color, borderRadius: BorderRadius.circular(18)),
      child: Row(
        children: [
          const DockClock(),
          const Spacer(),
          if (canAdd) ...[
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onPressed: _addWindow,
              icon: const Icon(Icons.add_rounded, size: 16),
              label: const Text('Окно'),
            ),
            const SizedBox(width: 6),
          ],
          if (_liveMode || _editing)
            FilledButton.icon(
              style: _compactBtn,
              onPressed: _toggleEditing,
              icon: Icon(_editing ? Icons.check_rounded : Icons.edit_rounded, size: 16),
              label: Text(_editing ? 'Готово' : 'Изменить'),
            )
          else ...[
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: 'Изменить раскладку',
              icon: const Icon(Icons.edit_rounded, size: 20),
              onPressed: _toggleEditing,
            ),
            FilledButton.icon(
              style: _compactBtn,
              onPressed: _layingOut ? null : _layoutAllWindows,
              icon: _layingOut
                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.dashboard_rounded, size: 16),
              label: const Text('Разложить'),
            ),
          ],
          const SizedBox(width: 2),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: 'Настройки',
            icon: const Icon(Icons.settings_rounded, size: 22),
            onPressed: _openSettings,
          ),
        ],
      ),
    );
  }

  Widget _buildCanvas() {
    final layout = _layout;
    return LayoutBuilder(
      builder: (context, c) {
        final areaW = c.maxWidth;
        final areaH = c.maxHeight;
        return Stack(
          children: [
            if (_editing) Positioned.fill(child: _gridBackdrop()),
            for (final r in layout)
              Positioned(
                left: r.x * areaW,
                top: r.y * areaH,
                width: r.w * areaW,
                height: r.h * areaH,
                child: Padding(
                  padding: const EdgeInsets.all(_gap),
                  child: _editing ? _editableWindow(r, areaW, areaH) : _windowCard(r.slotId),
                ),
              ),
          ],
        );
      },
    );
  }

  /// Еле заметная сетка в режиме правки — подсказывает привязку.
  Widget _gridBackdrop() {
    final color = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.06);
    return CustomPaint(painter: _GridPainter(color: color, step: WindowRect.snap));
  }

  Widget _editableWindow(WindowRect r, double areaW, double areaH) {
    final theme = Theme.of(context);
    final slot = slotById(r.slotId);

    Widget roundBtn(IconData icon, VoidCallback onTap, {String? tip}) => Material(
          color: theme.colorScheme.surface.withValues(alpha: 0.9),
          shape: const CircleBorder(),
          elevation: 2,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: Padding(padding: const EdgeInsets.all(7), child: Icon(icon, size: 20)),
          ),
        );

    return GestureDetector(
      // Перетаскивание всего окна.
      onPanStart: (_) => _updateDraft(r.slotId, (x) => x, toFront: true),
      onPanUpdate: (d) => _updateDraft(
        r.slotId,
        (x) => x.copyWith(x: x.x + d.delta.dx / areaW, y: x.y + d.delta.dy / areaH),
      ),
      onPanEnd: (_) => _snapDraft(r.slotId),
      child: Stack(
        fit: StackFit.expand,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: theme.colorScheme.primary, width: 2),
            ),
            child: _windowCard(r.slotId, editing: true),
          ),
          Positioned(
            top: 6,
            left: 6,
            child: roundBtn(Icons.settings_rounded, () => _pickApp(slot)),
          ),
          Positioned(
            top: 6,
            right: 6,
            child: roundBtn(Icons.delete_outline_rounded, () => _removeWindow(r.slotId)),
          ),
          // Уголок: изменение размера по ширине и высоте.
          Positioned(
            right: 0,
            bottom: 0,
            child: GestureDetector(
              onPanStart: (_) => _updateDraft(r.slotId, (x) => x, toFront: true),
              onPanUpdate: (d) => _updateDraft(
                r.slotId,
                (x) => x.copyWith(w: x.w + d.delta.dx / areaW, h: x.h + d.delta.dy / areaH),
              ),
              onPanEnd: (_) => _snapDraft(r.slotId),
              child: Container(
                width: 44,
                height: 44,
                alignment: Alignment.bottomRight,
                padding: const EdgeInsets.all(4),
                child: Material(
                  color: theme.colorScheme.primary,
                  shape: const CircleBorder(),
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Icon(Icons.open_in_full_rounded, size: 18, color: theme.colorScheme.onPrimary),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _appIcon(String slotId, double size) {
    final pkg = context.read<PresetService>().packageFor(slotId);
    final app = pkg == null ? null : _apps[pkg];
    if (app != null) return Image.memory(app.icon, width: size, height: size, gaplessPlayback: true);
    return Icon(Icons.add_rounded, size: size * 0.7, color: Theme.of(context).colorScheme.primary);
  }

  Widget _windowCard(String slotId, {bool editing = false}) {
    final theme = Theme.of(context);
    final slot = slotById(slotId);
    final pkg = context.read<PresetService>().packageFor(slotId);
    final app = pkg == null ? null : _apps[pkg];
    final missing = pkg != null && _appsLoaded && app == null;

    final String title;
    final String subtitle;
    if (pkg == null) {
      title = slot.hint;
      subtitle = editing ? '⚙ — выбрать приложение' : 'Нажмите, чтобы выбрать приложение';
    } else if (missing) {
      title = slot.hint;
      subtitle = 'Приложение удалено';
    } else {
      title = app?.label ?? slot.hint;
      subtitle = editing ? 'тяните — переместить, уголок — размер' : (_liveMode ? 'Живое окно' : 'Нажмите, чтобы открыть в окне');
    }

    final content = Padding(
      padding: const EdgeInsets.all(8),
      child: Center(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(width: 56, height: 56, child: Center(child: _appIcon(slotId, 56))),
              const SizedBox(height: 8),
              Text(title, textAlign: TextAlign.center, maxLines: 1, style: theme.textTheme.titleMedium),
              const SizedBox(height: 2),
              Text(subtitle,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  )),
            ],
          ),
        ),
      ),
    );

    return Card(
      key: _keys[slotId],
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: editing
          ? content
          : InkWell(
              onTap: () {
                if (_liveMode) {
                  _withWindowsHidden(() => _pickApp(slot));
                } else {
                  _openWindow(slotId);
                }
              },
              onLongPress: () => _withWindowsHidden(() => _pickApp(slot)),
              child: content,
            ),
    );
  }
}

class _GridPainter extends CustomPainter {
  _GridPainter({required this.color, required this.step});

  final Color color;
  final double step;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    for (var f = step; f < 1; f += step * 4) {
      canvas.drawLine(Offset(f * size.width, 0), Offset(f * size.width, size.height), paint);
      canvas.drawLine(Offset(0, f * size.height), Offset(size.width, f * size.height), paint);
    }
  }

  @override
  bool shouldRepaint(_GridPainter old) => old.color != color || old.step != step;
}
