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
    return k >= 10 ? '${k.toStringAsFixed(0)} kHz' : '${k.toStringAsFixed(1)} kHz';
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

List<AxisTick> dbAxisTicks({
  required double minDb,
  required double maxDb,
  int count = 5,
}) {
  final ticks = <AxisTick>[];
  for (var i = 0; i < count; i++) {
    final t = count == 1 ? 0.0 : i / (count - 1);
    final db = minDb + t * (maxDb - minDb);
    ticks.add(AxisTick(norm: t, label: '${db.round()}'));
  }
  return ticks;
}

/// Plot chrome with multi-tick Y axis (and optional multi-tick X axis).
class PlotChrome extends StatelessWidget {
  const PlotChrome({
    super.key,
    required this.child,
    required this.yTicks,
    required this.xMinLabel,
    required this.xMaxLabel,
    this.xMidLabel,
    this.xTicks,
    this.yAxisWidth = 48,
    this.xAxisHeight = 22,
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
  final double yAxisWidth;
  final double xAxisHeight;
  final String? yAxisTitle;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelSmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
          fontFeatures: const [FontFeature.tabularFigures()],
          fontSize: 10,
        );
    final titleStyle = style?.copyWith(
      fontSize: 9,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.3,
      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
    );

    return Column(
      children: [
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: yAxisWidth,
                child: Stack(
                  children: [
                    if (yAxisTitle != null)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: RotatedBox(
                          quarterTurns: 3,
                          child: Text(yAxisTitle!, style: titleStyle),
                        ),
                      ),
                    ...yTicks.map((tick) {
                      // norm 0 at bottom → Alignment y = 1, norm 1 at top → -1
                      final alignY = 1.0 - 2.0 * tick.norm.clamp(0.0, 1.0);
                      return Align(
                        alignment: Alignment(1, alignY),
                        child: Padding(
                          padding: const EdgeInsets.only(right: 5),
                          child: Text(tick.label, style: style),
                        ),
                      );
                    }),
                  ],
                ),
              ),
              Expanded(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .surface
                        .withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Theme.of(context)
                          .colorScheme
                          .outline
                          .withValues(alpha: 0.35),
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
            padding: EdgeInsets.only(left: yAxisWidth),
            child: xTicks != null && xTicks!.isNotEmpty
                ? Stack(
                    children: [
                      for (final tick in xTicks!)
                        Align(
                          alignment: Alignment(
                            -1 + 2 * tick.norm.clamp(0.0, 1.0),
                            0,
                          ),
                          child: Text(tick.label, style: style),
                        ),
                    ],
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(xMinLabel, style: style),
                      if (xMidLabel != null) Text(xMidLabel!, style: style),
                      Text(xMaxLabel, style: style),
                    ],
                  ),
          ),
        ),
      ],
    );
  }
}
