import 'dart:async';
import 'dart:typed_data';

import 'package:record/record.dart';

/// Thin wrapper around the [record] package for mono PCM16 streaming.
class AudioCaptureService {
  AudioCaptureService({AudioRecorder? recorder})
    : _recorder = recorder ?? AudioRecorder();

  /// No platform plugin — for unit tests and offline analysis.
  AudioCaptureService.none() : _recorder = null;

  final AudioRecorder? _recorder;
  StreamSubscription<Uint8List>? _sub;

  bool get isRecording => _sub != null;

  Future<bool> hasPermission() async {
    final recorder = _recorder;
    if (recorder == null) return false;
    try {
      return await recorder.hasPermission();
    } catch (_) {
      return false;
    }
  }

  /// Enumerate capture devices (Android + Linux supported by `record`).
  Future<List<InputDevice>> listInputDevices() async {
    final recorder = _recorder;
    if (recorder == null) return const [];
    try {
      return await recorder.listInputDevices();
    } catch (_) {
      // MissingPluginException in tests / unsupported hosts.
      return const [];
    }
  }

  Future<void> start({
    required int sampleRate,
    required void Function(Uint8List pcm) onPcm,
    InputDevice? device,
    void Function(Object error)? onError,
  }) async {
    final recorder = _recorder;
    if (recorder == null) {
      throw StateError('Audio capture is not available');
    }
    await stop();

    final stream = await recorder.startStream(
      RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: sampleRate,
        numChannels: 1,
        device: device,
        // Prefer raw path without AGC for accurate levels when available.
        autoGain: false,
        echoCancel: false,
        noiseSuppress: false,
      ),
    );

    _sub = stream.listen(
      onPcm,
      onError: (Object e, StackTrace st) {
        onError?.call(e);
      },
      cancelOnError: false,
    );
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    final recorder = _recorder;
    if (recorder == null) return;
    try {
      if (await recorder.isRecording()) {
        await recorder.stop();
      }
    } catch (_) {
      // MissingPluginException in tests / host without record_linux.
    }
  }

  Future<void> dispose() async {
    await stop();
    try {
      _recorder?.dispose();
    } catch (_) {}
  }
}
