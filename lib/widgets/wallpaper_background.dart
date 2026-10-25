import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/settings_service.dart';
import '../theme/app_theme.dart';

/// Варианты фона главного экрана (Настройки → Оформление → Фон).
enum Wallpaper {
  /// Градиент по теме (светлая/тёмная) — как было изначально.
  gradient('Градиент'),

  /// Тёмная сетка из перекрещивающихся зигзагов — как за цифрами
  /// на спидометре пользователя.
  speedoMesh('Сетка спидометра'),

  /// Та же сетка с синим свечением снизу — как кольцо спидометра.
  speedoGlow('Сетка + свечение'),

  /// Просто чёрный.
  black('Чёрный');

  const Wallpaper(this.title);
  final String title;

  static Wallpaper byName(String? name) =>
      Wallpaper.values.firstWhere((w) => w.name == name, orElse: () => Wallpaper.gradient);
}

/// Фон экрана — выбранный в настройках вариант.
class WallpaperBackground extends StatelessWidget {
  const WallpaperBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final kind = context.watch<SettingsService>().wallpaper;
    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(child: RepaintBoundary(child: WallpaperPreview(kind: kind))),
        child,
      ],
    );
  }
}

/// Отрисовка одного варианта фона (и на экране, и в превью настроек).
class WallpaperPreview extends StatelessWidget {
  const WallpaperPreview({super.key, required this.kind, this.cell = 22});

  final Wallpaper kind;

  /// Размер ячейки сетки (в превью мельче).
  final double cell;

  @override
  Widget build(BuildContext context) {
    switch (kind) {
      case Wallpaper.gradient:
        return DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: AppTheme.wallpaper(Theme.of(context).brightness),
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
        );
      case Wallpaper.black:
        return const ColoredBox(color: Colors.black);
      case Wallpaper.speedoMesh:
      case Wallpaper.speedoGlow:
        return CustomPaint(
          painter: _MeshPainter(cell: cell, glow: kind == Wallpaper.speedoGlow),
          child: const SizedBox.expand(),
        );
    }
  }
}

/// Сетка «как на спидометре»: ряды зигзагов, амплитуда больше шага
/// между рядами — соседние ряды перекрещиваются и дают ромбы с двойными
/// гранями. Тонкие серые линии на почти чёрном.
class _MeshPainter extends CustomPainter {
  _MeshPainter({required this.cell, required this.glow});

  final double cell;
  final bool glow;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(rect, Paint()..color = const Color(0xFF050506));

    if (glow) {
      // Синее свечение снизу по центру, как подсветка кольца спидометра.
      final r = math.max(size.width, size.height) * 0.75;
      canvas.drawRect(
        rect,
        Paint()
          ..shader = RadialGradient(
            colors: const [Color(0x662962FF), Color(0x1A2962FF), Color(0x002962FF)],
            stops: const [0.0, 0.45, 1.0],
          ).createShader(Rect.fromCircle(center: Offset(size.width / 2, size.height * 1.05), radius: r)),
      );
    }

    final line = Paint()
      ..color = const Color(0xFF34363A)
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(0.8, cell / 22)
      ..isAntiAlias = true;

    final period = cell; // ширина одного зубца
    final amp = cell * 0.95; // высота зубца — больше шага рядов
    final rowStep = cell * 0.55;
    final rows = (size.height / rowStep).ceil() + 4;
    for (var i = -2; i < rows; i++) {
      final y0 = i * rowStep;
      // Чётные и нечётные ряды сдвинуты на полпериода — получаются ромбы.
      final shift = (i.isEven ? 0.0 : period / 2);
      final path = Path()..moveTo(-period + shift, y0);
      var up = true;
      for (var x = -period + shift; x < size.width + period; x += period / 2) {
        path.lineTo(x + period / 2, up ? y0 - amp / 2 : y0 + amp / 2);
        up = !up;
      }
      canvas.drawPath(path, line);
    }

    // Лёгкое затемнение к краям, чтобы сетка не спорила с окнами.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const RadialGradient(
          colors: [Color(0x00000000), Color(0x99000000)],
          stops: [0.55, 1.0],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_MeshPainter old) => old.cell != cell || old.glow != glow;
}
