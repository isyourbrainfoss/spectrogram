import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spectrogram/dsp/freq_axis.dart';
import 'package:spectrogram/features/plot/axis_labels.dart';
import 'package:spectrogram/models/app_settings.dart';

Widget _host(Widget child, {Size size = const Size(360, 640)}) {
  return MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(width: size.width, height: size.height, child: child),
      ),
    ),
  );
}

/// Asserts every visible Y tick label is a single line, sits inside the
/// gutter and inside the plot's vertical extent, and nothing overlaps.
void _expectCleanYAxis(WidgetTester tester, {required int minLabels}) {
  final axis = tester.getRect(find.byKey(const ValueKey('plot-y-axis')));
  final labels = find.byWidgetPredicate(
    (w) =>
        w is Text &&
        w.key is ValueKey<String> &&
        (w.key! as ValueKey<String>).value.startsWith('plot-y-tick-'),
  );
  final rects = labels
      .evaluate()
      .map((e) => tester.getRect(find.byWidget(e.widget)))
      .toList();
  expect(rects.length, greaterThanOrEqualTo(minLabels));

  final lineHeight = rects.map((r) => r.height).reduce((a, b) => a < b ? a : b);
  for (final r in rects) {
    expect(r.height, closeTo(lineHeight, 0.5), reason: 'label wrapped: $r');
    expect(
      r.left,
      greaterThanOrEqualTo(axis.left - 0.01),
      reason: 'clipped left: $r',
    );
    expect(r.right, lessThanOrEqualTo(axis.right + 0.01));
    expect(
      r.top,
      greaterThanOrEqualTo(axis.top - 0.01),
      reason: 'above plot: $r',
    );
    expect(
      r.bottom,
      lessThanOrEqualTo(axis.bottom + 0.01),
      reason: 'below plot: $r',
    );
  }
  for (var i = 0; i < rects.length; i++) {
    for (var j = i + 1; j < rects.length; j++) {
      expect(
        rects[i].overlaps(rects[j]),
        isFalse,
        reason: '${rects[i]} vs ${rects[j]}',
      );
    }
  }
  final title = find.byKey(const ValueKey('plot-y-title'));
  if (title.evaluate().isNotEmpty) {
    final t = tester.getRect(title);
    for (final r in rects) {
      expect(t.overlaps(r), isFalse, reason: 'title $t hits tick $r');
    }
    expect(t.left, greaterThanOrEqualTo(axis.left - 0.01));
  }
}

