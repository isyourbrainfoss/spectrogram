import 'dart:math' as math;
import 'dart:typed_data';

/// A local maximum in a dB spectrum.
class SpectrumPeak {
  const SpectrumPeak({required this.bin, required this.hz, required this.db});

  final int bin;
  final double hz;
  final double db;
}

/// Peak-hold envelope: each bin keeps max(current, hold − decay).
///
/// [decayDbPerSec] of 0 means infinite hold. [dtSec] is clamped so a long
/// pause cannot wipe the envelope in one jump.
void applyPeakHold({
  required Float32List hold,
  required Float32List current,
  required double decayDbPerSec,
  required double dtSec,
}) {
  final n = math.min(hold.length, current.length);
  final decay = decayDbPerSec <= 0
      ? 0.0
      : decayDbPerSec * dtSec.clamp(0.0, 0.5);
  for (var i = 0; i < n; i++) {
    var v = hold[i];
    if (decay > 0) v -= decay;
    final c = current[i];
    if (c > v) v = c;
    hold[i] = v;
  }
}

/// Parabolic bin offset in [−0.5, 0.5] around a discrete peak.
double parabolicOffset(double yLeft, double yCenter, double yRight) {
  final denom = yLeft - 2 * yCenter + yRight;
  if (denom.abs() < 1e-12) return 0;
  return (0.5 * (yLeft - yRight) / denom).clamp(-0.5, 0.5);
}

/// Sub-bin peak frequency using parabolic interpolation on a dB spectrum.
double interpolatePeakHz({
  required Float32List db,
  required int peakBin,
  required double Function(int bin) hzOfBin,
}) {
  if (peakBin <= 0 || peakBin >= db.length - 1) {
    return hzOfBin(peakBin);
  }
  final delta = parabolicOffset(db[peakBin - 1], db[peakBin], db[peakBin + 1]);
  final mid = hzOfBin(peakBin);
  if (delta < 0) {
    return mid + delta * (mid - hzOfBin(peakBin - 1));
  }
  if (delta > 0) {
    return mid + delta * (hzOfBin(peakBin + 1) - mid);
  }
  return mid;
}

/// Strongest local maxima, spaced at least [minSeparationBins] apart.
List<SpectrumPeak> findSpectrumPeaks({
  required Float32List db,
  required Float32List freqs,
  double floorDb = -90,
  int maxPeaks = 16,
  int minSeparationBins = 3,
}) {
  final n = math.min(db.length, freqs.length);
  if (n < 3 || maxPeaks <= 0) return const [];

  final candidates = <SpectrumPeak>[];
  for (var i = 1; i < n - 1; i++) {
    final v = db[i];
    if (v < floorDb) continue;
    if (v >= db[i - 1] && v > db[i + 1]) {
      final hz = interpolatePeakHz(
        db: db,
        peakBin: i,
        hzOfBin: (k) => freqs[k],
      );
      candidates.add(SpectrumPeak(bin: i, hz: hz, db: v));
    }
  }
  if (candidates.isEmpty) return const [];

  candidates.sort((a, b) => b.db.compareTo(a.db));
  final picked = <SpectrumPeak>[];
  for (final c in candidates) {
    if (picked.length >= maxPeaks) break;
    var near = false;
    for (final p in picked) {
      if ((p.bin - c.bin).abs() < minSeparationBins) {
        near = true;
        break;
      }
    }
    if (!near) picked.add(c);
  }
  picked.sort((a, b) => a.hz.compareTo(b.hz));
  return picked;
}
