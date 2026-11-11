import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:spectrogram/dsp/freq_axis.dart';
import 'package:spectrogram/dsp/spectrum_analysis.dart';
import 'package:spectrogram/features/plot/spectrogram_view.dart';
import 'package:spectrogram/models/app_settings.dart';

void main() {
  test('peaks are spaced on the plotted axis, not only in bins', () {
    // Ripple: a local max every 4 bins between 2 and 3 kHz (packed tightly
    // on a log axis) plus one strong low peak.
    const n = 1024;
    final freqs = Float32List.fromList(
      List.generate(n, (i) => i * 12000 / n),
    );
    final db = Float32List.fromList(List.filled(n, -90));
    for (var i = 171; i < 256; i += 4) {
      db[i] = -20 - (i % 8 == 3 ? 0.5 : 0);
    }
    db[20] = -10;
    double pos(double hz) =>
        FreqAxis.freqToNorm(hz, 20, 12000, FreqScale.logarithmic);

    final binOnly = findSpectrumPeaks(db: db, freqs: freqs, maxPeaks: 8);
    expect(binOnly.length, 8);

    final spaced = findSpectrumPeaks(
      db: db,
      freqs: freqs,
      maxPeaks: 8,
      axisPos: pos,
      minAxisGap: 0.04,
    );
    expect(spaced.length, lessThan(binOnly.length));
    for (var i = 1; i < spaced.length; i++) {
      expect(
        pos(spaced[i].hz) - pos(spaced[i - 1].hz),
        greaterThanOrEqualTo(0.04),
      );
    }
    // The strongest peak always survives.
    expect(spaced.any((p) => p.bin == 20), isTrue);
  });

  test('time-axis hint matches the input device', () {
    expect(timeAxisHint(canZoom: false, canPan: false, touch: true), 'time');
    expect(
      timeAxisHint(canZoom: true, canPan: true, touch: true),
      'pinch zoom · two-finger pan',
    );
    expect(
      timeAxisHint(canZoom: true, canPan: false, touch: false),
      'wheel zoom',
    );
  });
}
