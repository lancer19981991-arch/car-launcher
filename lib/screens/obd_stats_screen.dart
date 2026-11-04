import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/native_bridge.dart';
import '../services/obd_log.dart';
import '../services/obd_service.dart';

/// Статистика OBD: за выбранный день — график температур двигателя и
/// вариатора и график напряжения; мин/макс/среднее; выгрузка в CSV.
/// Касание графика показывает значения в этот момент.
class ObdStatsScreen extends StatefulWidget {
  const ObdStatsScreen({super.key});

  @override
  State<ObdStatsScreen> createState() => _ObdStatsScreenState();
}

class _ObdStatsScreenState extends State<ObdStatsScreen> {
  static const engineColor = Color(0xFFFF9100);
  static const cvtColor = Color(0xFF00E5FF);
  static const voltColor = Color(0xFFC6FF00);

  List<String> _days = const [];
  int _index = 0;
  List<ObdLogPoint> _points = const [];
  bool _loading = true;

  /// Выбранный момент на графике (доля ширины 0..1) или null.
  double? _cursor;

  ObdLog get _log => context.read<ObdService>().log;

  @override
  void initState() {
    super.initState();
    _loadDays();
  }

  Future<void> _loadDays() async {
    final days = await _log.days();
    if (!mounted) return;
    setState(() => _days = days);
    await _loadDay(0);
  }

  Future<void> _loadDay(int i) async {
    if (_days.isEmpty) {
      setState(() => _loading = false);
      return;
    }
    setState(() {
      _index = i;
      _loading = true;
      _cursor = null;
    });
    final pts = await _log.read(_days[i]);
    if (!mounted) return;
    setState(() {
      _points = pts;
      _loading = false;
    });
  }

  static String _dayTitle(String day) {
    final p = day.split('-');
    if (p.length != 3) return day;
    const months = ['января', 'февраля', 'марта', 'апреля', 'мая', 'июня', 'июля', 'августа',
        'сентября', 'октября', 'ноября', 'декабря'];
    final m = int.tryParse(p[1]) ?? 1;
    return '${int.tryParse(p[2]) ?? p[2]} ${months[(m - 1).clamp(0, 11)]} ${p[0]}';
  }

