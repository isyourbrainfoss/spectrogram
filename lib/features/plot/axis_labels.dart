import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:spectrogram/dsp/freq_axis.dart';
import 'package:spectrogram/models/app_settings.dart';

/// Format frequency for axis / readout.
String formatFrequency(double hz) {
  if (hz >= 1000) {
    final k = hz / 1000;
    if ((k - k.round()).abs() < 0.05) {
      return '${k.round()} kHz';
    }
    return k >= 10
        ? '${k.toStringAsFixed(0)} kHz'
        : '${k.toStringAsFixed(1)} kHz';
  }
  if (hz >= 100) return '${hz.round()} Hz';
  if (hz >= 10) {
    return (hz - hz.round()).abs() < 0.15
        ? '${hz.round()} Hz'
        : '${hz.toStringAsFixed(1)} Hz';
  }
  return '${hz.toStringAsFixed(1)} Hz';
}

String formatDb(double db) {
  if (db.isNaN || db.isInfinite) return '— dBFS';
  final sign = db > 0 ? '+' : '';
  return '$sign${db.toStringAsFixed(1)} dBFS';
}

/// A labeled tick on an axis. [norm] is 0 at the min end, 1 at the max end.
class AxisTick {
  const AxisTick({required this.norm, required this.label});

  final double norm;
  final String label;
}

List<AxisTick> frequencyAxisTicks({
  required double minHz,
  required double maxHz,
  required FreqScale scale,
  int maxTicks = 8,
}) {
  return [
    for (final t in FreqAxis.ticks(
      minHz: minHz,
      maxHz: maxHz,
      scale: scale,
      maxTicks: maxTicks,
    ))
      AxisTick(norm: t.norm, label: formatFrequency(t.hz)),
  ];
}

/// dB ticks on "nice" steps (e.g. −80, −60, … 0), labels are numbers only;
/// the unit lives in one axis title.
List<AxisTick> dbAxisTicks({
  required double minDb,
  required double maxDb,
  int count = 5,
}) {
  final lo = math.min(minDb, maxDb);
  final hi = math.max(minDb, maxDb);
  final span = hi - lo;
  if (!(span > 0)) {
    return [AxisTick(norm: 0, label: formatDbTick(lo))];
  }
  final raw = span / math.max(1, count - 1);
  const steps = [1.0, 2.0, 2.5, 5.0, 10.0, 15.0, 20.0, 25.0, 30.0, 50.0];
  var step = steps.last;
  for (final s in steps) {
    if (s >= raw * 0.85) {
      step = s;
      break;
    }
  }
  final ticks = <AxisTick>[];
  for (var v = (lo / step).ceil() * step; v <= hi + 1e-9; v += step) {
    ticks.add(AxisTick(norm: (v - lo) / span, label: formatDbTick(v)));
  }
  return ticks;
}

/// Tick label for dB values, with a typographic minus.
String formatDbTick(double db) {
  final r = (db * 10).round() / 10;
  final text = r == r.roundToDouble()
      ? r.abs().toStringAsFixed(0)
      : r.abs().toStringAsFixed(1);
  if (r < 0) return '\u2212$text';
  return text;
}

/// One label placed along an axis: [start] is the top (Y) or left (X) edge.
class PlacedAxisLabel {
  const PlacedAxisLabel({
    required this.index,
    required this.start,
    required this.extent,
  });

  final int index;
  final double start;
  final double extent;
  double get end => start + extent;
}

/// Places labels centred on [centers] (pixels along an axis of [length]),
/// clamped so none spill past either end. Labels that would collide with an
/// already placed one (closer than [gap]) are dropped; the first and last
/// ticks win, then the rest in order.
List<PlacedAxisLabel> placeAxisLabels({
  required List<double> centers,
  required List<double> extents,
  required double length,
  double gap = 4,
}) {
  assert(centers.length == extents.length);
  final n = centers.length;
  if (n == 0 || length <= 0) return const [];
  final order = <int>[0, if (n > 1) n - 1, for (var i = 1; i < n - 1; i++) i];
  final placed = <PlacedAxisLabel>[];
  for (final i in order) {
    final ext = extents[i];
    if (ext > length) continue;
    final start = (centers[i] - ext / 2).clamp(0.0, length - ext);
    final candidate = PlacedAxisLabel(index: i, start: start, extent: ext);
    final clashes = placed.any(
      (p) => candidate.start < p.end + gap && p.start < candidate.end + gap,
    );
    if (!clashes) placed.add(candidate);
  }
  placed.sort((a, b) => a.start.compareTo(b.start));
  return placed;
}

Size _measure(String text, TextStyle? style, TextScaler scaler) {
  final tp = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
    textScaler: scaler,
    maxLines: 1,
  )..layout();
  final size = tp.size;
  tp.dispose();
  return size;
}

/// Plot chrome: a measured Y gutter (title column + tick labels + tick marks)
/// and an X label row. Labels never wrap, never leave the plot's vertical
/// extent, and never overlap each other or the title.
class PlotChrome extends StatelessWidget {
  const PlotChrome({
    super.key,
    required this.child,
    required this.yTicks,
    required this.xMinLabel,
    required this.xMaxLabel,
    this.xMidLabel,
    this.xTicks,
    this.xAxisHeight = 20,
    this.yAxisTitle,
  });

  final Widget child;

  /// Y ticks: [norm] 0 = bottom, 1 = top.
  final List<AxisTick> yTicks;
  final String xMinLabel;
  final String xMaxLabel;
  final String? xMidLabel;

