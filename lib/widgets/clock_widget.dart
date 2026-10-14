import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Крупные часы + дата для главного экрана.
class ClockWidget extends StatefulWidget {
  const ClockWidget({super.key});

  @override
  State<ClockWidget> createState() => _ClockWidgetState();
}

class _ClockWidgetState extends State<ClockWidget> {
  late DateTime _now;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _now = DateTime.now();
    // Обновляем раз в секунду — для автомобильного лаунчера это не нагрузка.
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final timeFormat = DateFormat.Hm();
    final dateFormat = DateFormat('EEEE, d MMMM');
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          timeFormat.format(_now),
          style: theme.textTheme.displayLarge?.copyWith(
            fontWeight: FontWeight.w600,
            fontSize: 64,
            height: 1.0,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          _capitalize(dateFormat.format(_now)),
          style: theme.textTheme.titleMedium?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
          ),
        ),
      ],
    );
  }

  String _capitalize(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}
