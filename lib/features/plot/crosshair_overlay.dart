import 'package:flutter/material.dart';
import 'package:spectrogram/features/plot/axis_labels.dart';

/// Crosshair position in normalized plot coordinates (0–1).
class CrosshairPoint {
  const CrosshairPoint({required this.nx, required this.ny});

  /// 0 = left / oldest, 1 = right / newest (or min→max freq in spectrum).
  final double nx;

  /// 0 = bottom, 1 = top of plot.
  final double ny;

  CrosshairPoint clamp01() => CrosshairPoint(
        nx: nx.clamp(0.0, 1.0),
        ny: ny.clamp(0.0, 1.0),
      );
}

class CrosshairReadout {
  const CrosshairReadout({
    required this.freqHz,
    required this.db,
    this.timeSec,
  });

  final double freqHz;
  final double db;

  /// Time relative to the right edge (“now”), negative = past. Spectrogram only.
  final double? timeSec;

  String get label {
    final parts = <String>[
      if (timeSec != null) formatTimeOffset(timeSec!),
      formatFrequency(freqHz),
      formatDb(db),
    ];
    return parts.join(' · ');
  }
}

/// Format seconds relative to “now” (e.g. −1.25 s, −80 ms, now).
String formatTimeOffset(double sec) {
  if (sec.isNaN || sec.isInfinite) return '—';
  if (sec.abs() < 0.0005) return 'now';
  final sign = sec < 0 ? '−' : '+';
  final a = sec.abs();
  if (a < 1.0) {
    return '$sign${(a * 1000).round()} ms';
  }
  if (a < 10) {
    return '$sign${a.toStringAsFixed(2)} s';
  }
  return '$sign${a.toStringAsFixed(1)} s';
}

/// Draws crosshair lines + floating readout chip over a plot.
///
/// [fingerLocal] (when set) pushes the readout away from the finger so it
/// stays visible on touch devices.
class CrosshairOverlay extends StatelessWidget {
  const CrosshairOverlay({
    super.key,
    required this.point,
    required this.readout,
    this.fingerLocal,
    this.showHorizontal = true,
    this.showVertical = true,
  });

  final CrosshairPoint point;
  final CrosshairReadout readout;

  /// Latest finger/cursor position in plot local coords (for readout placement).
  final Offset? fingerLocal;
  final bool showHorizontal;
  final bool showVertical;

  static const _chipW = 200.0;
  static const _chipH = 28.0;
  /// Keep readout well clear of the crosshair / fingertip.
  static const _clearance = 56.0;

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
        final chipPos = _readoutPosition(
          crossX: x,
          crossY: y,
          plotW: w,
          plotH: h,
          finger: fingerLocal,
        );

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
              left: chipPos.dx,
              top: chipPos.dy,
              child: Material(
                color: scheme.surface.withValues(alpha: 0.94),
                elevation: 3,
                shadowColor: Colors.black54,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  child: Text(
                    readout.label,
                    key: const Key('chart_crosshair_readout'),
                    style: TextStyle(
                      color: scheme.onSurface,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
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

  /// Place chip away from crosshair and finger; clamp inside plot.
  static Offset _readoutPosition({
    required double crossX,
    required double crossY,
    required double plotW,
    required double plotH,
    Offset? finger,
  }) {
    // Prefer above the crosshair; if finger is above it, put chip below.
    final fingerAbove =
        finger != null && finger.dy < crossY - 8;
    var left = crossX - _chipW / 2;
    var top = fingerAbove ? crossY + _clearance : crossY - _clearance - _chipH;

    // Keep clear of finger horizontally if they overlap a lot.
    if (finger != null && (finger.dx - crossX).abs() < _chipW * 0.6) {
      left = finger.dx < plotW / 2 ? crossX + 20 : crossX - _chipW - 20;
    }

    if (left + _chipW > plotW - 4) left = plotW - _chipW - 4;
    if (left < 4) left = 4;
    if (top + _chipH > plotH - 4) top = plotH - _chipH - 4;
    if (top < 4) top = 4;

    return Offset(left, top);
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
    canvas.drawCircle(Offset(x, y), 4, Paint()..color = color);
    // Outer ring so the target stays visible under a fingertip halo.
    canvas.drawCircle(
      Offset(x, y),
      10,
      Paint()
        ..color = color.withValues(alpha: 0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(covariant _CrosshairPainter old) =>
      old.x != x ||
      old.y != y ||
      old.color != color ||
      old.showHorizontal != showHorizontal ||
      old.showVertical != showVertical;
}