  /// Optional X ticks: [norm] 0 = left, 1 = right. When set, replaces simple min/mid/max.
  final List<AxisTick>? xTicks;
  final double xAxisHeight;

  /// Unit/title drawn rotated in its own column left of the tick labels.
  final String? yAxisTitle;

  static const double tickMarkLength = 4;
  static const double labelGap = 4;
  static const double titleGap = 4;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final scaler = MediaQuery.textScalerOf(context);
    final style = theme.textTheme.labelSmall?.copyWith(
      color: scheme.onSurfaceVariant,
      fontFeatures: const [FontFeature.tabularFigures()],
      fontSize: 10,
      height: 1.2,
      fontWeight: FontWeight.w500,
      letterSpacing: 0.1,
    );
    final titleStyle = style?.copyWith(
      fontSize: 10,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.6,
      color: scheme.onSurfaceVariant.withValues(alpha: 0.8),
    );
    final tickColor = scheme.outline.withValues(alpha: 0.55);

    final ySizes = [for (final t in yTicks) _measure(t.label, style, scaler)];
    final labelWidth = ySizes.fold<double>(0, (m, s) => math.max(m, s.width));
    final titleSize = yAxisTitle == null
        ? Size.zero
        : _measure(yAxisTitle!, titleStyle, scaler);
    final titleColumn = yAxisTitle == null ? 0.0 : titleSize.height + titleGap;
    final yAxisWidth =
        (titleColumn + labelWidth.ceilToDouble() + labelGap + tickMarkLength)
            .ceilToDouble();

    return Column(
      children: [
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                key: const ValueKey('plot-y-axis'),
                width: yAxisWidth,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final h = constraints.maxHeight;
                    final placed = placeAxisLabels(
                      centers: [
                        for (final t in yTicks)
                          (1 - t.norm.clamp(0.0, 1.0)) * h,
                      ],
                      extents: [for (final s in ySizes) s.height],
                      length: h,
                      gap: 2,
                    );
                    return Stack(
                      clipBehavior: Clip.none,
                      children: [
                        if (yAxisTitle != null && titleSize.width <= h)
                          Positioned(
                            left: 0,
                            top: 0,
                            bottom: 0,
                            width: titleSize.height,
                            child: Center(
                              child: RotatedBox(
                                quarterTurns: 3,
                                child: Text(
                                  yAxisTitle!,
                                  key: const ValueKey('plot-y-title'),
                                  style: titleStyle,
                                  maxLines: 1,
                                  softWrap: false,
                                ),
                              ),
                            ),
                          ),
                        Positioned.fill(
                          child: CustomPaint(
                            painter: _TickMarkPainter(
                              norms: [for (final t in yTicks) t.norm],
                              color: tickColor,
                              length: tickMarkLength,
                            ),
                          ),
                        ),
                        for (final p in placed)
                          Positioned(
                            top: p.start,
                            right: tickMarkLength + labelGap,
                            child: Text(
                              yTicks[p.index].label,
                              key: ValueKey(
                                'plot-y-tick-${yTicks[p.index].label}',
                              ),
                              style: style,
                              maxLines: 1,
                              softWrap: false,
                              textAlign: TextAlign.right,
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),
              Expanded(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: scheme.surface.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: scheme.outline.withValues(alpha: 0.35),
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(7),
                    child: child,
                  ),
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: xAxisHeight,
          child: Padding(
            padding: EdgeInsets.only(left: yAxisWidth, top: 3),
            child: xTicks != null && xTicks!.isNotEmpty
                ? LayoutBuilder(
                    builder: (context, constraints) {
                      final w = constraints.maxWidth;
                      final ticks = xTicks!;
                      final sizes = [
                        for (final t in ticks) _measure(t.label, style, scaler),
                      ];
                      final placed = placeAxisLabels(
                        centers: [
                          for (final t in ticks) t.norm.clamp(0.0, 1.0) * w,
                        ],
                        extents: [for (final s in sizes) s.width],
                        length: w,
                        gap: 8,
                      );
                      return Stack(
                        clipBehavior: Clip.none,
                        children: [
                          for (final p in placed)
                            Positioned(
                              left: p.start,
                              top: 0,
                              child: Text(
                                ticks[p.index].label,
                                key: ValueKey(
                                  'plot-x-tick-${ticks[p.index].label}',
                                ),
                                style: style,
                                maxLines: 1,
                                softWrap: false,
                              ),
                            ),
                        ],
                      );
                    },
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        xMinLabel,
                        style: style,
                        maxLines: 1,
                        softWrap: false,
                      ),
                      if (xMidLabel != null)
                        Flexible(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: Text(
                              xMidLabel!,
                              style: style?.copyWith(
                                color: scheme.onSurfaceVariant.withValues(
                                  alpha: 0.65,
                                ),
                              ),
                              maxLines: 1,
                              softWrap: false,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                      Text(
                        xMaxLabel,
                        style: style,
                        maxLines: 1,
                        softWrap: false,
                      ),
                    ],
                  ),
          ),
        ),
      ],
    );
  }
}

class _TickMarkPainter extends CustomPainter {
  _TickMarkPainter({
    required this.norms,
    required this.color,
    required this.length,
  });

  final List<double> norms;
  final Color color;
  final double length;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    for (final n in norms) {
      final y = ((1 - n.clamp(0.0, 1.0)) * size.height).clamp(
        0.5,
        size.height - 0.5,
      );
      canvas.drawLine(
        Offset(size.width - length, y),
        Offset(size.width, y),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_TickMarkPainter old) =>
      old.color != color || old.length != length || !_listEq(old.norms, norms);

  static bool _listEq(List<double> a, List<double> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
