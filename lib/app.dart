import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'screens/home_screen.dart';
import 'screens/media_pane_screen.dart';
import 'services/settings_service.dart';
import 'theme/app_theme.dart';

class CarLauncherApp extends StatelessWidget {
  const CarLauncherApp({super.key, required this.settings});

  final SettingsService settings;

  @override
  Widget build(BuildContext context) {
    // У лаунчера два независимых "окна" — MainActivity и MediaPaneActivity
    // (см. android/.../CarLauncherApplication.kt). Каждое запускает один и
    // тот же Dart-энтрипойнт, но с разным initial route, который нативная
    // сторона передаёт через FlutterEngineGroup.createAndRunEngine(...).
    // По этому имени и выбираем, какой экран показать в данном окне —
    // Navigator тут не нужен, окна физически разные.
    final initialRoute = WidgetsBinding.instance.platformDispatcher.defaultRouteName;
    final isMediaPane = initialRoute == '/media_pane';

    return ChangeNotifierProvider<SettingsService>.value(
      value: settings,
      child: Consumer<SettingsService>(
        builder: (context, settings, _) {
          return MaterialApp(
            title: 'Car Launcher',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light(),
            darkTheme: AppTheme.dark(),
            themeMode: settings.themeMode,
            home: isMediaPane ? const MediaPaneScreen() : const HomeScreen(),
          );
        },
      ),
    );
  }
}
