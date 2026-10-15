import 'package:flutter/material.dart';

import '../models/app_info.dart';
import '../services/native_bridge.dart';

/// Выбор приложения для пресета. Показывает все установленные
/// приложения с поиском; возвращает выбранное через Navigator.pop.
class AppPickerScreen extends StatefulWidget {
  const AppPickerScreen({super.key, required this.title});

  final String title;

  @override
  State<AppPickerScreen> createState() => _AppPickerScreenState();
}

class _AppPickerScreenState extends State<AppPickerScreen> {
  late Future<List<AppInfo>> _appsFuture;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _appsFuture = NativeBridge.getInstalledApps();
  }

  void _reload() {
    setState(() => _appsFuture = NativeBridge.getInstalledApps());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(64),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Поиск приложения',
                prefixIcon: const Icon(Icons.search_rounded),
                filled: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
                isDense: true,
              ),
              onChanged: (value) =>
                  setState(() => _query = value.trim().toLowerCase()),
            ),
          ),
        ),
      ),
      body: FutureBuilder<List<AppInfo>>(
        future: _appsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _Message(
              text: 'Не удалось получить список приложений:\n${snapshot.error}',
              actionLabel: 'Повторить',
              onAction: _reload,
            );
          }

          final apps = (snapshot.data ?? const <AppInfo>[])
              .where((a) => _query.isEmpty || a.label.toLowerCase().contains(_query))
              .toList();

          if (apps.isEmpty) {
            return _Message(
              text: _query.isEmpty
                  ? 'Приложения не найдены'
                  : 'Ничего не найдено по запросу «$_query»',
            );
          }

          return GridView.builder(
            padding: const EdgeInsets.all(16),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 120,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 0.9,
            ),
            itemCount: apps.length,
            itemBuilder: (context, index) {
              final app = apps[index];
              return InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => Navigator.of(context).pop(app),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Image.memory(app.icon, width: 56, height: 56, gaplessPlayback: true),
                    const SizedBox(height: 8),
                    Text(
                      app.label,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.text, this.actionLabel, this.onAction});

  final String text;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(text, textAlign: TextAlign.center),
            if (actionLabel != null) ...[
              const SizedBox(height: 16),
              FilledButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}
