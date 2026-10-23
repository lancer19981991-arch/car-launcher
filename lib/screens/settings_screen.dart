import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/weather_place.dart';
import '../services/native_bridge.dart';
import '../services/settings_service.dart';
import '../services/weather_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool? _isDefaultLauncher;
  bool? _isDeviceOwner;
  bool _kioskOn = false;

  @override
  void initState() {
    super.initState();
    _refreshStatus();
  }

  Future<void> _refreshStatus() async {
    final isDefault = await NativeBridge.isDefaultLauncher();
    final isOwner = await NativeBridge.isDeviceOwner();
    if (!mounted) return;
    setState(() {
      _isDefaultLauncher = isDefault;
      _isDeviceOwner = isOwner;
    });
  }

  String _weatherStatus(BuildContext context) {
    final w = context.watch<WeatherService>();
    if (w.error != null) return w.error!;
    if (w.text != null) return 'Сейчас: ${w.text}';
    return 'Загрузка…';
  }

  Future<void> _pickCity(BuildContext context) async {
    final settings = context.read<SettingsService>();
    final place = await showDialog<WeatherPlace>(
      context: context,
      builder: (_) => const _CitySearchDialog(),
    );
    if (place != null) await settings.setWeatherCity(place);
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();

    return Scaffold(
      appBar: AppBar(title: const Text('Настройки')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _SectionLabel('Окна'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Раскладка окон: нажмите пилюлю с часами → «Изменить '
                    'раскладку». Окно тянется — перемещается, уголок — меняет '
                    'размер, «+ Окно» — добавить (до 4), корзина — убрать. '
                    'Пилюлю с часами тоже можно перетащить.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                        ),
                  ),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: () => settings.resetWindowLayout(),
                    icon: const Icon(Icons.restart_alt_rounded),
                    label: const Text('Сбросить раскладку (3 окна стопкой)'),
                  ),
                  const Divider(height: 24),
                  Text('Запас снизу (под климат-панель): ${settings.bottomReserve.round()} px'),
                  Slider(
                    min: 0,
                    max: 400,
                    divisions: 80,
                    value: settings.bottomReserve,
                    label: '${settings.bottomReserve.round()}',
                    onChanged: (v) => settings.setBottomReserve(v),
                  ),
                  const Text('Увеличивайте, пока нижнее окно не перестанет '
                      'заходить под панель климата.'),
                  const SizedBox(height: 12),
                  Text('Запас сверху (под статус-бар): ${settings.topReserve.round()} px'),
                  Slider(
                    min: 0,
                    max: 200,
                    divisions: 40,
                    value: settings.topReserve,
                    label: '${settings.topReserve.round()}',
                    onChanged: (v) => settings.setTopReserve(v),
                  ),
                  const Divider(height: 24),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Не перезапускать окна при открытии настроек'),
                    subtitle: const Text(
                      'Окна только прячутся на время настроек, меню и выбора '
                      'приложения. Экспериментально: если после настроек окна '
                      'ведут себя странно — выключите.',
                    ),
                    value: settings.keepWindowsInLauncher,
                    onChanged: (v) => settings.setKeepWindowsInLauncher(v),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Не перезапускать окна при выходе из лаунчера'),
                    subtitle: const Text(
                      'Приложения в окнах продолжат работать, пока открыто другое '
                      'приложение. Экспериментально: если приложение из окна, '
                      'запущенное отдельно, не появляется на экране — выключите.',
                    ),
                    value: settings.keepWindowsInBackground,
                    onChanged: (v) => settings.setKeepWindowsInBackground(v),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          _SectionLabel('Погода'),
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text('Погода в пилюле с часами'),
                  subtitle: const Text('Значок и температура рядом с часами'),
                  value: settings.weatherEnabled,
                  onChanged: (v) => settings.setWeatherEnabled(v),
                ),
                if (settings.weatherEnabled) ...[
                  ListTile(
                    leading: const Icon(Icons.location_on_outlined),
                    title: Text(settings.weatherCity?.name ?? 'По местоположению (GPS)'),
                    subtitle: Text(_weatherStatus(context)),
                    trailing: TextButton(
                      onPressed: () => _pickCity(context),
                      child: const Text('Выбрать город'),
                    ),
                  ),
                  if (settings.weatherCity != null)
                    ListTile(
                      leading: const Icon(Icons.my_location_rounded),
                      title: const Text('Определять по местоположению'),
                      onTap: () => settings.setWeatherCity(null),
                    ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 24),
          _SectionLabel('Оформление'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Подсветка контура окон'),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      _ColorDot(
                        color: null,
                        selected: settings.windowBorderColor == null,
                        onTap: () => settings.setWindowBorderColor(null),
                      ),
                      for (final c in SettingsService.borderColors)
                        _ColorDot(
                          color: c,
                          selected: settings.windowBorderColor?.toARGB32() == c.toARGB32(),
                          onTap: () => settings.setWindowBorderColor(c),
                        ),
                    ],
                  ),
                  if (settings.windowBorderColor != null) ...[
                    const SizedBox(height: 12),
                    Text('Толщина контура: ${settings.windowBorderWidth.round()} px'),
                    Slider(
                      min: 1,
                      max: 8,
                      divisions: 7,
                      value: settings.windowBorderWidth,
                      label: '${settings.windowBorderWidth.round()}',
                      onChanged: (v) => settings.setWindowBorderWidth(v),
                    ),
                    Text('Свечение: ${(settings.windowGlow * 100).round()}%'),
                    Slider(
                      min: 0,
                      max: 1,
                      divisions: 10,
                      value: settings.windowGlow,
                      label: '${(settings.windowGlow * 100).round()}%',
                      onChanged: (v) => settings.setWindowGlow(v),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Text('Скругление углов окон: ${settings.windowCornerRadius.round()} px'),
                  Slider(
                    min: 0,
                    max: 40,
                    divisions: 20,
                    value: settings.windowCornerRadius,
                    label: '${settings.windowCornerRadius.round()}',
                    onChanged: (v) => settings.setWindowCornerRadius(v),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                RadioListTile<ThemeMode>(
                  title: const Text('Как в системе'),
                  value: ThemeMode.system,
                  groupValue: settings.themeMode,
                  onChanged: (m) => settings.setThemeMode(m!),
                ),
                RadioListTile<ThemeMode>(
                  title: const Text('Светлая'),
                  value: ThemeMode.light,
                  groupValue: settings.themeMode,
                  onChanged: (m) => settings.setThemeMode(m!),
                ),
                RadioListTile<ThemeMode>(
                  title: const Text('Тёмная'),
                  value: ThemeMode.dark,
                  groupValue: settings.themeMode,
                  onChanged: (m) => settings.setThemeMode(m!),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          _SectionLabel('Лаунчер по умолчанию'),
          Card(
            child: ListTile(
              leading: Icon(
                _isDefaultLauncher == true
                    ? Icons.check_circle_rounded
                    : Icons.info_outline_rounded,
                color: _isDefaultLauncher == true ? Colors.green : null,
              ),
              title: Text(
                _isDefaultLauncher == true
                    ? 'Приложение уже является домашним экраном'
                    : 'Приложение ещё не назначено домашним экраном',
              ),
              subtitle: const Text(
                'Нужно, чтобы экран открывался при включении устройства '
                'вместо стандартного лаунчера Android.',
              ),
              trailing: FilledButton(
                onPressed: () async {
                  await NativeBridge.requestDefaultLauncher();
                  await _refreshStatus();
                },
                child: const Text('Назначить'),
              ),
            ),
          ),
          const SizedBox(height: 24),
          _SectionLabel('Киоск-режим (Device Owner)'),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: Icon(
                    _isDeviceOwner == true
                        ? Icons.verified_user_rounded
                        : Icons.lock_outline_rounded,
                    color: _isDeviceOwner == true ? Colors.green : null,
                  ),
                  title: Text(
                    _isDeviceOwner == true
                        ? 'Приложение зарегистрировано как Device Owner'
                        : 'Device Owner не настроен',
                  ),
                  subtitle: const Text(
                    'Без Device Owner пользователь всегда сможет свернуть '
                    'или закрыть лаунчер — это нормальное ограничение '
                    'Android для обычных приложений. Как включить Device '
                    'Owner — см. README проекта.',
                  ),
                ),
                if (_isDeviceOwner == true)
                  SwitchListTile(
                    title: const Text('Полноэкранный киоск-режим'),
                    subtitle: const Text(
                      'Блокирует кнопки "Домой"/"Недавние" и статус-бар',
                    ),
                    value: _kioskOn,
                    onChanged: (value) async {
                      if (value) {
                        final ok = await NativeBridge.startKioskMode();
                        setState(() => _kioskOn = ok);
                      } else {
                        await NativeBridge.stopKioskMode();
                        setState(() => _kioskOn = false);
                      }
                    },
                  ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Center(
            child: Text(
              'Car Launcher · версия 1.0.0',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Theme.of(context).disabledColor),
            ),
          ),
        ],
      ),
    );
  }
}

