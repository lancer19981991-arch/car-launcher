import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/tpms_service.dart';

/// Встроенная панель шин: схема машины сверху и четыре колеса вокруг.
/// Минималистично, в стиле лаунчера; тревога — красным.
class TpmsPanel extends StatelessWidget {
  const TpmsPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final tpms = context.watch<TpmsService>();
    final pos = tpms.byPosition;
    final last = tpms.lastAt;
    final stale = last == null || DateTime.now().difference(last) > const Duration(minutes: 5);

    // Свой тёмный фон — панель читается при любой теме и обоях.
    return ColoredBox(color: const Color(0xE6080A0F), child: LayoutBuilder(builder: (context, c) {
      // Всё масштабируется от размера окна.
      final s = (c.biggest.shortestSide / 220).clamp(0.5, 2.5);
      final car = Container(
        width: 46 * s,
        height: 96 * s,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18 * s),
          border: Border.all(color: Colors.white.withValues(alpha: 0.35), width: 2 * s),
        ),
      );
      return Padding(
        padding: EdgeInsets.all(8 * s),
        child: Column(
          children: [
            Expanded(
              child: Row(
                children: [
                  Expanded(child: _TireColumn(left: true, front: pos[0], rear: pos[2], scale: s)),
                  car,
                  Expanded(child: _TireColumn(left: false, front: pos[1], rear: pos[3], scale: s)),
                ],
              ),
            ),
            if (stale)
              Padding(
                padding: EdgeInsets.only(top: 4 * s),
                child: Text(
                  last == null ? 'Нет данных от TPMS-приложения' : 'Нет новых данных больше 5 мин',
                  style: TextStyle(color: Colors.white54, fontSize: 11 * s),
                  textAlign: TextAlign.center,
                ),
              ),
          ],
        ),
      );
    }));
  }
}

class _TireColumn extends StatelessWidget {
  const _TireColumn({required this.left, required this.front, required this.rear, required this.scale});

  final bool left;
  final TireState? front;
  final TireState? rear;
  final double scale;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      crossAxisAlignment: left ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        _Tire(state: front, left: left, scale: scale),
        _Tire(state: rear, left: left, scale: scale),
      ],
    );
  }
}

class _Tire extends StatelessWidget {
  const _Tire({required this.state, required this.left, required this.scale});

  final TireState? state;
  final bool left;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final st = state;
    final s = scale;
    final Color color;
    final String note;
    if (st == null) {
      color = Colors.white38;
      note = '';
    } else if (st.noSignal) {
      color = Colors.white38;
      note = 'нет сигнала';
    } else if (st.leakage) {
      color = const Color(0xFFFF1744);
      note = 'утечка!';
    } else if (st.lowPower) {
      color = const Color(0xFFFFC400);
      note = 'батарейка';
    } else {
      color = Colors.white;
      note = '';
    }
    final align = left ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 10 * s),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: align,
        children: [
          Text.rich(
            TextSpan(children: [
              TextSpan(
                text: st?.pressureText ?? '—',
                style: TextStyle(fontSize: 26 * s, fontWeight: FontWeight.w700, color: color),
              ),
              TextSpan(
                text: ' ${st?.unitShort ?? ''}',
                style: TextStyle(fontSize: 11 * s, color: color.withValues(alpha: 0.7)),
              ),
            ]),
            maxLines: 1,
          ),
          Text(
            st?.temperature == null ? '' : '${st!.temperature}°C',
            style: TextStyle(fontSize: 14 * s, color: Colors.white70),
          ),
          if (note.isNotEmpty)
            Text(note, style: TextStyle(fontSize: 11 * s, color: color, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
