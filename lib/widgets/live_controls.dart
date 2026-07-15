import 'package:flutter/material.dart';
import 'package:spectrogram/features/plot/axis_labels.dart';
import 'package:spectrogram/services/spectrogram_engine.dart';

/// Compact start/stop, freeze, clear-crosshair controls + peak chips.
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
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (engine.peakFreqHz != null && running)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Wrap(
                spacing: 8,
                runSpacing: 6,
                alignment: WrapAlignment.center,
                children: [
                  _Chip(
                    icon: Icons.graphic_eq,
                    label: 'Peak ${formatFrequency(engine.peakFreqHz!)}',
                    color: scheme.tertiary,
                  ),
                  _Chip(
                    icon: Icons.straighten,
                    label: formatDb(engine.peakDb ?? engine.settings.minDb),
                    color: scheme.secondary,
                  ),
                  if (engine.frozen)
                    _Chip(
                      icon: Icons.pause_circle_filled,
                      label: 'Frozen',
                      color: scheme.outline,
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
                  icon: Icon(running ? Icons.stop_rounded : Icons.mic_rounded),
                  label: Text(running ? 'Stop' : 'Start'),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                tooltip: engine.frozen ? 'Unfreeze' : 'Freeze',
                onPressed: running || engine.filledColumns > 0
                    ? engine.toggleFreeze
                    : null,
                icon: Icon(
                  engine.frozen ? Icons.play_arrow_rounded : Icons.pause_rounded,
                ),
              ),
              const SizedBox(width: 4),
              IconButton.filledTonal(
                tooltip: 'Clear history',
                onPressed: engine.filledColumns > 0 ? engine.clearHistory : null,
                icon: const Icon(Icons.layers_clear_rounded),
              ),
              const SizedBox(width: 4),
              IconButton.filledTonal(
                tooltip: 'Clear crosshair',
                onPressed: hasCrosshair ? onClearCrosshair : null,
                icon: const Icon(Icons.gps_off_rounded),
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
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
