import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/obd_service.dart';

/// Встроенная панель приборов OBD: напряжение сети и температура
/// двигателя — крупно, минималистично; выход за норму — цветом.
class ObdPanel extends StatelessWidget {
  const ObdPanel({super.key});

  static Color _voltColor(double? v) {
    if (v == null) return Colors.white38;
    if (v < 11.8 || v > 15.0) return const Color(0xFFFF1744);
    if (v < 12.2 || v > 14.7) return const Color(0xFFFFC400);
    return Colors.white;
  }

  static Color _tempColor(int? t) {
    if (t == null) return Colors.white38;
    if (t >= 105) return const Color(0xFFFF1744);
    if (t >= 100) return const Color(0xFFFFC400);
    if (t < 60) return const Color(0xFF40C4FF); // ещё не прогрет
    return Colors.white;
  }

  @override
  Widget build(BuildContext context) {
    final obd = context.watch<ObdService>();
    final v = obd.voltage;
    final t = obd.coolant;
    final ok = obd.state == 'connected';
    final volt = _Gauge(
      icon: Icons.battery_charging_full_rounded,
      value: v == null ? '—' : v.toStringAsFixed(1).replaceAll('.', ','),
      unit: 'В',
      color: ok ? _voltColor(v) : Colors.white38,
    );
    final temp = _Gauge(
      icon: Icons.thermostat_rounded,
      value: t == null ? '—' : '$t',
      unit: '°C',
      color: ok ? _tempColor(t) : Colors.white38,
    );
    return ColoredBox(
      color: const Color(0xE6080A0F),
      child: LayoutBuilder(builder: (context, c) {
        final wide = c.maxWidth > c.maxHeight * 1.2;
        final gauges = wide
            ? Row(children: [Expanded(child: volt), Expanded(child: temp)])
            : Column(children: [Expanded(child: volt), Expanded(child: temp)]);
        return Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            children: [
              Expanded(child: gauges),
              if (!ok || obd.ecuSilent)
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(obd.statusText, style: const TextStyle(color: Colors.white54, fontSize: 11)),
                ),
            ],
          ),
        );
      }),
    );
  }
}

class _Gauge extends StatelessWidget {
  const _Gauge({required this.icon, required this.value, required this.unit, required this.color});

  final IconData icon;
  final String value;
  final String unit;
  final Color color;

  @override
  Widget build(BuildContext context) {
    // Всё ужимается под размер окна.
    return Center(
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color.withValues(alpha: 0.8), size: 30),
            const SizedBox(width: 6),
            Text(value, style: TextStyle(color: color, fontSize: 44, fontWeight: FontWeight.w700)),
            const SizedBox(width: 4),
            Text(unit, style: TextStyle(color: color.withValues(alpha: 0.7), fontSize: 18)),
          ],
        ),
      ),
    );
  }
}
