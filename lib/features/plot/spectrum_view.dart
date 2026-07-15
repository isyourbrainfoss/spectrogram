import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:spectrogram/features/plot/axis_labels.dart';
import 'package:spectrogram/features/plot/crosshair_overlay.dart';
import 'package:spectrogram/services/spectrogram_engine.dart';

/// Live frequency vs amplitude (dBFS) spectrum plot with optional crosshair.
class SpectrumView extends StatelessWidget {
  const SpectrumView({
    super.key,
    required this.engine,
    this.crosshair,
    this.onCrosshairChanged,
  });

  final SpectrogramEngine engine;
  final CrosshairPoint? crosshair;
  final ValueChanged<CrosshairPoint?>? onCrosshairChanged;

  void _handleLocal(Offset local, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    final nx = (local.dx / size.width).clamp(0.0, 1.0);
    // Snap ny to curve for nicer readout.
    final sample = engine.sampleSpectrum(nx);
    final s = engine.settings;
    final span = (s.maxDb - s.minDb).abs();
    final ny = sample == null || span < 1e-9
        ? (1.0 - local.dy / size.height).clamp(0.0, 1.0)
        : ((sample.db - s.minDb) / span).clamp(0.0, 1.0);
    onCrosshairChanged?.call(CrosshairPoint(nx: nx, ny: ny));
  }

  @override
  Widget build(BuildContext context) {
    final s = engine.settings;
    final scheme = Theme.of(context).colorScheme;

    return PlotChrome(
      yMinLabel: formatDb(s.minDb),
      yMidLabel: formatDb((s.minDb + s.maxDb) / 2),
      yMaxLabel: formatDb(s.maxDb),
      xMinLabel: formatFrequency(s.minFreqHz),
      xMidLabel: 'frequency',
      xMaxLabel: formatFrequency(s.maxFreqHz),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = Size(constraints.maxWidth, constraints.maxHeight);
          return Listener(
            onPointerDown: (ev) => _handleLocal(ev.localPosition, size),
            onPointerMove: (ev) {
              if (ev.down) _handleLocal(ev.localPosition, size);
            },
            child: MouseRegion(
              onHover: (ev) {
                if (crosshair != null) {
                  _handleLocal(ev.localPosition, size);
                }
              },
              child: Stack(
                fit: StackFit.expand,
                children: [
                  RepaintBoundary(
                    child: CustomPaint(
                      painter: _SpectrumPainter(
                        db: Float32List.fromList(engine.displayDb),
                        freqs: Float32List.fromList(engine.displayFreqs),
                        minDb: s.minDb,
                        maxDb: s.maxDb,
                        lineColor: scheme.primary,
                        fillColor: scheme.primary.withValues(alpha: 0.22),
                        gridColor: scheme.outline.withValues(alpha: 0.25),
                        bgColor: scheme.surfaceContainerHighest,
                      ),
                      size: size,
                    ),
                  ),
                  if (crosshair != null)
                    Builder(
                      builder: (context) {
                        final sample = engine.sampleSpectrum(crosshair!.nx);
                        if (sample == null) return const SizedBox.shrink();
                        final span = (s.maxDb - s.minDb).abs();
                        final ny = span < 1e-9
                            ? 0.0
                            : ((sample.db - s.minDb) / span).clamp(0.0, 1.0);
                        return CrosshairOverlay(
                          point: CrosshairPoint(nx: crosshair!.nx, ny: ny),
                          readout: CrosshairReadout(
                            freqHz: sample.freqHz,
                            db: sample.db,
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _SpectrumPainter extends CustomPainter {
  _SpectrumPainter({
    required this.db,
    required this.freqs,
    required this.minDb,
    required this.maxDb,
    required this.lineColor,
    required this.fillColor,
    required this.gridColor,
    required this.bgColor,
  });

  final Float32List db;
  final Float32List freqs;
  final double minDb;
  final double maxDb;
  final Color lineColor;
  final Color fillColor;
  final Color gridColor;
  final Color bgColor;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = bgColor);

    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (var i = 0; i <= 4; i++) {
      final y = size.height * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
    for (var i = 0; i <= 4; i++) {
      final x = size.width * i / 4;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }

    if (db.isEmpty) return;

    final span = math.max(1e-9, maxDb - minDb);
    final path = Path();
    final fill = Path();
    for (var i = 0; i < db.length; i++) {
      final x = db.length == 1 ? 0.0 : i / (db.length - 1) * size.width;
      final t = ((db[i] - minDb) / span).clamp(0.0, 1.0);
      final y = size.height - t * size.height;
      if (i == 0) {
        path.moveTo(x, y);
        fill.moveTo(x, size.height);
        fill.lineTo(x, y);
      } else {
        path.lineTo(x, y);
        fill.lineTo(x, y);
      }
    }
    fill.lineTo(size.width, size.height);
    fill.close();

    canvas.drawPath(fill, Paint()..color = fillColor);
    canvas.drawPath(
      path,
      Paint()
        ..color = lineColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..isAntiAlias = true,
    );
  }

  @override
  bool shouldRepaint(covariant _SpectrumPainter old) {
    if (old.db.length != db.length ||
        old.minDb != minDb ||
        old.maxDb != maxDb ||
        old.lineColor != lineColor) {
      return true;
    }
    for (var i = 0; i < db.length; i++) {
      if (old.db[i] != db[i]) return true;
    }
    return false;
  }
}