/// Поиск города для погоды по названию.
class _CitySearchDialog extends StatefulWidget {
  const _CitySearchDialog();

  @override
  State<_CitySearchDialog> createState() => _CitySearchDialogState();
}

class _CitySearchDialogState extends State<_CitySearchDialog> {
  final _controller = TextEditingController();
  List<WeatherPlace> _results = const [];
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final q = _controller.text.trim();
    if (q.length < 2) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await WeatherService.searchCity(q);
      if (!mounted) return;
      setState(() {
        _results = r;
        if (r.isEmpty) _error = 'Ничего не найдено';
      });
    } catch (_) {
      if (mounted) setState(() => _error = 'Нет связи с сервером погоды');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Город для погоды'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _controller,
              autofocus: true,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Например: Москва',
                suffixIcon: IconButton(icon: const Icon(Icons.search_rounded), onPressed: _search),
              ),
              onSubmitted: (_) => _search(),
            ),
            const SizedBox(height: 8),
            if (_loading) const Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator()),
            if (_error != null) Padding(padding: const EdgeInsets.all(8), child: Text(_error!)),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final p in _results)
                    ListTile(
                      title: Text(p.name),
                      subtitle: p.region == null || p.region!.isEmpty ? null : Text(p.region!),
                      onTap: () => Navigator.of(context).pop(p),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Отмена')),
      ],
    );
  }
}

/// Кружок выбора цвета подсветки; [color] == null — «без подсветки».
class _ColorDot extends StatelessWidget {
  const _ColorDot({required this.color, required this.selected, required this.onTap});

  final Color? color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      customBorder: const CircleBorder(),
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color ?? scheme.surfaceContainerHighest,
          border: Border.all(
            color: selected ? scheme.primary : scheme.outline.withValues(alpha: 0.4),
            width: selected ? 3 : 1,
          ),
          boxShadow: color != null && selected
              ? [BoxShadow(color: color!.withValues(alpha: 0.6), blurRadius: 8)]
              : null,
        ),
        child: color == null
            ? Icon(Icons.block_rounded, size: 20, color: scheme.onSurface.withValues(alpha: 0.6))
            : (selected ? const Icon(Icons.check_rounded, size: 20, color: Colors.black) : null),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 4),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: Theme.of(context).colorScheme.primary,
            ),
      ),
    );
  }
}
