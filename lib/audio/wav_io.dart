import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

/// Minimal PCM16 mono/stereo WAV reader/writer (little-endian RIFF).
class WavData {
  const WavData({
    required this.samples,
    required this.sampleRate,
    required this.channels,
  });

  /// Mono float samples in [-1, 1]. Stereo is averaged to mono on decode.
  final Float32List samples;
  final int sampleRate;
  final int channels;
}

abstract final class WavIo {
  /// Encode mono float samples as 16-bit PCM WAV.
  static Uint8List encodeMonoPcm16({
    required Float32List samples,
    required int sampleRate,
  }) {
    final dataSize = samples.length * 2;
    final bytes = BytesBuilder(copy: false);
    final header = ByteData(44);
    void writeStr(int offset, String s) {
      final u = ascii.encode(s);
      for (var i = 0; i < u.length; i++) {
        header.setUint8(offset + i, u[i]);
      }
    }

    writeStr(0, 'RIFF');
    header.setUint32(4, 36 + dataSize, Endian.little);
    writeStr(8, 'WAVE');
    writeStr(12, 'fmt ');
    header.setUint32(16, 16, Endian.little); // PCM chunk size
    header.setUint16(20, 1, Endian.little); // PCM
    header.setUint16(22, 1, Endian.little); // mono
    header.setUint32(24, sampleRate, Endian.little);
    header.setUint32(28, sampleRate * 2, Endian.little); // byte rate
    header.setUint16(32, 2, Endian.little); // block align
    header.setUint16(34, 16, Endian.little); // bits
    writeStr(36, 'data');
    header.setUint32(40, dataSize, Endian.little);
    bytes.add(header.buffer.asUint8List());

    final pcm = ByteData(dataSize);
    for (var i = 0; i < samples.length; i++) {
      final v = (samples[i].clamp(-1.0, 1.0) * 32767.0).round();
      pcm.setInt16(i * 2, v, Endian.little);
    }
    bytes.add(pcm.buffer.asUint8List());
    return bytes.toBytes();
  }

  /// Encode raw little-endian PCM16 mono bytes as WAV.
  static Uint8List encodeMonoPcm16Bytes({
    required Uint8List pcm16le,
    required int sampleRate,
  }) {
    final evenLen = pcm16le.length & ~1;
    final data = pcm16le.sublist(0, evenLen);
    final dataSize = data.length;
    final out = ByteData(44 + dataSize);
    void writeStr(int offset, String s) {
      final u = ascii.encode(s);
      for (var i = 0; i < u.length; i++) {
        out.setUint8(offset + i, u[i]);
      }
    }

    writeStr(0, 'RIFF');
    out.setUint32(4, 36 + dataSize, Endian.little);
    writeStr(8, 'WAVE');
    writeStr(12, 'fmt ');
    out.setUint32(16, 16, Endian.little);
    out.setUint16(20, 1, Endian.little);
    out.setUint16(22, 1, Endian.little);
    out.setUint32(24, sampleRate, Endian.little);
    out.setUint32(28, sampleRate * 2, Endian.little);
    out.setUint16(32, 2, Endian.little);
    out.setUint16(34, 16, Endian.little);
    writeStr(36, 'data');
    out.setUint32(40, dataSize, Endian.little);
    final bytes = out.buffer.asUint8List();
    bytes.setRange(44, 44 + dataSize, data);
    return bytes;
  }

  /// Decode a WAV file to mono float samples.
  static WavData decode(Uint8List bytes) {
    if (bytes.length < 44) {
      throw const FormatException('WAV too short');
    }
    final data = ByteData.sublistView(bytes);
    final riff = ascii.decode(bytes.sublist(0, 4));
    final wave = ascii.decode(bytes.sublist(8, 12));
    if (riff != 'RIFF' || wave != 'WAVE') {
      throw const FormatException('Not a RIFF/WAVE file');
    }

    var offset = 12;
    int? sampleRate;
    int? channels;
    int? bitsPerSample;
    int? audioFormat;
    Uint8List? pcm;

    while (offset + 8 <= bytes.length) {
      final chunkId = ascii.decode(bytes.sublist(offset, offset + 4));
      final chunkSize = data.getUint32(offset + 4, Endian.little);
      final chunkDataStart = offset + 8;
      final chunkDataEnd = math.min(chunkDataStart + chunkSize, bytes.length);

      if (chunkId == 'fmt ' && chunkSize >= 16) {
        audioFormat = data.getUint16(chunkDataStart, Endian.little);
        channels = data.getUint16(chunkDataStart + 2, Endian.little);
        sampleRate = data.getUint32(chunkDataStart + 4, Endian.little);
        bitsPerSample = data.getUint16(chunkDataStart + 14, Endian.little);
      } else if (chunkId == 'data') {
        pcm = bytes.sublist(chunkDataStart, chunkDataEnd);
      }

      offset = chunkDataEnd + (chunkSize.isOdd ? 1 : 0);
    }

    if (pcm == null ||
        sampleRate == null ||
        channels == null ||
        bitsPerSample == null ||
        audioFormat == null) {
      throw const FormatException('Incomplete WAV (missing fmt/data)');
    }
    if (audioFormat != 1) {
      throw FormatException('Only PCM WAV supported (format=$audioFormat)');
    }
    if (bitsPerSample != 16) {
      throw FormatException('Only 16-bit PCM WAV supported (bits=$bitsPerSample)');
    }
    if (channels < 1) {
      throw const FormatException('Invalid channel count');
    }

    final frameCount = pcm.length ~/ (2 * channels);
    final samples = Float32List(frameCount);
    final view = ByteData.sublistView(pcm);
    for (var f = 0; f < frameCount; f++) {
      var sum = 0.0;
      for (var c = 0; c < channels; c++) {
        sum += view.getInt16((f * channels + c) * 2, Endian.little) / 32768.0;
      }
      samples[f] = sum / channels;
    }

    return WavData(
      samples: samples,
      sampleRate: sampleRate,
      channels: channels,
    );
  }
}
