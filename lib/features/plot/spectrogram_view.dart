import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:spectrogram/dsp/freq_axis.dart';
import 'package:spectrogram/features/plot/axis_labels.dart';
import 'package:spectrogram/features/plot/crosshair_overlay.dart';
import 'package:spectrogram/models/app_settings.dart';
import 'package:spectrogram/services/spectrogram_engine.dart';

/// Live scrolling spectrogram with optional crosshair.
class SpectrogramView extends StatefulWidget {
  const SpectrogramView({
    super.key,
    required this.engine,
    this.crosshair,
    this.onCrosshairChanged,
  });

  final SpectrogramEngine engine;
  final CrosshairPoint? crosshair;
  final ValueChanged<CrosshairPoint?>? onCrosshairChanged;

  @override
  State<SpectrogramView> createState() => _SpectrogramViewState();
}

class _SpectrogramViewState extends State<SpectrogramView> {
  ui.Image? _image;
  int _lastFilled = -1;
  int _lastWrite = -1;
  FreqScale? _lastScale;
  int _gen = 0;

  /// Fixed image height for log remapping (smooth on all scales).
  static const _imageHeight = 256;

  @override
  void initState() {
    super.initState();
    widget.engine.addListener(_onEngine);
  }

  @override
  void didUpdateWidget(covariant SpectrogramView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.engine != widget.engine) {
      oldWidget.engine.removeListener(_onEngine);
      widget.engine.addListener(_onEngine);
      _image?.dispose();
      _image = null;
      _lastFilled = -1;
    }
  }

  @override
  void dispose() {
    widget.engine.removeListener(_onEngine);
    _image?.dispose();
    super.dispose();
  }

  void _onEngine() {
    final e = widget.engine;
    final scale = e.settings.freqScale;
    if (e.filledColumns == _lastFilled &&
        e.writeIndex == _lastWrite &&
        scale == _lastScale) {
      return;
    }
    _lastFilled = e.filledColumns;
    _lastWrite = e.writeIndex;
    _lastScale = scale;
    unawaited(_rebuildImage());
  }

  Future<void> _rebuildImage() async {
    final e = widget.engine;
    final w = e.filledColumns;
    final bins = e.displayBins;
    if (w == 0 || bins == 0) {
      if (mounted) setState(() {});
      return;
    }

    final s = e.settings;
    final h = _imageHeight;
    final freqs = e.displayFreqs;
    final pixels = Uint8List(w * h * 4);

    // Precompute bin index per image row (0 = top = max freq).
    final rowBin = Int32List(h);
    for (var row = 0; row < h; row++) {
      final normFromBottom = h == 1 ? 0.0 : (h - 1 - row) / (h - 1);
      final hz = FreqAxis.normToFreq(
        normFromBottom,
        s.minFreqHz,
        s.maxFreqHz,
        s.freqScale,
      );
      rowBin[row] = FreqAxis.binForFreq(freqs, hz);
    }

    for (var x = 0; x < w; x++) {
      final col = e.colorColumnAt(x);
      for (var row = 0; row < h; row++) {
        final argb = col[rowBin[row]];
        final offset = (row * w + x) * 4;
        pixels[offset] = (argb >> 16) & 0xFF;
        pixels[offset + 1] = (argb >> 8) & 0xFF;
        pixels[offset + 2] = argb & 0xFF;
        pixels[offset + 3] = 0xFF;
      }
    }

    final myGen = ++_gen;
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      pixels,
      w,
      h,
      ui.PixelFormat.rgba8888,
      completer.complete,
    );
    final image = await completer.future;
    if (!mounted || myGen != _gen) {
      image.dispose();
      return;
    }
    setState(() {
      _image?.dispose();
      _image = image;
    });
  }

  void _handleLocal(Offset local, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    final nx = (local.dx / size.width).clamp(0.0, 1.0);
    final ny = (1.0 - local.dy / size.height).clamp(0.0, 1.0);
    widget.onCrosshairChanged?.call(CrosshairPoint(nx: nx, ny: ny));
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.engine;
    final s = e.settings;
    final yTicks = frequencyAxisTicks(
      minHz: s.minFreqHz,
      maxHz: s.maxFreqHz,
      scale: s.freqScale,
      maxTicks: 8,
    );

    return PlotChrome(
      yTicks: yTicks,
      yAxisTitle: s.freqScale == FreqScale.logarithmic ? 'Hz (log)' : 'Hz',
      xMinLabel: '−${s.timeWindowSec.toStringAsFixed(0)}s',
      xMidLabel: 'time',
      xMaxLabel: 'now',
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
                if (widget.crosshair != null) {
                  _handleLocal(ev.localPosition, size);
                }
              },
              child: Stack(
                fit: StackFit.expand,
                children: [
                  RepaintBoundary(
                    child: CustomPaint(
                      painter: _SpectrogramPainter(
                        image: _image,
                        emptyColor: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest,
                      ),
                      size: size,
                    ),
                  ),
                  if (widget.crosshair != null)
                    Builder(
                      builder: (context) {
                        final sample = e.sampleSpectrogram(
                          normX: widget.crosshair!.nx,
                          normY: widget.crosshair!.ny,
                        );
                        if (sample == null) return const SizedBox.shrink();
                        return CrosshairOverlay(
                          point: widget.crosshair!,
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

class _SpectrogramPainter extends CustomPainter {
  _SpectrogramPainter({required this.image, required this.emptyColor});

  final ui.Image? image;
  final Color emptyColor;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = emptyColor);
    final img = image;
    if (img == null) return;
    paintImage(
      canvas: canvas,
      rect: Offset.zero & size,
      image: img,
      fit: BoxFit.fill,
      filterQuality: FilterQuality.low,
    );
  }

  @override
  bool shouldRepaint(covariant _SpectrogramPainter old) =>
      old.image != image || old.emptyColor != emptyColor;
}
