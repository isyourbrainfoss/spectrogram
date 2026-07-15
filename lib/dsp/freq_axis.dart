import 'dart:math' as math;
import 'dart:typed_data';

import 'package:spectrogram/models/app_settings.dart';

/// Frequency axis mapping and “nice” tick generation.
///
/// [norm] is 0 at [minHz] and 1 at [maxHz] (plot bottom → top for spectrogram Y,
/// left → right for spectrum X).
abstract final class FreqAxis {
  /// Prefer these audible / ISO R10-ish landmarks when they fall in range.
  static const commonHz = <double>[
    20,
    25,
    31.5,
    40,
    50,
    63,
    80,
    100,
    125,
    160,
    200,
    250,
    315,
    400,
    500,
    630,
    800,
    1000,
    1250,
    1600,
    2000,
    2500,
    3150,
    4000,
    5000,
    6300,
    8000,
    10000,
    12500,
    16000,
    20000,
  ];

  static double freqToNorm(
    double hz,
    double minHz,
    double maxHz,
    FreqScale scale,
  ) {
    final lo = math.max(minHz, 1e-6);
    final hi = math.max(maxHz, lo * 1.0001);
    final f = hz.clamp(lo, hi);
    switch (scale) {
      case FreqScale.linear:
        return ((f - lo) / (hi - lo)).clamp(0.0, 1.0);
      case FreqScale.logarithmic:
        final lnLo = math.log(lo);
        final lnHi = math.log(hi);
        return ((math.log(f) - lnLo) / (lnHi - lnLo)).clamp(0.0, 1.0);
    }
  }

  static double normToFreq(
    double norm,
    double minHz,
    double maxHz,
    FreqScale scale,
  ) {
    final lo = math.max(minHz, 1e-6);
    final hi = math.max(maxHz, lo * 1.0001);
    final t = norm.clamp(0.0, 1.0);
    switch (scale) {
      case FreqScale.linear:
        return lo + t * (hi - lo);
      case FreqScale.logarithmic:
        final lnLo = math.log(lo);
        final lnHi = math.log(hi);
        return math.exp(lnLo + t * (lnHi - lnLo));
    }
  }

  /// Ticks as (norm 0..1, frequency Hz), spaced for readability.
  static List<({double norm, double hz})> ticks({
    required double minHz,
    required double maxHz,
    required FreqScale scale,
    int maxTicks = 8,
  }) {
    final lo = math.max(minHz, 1e-6);
    final hi = math.max(maxHz, lo * 1.0001);
    final candidates = <double>{lo, hi};
    for (final c in commonHz) {
      if (c >= lo * 0.999 && c <= hi * 1.001) {
        candidates.add(c.clamp(lo, hi));
      }
    }

    for (var i = 1; i < 6; i++) {
      candidates.add(normToFreq(i / 6, lo, hi, scale));
    }

    final sorted = candidates.toList()..sort();
    if (sorted.length <= maxTicks) {
      return [
        for (final hz in sorted)
          (norm: freqToNorm(hz, lo, hi, scale), hz: hz),
      ];
    }

    final picked = <double>{sorted.first, sorted.last};
    while (picked.length < maxTicks) {
      var bestHz = sorted[sorted.length ~/ 2];
      var bestGap = -1.0;
      for (final hz in sorted) {
        if (picked.contains(hz)) continue;
        final n = freqToNorm(hz, lo, hi, scale);
        var minDist = double.infinity;
        for (final p in picked) {
          final d = (n - freqToNorm(p, lo, hi, scale)).abs();
          if (d < minDist) minDist = d;
        }
        if (minDist > bestGap) {
          bestGap = minDist;
          bestHz = hz;
        }
      }
      if (bestGap < 0) break;
      picked.add(bestHz);
    }

    final out = picked.toList()..sort();
    return [
      for (final hz in out) (norm: freqToNorm(hz, lo, hi, scale), hz: hz),
    ];
  }

  /// Nearest bin index for [hz] given monotonic [freqs].
  static int binForFreq(Float32List freqs, double hz) {
    if (freqs.isEmpty) return 0;
    if (hz <= freqs[0]) return 0;
    if (hz >= freqs[freqs.length - 1]) return freqs.length - 1;
    var lo = 0;
    var hi = freqs.length - 1;
    while (hi - lo > 1) {
      final mid = (lo + hi) >> 1;
      if (freqs[mid] <= hz) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    final dLo = (hz - freqs[lo]).abs();
    final dHi = (freqs[hi] - hz).abs();
    return dLo <= dHi ? lo : hi;
  }
}
