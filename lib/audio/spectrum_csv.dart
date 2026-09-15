import 'dart:typed_data';

import 'package:spectrogram/dsp/spectrum_analysis.dart';

/// CSV of a spectrum (all bins) with optional peak-hold and peak flags.
String formatSpectrumCsv({
  required Float32List freqs,
  required Float32List db,
  Float32List? peakHold,
  Set<int> peakBins = const {},
}) {
  final buf = StringBuffer('frequency_hz,dbfs');
  if (peakHold != null) buf.write(',peak_hold_dbfs');
  buf.write(',is_peak\n');
  final n = freqs.length < db.length ? freqs.length : db.length;
  for (var i = 0; i < n; i++) {
    buf.write(freqs[i].toStringAsFixed(6));
    buf.write(',');
    buf.write(db[i].toStringAsFixed(3));
    if (peakHold != null) {
      buf.write(',');
      final h = i < peakHold.length ? peakHold[i] : db[i];
      buf.write(h.toStringAsFixed(3));
    }
    buf.write(',');
    buf.write(peakBins.contains(i) ? '1' : '0');
    buf.write('\n');
  }
  return buf.toString();
}

/// Convenience: mark bins returned by [findSpectrumPeaks].
Set<int> peakBinSet(List<SpectrumPeak> peaks) => {for (final p in peaks) p.bin};
