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
    bool inRange(double v) => v >= lo * 0.999 && v <= hi * 1.001;

    switch (scale) {
      case FreqScale.logarithmic:
        // 1-2-5 per decade reads cleanly (20, 50, 100, 200, 500, 1k, ...).
        final firstDecade = (math.log(lo) / math.ln10).floor();
        final lastDecade = (math.log(hi) / math.ln10).ceil();
        for (var d = firstDecade; d <= lastDecade; d++) {
          for (final m in const [1.0, 2.0, 5.0]) {
            final v = m * math.pow(10, d).toDouble();
            if (inRange(v)) candidates.add(v.clamp(lo, hi));
          }
        }
      case FreqScale.linear:
        final step = niceStep((hi - lo) / math.max(1, maxTicks - 1));
        for (var v = (lo / step).ceil() * step; v <= hi * 1.001; v += step) {
          if (inRange(v)) candidates.add(v.clamp(lo, hi));
        }
    }

    // Narrow ranges: fall back to ISO landmarks, then rounded fillers.
    if (candidates.length < 4) {
      for (final c in commonHz) {
        if (inRange(c)) candidates.add(c.clamp(lo, hi));
      }
    }
    if (candidates.length < 3) {
      for (var i = 1; i < 4; i++) {
        candidates.add(
          roundSignificant(normToFreq(i / 4, lo, hi, scale), 2).clamp(lo, hi),
        );
      }
    }

    // A landmark hugging an end (10 kHz next to a 12 kHz max) only crowds it.
    candidates.removeWhere(
      (hz) =>
          hz != lo &&
          hz != hi &&
          (freqToNorm(hz, lo, hi, scale) < 0.035 ||
              freqToNorm(hz, lo, hi, scale) > 0.965),
    );

    final sorted = candidates.toList()..sort();
    if (sorted.length <= maxTicks) {
      return [
        for (final hz in sorted) (norm: freqToNorm(hz, lo, hi, scale), hz: hz),
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

  /// A "nice" step (1, 2, 2.5 or 5 × 10^n) at or just above [raw].
  static double niceStep(double raw) {
    if (!(raw > 0) || raw.isInfinite) return 1;
    final exp = math.pow(10, (math.log(raw) / math.ln10).floor()).toDouble();
    final f = raw / exp;
    final m = f <= 1
        ? 1.0
        : f <= 2
        ? 2.0
        : f <= 2.5
        ? 2.5
        : f <= 5
        ? 5.0
        : 10.0;
    return m * exp;
  }

  /// Rounds [v] to [digits] significant digits (e.g. 487 → 490).
  static double roundSignificant(double v, int digits) {
    if (v == 0 || v.isNaN || v.isInfinite) return v;
    final mag = (math.log(v.abs()) / math.ln10).floor() - digits + 1;
    final scale = math.pow(10, mag).toDouble();
    return (v / scale).round() * scale;
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
