import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:spectrogram/dsp/colormap.dart';
import 'package:spectrogram/dsp/freq_axis.dart';
import 'package:spectrogram/dsp/pcm.dart';
import 'package:spectrogram/dsp/stft_processor.dart';
import 'package:spectrogram/models/app_settings.dart';

void main() {
  group('pcm16ToMonoFloat', () {
    test('converts little-endian int16 to float', () {
      final bytes = Uint8List.fromList([
        0x00, 0x00, // 0
        0x00, 0x40, // 16384 ≈ 0.5
        0x00, 0x80, // -32768 ≈ -1.0
      ]);
      final out = pcm16ToMonoFloat(bytes);
      expect(out.length, 3);
      expect(out[0], closeTo(0.0, 1e-9));
      expect(out[1], closeTo(0.5, 1e-4));
      expect(out[2], closeTo(-1.0, 1e-9));
    });
  });

  group('StftProcessor', () {
    test('peaks near 1 kHz for a full-scale 1 kHz sine @ 48 kHz', () {
      const sr = 48000;
      const fft = 2048;
      const hop = 512;
      const tone = 1000.0;

      final sine = generateSine(
        freqHz: tone,
        sampleRate: sr,
        length: fft * 8,
        amplitude: 1.0,
      );

      final proc = StftProcessor(fftSize: fft, hopSize: hop);
      final frames = proc.processAll(sine);
      expect(frames, isNotEmpty);

      // Use a middle frame (after window settles).
      final frame = frames[frames.length ~/ 2];
      final peak = StftProcessor.peakBin(frame, from: 1); // skip DC
      final peakHz = proc.frequencyOfBin(peak, sr);
      final binRes = sr / fft;

      expect(peakHz, closeTo(tone, binRes * 1.5));
      // Full-scale sine should be strong (near 0 dBFS; allow window loss).
      expect(frame[peak], greaterThan(-12.0));
      expect(frame[peak], lessThan(3.0));
    });

    test('bin frequency mapping', () {
      final proc = StftProcessor(fftSize: 2048, hopSize: 512);
      expect(proc.frequencyOfBin(0, 48000), 0);
      expect(proc.frequencyOfBin(1, 48000), closeTo(48000 / 2048, 1e-9));
      final bin = proc.binOfFrequency(1000, 48000);
      expect(proc.frequencyOfBin(bin, 48000), closeTo(1000, 48000 / 2048));
    });
  });

  group('ColorMap', () {
    test('maps endpoints of viridis', () {
      final map = ColorMap.of(ColormapKind.viridis);
      final low = map.map(0);
      final high = map.map(1);
      expect(low, isNot(equals(high)));
      // Alpha channel set.
      expect((low >> 24) & 0xFF, 0xFF);
      expect((high >> 24) & 0xFF, 0xFF);
    });

    test('mapDb clamps outside range', () {
      final map = ColorMap.of(ColormapKind.grayscale);
      final below = map.mapDb(-200, -90, 0);
      final above = map.mapDb(10, -90, 0);
      expect(below, map.map(0));
      expect(above, map.map(1));
    });
  });

  group('AppSettings', () {
    test('round-trips through map', () {
      const s = AppSettings(
        sampleRate: 44100,
        fftSize: 4096,
        hopSize: 1024,
        colormap: ColormapKind.turbo,
        colorScheme: ThemePreference.dark,
      );
      final copy = AppSettings.fromMap(s.toMap());
      expect(copy, s);
    });

    test('columnCount is positive and bounded', () {
      const s = AppSettings();
      expect(s.columnCount, greaterThan(0));
      expect(s.columnCount, lessThanOrEqualTo(2048));
    });
  });

  group('generateSine', () {
    test('amplitude bounds', () {
      final s = generateSine(
        freqHz: 440,
        sampleRate: 48000,
        length: 1000,
        amplitude: 0.5,
      );
      final peak = s.reduce((a, b) => math.max(a.abs(), b.abs()));
      expect(peak, lessThanOrEqualTo(0.5 + 1e-9));
    });
  });

  group('FreqAxis', () {
    test('linear endpoints', () {
      expect(
        FreqAxis.freqToNorm(20, 20, 12000, FreqScale.linear),
        closeTo(0, 1e-9),
      );
      expect(
        FreqAxis.freqToNorm(12000, 20, 12000, FreqScale.linear),
        closeTo(1, 1e-9),
      );
      expect(
        FreqAxis.normToFreq(0.5, 0, 1000, FreqScale.linear),
        closeTo(500, 1e-6),
      );
    });

    test('log maps mid-octave-ish below linear midpoint', () {
      // Geometric mean of 20 and 20000 is ~632, not 10010.
      final mid = FreqAxis.normToFreq(0.5, 20, 20000, FreqScale.logarithmic);
      expect(mid, closeTo(math.sqrt(20 * 20000), 1));
      expect(mid, lessThan(5000));
    });

    test('common ticks include 100 Hz and 1 kHz in default range', () {
      final ticks = FreqAxis.ticks(
        minHz: 20,
        maxHz: 12000,
        scale: FreqScale.logarithmic,
        maxTicks: 8,
      );
      final values = ticks.map((t) => t.hz).toList();
      expect(values.any((h) => (h - 100).abs() < 1), isTrue);
      expect(values.any((h) => (h - 1000).abs() < 1), isTrue);
    });
  });
}
