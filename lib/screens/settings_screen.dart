import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/native_bridge.dart';
import '../services/settings_service.dart';

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
                  const Text('Количество окон на экране'),
                  const SizedBox(height: 12),
                  SegmentedButton<int>(
                    segments: const [
                      ButtonSegment(value: 1, label: Text('1')),
                      ButtonSegment(value: 2, label: Text('2')),
                      ButtonSegment(value: 3, label: Text('3')),
                    ],
                    selected: {settings.windowCount},
                    onSelectionChanged: (s) => settings.setWindowCount(s.first),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Размер окон меняется перетаскиванием разделителей '
                    'в режиме «Изменить» на главном экране.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                        ),
                  ),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: () => settings.setWindowWeights(const [2.0, 1.0, 1.0]),
                    icon: const Icon(Icons.restart_alt_rounded),
                    label: const Text('Сбросить пропорции'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          _SectionLabel('Оформление'),
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
