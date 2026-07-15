import 'dart:ui' show Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spectrogram/app.dart';
import 'package:spectrogram/core/constants.dart';
import 'package:spectrogram/services/settings_repository.dart';
import 'package:spectrogram/services/spectrogram_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('app shell shows Live and Settings destinations', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final repo = await SettingsRepository.create();
    final engine = SpectrogramEngine(settings: repo.load());

    await tester.pumpWidget(
      SpectrogramApp(repository: repo, engine: engine),
    );
    await tester.pumpAndSettle();

    expect(find.text(AppConstants.appName), findsWidgets);
    expect(find.text('Start mic'), findsOneWidget);
    expect(find.text('Live'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();

    expect(find.text('Sample rate'), findsOneWidget);
    expect(find.text('FFT size'), findsOneWidget);
    expect(find.text('Colormap'), findsOneWidget);

    engine.dispose();
  });

  testWidgets('mode toggle switches segmented button', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final repo = await SettingsRepository.create();
    final engine = SpectrogramEngine(settings: repo.load());

    // Wide surface so mode labels are full words.
    await tester.binding.setSurfaceSize(const Size(900, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      SpectrogramApp(repository: repo, engine: engine),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Spectrum'));
    await tester.pumpAndSettle();

    expect(find.textContaining('dBFS'), findsWidgets);

    engine.dispose();
  });
}
