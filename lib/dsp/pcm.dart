import 'dart:typed_data';

/// Convert little-endian signed 16-bit PCM bytes to mono float samples in [-1, 1].
///
/// If [channels] > 1, samples are averaged down to mono.
Float32List pcm16ToMonoFloat(
  Uint8List bytes, {
  int channels = 1,
}) {
  final sampleCount = bytes.length ~/ 2;
  if (sampleCount == 0) {
    return Float32List(0);
  }

  final view = ByteData.sublistView(bytes);
  if (channels <= 1) {
    final out = Float32List(sampleCount);
    for (var i = 0; i < sampleCount; i++) {
      out[i] = view.getInt16(i * 2, Endian.little) / 32768.0;
    }
    return out;
  }

  final frames = sampleCount ~/ channels;
  final out = Float32List(frames);
  for (var f = 0; f < frames; f++) {
    var sum = 0.0;
    for (var c = 0; c < channels; c++) {
      sum += view.getInt16((f * channels + c) * 2, Endian.little) / 32768.0;
    }
    out[f] = sum / channels;
  }
  return out;
}

/// Append [chunk] into a ring-like growable buffer used by the STFT hop loop.
void appendFloat32(List<double> buffer, Float32List chunk) {
  for (var i = 0; i < chunk.length; i++) {
    buffer.add(chunk[i]);
  }
}
