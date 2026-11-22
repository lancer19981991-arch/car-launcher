import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

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

/// Заставка при холодном запуске: проигрывает assets/splash.mp4 (без звука)
/// один раз и плавно гаснет по окончании. Если видео не открылось — гаснет
/// через пару секунд. Создаётся один раз при старте, поэтому при возврате
/// с настроек или из другого приложения не показывается.
class _Splash extends StatefulWidget {
  const _Splash({required this.child});

  final Widget child;

  @override
  State<_Splash> createState() => _SplashState();
}

class _SplashState extends State<_Splash> {
  VideoPlayerController? _video;
  bool _visible = true;
  Timer? _fallback;

  @override
  void initState() {
    super.initState();
    // Страховка: даже если видео не загрузилось, заставка не висит вечно.
    _fallback = Timer(const Duration(seconds: 12), _hide);
    _startVideo();
  }

  Future<void> _startVideo() async {
    try {
      final c = VideoPlayerController.asset('assets/splash.mp4');
      _video = c;
      await c.setVolume(0);
      await c.initialize();
      if (!mounted) return;
      c.addListener(() {
        if (c.value.position >= c.value.duration && c.value.duration > Duration.zero) {
          _hide();
        }
      });
      setState(() {});
      await c.play();
    } catch (_) {
      // Видео не открылось — просто короткая заставка.
      _fallback?.cancel();
      _fallback = Timer(const Duration(milliseconds: 1500), _hide);
    }
  }

  void _hide() {
    if (mounted && _visible) setState(() => _visible = false);
  }

  @override
  void dispose() {
    _fallback?.cancel();
    _video?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _video;
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        IgnorePointer(
          child: AnimatedOpacity(
            opacity: _visible ? 1 : 0,
            duration: const Duration(milliseconds: 600),
            child: ColoredBox(
              color: Colors.black,
              child: c != null && c.value.isInitialized
                  ? Center(
                      child: AspectRatio(
                        aspectRatio: c.value.aspectRatio,
                        child: VideoPlayer(c),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ),
        ),
      ],
    );
  }
}
