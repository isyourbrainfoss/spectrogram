import 'package:flutter/material.dart';
import 'package:spectrogram/features/plot/axis_labels.dart';

/// Crosshair position in normalized plot coordinates (0–1).
class CrosshairPoint {
  const CrosshairPoint({required this.nx, required this.ny});

  /// 0 = left / oldest, 1 = right / newest (or min→max freq in spectrum).
  final double nx;

  /// 0 = bottom, 1 = top of plot.
  final double ny;
}

class CrosshairReadout {
  const CrosshairReadout({required this.freqHz, required this.db});

  final double freqHz;
  final double db;

  String get label => '${formatFrequency(freqHz)} · ${formatDb(db)}';
}

/// Draws crosshair lines + floating readout chip over a plot.
class CrosshairOverlay extends StatelessWidget {
  const CrosshairOverlay({
    super.key,
    required this.point,
    required this.readout,
    this.showHorizontal = true,
    this.showVertical = true,
  });

  final CrosshairPoint point;
  final CrosshairReadout readout;
  final bool showHorizontal;
  final bool showVertical;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;
        final x = point.nx.clamp(0.0, 1.0) * w;
        final y = (1.0 - point.ny.clamp(0.0, 1.0)) * h; // ny=1 at top
        final scheme = Theme.of(context).colorScheme;
        final lineColor = scheme.onSurface.withValues(alpha: 0.75);

        return Stack(
          clipBehavior: Clip.none,
          children: [
            CustomPaint(
              size: Size(w, h),
              painter: _CrosshairPainter(
                x: x,
                y: y,
                color: lineColor,
                showHorizontal: showHorizontal,
                showVertical: showVertical,
              ),
            ),
            Positioned(
              left: (x + 10).clamp(4.0, w - 160),
              top: (y - 28).clamp(4.0, h - 32),
              child: Material(
                color: scheme.surface.withValues(alpha: 0.92),
                elevation: 2,
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Text(
                    readout.label,
                    key: const Key('chart_crosshair_readout'),
                    style: TextStyle(
                      color: scheme.onSurface,
                      fontSize: 11,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _CrosshairPainter extends CustomPainter {
  _CrosshairPainter({
    required this.x,
    required this.y,
    required this.color,
    required this.showHorizontal,
    required this.showVertical,
  });

  final double x;
  final double y;
  final Color color;
  final bool showHorizontal;
  final bool showVertical;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1
      ..isAntiAlias = false;

    if (showVertical) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    if (showHorizontal) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
    canvas.drawCircle(Offset(x, y), 3.5, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _CrosshairPainter old) =>
      old.x != x ||
      old.y != y ||
      old.color != color ||
      old.showHorizontal != showHorizontal ||
      old.showVertical != showVertical;
}
