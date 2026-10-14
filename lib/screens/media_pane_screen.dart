import 'package:flutter/material.dart';

import '../widgets/media_player_card.dart';
import '../widgets/wallpaper_background.dart';

/// Правая панель лаунчера — отдельное окно (MediaPaneActivity на
/// нативной стороне), показывается рядом с главным экраном, когда
/// устройство поддерживает Jetpack Activity Embedding (см. README).
///
/// Это самостоятельное Flutter-окно (свой FlutterEngine из общей
/// FlutterEngineGroup, свой initial route "/media_pane" — см. app.dart),
/// поэтому у него нет доступа к состоянию главного окна напрямую:
/// обмен данными между панелями, если понадобится, делайте через
/// нативную сторону (MethodChannel/EventChannel) или общее хранилище
/// (SharedPreferences и т.п.), а не через Dart-объекты в памяти.
class MediaPaneScreen extends StatelessWidget {
  const MediaPaneScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: WallpaperBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Медиа', style: theme.textTheme.titleLarge),
                const SizedBox(height: 16),
                const MediaPlayerCard(),
                const SizedBox(height: 16),
                Expanded(
                  child: Center(
                    child: Icon(
                      Icons.graphic_eq_rounded,
                      size: 96,
                      color: theme.colorScheme.primary.withValues(alpha: 0.25),
                    ),
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
