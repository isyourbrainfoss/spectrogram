import 'package:record/record.dart';

/// Human-readable labels for [InputDevice], including type / id when names clash
/// (e.g. Fairphone listing two mics both as "FP5").
abstract final class InputDeviceLabels {
  static String format(
    InputDevice device, {
    List<InputDevice> all = const [],
  }) {
    final base = device.label.trim().isEmpty ? 'Input' : device.label.trim();
    final parts = <String>[base];

    final typeLabel = _typeLabel(device.type);
    if (typeLabel != null) {
      parts.add(typeLabel);
    }

    // When several devices share the same product name, disambiguate.
    final sameName = all.where((d) => d.label.trim() == device.label.trim()).toList();
    if (sameName.length > 1) {
      final index = sameName.indexWhere((d) => d.id == device.id) + 1;
      if (index > 0) {
        parts.add('mic $index');
      }
      // Short stable id for exact selection.
      final shortId = _shortId(device.id);
      if (shortId.isNotEmpty) {
        parts.add('id $shortId');
      }
    } else if (device.id.isNotEmpty &&
        device.id != device.label &&
        !_looksLikeUuid(device.id)) {
      // Unique name: still show id when it adds information (Linux ALSA names).
      if (device.id.length <= 24) {
        parts.add(device.id);
      }
    }

    if (device.sampleRates.isNotEmpty) {
      final preferred = device.sampleRates.contains(48000)
          ? 48000
          : device.sampleRates.contains(44100)
              ? 44100
              : device.sampleRates.first;
      parts.add('$preferred Hz');
    }

    return parts.join(' · ');
  }

  static String? _typeLabel(InputDeviceType type) => switch (type) {
        InputDeviceType.builtIn => 'Built-in',
        InputDeviceType.wiredHeadset => 'Headset',
        InputDeviceType.lineIn => 'Line-in',
        InputDeviceType.bluetoothSco => 'Bluetooth (SCO)',
        InputDeviceType.bluetoothA2dp => 'Bluetooth (A2DP)',
        InputDeviceType.bluetoothLe => 'Bluetooth LE',
        InputDeviceType.usb => 'USB',
        InputDeviceType.hdmi => 'HDMI',
        InputDeviceType.airPlay => 'AirPlay',
        InputDeviceType.thunderbolt => 'Thunderbolt',
        InputDeviceType.displayPort => 'DisplayPort',
        InputDeviceType.unknown => null,
      };

  static String _shortId(String id) {
    final t = id.trim();
    if (t.isEmpty) return '';
    if (t.length <= 8) return t;
    // Prefer trailing digits (Android device ids are often numeric).
    final digits = RegExp(r'\d+$').firstMatch(t);
    if (digits != null) return digits.group(0)!;
    return t.substring(0, 8);
  }

  static bool _looksLikeUuid(String id) =>
      RegExp(r'^[0-9a-fA-F-]{20,}$').hasMatch(id);
}
