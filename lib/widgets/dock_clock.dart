import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Компактные часы для дока.
class DockClock extends StatefulWidget {
  const DockClock({super.key});

  @override
  State<DockClock> createState() => _DockClockState();
}

class _DockClockState extends State<DockClock> {
  DateTime _now = DateTime.now();
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      final now = DateTime.now();
      if (now.minute != _now.minute) setState(() => _now = now);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Одна строка: крупное время + мелкая дата рядом — минимум высоты.
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.firstBaseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          DateFormat.Hm().format(_now),
          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(width: 6),
        Text(
          DateFormat('d.MM').format(_now),
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
      ],
    );
  }
}
