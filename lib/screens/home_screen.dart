import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/app_info.dart';
import '../models/freeform_status.dart';
import '../models/layout_preset.dart';
import '../models/live_windows_status.dart';
import '../models/preset.dart';
import '../models/widget_provider.dart';
import '../models/window_rect.dart';
import '../services/native_bridge.dart';
import '../services/preset_service.dart';
import '../services/settings_service.dart';
import '../services/weather_service.dart';
import '../widgets/dock_clock.dart';
import '../widgets/wallpaper_background.dart';
import 'app_picker_screen.dart';
import 'presets_screen.dart';
import 'settings_screen.dart';
import 'widget_picker_screen.dart';

/// Главный экран: весь экран — холст с окнами (свободная раскладка).
/// Поверх — маленькая полупрозрачная «пилюля» с часами и шестерёнкой;
/// нажатие открывает меню (правка раскладки, настройки). В режиме правки
/// окна двигаются и тянутся за уголок, пилюля тоже перетаскивается.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  static const double _gap = 3; // отступ внутри каждой ячейки окна
  static const int _maxWindows = 4;
  static const double _pillH = 38;

  /// Пилюля шире, когда в ней есть погода.
  double get _pillW => context.read<WeatherService>().pillText != null ? 172 : 104;

  Map<String, AppInfo> _apps = const {};
  bool _appsLoaded = false;

  FreeformStatus? _freeform;
  LiveWindowsStatus? _live;
  bool get _liveMode => _live?.available == true;

  final Map<String, GlobalKey> _keys = {for (final s in kWindowSlots) s.id: GlobalKey()};
  final GlobalKey _canvasKey = GlobalKey();

  static bool _autoLayoutDone = false;
  bool _layingOut = false;
  bool _editing = false;
  bool _menuOpen = false;

  /// Черновики, пока идёт правка.
  List<WindowRect>? _draft;
  Offset? _pillDraft;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    NativeBridge.onWindowLongPress = _onLiveWindowLongPress;
    NativeBridge.onPillTap = _showMenu;
    NativeBridge.ensureIncomingHandler();
    _weather = context.read<WeatherService>()..addListener(_onWeather);
    _init();
  }

  WeatherService? _weather;
  String? _shownWeather;

  /// Погода обновилась — перерисовать пилюлю (и нативную тоже).
  void _onWeather() {
    final t = _weather?.pillText;
    if (t == _shownWeather || !mounted) return;
    _shownWeather = t;
    setState(() {});
    if (_liveMode && !_editing && !_menuOpen) _scheduleSync();
  }

  @override
  void dispose() {
    NativeBridge.onWindowLongPress = null;
    NativeBridge.onPillTap = null;
    _weather?.removeListener(_onWeather);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _weather?.refreshIfStale();
      _loadApps();
      _loadFreeformStatus();
      _loadLiveStatus().then((_) {
        if (_liveMode && !_editing && !_menuOpen) _scheduleSync();
      });
    }
  }

  List<WindowRect> get _layout => _draft ?? context.read<SettingsService>().windowLayout;
  Offset get _pillAlign => _pillDraft ?? context.read<SettingsService>().pillAlign;

  void _scheduleSync() {
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncLiveWindows());
    // Колбэк после кадра срабатывает, только если кадр будет. Когда экран
    // неподвижен (например, через полсекунды после закрытия настроек),
    // кадр нужно запросить явно — иначе окна так и не покажутся.
    WidgetsBinding.instance.scheduleFrame();
  }

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

  // ---------- координаты ----------

  double get _dpr => MediaQuery.devicePixelRatioOf(context);

  Rect? _boundsPx(String slotId) {
    final box = _keys[slotId]?.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    final topLeft = box.localToGlobal(Offset.zero);
    return Rect.fromLTWH(topLeft.dx * _dpr, topLeft.dy * _dpr, box.size.width * _dpr, box.size.height * _dpr);
  }

  /// Положение пилюли внутри холста (логические px).
  Offset _pillOffset(double areaW, double areaH) {
    final a = _pillAlign;
    return Offset(a.dx * (areaW - _pillW).clamp(0, double.infinity), a.dy * (areaH - _pillH).clamp(0, double.infinity));
  }

  /// Положение пилюли в физических px экрана — для нативной пилюли.
  Rect? _pillPx() {
    final box = _canvasKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    final origin = box.localToGlobal(Offset.zero);
    final o = _pillOffset(box.size.width, box.size.height);
    return Rect.fromLTWH((origin.dx + o.dx) * _dpr, (origin.dy + o.dy) * _dpr, _pillW * _dpr, _pillH * _dpr);
  }

  // ---------- живые окна ----------

  Future<void> _syncLiveWindows() async {
    if (!_liveMode || _editing || _menuOpen || !mounted) return;
    final presets = context.read<PresetService>();
    final specs = <AppWindowSpec>[];
    for (final r in _layout) {
      final widgetId = presets.widgetFor(r.slotId);
      final pkg = presets.packageFor(r.slotId);
      if (widgetId == null && pkg == null) continue;
      final bounds = _boundsPx(r.slotId);
      if (bounds == null) continue;
      specs.add(widgetId != null
          ? AppWindowSpec(slotId: r.slotId, packageName: '', boundsPx: bounds, widgetId: widgetId)
          : AppWindowSpec(slotId: r.slotId, packageName: pkg!, boundsPx: bounds));
    }
    final settings = context.read<SettingsService>();
    try {
      await NativeBridge.syncAppWindows(
        specs,
        pillPx: _pillPx(),
        pillWeather: context.read<WeatherService>().pillText,
        borderColor: settings.windowBorderColor,
        borderWidthPx: settings.windowBorderWidth * _dpr,
        cornerRadiusPx: settings.windowCornerRadius * _dpr,
      );
    } catch (_) {}
  }

  Future<void> _hideLive() async {
    if (!_liveMode) return;
    try {
      // Надёжный режим (по умолчанию): окна закрываются и потом
      // запускаются заново. Иначе — только прячутся, без перезапуска.
      if (context.read<SettingsService>().keepWindowsInLauncher) {
        await NativeBridge.hideAppWindows();
      } else {
        await NativeBridge.clearAppWindows();
      }
    } catch (_) {}
  }

  /// Живые окна — нативные View поверх Flutter, они перекрыли бы экраны
  /// выбора и настроек. Убираем их на время действия и возвращаем.
  Future<void> _withWindowsHidden(Future<void> Function() action) async {
    await _hideLive();
    await action();
    _syncAfterTransition();
  }

  /// После закрытия экрана поверх главного (настройки, выбор приложения)
  /// ещё секунду-другую идёт анимация, и главный экран в это время
  /// масштабирован. Ставим окна после её окончания и ещё раз чуть позже
  /// для надёжности (повторная синхронизация ничего не перезапускает).
  void _syncAfterTransition() {
    for (final ms in const [450, 1200]) {
      Future.delayed(Duration(milliseconds: ms), () {
        if (_liveMode && mounted && !_editing && !_menuOpen) _scheduleSync();
      });
    }
  }

  void _onLiveWindowLongPress(String slotId) {
    _withWindowsHidden(() => _pickContent(slotById(slotId)));
  }

  // ---------- меню пилюли ----------

  Future<void> _showMenu() async {
    if (_menuOpen || !mounted) return;
    _menuOpen = true;
    await _hideLive();
    if (!mounted) return;
    final saved = context.read<PresetService>().savedPresets;
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (saved.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (var i = 0; i < saved.length; i++)
                        ActionChip(
                          avatar: const Icon(Icons.dashboard_rounded, size: 18),
                          label: Text(saved[i].name),
                          onPressed: () => Navigator.of(ctx).pop('preset:$i'),
                        ),
                    ],
                  ),
                ),
              ListTile(
                leading: const Icon(Icons.bookmarks_rounded),
                title: const Text('Пресеты'),
                subtitle: const Text('Сохранить раскладку, переключить, удалить'),
                onTap: () => Navigator.of(ctx).pop('presets'),
              ),
              ListTile(
                leading: const Icon(Icons.dashboard_customize_rounded),
                title: const Text('Изменить раскладку окон'),
                onTap: () => Navigator.of(ctx).pop('edit'),
              ),
              if (!_liveMode)
                ListTile(
                  leading: const Icon(Icons.dashboard_rounded),
                  title: const Text('Разложить окна'),
                  onTap: () => Navigator.of(ctx).pop('layout'),
                ),
              ListTile(
                leading: const Icon(Icons.settings_rounded),
                title: const Text('Настройки'),
                onTap: () => Navigator.of(ctx).pop('settings'),
              ),
            ],
            ),
        ),
      ),
    );
    _menuOpen = false;
    if (!mounted) return;
    if (choice != null && choice.startsWith('preset:')) {
      final i = int.tryParse(choice.substring(7));
      if (i != null && i < saved.length) await _applyPreset(saved[i]);
      if (_liveMode && !_editing) _scheduleSync();
      return;
    }
    switch (choice) {
      case 'presets':
        await _openPresets();
      case 'edit':
        if (!_editing) await _toggleEditing();
      case 'settings':
        await _openSettings();
      case 'layout':
        await _layoutAllWindows();
      default:
        if (_liveMode && !_editing) _scheduleSync();
    }
  }

  // ---------- пресеты ----------

  Future<void> _openPresets() => _withWindowsHidden(() async {
        final preset = await Navigator.of(context).push<LayoutPreset>(
          MaterialPageRoute(
            builder: (_) => PresetsScreen(
              appLabels: {for (final a in _apps.values) a.packageName: a.label},
            ),
          ),
        );
        if (preset != null && mounted) await _applyPreset(preset);
      });

  /// Включить пресет: раскладка, пилюля и содержимое окон.
  Future<void> _applyPreset(LayoutPreset preset) async {
    final settings = context.read<SettingsService>();
    final presets = context.read<PresetService>();
    final unused = await presets.applyContents(preset);
    await settings.setWindowLayout(preset.layout);
    await settings.setPillAlign(preset.pill);
    for (final id in unused) {
      NativeBridge.deleteWidget(id).catchError((_) {});
    }
    if (mounted) setState(() {});
  }

  /// Удалить виджеты из системы, если они больше не стоят ни в окне,
  /// ни в одном пресете.
  void _deleteWidgetsIfUnused(PresetService presets, List<int> ids) {
    for (final id in ids) {
      if (!presets.widgetInUse(id)) NativeBridge.deleteWidget(id).catchError((_) {});
    }
  }

  // ---------- назначение ----------

  /// Выбор содержимого окна. В системном режиме — приложение или виджет
  /// рабочего стола; в запасном режиме — только приложение.
  Future<void> _pickContent(PresetSlot slot) async {
    if (!_liveMode) return _pickApp(slot);
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.apps_rounded),
              title: const Text('Приложение'),
              subtitle: const Text('Живое окно приложения'),
              onTap: () => Navigator.of(ctx).pop('app'),
            ),
            ListTile(
              leading: const Icon(Icons.widgets_rounded),
              title: const Text('Виджет'),
              subtitle: const Text('Виджет рабочего стола (например, TPMS)'),
              onTap: () => Navigator.of(ctx).pop('widget'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || choice == null) return;
    if (choice == 'widget') {
      await _pickWidget(slot);
    } else {
      await _pickApp(slot);
    }
  }

  Future<void> _pickApp(PresetSlot slot) async {
    final presets = context.read<PresetService>();
    final app = await Navigator.of(context).push<AppInfo>(
      MaterialPageRoute(builder: (_) => AppPickerScreen(title: '«${slot.hint}»: выбор приложения')),
    );
    if (app == null) return;
    final oldWidget = presets.widgetFor(slot.id);
    await presets.assign(slot.id, app.packageName);
    if (oldWidget != null) _deleteWidgetsIfUnused(presets, [oldWidget]);
    if (!mounted) return;
    setState(() => _apps = {..._apps, app.packageName: app});
  }

  Future<void> _pickWidget(PresetSlot slot) async {
    final presets = context.read<PresetService>();
    final messenger = ScaffoldMessenger.of(context);
    final w = await Navigator.of(context).push<WidgetProvider>(
      MaterialPageRoute(builder: (_) => WidgetPickerScreen(title: '«${slot.hint}»: выбор виджета')),
    );
    if (w == null) return;
    int? id;
    try {
      id = await NativeBridge.bindWidget(w.provider);
    } on PlatformException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Не удалось добавить виджет: ${e.message}')));
      return;
    }
    if (id == null) return; // настройку виджета отменили
    final oldWidget = presets.widgetFor(slot.id);
    await presets.assignWidget(slot.id, id, w.label);
    if (oldWidget != null) _deleteWidgetsIfUnused(presets, [oldWidget]);
    if (mounted) setState(() {});
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
      if (pickIfEmpty) await _withWindowsHidden(() => _pickContent(slot));
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
      await _withWindowsHidden(() => _pickContent(slot));
    }
    return ok;
  }

  Future<void> _layoutAllWindows() async {
    if (_layingOut) return;
    final presets = context.read<PresetService>();
    final ids = _layout.map((r) => r.slotId).toList();
    if (!ids.any((id) => presets.packageFor(id) != null || presets.widgetFor(id) != null)) {
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
      final pill = _pillDraft;
      setState(() {
        _editing = false;
        _draft = null;
        _pillDraft = null;
      });
      if (draft != null) await settings.setWindowLayout(draft);
      if (pill != null) await settings.setPillAlign(pill);
      _scheduleSync();
    } else {
      setState(() {
        _editing = true;
        _draft = [...settings.windowLayout];
        _pillDraft = settings.pillAlign;
      });
      await _hideLive();
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
    return Scaffold(
      body: WallpaperBackground(child: _buildCanvas()),
    );
  }

  Widget _buildCanvas() {
    final layout = _layout;
    final showFreeformWarning = !_liveMode && _freeform != null && !_freeform!.supported;
    // В системном режиме пилюлю рисует нативная сторона (поверх живых
    // окон). Flutter-пилюля — в правке и в запасном режиме.
    final showFlutterPill = _editing || !_liveMode;

    return LayoutBuilder(
      key: _canvasKey,
      builder: (context, c) {
        final areaW = c.maxWidth;
        final areaH = c.maxHeight;
        final pillPos = _pillOffset(areaW, areaH);
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
            if (showFreeformWarning && !_editing)
              Positioned(left: 8, right: 8, bottom: 8, child: _freeformWarning()),
            if (showFlutterPill)
              Positioned(
                left: pillPos.dx,
                top: pillPos.dy,
                width: _pillW,
                height: _pillH,
                child: _editing ? _draggablePill(areaW, areaH) : _pill(onTap: _showMenu),
              ),
            if (_editing) Positioned(left: 0, right: 0, bottom: 12, child: _editToolbar()),
          ],
        );
      },
    );
  }

  Widget _pill({VoidCallback? onTap, bool highlighted = false}) {
    final weather = context.read<WeatherService>().pillText;
    return Material(
      color: Colors.black.withValues(alpha: 0.35),
      shape: StadiumBorder(
        side: highlighted
            ? BorderSide(color: Theme.of(context).colorScheme.primary, width: 2)
            : BorderSide.none,
      ),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const PillClock(),
            if (weather != null) ...[
              const SizedBox(width: 8),
              Text(
                weather,
                maxLines: 1,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  shadows: [Shadow(color: Colors.black, blurRadius: 4, offset: Offset(0, 1))],
                ),
              ),
            ],
            const SizedBox(width: 6),
            const Icon(Icons.settings_rounded, color: Colors.white, size: 20,
                shadows: [Shadow(color: Colors.black, blurRadius: 4)]),
          ],
        ),
      ),
    );
  }

  Widget _draggablePill(double areaW, double areaH) {
    final freeW = (areaW - _pillW).clamp(1.0, double.infinity);
    final freeH = (areaH - _pillH).clamp(1.0, double.infinity);
    return GestureDetector(
      onPanUpdate: (d) => setState(() {
        final a = _pillAlign;
        _pillDraft = Offset(
          (a.dx + d.delta.dx / freeW).clamp(0.0, 1.0),
          (a.dy + d.delta.dy / freeH).clamp(0.0, 1.0),
        );
      }),
      child: _pill(highlighted: true),
    );
  }

  Widget _editToolbar() {
    final canAdd = (_draft?.length ?? 0) < _maxWindows;
    final style = FilledButton.styleFrom(
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
    );
    return Center(
      child: Material(
        color: Colors.black.withValues(alpha: 0.55),
        shape: const StadiumBorder(),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (canAdd) ...[
                FilledButton.tonalIcon(
                  style: style,
                  onPressed: _addWindow,
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Окно'),
                ),
                const SizedBox(width: 6),
              ],
              FilledButton.tonalIcon(
                style: style,
                onPressed: _openSettings,
                icon: const Icon(Icons.settings_rounded, size: 18),
                label: const Text('Настройки'),
              ),
              const SizedBox(width: 6),
              FilledButton.icon(
                style: style,
                onPressed: _toggleEditing,
                icon: const Icon(Icons.check_rounded, size: 18),
                label: const Text('Готово'),
              ),
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

  /// Еле заметная сетка в режиме правки — подсказывает привязку.
  Widget _gridBackdrop() {
    final color = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.06);
    return CustomPaint(painter: _GridPainter(color: color, step: WindowRect.snap));
  }

  Widget _editableWindow(WindowRect r, double areaW, double areaH) {
    final theme = Theme.of(context);
    final slot = slotById(r.slotId);

    Widget roundBtn(IconData icon, VoidCallback onTap) => Material(
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
          Positioned(top: 6, left: 6, child: roundBtn(Icons.settings_rounded, () => _pickContent(slot))),
          Positioned(top: 6, right: 6, child: roundBtn(Icons.delete_outline_rounded, () => _removeWindow(r.slotId))),
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
    final presets = context.read<PresetService>();
    if (presets.widgetFor(slotId) != null) {
      return Icon(Icons.widgets_rounded, size: size * 0.7, color: Theme.of(context).colorScheme.primary);
    }
    final pkg = presets.packageFor(slotId);
    final app = pkg == null ? null : _apps[pkg];
    if (app != null) return Image.memory(app.icon, width: size, height: size, gaplessPlayback: true);
    return Icon(Icons.add_rounded, size: size * 0.7, color: Theme.of(context).colorScheme.primary);
  }

  Widget _windowCard(String slotId, {bool editing = false}) {
    final theme = Theme.of(context);
    final slot = slotById(slotId);
    final presets = context.read<PresetService>();
    final widgetId = presets.widgetFor(slotId);
    final pkg = presets.packageFor(slotId);
    final app = pkg == null ? null : _apps[pkg];
    final missing = pkg != null && _appsLoaded && app == null;

    // Виджет в системном режиме рисуется нативно поверх; у многих виджетов
    // прозрачный фон — под ним должны быть обои, а не карточка с текстом.
    if (widgetId != null && _liveMode && !editing) {
      return SizedBox.expand(key: _keys[slotId]);
    }

    final String title;
    final String subtitle;
    if (widgetId != null) {
      title = presets.widgetLabelFor(slotId) ?? 'Виджет';
      subtitle = editing ? 'тяните — переместить, уголок — размер' : 'Виджет';
    } else if (pkg == null) {
      title = slot.hint;
      subtitle = editing ? '⚙ — выбрать приложение' : 'Нажмите, чтобы выбрать приложение';
    } else if (missing) {
      title = slot.hint;
      subtitle = 'Приложение удалено';
    } else {
      title = app?.label ?? slot.hint;
      subtitle = editing
          ? 'тяните — переместить, уголок — размер'
          : (_liveMode ? 'Живое окно' : 'Нажмите, чтобы открыть в окне');
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

    // Подсветка контура (в правке рамку рисует режим правки). В системном
    // режиме поверх карточки лежит живое окно со своей рамкой, а свечение
    // вокруг всё равно видно.
    final settings = context.read<SettingsService>();
    final glow = editing ? null : settings.windowBorderColor;
    final glowW = settings.windowBorderWidth;
    final glowS = settings.windowGlow;
    final radius = BorderRadius.circular(settings.windowCornerRadius);

    final card = Card(
      key: _keys[slotId],
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: glow == null ? BorderSide.none : BorderSide(color: glow, width: glowW),
      ),
      child: editing
          ? content
          : InkWell(
              onTap: () {
                if (_liveMode) {
                  _withWindowsHidden(() => _pickContent(slot));
                } else {
                  _openWindow(slotId);
                }
              },
              onLongPress: () => _withWindowsHidden(() => _pickContent(slot)),
              child: content,
            ),
    );
    if (glow == null || glowS <= 0) return card;
    // Два слоя: широкий мягкий ореол и плотное свечение у самого контура.
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: [
          BoxShadow(
            color: glow.withValues(alpha: 0.35 + 0.6 * glowS),
            blurRadius: 8 + 40 * glowS,
            spreadRadius: 1 + 6 * glowS,
          ),
          BoxShadow(
            color: glow.withValues(alpha: 0.5 + 0.5 * glowS),
            blurRadius: 2 + 10 * glowS,
            spreadRadius: glowS * 2,
          ),
        ],
      ),
      child: card,
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
