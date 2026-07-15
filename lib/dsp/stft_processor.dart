import 'dart:math' as math;
import 'dart:typed_data';

import 'package:fftea/fftea.dart';

/// Streaming STFT processor for live spectrograms.
///
/// dBFS convention for a real-valued mono signal:
///   dBFS = 20 * log10(max(2 * |X[k]| / N, ε))
/// where N is the FFT size. A pure full-scale sine near a bin center yields
/// approximately 0 dBFS at that bin (Hann coherent gain is only partially
/// compensated; levels stay consistent for comparative readout).
class StftProcessor {
  StftProcessor({
    required this.fftSize,
    required this.hopSize,
  })  : assert(fftSize >= 64 && (fftSize & (fftSize - 1)) == 0),
        assert(hopSize > 0 && hopSize <= fftSize),
        _stft = STFT(fftSize, Window.hanning(fftSize)),
        binCount = fftSize ~/ 2 + 1,
        _dbBuffer = Float32List(fftSize ~/ 2 + 1);

  final int fftSize;
  final int hopSize;
  final int binCount;

  final STFT _stft;
  final Float32List _dbBuffer;

  static const double epsilon = 1e-20;
  static const double _dbFloor = -200.0;

  void reset() {
    // Drain any residual streaming state by flushing into a no-op.
    _stft.flush((_) {});
  }

  /// Push mono float samples. Calls [onFrame] for each completed hop with
  /// a dBFS spectrum of length [binCount] (reused buffer — copy if storing).
  void push(Float32List samples, void Function(Float32List dbSpectrum) onFrame) {
    if (samples.isEmpty) return;
    // STFT.stream expects List<double>; Float32List implements that.
    _stft.stream(samples, (Float64x2List freq) {
      _toDb(freq);
      onFrame(_dbBuffer);
    }, hopSize);
  }

  /// Process a full buffer offline (tests / analysis).
  List<Float32List> processAll(Float32List samples) {
    final out = <Float32List>[];
    reset();
    push(samples, (frame) => out.add(Float32List.fromList(frame)));
    return out;
  }

  void _toDb(Float64x2List freq) {
    final mags = freq.discardConjugates().magnitudes();
    final scale = 2.0 / fftSize;
    final n = math.min(binCount, mags.length);
    for (var k = 0; k < n; k++) {
      final mag = mags[k] * scale;
      final db = 20.0 * math.log(math.max(mag, epsilon)) / math.ln10;
      _dbBuffer[k] = db < _dbFloor ? _dbFloor : db;
    }
    // DC bin is often not doubled; keep simple uniform scale for consistency.
  }

  /// Frequency of bin [k] in Hz.
  double frequencyOfBin(int k, int sampleRate) =>
      _stft.frequency(k, sampleRate.toDouble());

  /// Nearest bin for [freqHz].
  int binOfFrequency(double freqHz, int sampleRate) {
    final k = _stft.indexOfFrequency(freqHz, sampleRate.toDouble()).round();
    return k.clamp(0, binCount - 1);
  }

  /// Index of peak bin in a dB spectrum (optionally within a bin range).
  static int peakBin(Float32List db, {int from = 0, int? to}) {
    final end = (to ?? db.length).clamp(1, db.length);
    final start = from.clamp(0, end - 1);
    var best = start;
    var bestVal = db[start];
    for (var i = start + 1; i < end; i++) {
      if (db[i] > bestVal) {
        bestVal = db[i];
        best = i;
      }
    }
    return best;
  }
}

/// Generate a mono sine wave of [amplitude] (1.0 = full scale) at [freqHz].
Float32List generateSine({
  required double freqHz,
  required int sampleRate,
  required int length,
  double amplitude = 1.0,
  double phase = 0.0,
}) {
  final out = Float32List(length);
  final w = 2 * math.pi * freqHz / sampleRate;
  for (var i = 0; i < length; i++) {
    out[i] = amplitude * math.sin(phase + w * i);
  }
  return out;
}
