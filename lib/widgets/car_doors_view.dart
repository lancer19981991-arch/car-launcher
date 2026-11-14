import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/doors_service.dart';

/// Машина пользователя сверху (assets/car_top.png, перед вверх) с живыми
/// дверями: створка — вырезанная из того же фото полоска борта — плавно
/// поворачивается на петле у переднего края, в проёме тёмный порог и узкая
/// полоска салона; багажник — крышка укорачивается к заднему стеклу, сзади
/// тёмный проём; капот — красная подсветка. Геометрия — доли картинки.
class CarDoorsView extends StatelessWidget {
  const CarDoorsView({super.key, required this.height});

  final double height;

  static const aspect = 391 / 900; // ширина / высота car_top.png
  static const _doors = {
    // сторона (−1 лев., +1 прав.), x0, x1, y0, y1
    'fl': (-1, 0.035, 0.165, 0.360, 0.548),
    'rl': (-1, 0.035, 0.165, 0.548, 0.735),
    'fr': (1, 0.835, 0.965, 0.360, 0.548),
    'rr': (1, 0.835, 0.965, 0.548, 0.735),
  };

  @override
  Widget build(BuildContext context) {
    final doors = context.watch<DoorsService>();
    final w = height * aspect;
    final h = height;
    final img = Image.asset('assets/car_top.png', width: w, height: h, fit: BoxFit.fill, filterQuality: FilterQuality.medium);

    Widget anim(bool open, Duration d, Widget Function(double t) build) => TweenAnimationBuilder<double>(
          tween: Tween(end: open ? 1 : 0),
          duration: d,
          curve: Curves.easeInOut,
          builder: (_, t, __) => t <= 0.001 ? const SizedBox.shrink() : build(t),
        );

    /// Кусок фото машины в прямоугольнике [x0..x1]×[y0..y1] (доли).
    Widget piece(double x0, double y0, double x1, double y1) => ClipRect(
          child: OverflowBox(
            alignment: Alignment.topLeft,
            minWidth: w,
            maxWidth: w,
            minHeight: h,
            maxHeight: h,
            child: Transform.translate(offset: Offset(-x0 * w, -y0 * h), child: img),
          ),
        );

    final layers = <Widget>[Positioned.fill(child: img)];

    // Капот: подсветка
    layers.add(anim(doors.isOpen('hood'), const Duration(milliseconds: 350), (t) => Positioned(
          left: 0.16 * w,
          top: 0.03 * h,
          width: 0.68 * w,
          height: 0.25 * h,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: const Color(0xFFFF283C).withValues(alpha: 0.28 * t),
              borderRadius: BorderRadius.circular(0.1 * w),
              border: Border.all(color: const Color(0xFFFF283C).withValues(alpha: t), width: 2),
            ),
          ),
        )));

    // Двери
    for (final e in _doors.entries) {
      final (side, x0, x1, y0, y1) = e.value;
      final pw = (x1 - x0) * w, ph = (y1 - y0) * h;
      layers.add(anim(doors.isOpen(e.key), const Duration(milliseconds: 450), (t) {
        final hingeLeft = side < 0;
        return Positioned(
          left: x0 * w,
          top: y0 * h,
          width: pw,
          height: ph,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // проём: тёмный порог + узкая полоска салона у крыши
              Positioned.fill(
                child: Opacity(
                  opacity: (t * 3).clamp(0.0, 1.0),
                  child: Container(
                    color: const Color(0xFF0E0E11),
                    alignment: hingeLeft ? Alignment.centerRight : Alignment.centerLeft,
                    child: FractionallySizedBox(
                      widthFactor: 0.38,
                      heightFactor: 0.52,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: const Color(0xFF34241A),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              // створка на петле (внешний передний угол)
              Positioned.fill(
                child: Transform.rotate(
                  angle: (hingeLeft ? 1 : -1) * 62 * t * 3.14159265 / 180,
                  alignment: hingeLeft ? Alignment.topLeft : Alignment.topRight,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.5 * t), blurRadius: 6)],
                      border: Border(
                        left: hingeLeft ? BorderSide(color: Colors.white.withValues(alpha: 0.6 * t)) : BorderSide.none,
                        right: hingeLeft ? BorderSide.none : BorderSide(color: Colors.white.withValues(alpha: 0.6 * t)),
                      ),
                    ),
                    child: piece(x0, y0, x1, y1),
                  ),
                ),
              ),
            ],
          ),
        );
      }));
    }

    // Багажник
    const tx0 = 0.22, tx1 = 0.78, ty0 = 0.888, ty1 = 0.962;
    layers.add(anim(doors.isOpen('trunk'), const Duration(milliseconds: 600), (t) => Positioned(
          left: tx0 * w,
          top: ty0 * h,
          width: (tx1 - tx0) * w,
          height: (ty1 - ty0) * h,
          child: Stack(
            children: [
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF121215),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: const Color(0xFF464850), width: 1.5),
                  ),
                  padding: const EdgeInsets.all(4),
                  child: DecoratedBox(
                    decoration: BoxDecoration(color: const Color(0xFF222226), borderRadius: BorderRadius.circular(4)),
                  ),
                ),
              ),
              // крышка укорачивается к петлям (к заднему стеклу) и светлеет
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                height: (ty1 - ty0) * h * (1 - 0.72 * t),
                child: DecoratedBox(
                  position: DecorationPosition.foreground,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.12 * t),
                    border: Border(bottom: BorderSide(color: const Color(0xFFBEC3CD).withValues(alpha: 0.8 * t), width: 1.5)),
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.55 * t), blurRadius: 5, offset: const Offset(0, 3))],
                  ),
                  child: ClipRect(
                    child: FittedBox(
                      fit: BoxFit.fill,
                      child: SizedBox(
                        width: (tx1 - tx0) * w,
                        height: (ty1 - ty0) * h,
                        child: piece(tx0, ty0, tx1, ty1),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        )));

    return SizedBox(width: w, height: h, child: Stack(clipBehavior: Clip.none, children: layers));
  }
}
