import 'package:flutter/material.dart';

/// Цветовые токены и темы приложения.
///
/// Вместо картинок-обоев фон главного экрана рисуется градиентом —
/// это даёт тот же эффект "тема дня/ночи", но без лишних ассетов.
class AppPalette {
  const AppPalette._();

  static const Color accent = Color(0xFF4F8CFF);
  static const Color accentDark = Color(0xFF2C5FD6);

  static const List<Color> wallpaperLight = [
    Color(0xFFEAF1FF),
    Color(0xFFD7E4FF),
  ];

  static const List<Color> wallpaperDark = [
    Color(0xFF0B1220),
    Color(0xFF1B2436),
  ];
}

class AppTheme {
  const AppTheme._();

  static ThemeData light() {
    final base = ThemeData.light(useMaterial3: true);
    return base.copyWith(
      colorScheme: base.colorScheme.copyWith(
        primary: AppPalette.accent,
        secondary: AppPalette.accentDark,
      ),
      scaffoldBackgroundColor: Colors.transparent,
      cardTheme: base.cardTheme.copyWith(
        elevation: 0,
        color: Colors.white.withValues(alpha: 0.72),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28),
        ),
      ),
    );
  }

  static ThemeData dark() {
    final base = ThemeData.dark(useMaterial3: true);
    return base.copyWith(
      colorScheme: base.colorScheme.copyWith(
        primary: AppPalette.accent,
        secondary: AppPalette.accentDark,
      ),
      scaffoldBackgroundColor: Colors.transparent,
      cardTheme: base.cardTheme.copyWith(
        elevation: 0,
        color: Colors.white.withValues(alpha: 0.08),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28),
        ),
      ),
    );
  }

  static List<Color> wallpaper(Brightness brightness) {
    return brightness == Brightness.dark
        ? AppPalette.wallpaperDark
        : AppPalette.wallpaperLight;
  }
}
