import 'dart:io';

import 'native_bridge.dart';

/// Одна точка журнала OBD.
class ObdLogPoint {
  const ObdLogPoint(this.time, this.engine, this.cvt, this.voltage);

  final DateTime time;
  final double? engine;
  final double? cvt;
  final double? voltage;
}

/// Журнал температур двигателя/вариатора и напряжения: по файлу CSV на
/// день во внутренней памяти лаунчера (`files/obd_log/2026-11-04.csv`),
/// хранится бессрочно. Запись — не чаще раза в 10 с, пока двигатель
/// отвечает.
class ObdLog {
  static const header = 'time,engine_c,cvt_c,voltage_v';
  static const interval = Duration(seconds: 10);

  Directory? _dir;
  DateTime? _lastWrite;
  bool _writing = false;

  Future<Directory?> dir() async {
    if (_dir != null) return _dir;
    final base = await NativeBridge.filesDir();
    if (base == null) return null;
    final d = Directory('$base/obd_log');
    if (!await d.exists()) await d.create(recursive: true);
    return _dir = d;
  }

  static String _two(int v) => v.toString().padLeft(2, '0');
  static String dayName(DateTime t) => '${t.year}-${_two(t.month)}-${_two(t.day)}';
  static String _stamp(DateTime t) => '${dayName(t)} ${_two(t.hour)}:${_two(t.minute)}:${_two(t.second)}';

  /// Записать показания, если прошло 10 с с прошлой записи.
  Future<void> maybeAppend({double? engine, double? cvt, double? voltage}) async {
    final now = DateTime.now();
    final last = _lastWrite;
    if (_writing || (last != null && now.difference(last) < interval)) return;
    if (engine == null && cvt == null) return;
    _writing = true;
    _lastWrite = now;
    try {
      final d = await dir();
      if (d == null) return;
      final f = File('${d.path}/${dayName(now)}.csv');
      final exists = await f.exists();
      String n(double? v, int digits) => v == null ? '' : v.toStringAsFixed(digits);
      await f.writeAsString(
        '${exists ? '' : '$header\n'}${_stamp(now)},${n(engine, 0)},${n(cvt, 1)},${n(voltage, 1)}\n',
        mode: FileMode.append,
        flush: true,
      );
    } catch (_) {
      // Журнал не должен мешать работе панели.
    } finally {
      _writing = false;
    }
  }

  /// Дни, за которые есть записи, — новые первыми.
  Future<List<String>> days() async {
    final d = await dir();
    if (d == null) return const [];
    final names = <String>[];
    await for (final e in d.list()) {
      final name = e.uri.pathSegments.last;
      if (e is File && name.endsWith('.csv') && name.length == 14) names.add(name.substring(0, 10));
    }
    names.sort((a, b) => b.compareTo(a));
    return names;
  }

  Future<File?> fileFor(String day) async {
    final d = await dir();
    if (d == null) return null;
    final f = File('${d.path}/$day.csv');
    return await f.exists() ? f : null;
  }

  Future<List<ObdLogPoint>> read(String day) async {
    final f = await fileFor(day);
    if (f == null) return const [];
    final out = <ObdLogPoint>[];
    for (final line in await f.readAsLines()) {
      final p = line.split(',');
      if (p.length < 4) continue;
      final t = DateTime.tryParse(p[0].replaceFirst(' ', 'T'));
      if (t == null) continue;
      out.add(ObdLogPoint(t, double.tryParse(p[1]), double.tryParse(p[2]), double.tryParse(p[3])));
    }
    return out;
  }

  /// Всё в один CSV (для выгрузки) — во временный файл.
  Future<File?> mergeAll() async {
    final d = await dir();
    if (d == null) return null;
    final all = (await days()).reversed.toList();
    final out = File('${d.parent.path}/obd_log_all.csv');
    final sink = out.openWrite();
    sink.writeln(header);
    for (final day in all) {
      final f = await fileFor(day);
      if (f == null) continue;
      for (final line in await f.readAsLines()) {
        if (line.isNotEmpty && line != header) sink.writeln(line);
      }
    }
    await sink.close();
    return out;
  }
}
