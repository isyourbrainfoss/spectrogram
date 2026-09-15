import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:spectrogram/features/plot/axis_labels.dart';
import 'package:spectrogram/services/spectrogram_engine.dart';

/// Compact start/stop, record, and utility icons under the plot.
class LiveControls extends StatelessWidget {
  const LiveControls({
    super.key,
    required this.engine,
    required this.hasCrosshair,
    required this.onClearCrosshair,
    this.onToggleRecord,
    this.onImport,
    this.onTogglePeakHold,
    this.onResetPeakHold,
  });

  final SpectrogramEngine engine;
  final bool hasCrosshair;
  final VoidCallback onClearCrosshair;
  final VoidCallback? onToggleRecord;
  final VoidCallback? onImport;
  final VoidCallback? onTogglePeakHold;
  final VoidCallback? onResetPeakHold;

  static bool get _desktop {
    switch (defaultTargetPlatform) {
      case TargetPlatform.linux:
      case TargetPlatform.windows:
      case TargetPlatform.macOS:
        return true;
      default:
        return false;
    }
  }

  static String _tip(String label, String? key) {
    if (!_desktop || key == null) return label;
    return '$label ($key)';
  }

  @override
  Widget build(BuildContext context) {
    final running = engine.isRunning;
    final hasData = engine.filledColumns > 0;
    final recording = engine.isRecordingToFile;
    final scheme = Theme.of(context).colorScheme;
    final phone = MediaQuery.sizeOf(context).shortestSide < 600;
    final tap = phone ? const Size(48, 48) : const Size(40, 40);

    Widget iconBtn({
      required String tooltip,
      required VoidCallback? onPressed,
      required IconData icon,
      Color? color,
      bool selected = false,
    }) {
      return IconButton.filledTonal(
        tooltip: tooltip,
        isSelected: selected,
        visualDensity: VisualDensity.compact,
        style: IconButton.styleFrom(
          minimumSize: tap,
          tapTargetSize: phone
              ? MaterialTapTargetSize.padded
              : MaterialTapTargetSize.shrinkWrap,
          foregroundColor: color,
        ),
        onPressed: onPressed,
        icon: Icon(icon, size: 22),
      );
    }

    final start = FilledButton.icon(
      onPressed: () {
        if (running) {
          engine.stop();
        } else {
          engine.start();
        }
      },
      style: FilledButton.styleFrom(
        visualDensity: phone
            ? VisualDensity.standard
            : const VisualDensity(vertical: -2),
        padding: EdgeInsets.symmetric(vertical: phone ? 12 : 10),
        minimumSize: Size(0, phone ? 48 : 40),
        tapTargetSize: phone
            ? MaterialTapTargetSize.padded
            : MaterialTapTargetSize.shrinkWrap,
      ),
      icon: Icon(running ? Icons.stop_rounded : Icons.mic_rounded, size: 22),
      label: Text(running ? 'Stop' : 'Start'),
    );

    final icons = <Widget>[
      iconBtn(
        tooltip: recording
            ? _tip('Stop recording & save WAV', 'R')
            : _tip('Record WAV while live', 'R'),
        onPressed: onToggleRecord,
        icon: recording
            ? Icons.stop_circle_outlined
            : Icons.fiber_manual_record,
        color: recording ? scheme.error : null,
      ),
      iconBtn(
        tooltip: _tip('Import WAV', null),
        onPressed: onImport,
        icon: Icons.folder_open_rounded,
      ),
      iconBtn(
        tooltip: engine.isFrozen
            ? _tip('Unfreeze spectrogram', 'F')
            : _tip('Freeze spectrogram', 'F'),
        onPressed: hasData || engine.isFrozen ? engine.toggleFreeze : null,
        icon: Icons.pause_rounded,
        selected: engine.isFrozen,
      ),
      GestureDetector(
        onLongPress: onResetPeakHold,
        child: iconBtn(
          tooltip: engine.settings.peakHold
              ? _tip('Peak hold on — long-press to reset', 'H')
              : _tip('Peak hold off', 'H'),
          onPressed: onTogglePeakHold,
          icon: Icons.stacked_line_chart,
          selected: engine.settings.peakHold,
        ),
      ),
      iconBtn(
        tooltip: _tip('Clear history', null),
        onPressed: hasData ? engine.clearHistory : null,
        icon: Icons.layers_clear_rounded,
      ),
      iconBtn(
        tooltip: _tip('Clear crosshair', 'Esc'),
        onPressed: hasCrosshair ? onClearCrosshair : null,
        icon: Icons.gps_off_rounded,
      ),
    ];

    return Padding(
      padding: EdgeInsets.fromLTRB(8, 4, 8, phone ? 10 : 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if ((engine.peakFreqHz != null && hasData) ||
              engine.sourceLabel != null ||
              recording ||
              engine.isFrozen)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Wrap(
                spacing: 6,
                runSpacing: 4,
                alignment: WrapAlignment.center,
                children: [
                  if (engine.sourceLabel != null)
                    _Chip(
                      icon: Icons.audio_file_outlined,
                      label: engine.sourceLabel!,
                      color: scheme.primary,
                    ),
                  if (engine.isFrozen)
                    _Chip(
                      icon: Icons.pause_rounded,
                      label: 'HOLD',
                      color: scheme.tertiary,
                    ),
                  if (recording)
                    _Chip(
                      icon: Icons.fiber_manual_record,
                      label:
                          'REC ${engine.recordingSeconds.toStringAsFixed(1)}s',
                      color: scheme.error,
                    ),
                  if (engine.peakFreqHz != null && hasData) ...[
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
                ],
              ),
            ),
          if (phone) ...[
            SizedBox(width: double.infinity, child: start),
            const SizedBox(height: 4),
            Row(
              children: [
                for (var i = 0; i < icons.length; i++) ...[
                  if (i > 0) const SizedBox(width: 2),
                  Expanded(child: Center(child: icons[i])),
                ],
              ],
            ),
          ] else
            Row(
              children: [
                Expanded(child: start),
                const SizedBox(width: 6),
                for (var i = 0; i < icons.length; i++) ...[
                  if (i > 0) const SizedBox(width: 2),
                  icons[i],
                ],
              ],
            ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.icon, required this.label, required this.color});

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
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 160),
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurface,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
