import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:spectrogram/dsp/freq_axis.dart';
import 'package:spectrogram/features/plot/axis_labels.dart';
import 'package:spectrogram/features/plot/crosshair_overlay.dart';
import 'package:spectrogram/features/plot/plot_pointer.dart';
import 'package:spectrogram/models/app_settings.dart';
import 'package:spectrogram/services/spectrogram_engine.dart';

/// Live frequency vs amplitude (dBFS) spectrum plot with optional crosshair.
///
/// Listens to [engine] so it stays current when kept alive under an
/// [IndexedStack] (STFT/FFT toggle) without relying on parent rebuilds alone.
class SpectrumView extends StatefulWidget {
  const SpectrumView({
    super.key,
    required this.engine,
    this.crosshair,
    this.onCrosshairChanged,
  });

  final SpectrogramEngine engine;
  final CrosshairPoint? crosshair;
  final ValueChanged<CrosshairPoint?>? onCrosshairChanged;

  @override
  State<SpectrumView> createState() => _SpectrumViewState();
}

class _SpectrumViewState extends State<SpectrumView> {
  final _pointer = PlotPointerController();
  PointerDeviceKind _lastKind = PointerDeviceKind.touch;

  @override
  void initState() {
    super.initState();
    widget.engine.addListener(_onEngine);
  }

