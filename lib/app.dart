import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import 'screens/home_screen.dart';
import 'services/native_bridge.dart';
import 'services/splash_gate.dart';
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
            // Заставка лежит поверх всего, во весь экран — без запасов.
            builder: (context, child) => Stack(
              fit: StackFit.expand,
              children: [
                ColoredBox(
                  color: Colors.black,
                  child: Padding(
                    padding: EdgeInsets.only(
                      top: settings.topReserve,
                      bottom: settings.bottomReserve,
                    ),
                    child: child,
                  ),
                ),
                const _Splash(),
              ],
            ),
            home: const HomeScreen(),
          );
        },
      ),
    );
  }
}

/// Заставка при холодном запуске: assets/splash.mp4 (без звука) один раз на
/// весь экран, потом плавно гаснет. Пока она на экране, [splashGate] = true,
/// и живые окна не показываются. Создаётся один раз при старте.
class _Splash extends StatefulWidget {
  const _Splash();

  @override
  State<_Splash> createState() => _SplashState();
}

class _SplashState extends State<_Splash> {
  VideoPlayerController? _video;
  bool _visible = true;
  bool _finished = false;
  Timer? _fallback;

  @override
  void initState() {
    super.initState();
    // Страховка: заставка не висит дольше 12 секунд.
    _fallback = Timer(const Duration(seconds: 12), _hide);
    NativeBridge.ensureIncomingHandler();
    NativeBridge.onWake = _replay;
    _startVideo();
  }

  /// Магнитола проснулась (процесс жив) — проигрываем заставку заново.
  Future<void> _replay() async {
    final c = _video;
    if (!mounted || c == null || !c.value.isInitialized) return;
    splashGate.value = true;
    _finished = false;
    _fallback?.cancel();
    _fallback = Timer(const Duration(seconds: 12), _hide);
    // Окна, если они ещё видны, прячем на время заставки.
    try {
      await NativeBridge.hideAppWindows();
    } catch (_) {}
    setState(() => _visible = true);
    await c.seekTo(Duration.zero);
    await c.play();
  }

  Future<void> _startVideo() async {
    try {
      final c = VideoPlayerController.asset('assets/splash.mp4');
      _video = c;
      await c.setVolume(0);
      await c.initialize();
      if (!mounted) return;
      c.addListener(() {
        if (c.value.duration > Duration.zero &&
            c.value.position >= c.value.duration) {
          _hide();
        }
      });
      setState(() {});
      await c.play();
    } catch (_) {
      // Видео не открылось — короткая заставка без него.
      _fallback?.cancel();
      _fallback = Timer(const Duration(milliseconds: 1500), _hide);
    }
  }

  void _hide() {
    if (_finished || !mounted) return;
    _finished = true;
    _fallback?.cancel();
    setState(() => _visible = false);
    // Окна показываем, когда заставка уже погасла (600 мс — как анимация).
    Future.delayed(const Duration(milliseconds: 650), () {
      splashGate.value = false;
    });
  }

  @override
  void dispose() {
    if (NativeBridge.onWake == _replay) NativeBridge.onWake = null;
    _fallback?.cancel();
    _video?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _video;
    final ready = c != null && c.value.isInitialized;
    return IgnorePointer(
      child: AnimatedOpacity(
        opacity: _visible ? 1 : 0,
        // Появляется быстро (после сна), гаснет плавно.
        duration: Duration(milliseconds: _visible ? 150 : 600),
        child: ColoredBox(
          color: Colors.black,
          child: ready
              ? SizedBox.expand(
                  child: FittedBox(
                    fit: BoxFit.cover,
                    child: SizedBox(
                      width: c.value.size.width,
                      height: c.value.size.height,
                      child: VideoPlayer(c),
                    ),
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ),
    );
  }
}