  Future<void> _export({required bool all}) async {
    final messenger = ScaffoldMessenger.of(context);
    final f = all ? await _log.mergeAll() : await _log.fileFor(_days[_index]);
    if (f == null) return;
    final name = all ? 'obd_log_all.csv' : 'obd_log_${_days[_index]}.csv';
    final where = await NativeBridge.exportToDownloads(f.path, name);
    messenger.showSnackBar(SnackBar(
      content: Text(where == null ? 'Не удалось сохранить файл' : 'Сохранено: $where'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Статистика двигателя и вариатора'),
        actions: [
          if (_days.isNotEmpty)
            PopupMenuButton<String>(
              icon: const Icon(Icons.download_rounded),
              tooltip: 'Сохранить в Загрузки',
              onSelected: (v) => _export(all: v == 'all'),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'day', child: Text('Сохранить этот день (CSV)')),
                PopupMenuItem(value: 'all', child: Text('Сохранить всё (CSV)')),
              ],
            ),
        ],
      ),
      body: _days.isEmpty && !_loading
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Записей пока нет. Журнал пишется, пока лаунчер подключён к OBD '
                  'и двигатель работает — раз в 10 секунд.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : Column(
              children: [
                _dayBar(),
                if (_loading)
                  const Expanded(child: Center(child: CircularProgressIndicator()))
                else
                  Expanded(child: _charts()),
              ],
            ),
    );
  }

  Widget _dayBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Предыдущий день',
            onPressed: _index < _days.length - 1 ? () => _loadDay(_index + 1) : null,
            icon: const Icon(Icons.chevron_left_rounded),
          ),
          Expanded(
            child: Center(
              child: DropdownButton<int>(
                value: _days.isEmpty ? null : _index,
                underline: const SizedBox.shrink(),
                items: [
                  for (var i = 0; i < _days.length; i++)
                    DropdownMenuItem(value: i, child: Text(_dayTitle(_days[i]))),
                ],
                onChanged: (i) => i == null ? null : _loadDay(i),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Следующий день',
            onPressed: _index > 0 ? () => _loadDay(_index - 1) : null,
            icon: const Icon(Icons.chevron_right_rounded),
          ),
        ],
      ),
    );
  }

  ({double? min, double? max, double? avg}) _stats(double? Function(ObdLogPoint) f) {
    final v = _points.map(f).whereType<double>().toList();
    if (v.isEmpty) return (min: null, max: null, avg: null);
    return (min: v.reduce(math.min), max: v.reduce(math.max), avg: v.reduce((a, b) => a + b) / v.length);
  }

  Widget _charts() {
    if (_points.length < 2) {
      return const Center(child: Text('За этот день слишком мало записей'));
    }
    final t0 = _points.first.time;
    final t1 = _points.last.time;
    ObdLogPoint? at;
    if (_cursor != null) {
      final target = t0.add(Duration(milliseconds: (t1.difference(t0).inMilliseconds * _cursor!).round()));
      at = _points.reduce((a, b) =>
          (a.time.difference(target).abs() <= b.time.difference(target).abs()) ? a : b);
    }
    String fmt(double? v, int d) => v == null ? '—' : v.toStringAsFixed(d).replaceAll('.', ',');
    String time(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

    final eng = _stats((p) => p.engine);
    final cvt = _stats((p) => p.cvt);
    final volt = _stats((p) => p.voltage);

    Widget legend(Color c, String name, ({double? min, double? max, double? avg}) s, String unit, int d) =>
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
          child: Row(
            children: [
              Container(width: 14, height: 4, color: c),
              const SizedBox(width: 8),
              Expanded(child: Text(name)),
              Text('мин ${fmt(s.min, d)} · сред ${fmt(s.avg, d)} · макс ${fmt(s.max, d)} $unit',
                  style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        );

    Widget chart(List<_Series> series, double minY, double maxY, double step, String unit) => GestureDetector(
          onPanDown: (d) => _setCursor(d.localPosition.dx),
          onPanUpdate: (d) => _setCursor(d.localPosition.dx),
          child: LayoutBuilder(builder: (context, c) {
            _chartWidth = c.maxWidth;
            return CustomPaint(
              size: Size(c.maxWidth, c.maxHeight),
              painter: _ChartPainter(
                points: _points,
                series: series,
                minY: minY,
                maxY: maxY,
                stepY: step,
                unit: unit,
                cursor: _cursor,
                textColor: Theme.of(context).colorScheme.onSurface,
              ),
            );
          }),
        );

    // Шкала температур: от 0 (или ниже, зимой) до 120 (или выше).
    final temps = [eng.min, eng.max, cvt.min, cvt.max].whereType<double>();
    final tMin = math.min(0.0, ((temps.isEmpty ? 0 : temps.reduce(math.min)) / 20).floorToDouble() * 20);
    final tMax = math.max(120.0, ((temps.isEmpty ? 0 : temps.reduce(math.max)) / 20).ceilToDouble() * 20);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            at == null
                ? 'С ${time(t0)} до ${time(t1)} · касание графика — значения в этот момент'
                : '${time(at.time)} — двигатель ${fmt(at.engine, 0)} °C · вариатор ${fmt(at.cvt, 0)} °C · '
                    'сеть ${fmt(at.voltage, 1)} В',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        legend(engineColor, 'Двигатель', eng, '°C', 0),
        legend(cvtColor, 'Вариатор', cvt, '°C', 0),
        Expanded(
          flex: 3,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 12, 0),
            child: chart([
              _Series((p) => p.engine, engineColor),
              _Series((p) => p.cvt, cvtColor),
            ], tMin, tMax, 20, '°'),
          ),
        ),
        legend(voltColor, 'Напряжение', volt, 'В', 1),
        Expanded(
          flex: 1,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 12, 12),
            child: chart([_Series((p) => p.voltage, voltColor)], 11, 15, 1, ''),
          ),
        ),
      ],
    );
  }

  double _chartWidth = 1;

  void _setCursor(double dx) {
    final plotW = (_chartWidth - _ChartPainter.leftPad).clamp(1.0, double.infinity);
    setState(() => _cursor = ((dx - _ChartPainter.leftPad) / plotW).clamp(0.0, 1.0));
  }
}

