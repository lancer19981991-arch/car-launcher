import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/doors_service.dart';
import '../services/native_bridge.dart';

/// Разведка дверей: запись системных изменений, пока пользователь
/// открывает и закрывает дверь. Отчёт сохраняется в «Загрузки», и его
/// присылают — по нему видно, как прошивка передаёт состояние дверей.
class DoorProbeScreen extends StatefulWidget {
  const DoorProbeScreen({super.key});

  @override
  State<DoorProbeScreen> createState() => _DoorProbeScreenState();
}

class _DoorProbeScreenState extends State<DoorProbeScreen> {
  /// Перерисовка раз в полсекунды — чтобы подсветка изменившихся кодов гасла.
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  /// Таблица всех кодов шины: только что изменившиеся горят красным и
  /// плавно гаснут за 6 секунд — сразу видно, какой код на что реагирует.
  Widget _codesTable(DoorsService d) {
    final now = DateTime.now();
    final codes = d.values.keys.toList()..sort();
    if (codes.isEmpty) return const Text('Значений пока нет');
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        for (final c in codes)
          Builder(builder: (context) {
            final at = d.changedAt[c];
            final age = at == null ? 99.0 : now.difference(at).inMilliseconds / 1000;
            final heat = (1 - age / 6).clamp(0.0, 1.0);
            final v = d.values[c]!;
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: Color.lerp(Colors.white10, const Color(0xFFFF283C), heat),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: at == null ? Colors.white12 : Colors.white38),
              ),
              child: Text(
                '$c: ${v.length == 1 ? v.first : v.join(',')}',
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  fontWeight: heat > 0 ? FontWeight.w700 : FontWeight.w400,
                ),
              ),
            );
          }),
      ],
    );
  }

  bool _recording = false;
  bool _busy = false;
  String? _report;
  String? _savedTo;

  Future<void> _start() async {
    setState(() {
      _busy = true;
      _report = null;
      _savedTo = null;
    });
    await NativeBridge.doorProbeStart();
    if (mounted) {
      setState(() {
        _busy = false;
        _recording = true;
      });
    }
  }

  Future<void> _stop() async {
    setState(() => _busy = true);
    final r = await NativeBridge.doorProbeStop();
    String? saved;
    if (r != null) {
      final dir = await NativeBridge.filesDir();
      if (dir != null) {
        final now = DateTime.now();
        String two(int v) => v.toString().padLeft(2, '0');
        final name = 'door_report_${now.year}${two(now.month)}${two(now.day)}_${two(now.hour)}${two(now.minute)}.txt';
        final f = File('$dir/$name');
        await f.writeAsString(r);
        saved = await NativeBridge.exportToDownloads(f.path, name);
      }
    }
    if (mounted) {
      setState(() {
        _busy = false;
        _recording = false;
        _report = r;
        _savedTo = saved;
      });
    }
  }

  Future<void> _saveCanbusLog(DoorsService d) async {
    final messenger = ScaffoldMessenger.of(context);
    final dir = await NativeBridge.filesDir();
    if (dir == null) return;
    String two(int v) => v.toString().padLeft(2, '0');
    String t(DateTime x) => '${two(x.hour)}:${two(x.minute)}:${two(x.second)}';
    final sb = StringBuffer('=== Шина FYT (com.syu.ms, модуль CANBUS) ===\n${d.state}\n\n--- Изменения ---\n');
    for (final e in d.events) {
      sb.writeln('${t(e.time)}  код ${e.code} = ${e.ints}');
    }
    sb.writeln('\n--- Текущие значения ---');
    for (final k in d.values.keys.toList()..sort()) {
      sb.writeln('код $k = ${d.values[k]}');
    }
    final now = DateTime.now();
    final name = 'canbus_log_${now.year}${two(now.month)}${two(now.day)}_${two(now.hour)}${two(now.minute)}.txt';
    final f = File('$dir/$name');
    await f.writeAsString(sb.toString());
    final saved = await NativeBridge.exportToDownloads(f.path, name);
    messenger.showSnackBar(SnackBar(content: Text(saved == null ? 'Не удалось сохранить' : 'Сохранено: $saved')));
  }

  Widget _canbusCard(BuildContext context) {
    final d = context.watch<DoorsService>();
    String two(int v) => v.toString().padLeft(2, '0');
    final recent = d.events.reversed.take(40).toList();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Шина FYT — живые сообщения', style: TextStyle(fontWeight: FontWeight.w700)),
            Text(d.state, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 8),
            const Text('Откройте дверь и посмотрите, какой код появился сверху списка. '
                'Затем закройте — код должен смениться обратно. Сохраните журнал и пришлите.'),
            const SizedBox(height: 8),
            Text(
              'Сейчас по кодам: ${[for (final p in DoorsService.parts) '${DoorsService.names[p]} ${d.isOpen(p) ? 'ОТКРЫТ' : '—'}'].join(' · ')}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            const Text('Все коды (изменившийся горит красным несколько секунд; '
                'с рамкой — менялись хоть раз):', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            _codesTable(d),
            const SizedBox(height: 10),
            const Text('Журнал изменений (новые сверху):', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Container(
              height: 220,
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              color: Colors.black26,
              child: recent.isEmpty
                  ? const Text('Сообщений пока нет')
                  : ListView(
                      children: [
                        for (final e in recent)
                          Text(
                            '${two(e.time.hour)}:${two(e.time.minute)}:${two(e.time.second)}  код ${e.code} = ${e.ints}',
                            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                          ),
                      ],
                    ),
            ),
            OverflowBar(
              alignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () {
                    d.events.clear();
                    d.changedAt.clear();
                    setState(() {});
                  },
                  child: const Text('Очистить'),
                ),
                TextButton.icon(
                  onPressed: () => _saveCanbusLog(d),
                  icon: const Icon(Icons.save_alt_rounded),
                  label: const Text('Сохранить журнал'),
                ),
              ],
            ),
            const Divider(),
            const Text('Тест анимации (без машины)', style: TextStyle(fontWeight: FontWeight.w700)),
            const Text('Нажмите — на панели шин эта часть «откроется». Нажмите ещё раз — закроется.'),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                for (final p in DoorsService.parts)
                  FilterChip(
                    label: Text(DoorsService.names[p]!),
                    selected: d.simulated.contains(p),
                    onSelected: (_) => d.toggleSimulated(p),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Разведка: двери')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _canbusCard(context),
          const SizedBox(height: 16),
          const Text('Общая запись системы (старый способ)', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          const Text(
            'Магнитола сама показывает открытые двери — значит, данные о дверях в ней есть. '
            'Этот инструмент записывает, что меняется в системе, пока вы открываете дверь, '
            'чтобы понять, откуда лаунчеру брать эти данные.',
          ),
          const SizedBox(height: 16),
          Text(
            _recording
                ? 'Идёт запись. Откройте водительскую дверь, подождите 3 секунды, закройте её. '
                    'Можно так же — заднюю дверь и багажник. Затем нажмите «Стоп».'
                : '1. Нажмите «Начать запись».\n'
                    '2. Откройте водительскую дверь, подождите 3 секунды, закройте.\n'
                    '3. Нажмите «Стоп» — отчёт сохранится в «Загрузки».',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 16),
          if (_busy)
            const Center(child: CircularProgressIndicator())
          else
            FilledButton.icon(
              onPressed: _recording ? _stop : _start,
              icon: Icon(_recording ? Icons.stop_rounded : Icons.fiber_manual_record_rounded),
              label: Text(_recording ? 'Стоп' : 'Начать запись'),
            ),
          if (_report != null) ...[
            const SizedBox(height: 16),
            Text(
              _savedTo != null
                  ? 'Отчёт сохранён: $_savedTo. Пришлите этот файл в чат.'
                  : 'Не удалось сохранить файл — сфотографируйте отчёт ниже.',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            SelectableText(_report!, style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
          ],
        ],
      ),
    );
  }
}
