import 'dart:async';
import 'dart:typed_data';

import 'package:record/record.dart';

/// Thin wrapper around the [record] package for mono PCM16 streaming.
class AudioCaptureService {
  AudioCaptureService({AudioRecorder? recorder})
      : _recorder = recorder ?? AudioRecorder();

  final AudioRecorder _recorder;
  StreamSubscription<Uint8List>? _sub;

  bool get isRecording => _sub != null;

  Future<bool> hasPermission() => _recorder.hasPermission();

  /// Enumerate capture devices (Android + Linux supported by `record`).
  Future<List<InputDevice>> listInputDevices() async {
    try {
      final devices = await _recorder.listInputDevices();
      return devices;
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
    await stop();

    final stream = await _recorder.startStream(
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
    if (await _recorder.isRecording()) {
      await _recorder.stop();
    }
  }

  Future<void> dispose() async {
    await stop();
    _recorder.dispose();
  }
}
