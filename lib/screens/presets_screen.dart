import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/layout_preset.dart';
import '../services/native_bridge.dart';
import '../services/preset_service.dart';
import '../services/settings_service.dart';

/// Список сохранённых пресетов: сохранить текущую раскладку, включить,
/// перезаписать, переименовать, удалить. Возвращает пресет, который
/// нужно включить (или null).
class PresetsScreen extends StatelessWidget {
  const PresetsScreen({super.key, required this.appLabels});

  /// Пакет → название приложения, для подписи под пресетом.
  final Map<String, String> appLabels;

  static Future<String?> askName(BuildContext context, {required String title, String initial = ''}) {
    final controller = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Например: Город'),
          onSubmitted: (v) => Navigator.of(ctx).pop(v.trim()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Отмена')),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
  }

  String _summary(LayoutPreset p) {
    final parts = <String>[];
    for (final r in p.layout) {
      final c = p.slots[r.slotId];
      if (c == null) continue;
      parts.add(c.packageName != null
          ? (appLabels[c.packageName] ?? c.packageName!)
          : (c.widgetLabel ?? 'Виджет'));
    }
    return parts.isEmpty ? 'Окон: ${p.layout.length}, пустые' : parts.join(' · ');
  }

  void _deleteWidgets(List<int> ids) {
    for (final id in ids) {
      NativeBridge.deleteWidget(id).catchError((_) {});
    }
  }

  Future<void> _saveCurrent(BuildContext context, {int? index, String? name}) async {
    final presets = context.read<PresetService>();
    final settings = context.read<SettingsService>();
    final n = name ?? await askName(context, title: 'Новый пресет', initial: 'Пресет ${presets.savedPresets.length + 1}');
    if (n == null || n.isEmpty) return;
    final unused = await presets.savePreset(
      presets.snapshot(n, settings.windowLayout, settings.pillAlign),
      index: index,
    );
    _deleteWidgets(unused);
  }

  Future<void> _onAction(BuildContext context, String action, int index, LayoutPreset p) async {
    final presets = context.read<PresetService>();
    switch (action) {
      case 'overwrite':
        await _saveCurrent(context, index: index, name: p.name);
      case 'rename':
        final n = await askName(context, title: 'Переименовать', initial: p.name);
        if (n != null && n.isNotEmpty) await presets.renamePreset(index, n);
      case 'delete':
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text('Удалить «${p.name}»?'),
            actions: [
              TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Отмена')),
              FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Удалить')),
            ],
          ),
        );
        if (ok == true) _deleteWidgets(await presets.deletePreset(index));
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = context.watch<PresetService>().savedPresets;
    return Scaffold(
      appBar: AppBar(title: const Text('Пресеты')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          FilledButton.icon(
            onPressed: () => _saveCurrent(context),
            icon: const Icon(Icons.bookmark_add_rounded),
            label: const Text('Сохранить текущую раскладку'),
          ),
          const SizedBox(height: 8),
          Text(
            'Пресет запоминает, где стоят окна и что в них открыто. '
            'Переключаться можно из меню пилюли с часами.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          if (list.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: Text('Пресетов пока нет')),
            ),
          for (var i = 0; i < list.length; i++)
            Card(
              child: ListTile(
                leading: const Icon(Icons.dashboard_rounded),
                title: Text(list[i].name),
                subtitle: Text(_summary(list[i]), maxLines: 2, overflow: TextOverflow.ellipsis),
                onTap: () => Navigator.of(context).pop(list[i]),
                trailing: PopupMenuButton<String>(
                  onSelected: (a) => _onAction(context, a, i, list[i]),
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'overwrite', child: Text('Перезаписать текущей раскладкой')),
                    PopupMenuItem(value: 'rename', child: Text('Переименовать')),
                    PopupMenuItem(value: 'delete', child: Text('Удалить')),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
