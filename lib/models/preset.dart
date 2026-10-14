import 'package:flutter/material.dart';

/// Один "пресет" на главном экране — быстрый ярлык
/// (радиостанция, приложение, сценарий и т.п.).
///
/// [action] выполняется по тапу. Сюда позже можно подставить
/// реальный запуск приложения через NativeBridge.launchApp(packageName).
class CarPreset {
  const CarPreset({
    required this.title,
    required this.icon,
    required this.action,
  });

  final String title;
  final IconData icon;
  final VoidCallback action;
}
