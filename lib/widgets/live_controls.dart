import 'package:flutter/material.dart';
import 'package:spectrogram/features/plot/axis_labels.dart';
import 'package:spectrogram/services/spectrogram_engine.dart';

/// Compact start/stop + utility icons under the plot.
///
/// Stopping capture leaves the last spectrogram so crosshair still works.
class LiveControls extends StatelessWidget {
  const LiveControls({
    super.key,
    required this.engine,
    required this.hasCrosshair,
    required this.onClearCrosshair,
  });

  final SpectrogramEngine engine;
  final bool hasCrosshair;
  final VoidCallback onClearCrosshair;

  @override
  Widget build(BuildContext context) {
    final running = engine.isRunning;
    final hasData = engine.filledColumns > 0;
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (engine.peakFreqHz != null && hasData)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Wrap(
                spacing: 6,
                runSpacing: 4,
                alignment: WrapAlignment.center,
                children: [
                  _Chip(
                    icon: Icons.graphic_eq,
                    label: formatFrequency(engine.peakFreqHz!),
                    color: scheme.tertiary,
                  ),
                  _Chip(
                    icon: Icons.straighten,
                    label: formatDb(engine.peakDb ?? engine.settings.minDb),
                    color: scheme.secondary,
                  ),
                ],
              ),
            ),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () {
                    if (running) {
                      engine.stop();
                    } else {
                      engine.start();
                    }
                  },
                  style: FilledButton.styleFrom(
                    visualDensity: const VisualDensity(vertical: -2),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    minimumSize: const Size(0, 40),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  icon: Icon(
                    running ? Icons.stop_rounded : Icons.mic_rounded,
                    size: 20,
                  ),
                  label: Text(running ? 'Stop' : 'Start'),
                ),
              ),
              const SizedBox(width: 6),
              IconButton.filledTonal(
                tooltip: 'Clear history',
                visualDensity: VisualDensity.compact,
                style: IconButton.styleFrom(
                  minimumSize: const Size(40, 40),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: hasData ? engine.clearHistory : null,
                icon: const Icon(Icons.layers_clear_rounded, size: 20),
              ),
              const SizedBox(width: 2),
              IconButton.filledTonal(
                tooltip: 'Clear crosshair',
                visualDensity: VisualDensity.compact,
                style: IconButton.styleFrom(
                  minimumSize: const Size(40, 40),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: hasCrosshair ? onClearCrosshair : null,
                icon: const Icon(Icons.gps_off_rounded, size: 20),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurface,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
