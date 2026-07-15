import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spectrogram/app.dart';
import 'package:spectrogram/services/settings_repository.dart';
import 'package:spectrogram/services/spectrogram_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('plot-first shell: start + menu opens settings', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final repo = await SettingsRepository.create();
    final engine = SpectrogramEngine(settings: repo.load());

    await tester.pumpWidget(
      SpectrogramApp(repository: repo, engine: engine),
    );
    await tester.pumpAndSettle();

    // No tab bar / title chrome.
    expect(find.text('Live'), findsNothing);
    expect(find.text('Spectrogram'), findsNothing);
    expect(find.text('Start'), findsOneWidget);
    expect(find.text('STFT'), findsOneWidget);
    expect(find.text('FFT'), findsOneWidget);
    expect(find.byIcon(Icons.more_vert), findsOneWidget);

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();

    expect(find.text('Sample rate'), findsOneWidget);
    expect(find.text('FFT size'), findsOneWidget);
    expect(find.text('Colormap'), findsOneWidget);

    engine.dispose();
  });

  testWidgets('mode toggle switches to FFT spectrum view', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final repo = await SettingsRepository.create();
    final engine = SpectrogramEngine(settings: repo.load());

    await tester.binding.setSurfaceSize(const Size(900, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      SpectrogramApp(repository: repo, engine: engine),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('FFT'));
    await tester.pumpAndSettle();

    expect(find.textContaining('dB'), findsWidgets);

    engine.dispose();
  });
}
