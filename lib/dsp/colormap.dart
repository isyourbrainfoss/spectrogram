import 'dart:typed_data';
import 'dart:ui' show Color;

import 'package:spectrogram/models/app_settings.dart';

/// Lookup tables mapping normalized [0,1] amplitude to ARGB.
class ColorMap {
  ColorMap._(this._lut);

  final Uint32List _lut;

  static const lutSize = 256;

  /// ARGB packed for [ui.decodeImageFromPixels] (little-endian byte order in memory
  /// is handled by Flutter as RGBA8888 when using [PixelFormat.rgba8888]).
  int map(double t) {
    final i = (t.clamp(0.0, 1.0) * (lutSize - 1)).round();
    return _lut[i];
  }

  Color color(double t) {
    final argb = map(t);
    return Color(argb);
  }

  static final Map<ColormapKind, ColorMap> _cache = {};

  static ColorMap of(ColormapKind kind) {
    return _cache.putIfAbsent(kind, () => _build(kind));
  }

  static ColorMap _build(ColormapKind kind) {
    final lut = Uint32List(lutSize);
    for (var i = 0; i < lutSize; i++) {
      final t = i / (lutSize - 1);
      final c = switch (kind) {
        ColormapKind.viridis => _viridis(t),
        ColormapKind.magma => _magma(t),
        ColormapKind.turbo => _turbo(t),
        ColormapKind.grayscale => _grayscale(t),
      };
      // Store as 0xAARRGGBB for Color / Image.
      lut[i] = (0xFF << 24) |
          (c.$1 << 16) |
          (c.$2 << 8) |
          c.$3;
    }
    return ColorMap._(lut);
  }

  /// Map dBFS in [minDb, maxDb] to a packed color.
  int mapDb(double db, double minDb, double maxDb) {
    final span = (maxDb - minDb).abs();
    if (span < 1e-9) return map(0);
    final t = ((db - minDb) / span).clamp(0.0, 1.0);
    return map(t);
  }

  // Approximate viridis (dark purple → green → yellow).
  static (int, int, int) _viridis(double t) {
    final r = _lerpStops(t, const [
      (0.0, 68),
      (0.25, 59),
      (0.5, 33),
      (0.75, 94),
      (1.0, 253),
    ]);
    final g = _lerpStops(t, const [
      (0.0, 1),
      (0.25, 82),
      (0.5, 145),
      (0.75, 201),
      (1.0, 231),
    ]);
    final b = _lerpStops(t, const [
      (0.0, 84),
      (0.25, 139),
      (0.5, 140),
      (0.75, 98),
      (1.0, 37),
    ]);
    return (r, g, b);
  }

  // Magma: black → purple → orange → cream.
  static (int, int, int) _magma(double t) {
    final r = _lerpStops(t, const [
      (0.0, 0),
      (0.25, 80),
      (0.5, 183),
      (0.75, 252),
      (1.0, 252),
    ]);
    final g = _lerpStops(t, const [
      (0.0, 0),
      (0.25, 18),
      (0.5, 55),
      (0.75, 137),
      (1.0, 253),
    ]);
    final b = _lerpStops(t, const [
      (0.0, 4),
      (0.25, 123),
      (0.5, 121),
      (0.75, 91),
      (1.0, 191),
    ]);
    return (r, g, b);
  }

  // Turbo-like rainbow (readable for spectrograms).
  static (int, int, int) _turbo(double t) {
    final r = _lerpStops(t, const [
      (0.0, 48),
      (0.2, 34),
      (0.4, 35),
      (0.6, 188),
      (0.8, 249),
      (1.0, 122),
    ]);
    final g = _lerpStops(t, const [
      (0.0, 18),
      (0.2, 94),
      (0.4, 188),
      (0.6, 221),
      (0.8, 150),
      (1.0, 4),
    ]);
    final b = _lerpStops(t, const [
      (0.0, 59),
      (0.2, 168),
      (0.4, 116),
      (0.6, 56),
      (0.8, 37),
      (1.0, 3),
    ]);
    return (r, g, b);
  }

  static (int, int, int) _grayscale(double t) {
    final v = (t * 255).round().clamp(0, 255);
    return (v, v, v);
  }

  static int _lerpStops(double t, List<(double, int)> stops) {
    if (t <= stops.first.$1) return stops.first.$2;
    if (t >= stops.last.$1) return stops.last.$2;
    for (var i = 0; i < stops.length - 1; i++) {
      final a = stops[i];
      final b = stops[i + 1];
      if (t >= a.$1 && t <= b.$1) {
        final u = (t - a.$1) / (b.$1 - a.$1);
        return (a.$2 + (b.$2 - a.$2) * u).round().clamp(0, 255);
      }
    }
    return stops.last.$2;
  }
}

/// Convert 0xAARRGGBB to RGBA8888 bytes for [decodeImageFromPixels].
void writeRgba8888(Uint8List out, int offset, int argb) {
  out[offset] = (argb >> 16) & 0xFF; // R
  out[offset + 1] = (argb >> 8) & 0xFF; // G
  out[offset + 2] = argb & 0xFF; // B
  out[offset + 3] = (argb >> 24) & 0xFF; // A
}
