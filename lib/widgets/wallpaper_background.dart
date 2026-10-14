import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Фон экрана — градиент, зависящий от текущей темы (светлая/тёмная).
/// Заменяет собой набор картинок "wallpaper_X_light/dark.webp".
class WallpaperBackground extends StatelessWidget {
  const WallpaperBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: AppTheme.wallpaper(brightness),
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: child,
    );
  }
}
