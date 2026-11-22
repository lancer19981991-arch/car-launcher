import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'screens/home_screen.dart';
import 'services/doors_service.dart';
import 'services/obd_service.dart';
import 'services/preset_service.dart';
import 'services/settings_service.dart';
import 'services/tpms_service.dart';
import 'services/weather_service.dart';
import 'theme/app_theme.dart';

class CarLauncherApp extends StatelessWidget {
  const CarLauncherApp({
    super.key,
    required this.settings,
    required this.presets,
    required this.weather,
    required this.tpms,
    required this.obd,
    required this.doors,
  });

  final SettingsService settings;
  final PresetService presets;
  final WeatherService weather;
  final TpmsService tpms;
  final ObdService obd;
  final DoorsService doors;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<SettingsService>.value(value: settings),
        ChangeNotifierProvider<PresetService>.value(value: presets),
        ChangeNotifierProvider<WeatherService>.value(value: weather),
        ChangeNotifierProvider<TpmsService>.value(value: tpms),
        ChangeNotifierProvider<ObdService>.value(value: obd),
        ChangeNotifierProvider<DoorsService>.value(value: doors),
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
            home: const _Splash(child: HomeScreen()),
          );
        },
      ),
    );
  }
}

/// Заставка при холодном запуске: та же картинка, что и нативная (фон до
/// первого кадра Flutter), плавно гаснет через пару секунд. Создаётся один
/// раз при старте, поэтому при возврате с настроек или из другого приложения
/// не показывается.
class _Splash extends StatefulWidget {
  const _Splash({required this.child});

  final Widget child;

  @override
  State<_Splash> createState() => _SplashState();
}

class _SplashState extends State<_Splash> {
  bool _visible = true;

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 1800), () {
      if (mounted) setState(() => _visible = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        IgnorePointer(
          child: AnimatedOpacity(
            opacity: _visible ? 1 : 0,
            duration: const Duration(milliseconds: 600),
            child: const ColoredBox(
              color: Colors.black,
              child: Center(
                child: Image(
                  image: AssetImage('assets/car_top.png'),
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
