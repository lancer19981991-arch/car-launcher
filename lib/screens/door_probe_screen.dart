import 'dart:io';

import 'package:flutter/material.dart';

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Разведка: двери')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
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
