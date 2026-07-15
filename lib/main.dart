import 'package:flutter/material.dart';
import 'package:spectrogram/app.dart';
import 'package:spectrogram/services/settings_repository.dart';
import 'package:spectrogram/services/spectrogram_engine.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final repository = await SettingsRepository.create();
  final settings = repository.load();
  final engine = SpectrogramEngine(settings: settings);
  runApp(SpectrogramApp(repository: repository, engine: engine));
}