class _Series {
  const _Series(this.value, this.color);
  final double? Function(ObdLogPoint) value;
  final Color color;
}

/// Линии по времени; разрыв, если между записями больше 2 минут (машина
/// стояла заглушённой). Сетка по Y с шагом [stepY], подписи часов по X.
class _ChartPainter extends CustomPainter {
  _ChartPainter({
    required this.points,
    required this.series,
    required this.minY,
    required this.maxY,
    required this.stepY,
    required this.unit,
    required this.cursor,
    required this.textColor,
  });

  static const double leftPad = 36;
  static const double bottomPad = 18;

  final List<ObdLogPoint> points;
  final List<_Series> series;
  final double minY, maxY, stepY;
  final String unit;
  final double? cursor;
  final Color textColor;

  void _label(Canvas canvas, String s, Offset at, {bool right = false}) {
    final tp = TextPainter(
      text: TextSpan(text: s, style: TextStyle(color: textColor.withValues(alpha: 0.6), fontSize: 10)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, right ? at - Offset(tp.width, tp.height / 2) : at - Offset(tp.width / 2, 0));
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width - leftPad;
    final h = size.height - bottomPad;
    if (w <= 0 || h <= 0 || points.length < 2) return;
    final t0 = points.first.time.millisecondsSinceEpoch.toDouble();
    final span = math.max(1.0, points.last.time.millisecondsSinceEpoch - t0);
    double x(DateTime t) => leftPad + (t.millisecondsSinceEpoch - t0) / span * w;
    double y(double v) => h - (v.clamp(minY, maxY) - minY) / (maxY - minY) * h;

    final grid = Paint()
      ..color = textColor.withValues(alpha: 0.12)
      ..strokeWidth = 1;
    for (var v = minY; v <= maxY + 0.001; v += stepY) {
      canvas.drawLine(Offset(leftPad, y(v)), Offset(size.width, y(v)), grid);
      _label(canvas, '${v.round()}$unit', Offset(leftPad - 4, y(v)), right: true);
    }

    // Подписи времени: шаг, при котором подписей не больше ~6.
    final minutes = span / 60000;
    final step = [5, 10, 15, 30, 60, 120, 180, 240].firstWhere((s) => minutes / s <= 6, orElse: () => 360);
    final start = points.first.time;
    var tick = DateTime(start.year, start.month, start.day, start.hour, (start.minute ~/ step + 1) * step);
    while (tick.isBefore(points.last.time)) {
      final tx = x(tick);
      canvas.drawLine(Offset(tx, 0), Offset(tx, h), grid);
      _label(canvas, '${tick.hour.toString().padLeft(2, '0')}:${tick.minute.toString().padLeft(2, '0')}',
          Offset(tx, h + 3));
      tick = tick.add(Duration(minutes: step));
    }

    for (final s in series) {
      final paint = Paint()
        ..color = s.color
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round;
      final path = Path();
      var open = false;
      DateTime? prev;
      for (final p in points) {
        final v = s.value(p);
        final gap = prev != null && p.time.difference(prev).inSeconds > 120;
        if (v == null || gap) open = false;
        if (v != null) {
          if (open) {
            path.lineTo(x(p.time), y(v));
          } else {
            path.moveTo(x(p.time), y(v));
            open = true;
          }
        }
        prev = p.time;
      }
      canvas.drawPath(path, paint);
    }

    final c = cursor;
    if (c != null) {
      final cx = leftPad + c * w;
      canvas.drawLine(
        Offset(cx, 0),
        Offset(cx, h),
        Paint()
          ..color = textColor.withValues(alpha: 0.5)
          ..strokeWidth = 1,
      );
    }
  }

  @override
  bool shouldRepaint(_ChartPainter old) =>
      old.points != points || old.cursor != cursor || old.minY != minY || old.maxY != maxY;
}
