import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app.dart';
import 'services/settings_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Лаунчер живёт в альбомной ориентации и без системных жестов сверху —
  // типично для магнитолы/приборной панели. Уберите при необходимости.
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  final settings = await SettingsService.load();

  runApp(CarLauncherApp(settings: settings));
}