  @override
  void didUpdateWidget(covariant SpectrumView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.engine != widget.engine) {
      oldWidget.engine.removeListener(_onEngine);
      widget.engine.addListener(_onEngine);
    }
  }

  @override
  void dispose() {
    widget.engine.removeListener(_onEngine);
    super.dispose();
  }

  void _onEngine() {
    if (mounted) setState(() {});
  }

  /// Map free crosshair to spectrum: keep X, snap Y to the curve for display.
  CrosshairPoint _snapToCurve(CrosshairPoint free) {
    final sample = widget.engine.sampleSpectrum(free.nx);
    final s = widget.engine.settings;
    final span = (s.maxDb - s.minDb).abs();
    if (sample == null || span < 1e-9) return free.clamp01();
    final ny = ((sample.db - s.minDb) / span).clamp(0.0, 1.0);
    return CrosshairPoint(nx: free.nx.clamp(0.0, 1.0), ny: ny);
  }

  void _emit(CrosshairPoint free) {
    setState(() {});
    widget.onCrosshairChanged?.call(_snapToCurve(free));
  }

  @override
  Widget build(BuildContext context) {
    final engine = widget.engine;
    final s = engine.settings;
    final scheme = Theme.of(context).colorScheme;
    final yTicks = dbAxisTicks(minDb: s.minDb, maxDb: s.maxDb, count: 5);
    final xTicks = frequencyAxisTicks(
      minHz: s.minFreqHz,
      maxHz: s.maxFreqHz,
      scale: s.freqScale,
      maxTicks: 7,
    );

    final db = Float32List.fromList(engine.displayDb);
    final freqs = Float32List.fromList(engine.displayFreqs);

    return PlotChrome(
      yTicks: [
        for (final t in yTicks) AxisTick(norm: t.norm, label: '${t.label} dB'),
      ],
      yAxisTitle: 'dBFS',
      xMinLabel: formatFrequency(s.minFreqHz),
      xMaxLabel: formatFrequency(s.maxFreqHz),
      xTicks: xTicks,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = Size(constraints.maxWidth, constraints.maxHeight);
          if (size.width <= 0 || size.height <= 0) {
            return const SizedBox.expand();
          }
          return Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: (ev) {
              _lastKind = ev.kind;
              final p = _pointer.onPointerDown(
                ev.localPosition,
                size,
                ev.kind,
                existing: widget.crosshair,
              );
              _emit(p);
            },
            onPointerMove: (ev) {
              if (!ev.down) return;
              _lastKind = ev.kind;
              final p = _pointer.onPointerMove(
                ev.localPosition,
                size,
                ev.kind,
                current: widget.crosshair ??
                    const CrosshairPoint(nx: 0.5, ny: 0.5),
              );
              if (p != null) _emit(p);
            },
            onPointerUp: (_) => _pointer.onPointerUp(),
            onPointerCancel: (_) => _pointer.onPointerUp(),
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onLongPressStart: (details) {
                final p = _pointer.onLongPressStart(
                  details.localPosition,
                  size,
                  _lastKind,
                  existing: widget.crosshair,
                );
                _emit(p);
              },
              onLongPressMoveUpdate: (details) {
                final p = _pointer.onLongPressMove(
                  details.localPosition,
                  size,
                  current: widget.crosshair ??
                      const CrosshairPoint(nx: 0.5, ny: 0.5),
                );
                if (p != null) _emit(p);
              },
              onLongPressEnd: (_) => _pointer.onLongPressEnd(),
              child: MouseRegion(
                onHover: (ev) {
                  if (widget.crosshair == null) return;
                  final p = _pointer.localToPoint(ev.localPosition, size);
                  _pointer.fingerLocal = ev.localPosition;
                  _emit(p);
                },
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    RepaintBoundary(
                      child: CustomPaint(
                        painter: _SpectrumPainter(
                          db: db,
                          freqs: freqs,
                          minDb: s.minDb,
                          maxDb: s.maxDb,
                          minHz: s.minFreqHz,
                          maxHz: s.maxFreqHz,
                          scale: s.freqScale,
                          freqTicks: xTicks,
                          lineColor: scheme.primary,
                          fillColor: scheme.primary.withValues(alpha: 0.22),
                          gridColor: scheme.outline.withValues(alpha: 0.25),
                          bgColor: scheme.surfaceContainerHighest,
                          layoutSize: size,
                        ),
                        size: size,
                        isComplex: true,
                        willChange: engine.isRunning,
                      ),
                    ),
                    if (widget.crosshair != null)
                      Builder(
                        builder: (context) {
                          final sample =
                              engine.sampleSpectrum(widget.crosshair!.nx);
                          if (sample == null) return const SizedBox.shrink();
                          final span = (s.maxDb - s.minDb).abs();
                          final ny = span < 1e-9
                              ? 0.0
                              : ((sample.db - s.minDb) / span).clamp(0.0, 1.0);
                          final nx = FreqAxis.freqToNorm(
                            sample.freqHz,
                            s.minFreqHz,
                            s.maxFreqHz,
                            s.freqScale,
                          );
                          return CrosshairOverlay(
                            point: CrosshairPoint(nx: nx, ny: ny),
                            fingerLocal: _pointer.fingerLocal,
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
    required this.minHz,
    required this.maxHz,
    required this.scale,
    required this.freqTicks,
    required this.lineColor,
    required this.fillColor,
    required this.gridColor,
    required this.bgColor,
    required this.layoutSize,
  });

  final Float32List db;
  final Float32List freqs;
  final double minDb;
  final double maxDb;
  final double minHz;
  final double maxHz;
  final FreqScale scale;
  final List<AxisTick> freqTicks;
  final Color lineColor;
  final Color fillColor;
  final Color gridColor;
  final Color bgColor;
  final Size layoutSize;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    canvas.drawRect(Offset.zero & size, Paint()..color = bgColor);

    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (var i = 0; i <= 4; i++) {
      final y = size.height * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
    for (final tick in freqTicks) {
      final x = tick.norm * size.width;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }

    if (db.isEmpty || freqs.isEmpty) return;

    final span = math.max(1e-9, maxDb - minDb);
    final path = Path();
    final fill = Path();
    for (var i = 0; i < db.length; i++) {
      final nx = FreqAxis.freqToNorm(freqs[i], minHz, maxHz, scale);
      final x = nx * size.width;
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
        old.scale != scale ||
        old.lineColor != lineColor ||
        old.layoutSize != layoutSize) {
      return true;
    }
    for (var i = 0; i < db.length; i++) {
      if (old.db[i] != db[i]) return true;
    }
    return false;
  }
}
