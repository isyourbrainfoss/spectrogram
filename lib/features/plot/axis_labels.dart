import 'package:flutter/material.dart';

/// Format frequency for axis / readout.
String formatFrequency(double hz) {
  if (hz >= 1000) {
    final k = hz / 1000;
    return k >= 10 ? '${k.toStringAsFixed(0)} kHz' : '${k.toStringAsFixed(1)} kHz';
  }
  if (hz >= 100) return '${hz.toStringAsFixed(0)} Hz';
  if (hz >= 10) return '${hz.toStringAsFixed(1)} Hz';
  return '${hz.toStringAsFixed(2)} Hz';
}

String formatDb(double db) {
  if (db.isNaN || db.isInfinite) return '— dBFS';
  final sign = db > 0 ? '+' : '';
  return '$sign${db.toStringAsFixed(1)} dBFS';
}

/// Left frequency axis + bottom time/freq axis chrome around a plot child.
class PlotChrome extends StatelessWidget {
  const PlotChrome({
    super.key,
    required this.child,
    required this.yMinLabel,
    required this.yMaxLabel,
    required this.yMidLabel,
    required this.xMinLabel,
    required this.xMaxLabel,
    this.xMidLabel,
    this.yAxisWidth = 52,
    this.xAxisHeight = 22,
  });

  final Widget child;
  final String yMinLabel;
  final String yMaxLabel;
  final String yMidLabel;
  final String xMinLabel;
  final String xMaxLabel;
  final String? xMidLabel;
  final double yAxisWidth;
  final double xAxisHeight;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelSmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65),
          fontFeatures: const [FontFeature.tabularFigures()],
          fontSize: 10,
        );

    return Column(
      children: [
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: yAxisWidth,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(right: 6, top: 2),
                      child: Text(yMaxLabel, style: style),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: Text(yMidLabel, style: style),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(right: 6, bottom: 2),
                      child: Text(yMinLabel, style: style),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.35),
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
            child: Row(
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
