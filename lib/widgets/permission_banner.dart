import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:spectrogram/services/spectrogram_engine.dart';

class StatusBanner extends StatelessWidget {
  const StatusBanner({super.key, required this.engine, required this.onRetry});

  final SpectrogramEngine engine;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final status = engine.status;
    if (status == EngineStatus.running || status == EngineStatus.idle) {
      return const SizedBox.shrink();
    }

    final scheme = Theme.of(context).colorScheme;
    String title;
    String body;
    Color bg;
    IconData icon;

    switch (status) {
      case EngineStatus.noPermission:
        title = 'Microphone permission needed';
        body = defaultTargetPlatform == TargetPlatform.linux
            ? 'Grant mic access if prompted, and ensure PulseAudio/PipeWire is running.'
            : 'Allow microphone access to capture audio for the spectrogram.';
        bg = scheme.errorContainer;
        icon = Icons.mic_off_rounded;
      case EngineStatus.error:
        title = 'Capture error';
        body = engine.errorMessage ?? 'Unknown error';
        if (defaultTargetPlatform == TargetPlatform.linux) {
          body =
              '$body\nLinux needs: parecord, pactl, ffmpeg (package pulseaudio-utils).';
        }
        bg = scheme.errorContainer;
        icon = Icons.error_outline_rounded;
      case EngineStatus.starting:
        title = 'Starting microphone…';
        body = 'Requesting audio stream.';
        bg = scheme.surfaceContainerHighest;
        icon = Icons.hourglass_top_rounded;
      default:
        return const SizedBox.shrink();
    }

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Icon(icon, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(body, style: const TextStyle(fontSize: 12)),
                ],
              ),
            ),
            if (status == EngineStatus.noPermission ||
                status == EngineStatus.error)
              TextButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
