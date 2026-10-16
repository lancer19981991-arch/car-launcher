import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'screens/home_screen.dart';
import 'services/preset_service.dart';
import 'services/settings_service.dart';
import 'theme/app_theme.dart';

class CarLauncherApp extends StatelessWidget {
  const CarLauncherApp({super.key, required this.settings, required this.presets});

  final SettingsService settings;
  final PresetService presets;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<SettingsService>.value(value: settings),
        ChangeNotifierProvider<PresetService>.value(value: presets),
      ],
      child: Consumer<SettingsService>(
        builder: (context, settings, _) {
          return MaterialApp(
            title: 'Car Launcher',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light(),
            darkTheme: AppTheme.dark(),
            themeMode: settings.themeMode,
            // Запас сверху/снизу применяется ко ВСЕМ экранам сразу:
            // главному, настройкам, выбору приложений, диалогам — чтобы
            // ничего не заходило под системную панель климата магнитолы.
            builder: (context, child) => ColoredBox(
              color: Colors.black,
              child: Padding(
                padding: EdgeInsets.only(
                  top: settings.topReserve,
                  bottom: settings.bottomReserve,
                ),
                child: child,
              ),
            ),
            home: const HomeScreen(),
          );
        },
      ),
    );
  }
}
