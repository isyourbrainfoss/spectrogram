import 'package:flutter/material.dart';
import 'package:spectrogram/core/constants.dart';
import 'package:spectrogram/core/theme/spectrogram_theme.dart';
import 'package:spectrogram/features/home/home_screen.dart';
import 'package:spectrogram/models/app_settings.dart';
import 'package:spectrogram/services/settings_repository.dart';
import 'package:spectrogram/services/spectrogram_engine.dart';

class SpectrogramApp extends StatefulWidget {
  const SpectrogramApp({
    super.key,
    required this.repository,
    required this.engine,
  });

  final SettingsRepository repository;
  final SpectrogramEngine engine;

  @override
  State<SpectrogramApp> createState() => _SpectrogramAppState();
}

class _SpectrogramAppState extends State<SpectrogramApp> {
  late AppSettings _settings;

  @override
  void initState() {
    super.initState();
    _settings = widget.engine.settings;
  }

  void _onSettingsChanged(AppSettings s) {
    setState(() => _settings = s);
  }

  ThemeMode get _themeMode => switch (_settings.colorScheme) {
        ThemePreference.light => ThemeMode.light,
        ThemePreference.dark => ThemeMode.dark,
        ThemePreference.system => ThemeMode.system,
      };

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      theme: SpectrogramTheme.light(),
      darkTheme: SpectrogramTheme.dark(),
      themeMode: _themeMode,
      home: HomeScreen(
        engine: widget.engine,
        repository: widget.repository,
        onSettingsChanged: _onSettingsChanged,
      ),
    );
  }
}
