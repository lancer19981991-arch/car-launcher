import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app.dart';
import 'services/preset_service.dart';
import 'services/settings_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

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

  runApp(CarLauncherApp(settings: settings, presets: presets));
}
