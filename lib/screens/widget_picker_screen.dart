import 'package:flutter/material.dart';

import '../models/widget_provider.dart';
import '../services/native_bridge.dart';

/// Выбор виджета рабочего стола для окна. Виджеты сгруппированы по
/// приложениям, есть поиск. Возвращает выбранный WidgetProvider.
class WidgetPickerScreen extends StatefulWidget {
  const WidgetPickerScreen({super.key, required this.title});

  final String title;

  @override
  State<WidgetPickerScreen> createState() => _WidgetPickerScreenState();
}

class _WidgetPickerScreenState extends State<WidgetPickerScreen> {
  late Future<List<WidgetProvider>> _future;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _future = NativeBridge.getWidgetProviders();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(64),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Поиск виджета или приложения',
                prefixIcon: const Icon(Icons.search_rounded),
                filled: true,
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
              ),
              onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
            ),
          ),
        ),
      ),
      body: FutureBuilder<List<WidgetProvider>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text('Не удалось получить список виджетов:\n${snap.error}', textAlign: TextAlign.center));
          }
          final items = (snap.data ?? const <WidgetProvider>[])
              .where((w) =>
                  _query.isEmpty ||
                  w.label.toLowerCase().contains(_query) ||
                  w.appLabel.toLowerCase().contains(_query))
              .toList();
          if (items.isEmpty) {
            return const Center(child: Text('Виджеты не найдены'));
          }
          return ListView.builder(
            itemCount: items.length,
            itemBuilder: (context, i) {
              final w = items[i];
              final newGroup = i == 0 || items[i - 1].appLabel != w.appLabel;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (newGroup)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                      child: Text(w.appLabel,
                          style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.primary)),
                    ),
                  ListTile(
                    leading: SizedBox(
                      width: 40,
                      height: 40,
                      child: w.icon.isEmpty
                          ? const Icon(Icons.widgets_rounded)
                          : Image.memory(w.icon, gaplessPlayback: true),
                    ),
                    title: Text(w.label),
                    onTap: () => Navigator.of(context).pop(w),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}
