import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:spectrogram/audio/input_device_labels.dart';
import 'package:spectrogram/audio/spectrum_csv.dart';
import 'package:spectrogram/audio/wav_io.dart';
import 'package:spectrogram/dsp/colormap.dart';
import 'package:spectrogram/dsp/freq_axis.dart';
import 'package:spectrogram/dsp/pcm.dart';
import 'package:spectrogram/dsp/spectrum_analysis.dart';
import 'package:spectrogram/dsp/stft_processor.dart';
import 'package:spectrogram/models/app_settings.dart';
import 'package:spectrogram/services/audio_capture_service.dart';
import 'package:spectrogram/services/spectrogram_engine.dart';
import 'package:record/record.dart';

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

    test('bin-centred sine reads its true level in dBFS', () {
      const sr = 48000;
      const fft = 2048;
      final proc = StftProcessor(fftSize: fft, hopSize: 512);
      // Bin 43 centre ≈ 1007.8 Hz: no scalloping loss.
      const tone = 43 * sr / fft;
      for (final (amp, expectedDb) in [(1.0, 0.0), (0.1, -20.0)]) {
        final frames = proc.processAll(
          generateSine(
            freqHz: tone,
            sampleRate: sr,
            length: fft * 8,
            amplitude: amp,
          ),
        );
        final frame = frames[frames.length ~/ 2];
        expect(StftProcessor.peakBin(frame, from: 1), 43);
        expect(frame[43], closeTo(expectedDb, 0.1));
      }
    });

    test('DC and Nyquist bins are not doubled (1/Σw)', () {
      const fft = 2048;
      final proc = StftProcessor(fftSize: fft, hopSize: 512);
      for (final amp in [1.0, 0.1]) {
        final expectedDb = 20 * math.log(amp) / math.ln10;
        // Constant offset: all energy in the DC bin.
        final dc = Float32List(fft * 8)..fillRange(0, fft * 8, amp);
        final dcFrames = proc.processAll(dc);
        expect(dcFrames[dcFrames.length ~/ 2][0], closeTo(expectedDb, 0.1));
        // Alternating ±amp: a cosine at exactly Nyquist (fs/2).
        final ny = Float32List.fromList(
          List.generate(fft * 8, (i) => i.isEven ? amp : -amp),
        );
        final nyFrames = proc.processAll(ny);
        final frame = nyFrames[nyFrames.length ~/ 2];
        expect(frame.length, fft ~/ 2 + 1);
        expect(frame[fft ~/ 2], closeTo(expectedDb, 0.1));
      }
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
        peakHold: false,
        peakHoldDecayDbPerSec: 12,
        inputDeviceId: 'hw:1,0',
        inputDeviceLabel: 'USB Mic',
      );
      final copy = AppSettings.fromMap(s.toMap());
      expect(copy, s);
    });

    test('clearInputDevice resets mic selection', () {
      const s = AppSettings(
        inputDeviceId: 'mic-1',
        inputDeviceLabel: 'Built-in',
      );
      final cleared = s.copyWith(clearInputDevice: true);
      expect(cleared.inputDeviceId, isNull);
      expect(cleared.inputDeviceLabel, isNull);
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

  group('WavIo', () {
    test('round-trips mono PCM16', () {
      final sine = generateSine(
        freqHz: 440,
        sampleRate: 8000,
        length: 800,
        amplitude: 0.5,
      );
      final bytes = WavIo.encodeMonoPcm16(samples: sine, sampleRate: 8000);
      final decoded = WavIo.decode(bytes);
      expect(decoded.sampleRate, 8000);
      expect(decoded.channels, 1);
      expect(decoded.samples.length, sine.length);
      expect(decoded.samples[100], closeTo(sine[100], 2 / 32768));
    });
  });

  group('InputDeviceLabels', () {
    test('disambiguates duplicate product names', () {
      const a = InputDevice(
        id: '1',
        label: 'FP5',
        type: InputDeviceType.builtIn,
      );
      const b = InputDevice(
        id: '2',
        label: 'FP5',
        type: InputDeviceType.builtIn,
        sampleRates: [48000],
      );
      final all = [a, b];
      final la = InputDeviceLabels.format(a, all: all);
      final lb = InputDeviceLabels.format(b, all: all);
      expect(la, isNot(equals(lb)));
      expect(la, contains('Built-in'));
      expect(la, contains('mic 1'));
      expect(lb, contains('mic 2'));
      expect(lb, contains('48000 Hz'));
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

    test('binForFreq picks nearest', () {
      final freqs = Float32List.fromList([100, 200, 400, 800]);
      expect(FreqAxis.binForFreq(freqs, 100), 0);
      expect(FreqAxis.binForFreq(freqs, 190), 1);
      expect(FreqAxis.binForFreq(freqs, 800), 3);
    });
  });

  group('peak hold', () {
    test('keeps the max and decays toward current', () {
      final hold = Float32List.fromList([0, -6, -20]);
      final current = Float32List.fromList([-12, -3, -40]);
      applyPeakHold(
        hold: hold,
        current: current,
        decayDbPerSec: 6,
        dtSec: 0.5, // dt is clamped at 0.5 s so a pause cannot wipe the hold
      );
      // 0 - 3 = -3, vs current -12 → -3
      expect(hold[0], closeTo(-3, 1e-9));
      // -6 - 3 = -9, vs current -3 → -3
      expect(hold[1], closeTo(-3, 1e-9));
      // -20 - 3 = -23, vs current -40 → -23
      expect(hold[2], closeTo(-23, 1e-9));
    });

    test('infinite hold never decays', () {
      final hold = Float32List.fromList([0]);
      applyPeakHold(
        hold: hold,
        current: Float32List.fromList([-90]),
        decayDbPerSec: 0,
        dtSec: 10,
      );
      expect(hold[0], closeTo(0, 1e-9));
    });
  });

  group('spectrum peaks', () {
    test('parabolic offset leans toward the higher neighbor', () {
      // yRight closer to the peak than yLeft → positive offset.
      final d = parabolicOffset(-20, -6, -12);
      expect(d, greaterThan(0));
      expect(d, lessThan(0.5));
    });

    test('finds two well-separated local maxima', () {
      final db = Float32List(32);
      final freqs = Float32List(32);
      for (var i = 0; i < 32; i++) {
        db[i] = -80;
        freqs[i] = i * 100.0;
      }
      db[8] = -10;
      db[7] = -18;
      db[9] = -20;
      db[20] = -12;
      db[19] = -22;
      db[21] = -19;
      final peaks = findSpectrumPeaks(
        db: db,
        freqs: freqs,
        floorDb: -40,
        maxPeaks: 8,
        minSeparationBins: 3,
      );
      expect(peaks.length, 2);
      expect(peaks.first.hz, closeTo(800, 50));
      expect(peaks.last.hz, closeTo(2000, 50));
    });
  });

  group('spectrum CSV', () {
    test('marks peak bins', () {
      final csv = formatSpectrumCsv(
        freqs: Float32List.fromList([100, 200, 300]),
        db: Float32List.fromList([-20, -5, -40]),
        peakHold: Float32List.fromList([-10, -5, -30]),
        peakBins: {1},
      );
      final lines = csv.trim().split('\n');
      expect(lines.first, 'frequency_hz,dbfs,peak_hold_dbfs,is_peak');
      expect(lines[2], contains(',1'));
      expect(lines[1].endsWith(',0'), isTrue);
    });
  });

  group('SpectrogramEngine', () {
    test('1 kHz import peaks near 1 kHz and CSV is non-empty', () async {
      final engine = SpectrogramEngine(
        capture: AudioCaptureService.none(),
        settings: const AppSettings(
          sampleRate: 48000,
          fftSize: 2048,
          hopSize: 512,
        ),
      );
      addTearDown(engine.dispose);

      final sine = generateSine(
        freqHz: 1000,
        sampleRate: 48000,
        length: 48000,
        amplitude: 1.0,
      );
      await engine.analyzeMono(sine, 48000, label: 'tone.wav');
      expect(engine.filledColumns, greaterThan(8));
      expect(engine.peakFreqHz, closeTo(1000, 40));
      expect(engine.peakDb, greaterThan(-12));

      final peaks = engine.spectrumPeaks(maxPeaks: 4);
      expect(peaks, isNotEmpty);
      final strongest = peaks.reduce((a, b) => a.db >= b.db ? a : b);
      expect(strongest.hz, closeTo(1000, 80));

      final csv = engine.exportSpectrumCsv();
      expect(csv, isNotNull);
      expect(csv!, contains('frequency_hz,dbfs'));
      expect(csv.contains('is_peak'), isTrue);
    });

    test('recolors stored columns when colormap changes', () async {
      final engine = SpectrogramEngine(
        capture: AudioCaptureService.none(),
        settings: const AppSettings(
          sampleRate: 8000,
          fftSize: 512,
          hopSize: 128,
          colormap: ColormapKind.viridis,
        ),
      );
      addTearDown(engine.dispose);

      final sine = generateSine(
        freqHz: 440,
        sampleRate: 8000,
        length: 8000,
        amplitude: 0.8,
      );
      await engine.analyzeMono(sine, 8000);
      expect(engine.filledColumns, greaterThan(0));
      final mid = engine.displayBins ~/ 2;
      final before = engine.colorColumnAt(engine.filledColumns ~/ 2)[mid];

      await engine.applySettings(
        engine.settings.copyWith(colormap: ColormapKind.grayscale),
      );
      final after = engine.colorColumnAt(engine.filledColumns ~/ 2)[mid];
      expect(after, isNot(equals(before)));
    });

    test('freeze blocks new spectrogram columns', () async {
      final engine = SpectrogramEngine(
        capture: AudioCaptureService.none(),
        settings: const AppSettings(
          sampleRate: 8000,
          fftSize: 512,
          hopSize: 128,
        ),
      );
      addTearDown(engine.dispose);

      final sine = generateSine(
        freqHz: 440,
        sampleRate: 8000,
        length: 4000,
        amplitude: 0.5,
      );
      await engine.analyzeMono(sine, 8000);
      final filled = engine.filledColumns;
      engine.toggleFreeze();
      expect(engine.isFrozen, isTrue);
      // Import already stopped; freeze is a flag until the next live frames.
      expect(engine.filledColumns, filled);
      engine.toggleFreeze();
      expect(engine.isFrozen, isFalse);
    });
  });
}
