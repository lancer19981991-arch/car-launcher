import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app.dart';
import 'services/obd_service.dart';
import 'services/preset_service.dart';
import 'services/settings_service.dart';
import 'services/tpms_service.dart';
import 'services/weather_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Если что-то сломается при построении экрана, показываем текст
  // ошибки, а не пустое серое поле — так проблему видно на фото.
  ErrorWidget.builder = (details) => Material(
        color: const Color(0xFF300000),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Text(
            'Ошибка лаунчера:\n${details.exceptionAsString()}\n\n${details.stack}',
            style: const TextStyle(color: Colors.white, fontSize: 14),
          ),
        ),
      );

  try {
    await _start();
  } catch (e, st) {
    runApp(MaterialApp(
      home: Scaffold(
        backgroundColor: const Color(0xFF300000),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Text('Ошибка запуска лаунчера:\n$e\n\n$st',
                style: const TextStyle(color: Colors.white, fontSize: 14)),
          ),
        ),
      ),
    ));
  }
}

Future<void> _start() async {

  // Экран магнитолы вертикальный («тесла»-формат), поэтому закрепляем
  // портретную ориентацию. Раскладка на главном экране всё равно
  // адаптивная и переживёт поворот, но на фиксированном экране так
  // предсказуемее.
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);

  // Во весь экран: прячем системные панели, чтобы задействовать и место
  // верхнего статус-бара под свой интерфейс. immersiveSticky — панели
  // не мешают и возвращаются свайпом от края.
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

  final settings = await SettingsService.load();
  final presets = await PresetService.load();

  final weather = WeatherService(settings);

  final tpms = TpmsService(settings);
  final obd = ObdService(settings);

  runApp(CarLauncherApp(settings: settings, presets: presets, weather: weather, tpms: tpms, obd: obd));
}