void main() {
  group('frequency ticks', () {
    test('log default range uses round 1-2-5 values plus the ends', () {
      final ticks = FreqAxis.ticks(
        minHz: 20,
        maxHz: 12000,
        scale: FreqScale.logarithmic,
      );
      final hz = ticks.map((t) => t.hz).toList();
      expect(hz.first, 20);
      expect(hz.last, 12000);
      for (final v in hz.skip(1).take(hz.length - 2)) {
        var m = v;
        while (m >= 10) {
          m /= 10;
        }
        expect(
          [1.0, 2.0, 5.0],
          contains(closeTo(m, 1e-9)),
          reason: '$v is not a round tick',
        );
      }
      expect(hz, isNot(contains(10000)), reason: 'crowds the 12 kHz end');
      expect(hz.any((v) => v > 400 && v < 600 && v != 500), isFalse);
    });

    test('labels never contain line breaks', () {
      for (final hz in [20.0, 490.0, 2500.0, 12000.0, 22050.0]) {
        expect(formatFrequency(hz).contains('\n'), isFalse);
      }
    });

    test('linear range uses an even nice step', () {
      final ticks = FreqAxis.ticks(
        minHz: 0,
        maxHz: 8000,
        scale: FreqScale.linear,
        maxTicks: 9,
      );
      expect(ticks.map((t) => t.hz), containsAll(<double>[2000, 4000, 6000]));
    });
  });

  group('dB ticks', () {
    test('nice steps, numeric labels with a real minus', () {
      final ticks = dbAxisTicks(minDb: -90, maxDb: 0);
      expect(ticks.map((t) => t.label).toList(), [
        '\u221280',
        '\u221260',
        '\u221240',
        '\u221220',
        '0',
      ]);
      expect(ticks.every((t) => !t.label.contains('dB')), isTrue);
    });
  });

  group('placeAxisLabels', () {
    test('clamps the end labels inside the axis', () {
      final placed = placeAxisLabels(
        centers: [0, 50, 100],
        extents: [12, 12, 12],
        length: 100,
      );
      expect(placed.first.start, 0);
      expect(placed.last.end, 100);
    });

    test('drops a label that would collide, keeping the ends', () {
      final placed = placeAxisLabels(
        centers: [0, 6, 100],
        extents: [12, 12, 12],
        length: 100,
      );
      expect(placed.map((p) => p.index), [0, 2]);
    });
  });

  group('PlotChrome layout', () {
    testWidgets('log frequency Y axis: readable, unclipped, no overlap', (
      tester,
    ) async {
      for (final h in [640.0, 300.0, 160.0]) {
        await tester.pumpWidget(
          _host(
            PlotChrome(
              yTicks: frequencyAxisTicks(
                minHz: 20,
                maxHz: 12000,
                scale: FreqScale.logarithmic,
              ),
              xMinLabel: '-10 s',
              xMaxLabel: '0 s',
              xMidLabel: 'wheel zoom · shift+wheel pan',
              child: const SizedBox.expand(),
            ),
            size: Size(360, h),
          ),
        );
        _expectCleanYAxis(tester, minLabels: 2);
        expect(
          find.byKey(const ValueKey('plot-y-tick-12 kHz')),
          findsOneWidget,
        );
        expect(find.byKey(const ValueKey('plot-y-tick-20 Hz')), findsOneWidget);
      }
    });

    testWidgets('dB Y axis title has its own column', (tester) async {
      await tester.pumpWidget(
        _host(
          PlotChrome(
            yTicks: dbAxisTicks(minDb: -90, maxDb: 0),
            yAxisTitle: 'dBFS',
            xMinLabel: '20 Hz',
            xMaxLabel: '12 kHz',
            xTicks: frequencyAxisTicks(
              minHz: 20,
              maxHz: 12000,
              scale: FreqScale.logarithmic,
              maxTicks: 7,
            ),
            child: const SizedBox.expand(),
          ),
        ),
      );
      expect(find.byKey(const ValueKey('plot-y-title')), findsOneWidget);
      _expectCleanYAxis(tester, minLabels: 5);
    });

    testWidgets('large text scale still keeps labels on one line', (
      tester,
    ) async {
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.6)),
          child: _host(
            PlotChrome(
              yTicks: frequencyAxisTicks(
                minHz: 20,
                maxHz: 12000,
                scale: FreqScale.logarithmic,
              ),
              yAxisTitle: 'Hz',
              xMinLabel: 'a',
              xMaxLabel: 'b',
              child: const SizedBox.expand(),
            ),
          ),
        ),
      );
      _expectCleanYAxis(tester, minLabels: 3);
    });

    testWidgets('X tick labels stay inside the plot width and do not overlap', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          PlotChrome(
            yTicks: dbAxisTicks(minDb: -90, maxDb: 0),
            xMinLabel: '',
            xMaxLabel: '',
            xTicks: frequencyAxisTicks(
              minHz: 20,
              maxHz: 12000,
              scale: FreqScale.logarithmic,
              maxTicks: 9,
            ),
            child: const SizedBox.expand(),
          ),
          size: const Size(300, 400),
        ),
      );
      final host = tester.getRect(find.byType(PlotChrome));
      final rects = find
          .byWidgetPredicate(
            (w) =>
                w is Text &&
                w.key is ValueKey<String> &&
                (w.key! as ValueKey<String>).value.startsWith('plot-x-tick-'),
          )
          .evaluate()
          .map((e) => tester.getRect(find.byWidget(e.widget)))
          .toList();
      expect(rects.length, greaterThanOrEqualTo(3));
      for (var i = 0; i < rects.length; i++) {
        expect(rects[i].right, lessThanOrEqualTo(host.right + 0.01));
        for (var j = i + 1; j < rects.length; j++) {
          expect(rects[i].overlaps(rects[j]), isFalse);
        }
      }
    });
  });
}
