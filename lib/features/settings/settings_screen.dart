import 'package:flutter/material.dart';
import 'package:record/record.dart';
import 'package:spectrogram/audio/input_device_labels.dart';
import 'package:spectrogram/models/app_settings.dart';
import 'package:spectrogram/services/settings_repository.dart';
import 'package:spectrogram/services/spectrogram_engine.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.engine,
    required this.repository,
    required this.onSettingsChanged,
  });

  final SpectrogramEngine engine;
  final SettingsRepository repository;
  final ValueChanged<AppSettings> onSettingsChanged;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late AppSettings _draft;
  List<InputDevice> _devices = const [];
  bool _loadingDevices = false;
  String? _deviceError;

  @override
  void initState() {
    super.initState();
    _draft = widget.engine.settings;
    _refreshDevices();
  }

  @override
  void didUpdateWidget(covariant SettingsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.engine.settings != widget.engine.settings &&
        widget.engine.settings != _draft) {
      // External update (e.g. reset) — sync draft if still matching old.
      if (_draft == oldWidget.engine.settings) {
        _draft = widget.engine.settings;
      }
    }
  }

  Future<void> _refreshDevices() async {
    if (!mounted) return;
    setState(() {
      _loadingDevices = true;
      _deviceError = null;
    });
    try {
      // Permission helps Android populate the device list.
      // Errors (e.g. missing plugin in tests) fall through to empty list.
      try {
        await widget.engine.hasPermissionForDevices();
      } catch (_) {}
      final devices = await widget.engine.listInputDevices();
      if (!mounted) return;
      setState(() {
        _devices = devices;
        _loadingDevices = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _devices = const [];
        _deviceError = e.toString();
        _loadingDevices = false;
      });
    }
  }

  Future<void> _apply(AppSettings next) async {
    setState(() => _draft = next);
    await widget.repository.save(next);
    await widget.engine.applySettings(next);
    widget.onSettingsChanged(next);
  }

  Future<void> _reset() async {
    await widget.repository.resetToDefaults();
    await _apply(AppSettings.defaults);
  }

  Future<void> _selectDevice(String? id) async {
    if (id == null) {
      await _apply(_draft.copyWith(clearInputDevice: true));
      return;
    }
    InputDevice? match;
    for (final d in _devices) {
      if (d.id == id) {
        match = d;
        break;
      }
    }
    final label = match == null
        ? id
        : InputDeviceLabels.format(match, all: _devices);
    await _apply(
      _draft.copyWith(
        inputDeviceId: id,
        inputDeviceLabel: label,
      ),
    );
  }

  String _selectedDeviceSubtitle(AppSettings s) {
    if (s.inputDeviceId == null) return 'System default';
    for (final d in _devices) {
      if (d.id == s.inputDeviceId) {
        return InputDeviceLabels.format(d, all: _devices);
      }
    }
    return s.inputDeviceLabel ?? s.inputDeviceId ?? 'System default';
  }

  @override
  Widget build(BuildContext context) {
    final s = _draft;
    final deviceValue = _deviceDropdownValue(s);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        actions: [
          TextButton(onPressed: _reset, child: const Text('Reset')),
        ],
      ),
      body: ListView(
        children: [
          const _SectionHeader('Appearance'),
          ListTile(
            title: const Text('Color scheme'),
            trailing: DropdownButton<ThemePreference>(
              value: s.colorScheme,
              onChanged: (v) {
                if (v != null) _apply(s.copyWith(colorScheme: v));
              },
              items: const [
                DropdownMenuItem(
                  value: ThemePreference.system,
                  child: Text('System'),
                ),
                DropdownMenuItem(
                  value: ThemePreference.light,
                  child: Text('Light'),
                ),
                DropdownMenuItem(
                  value: ThemePreference.dark,
                  child: Text('Dark'),
                ),
              ],
            ),
          ),
          ListTile(
            title: const Text('Colormap'),
            trailing: DropdownButton<ColormapKind>(
              value: s.colormap,
              onChanged: (v) {
                if (v != null) _apply(s.copyWith(colormap: v));
              },
              items: ColormapKind.values
                  .map(
                    (c) => DropdownMenuItem(
                      value: c,
                      child: Text(_colormapLabel(c)),
                    ),
                  )
                  .toList(),
            ),
          ),
          ListTile(
            title: const Text('Frequency scale'),
            subtitle: Text(
              s.freqScale == FreqScale.logarithmic
                  ? 'Logarithmic — more space for low frequencies (typical for audio)'
                  : 'Linear — equal Hz spacing',
            ),
            trailing: DropdownButton<FreqScale>(
              value: s.freqScale,
              onChanged: (v) {
                if (v != null) _apply(s.copyWith(freqScale: v));
              },
              items: const [
                DropdownMenuItem(
                  value: FreqScale.logarithmic,
                  child: Text('Log'),
                ),
                DropdownMenuItem(
                  value: FreqScale.linear,
                  child: Text('Linear'),
                ),
              ],
            ),
          ),
          const _SectionHeader('Input'),
          ListTile(
            title: const Text('Microphone'),
            subtitle: Text(
              _loadingDevices
                  ? 'Scanning devices…'
                  : _deviceError != null
                      ? 'Could not list devices — $_deviceError'
                      : _selectedDeviceSubtitle(s),
            ),
            isThreeLine: true,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'Refresh device list',
                  onPressed: _loadingDevices ? null : _refreshDevices,
                  // Avoid animated indicators so widget tests can pumpAndSettle.
                  icon: Icon(
                    _loadingDevices ? Icons.hourglass_top : Icons.refresh,
                  ),
                ),
                DropdownButton<String?>(
                  value: deviceValue,
                  hint: const Text('Default'),
                  onChanged: _loadingDevices
                      ? null
                      : (v) {
                          _selectDevice(v);
                        },
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('System default'),
                    ),
                    ..._devices.map(
                      (d) => DropdownMenuItem<String?>(
                        value: d.id,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 260),
                          child: Text(
                            InputDeviceLabels.format(d, all: _devices),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ),
                    // Keep a saved device visible even if not currently listed.
                    if (s.inputDeviceId != null &&
                        !_devices.any((d) => d.id == s.inputDeviceId))
                      DropdownMenuItem<String?>(
                        value: s.inputDeviceId,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 260),
                          child: Text(
                            '${s.inputDeviceLabel ?? s.inputDeviceId} (unavailable)',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              'Labels include type and id when several mics share a product name '
              '(e.g. two built-in mics both called FP5). Changing the mic restarts '
              'capture if it is running.',
              style: TextStyle(fontSize: 12),
            ),
          ),
          const _SectionHeader('Audio & FFT'),
          ListTile(
            title: const Text('Sample rate'),
            subtitle: const Text('Requires restart of capture'),
            trailing: DropdownButton<int>(
              value: AppSettings.allowedSampleRates.contains(s.sampleRate)
                  ? s.sampleRate
                  : 48000,
              onChanged: (v) {
                if (v != null) _apply(s.copyWith(sampleRate: v));
              },
              items: AppSettings.allowedSampleRates
                  .map(
                    (r) => DropdownMenuItem(
                      value: r,
                      child: Text('$r Hz'),
                    ),
                  )
                  .toList(),
            ),
          ),
          ListTile(
            title: const Text('FFT size'),
            subtitle: Text('${s.fftSize} · finer freq resolution when larger'),
            trailing: DropdownButton<int>(
              value: AppSettings.allowedFftSizes.contains(s.fftSize)
                  ? s.fftSize
                  : 2048,
              onChanged: (v) {
                if (v != null) {
                  // Keep hop at 1/4 FFT by default when FFT changes.
                  final hop = (v / 4).round();
                  _apply(s.copyWith(fftSize: v, hopSize: hop));
                }
              },
              items: AppSettings.allowedFftSizes
                  .map(
                    (n) => DropdownMenuItem(value: n, child: Text('$n')),
                  )
                  .toList(),
            ),
          ),
          ListTile(
            title: const Text('Hop size'),
            subtitle: Text('${s.hopSize} samples · smaller = smoother time'),
            trailing: DropdownButton<int>(
              value: _validHop(s),
              onChanged: (v) {
                if (v != null) _apply(s.copyWith(hopSize: v));
              },
              items: _hopOptions(s.fftSize)
                  .map(
                    (h) => DropdownMenuItem(value: h, child: Text('$h')),
                  )
                  .toList(),
            ),
          ),
          const _SectionHeader('Display range'),
          _SliderTile(
            title: 'Visible time window',
            valueLabel: '${s.timeWindowSec.toStringAsFixed(0)} s',
            value: s.timeWindowSec,
            min: 2,
            max: 30,
            divisions: 28,
            onChanged: (v) => _apply(s.copyWith(timeWindowSec: v.roundToDouble())),
          ),
          _SliderTile(
            title: 'History kept in memory',
            valueLabel: '${s.historySec.toStringAsFixed(0)} s',
            value: s.historySec.clamp(8, 300),
            min: 8,
            max: 300,
            divisions: 292,
            onChanged: (v) {
              final hist = v.roundToDouble();
              final win = s.timeWindowSec > hist ? hist : s.timeWindowSec;
              _apply(s.copyWith(historySec: hist, timeWindowSec: win));
            },
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              'Visible window is what you see while live. History is how far you can '
              'pan after stop, and how much pre-roll is included when you hit Record.',
              style: TextStyle(fontSize: 12),
            ),
          ),
          _SliderTile(
            title: 'Min frequency',
            valueLabel: '${s.minFreqHz.round()} Hz',
            value: s.minFreqHz,
            min: 0,
            max: 2000,
            divisions: 40,
            onChanged: (v) {
              final minF = v.roundToDouble();
              final maxF = s.maxFreqHz <= minF ? minF + 100 : s.maxFreqHz;
              _apply(s.copyWith(minFreqHz: minF, maxFreqHz: maxF));
            },
          ),
          _SliderTile(
            title: 'Max frequency',
            valueLabel: '${s.maxFreqHz.round()} Hz',
            value: s.maxFreqHz.clamp(100, 24000),
            min: 1000,
            max: 24000,
            divisions: 46,
            onChanged: (v) {
              final maxF = v.roundToDouble();
              final minF = s.minFreqHz >= maxF ? maxF - 100 : s.minFreqHz;
              _apply(s.copyWith(maxFreqHz: maxF, minFreqHz: minF));
            },
          ),
          _SliderTile(
            title: 'Min level',
            valueLabel: '${s.minDb.round()} dBFS',
            value: s.minDb,
            min: -120,
            max: -20,
            divisions: 100,
            onChanged: (v) {
              final minDb = v.roundToDouble();
              final maxDb = s.maxDb <= minDb ? minDb + 10 : s.maxDb;
              _apply(s.copyWith(minDb: minDb, maxDb: maxDb));
            },
          ),
          _SliderTile(
            title: 'Max level',
            valueLabel: '${s.maxDb.round()} dBFS',
            value: s.maxDb,
            min: -40,
            max: 0,
            divisions: 40,
            onChanged: (v) {
              final maxDb = v.roundToDouble();
              final minDb = s.minDb >= maxDb ? maxDb - 10 : s.minDb;
              _apply(s.copyWith(maxDb: maxDb, minDb: minDb));
            },
          ),
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Defaults are tuned for speech and music on phone mics. '
              'Larger FFT improves frequency resolution; smaller hop improves time smoothness.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.6),
                  ),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  /// Dropdown value must be either null or one of the item values.
  String? _deviceDropdownValue(AppSettings s) {
    final id = s.inputDeviceId;
    if (id == null) return null;
    if (_devices.any((d) => d.id == id)) return id;
    // Keep selection even if device is temporarily missing.
    return id;
  }

  static String _colormapLabel(ColormapKind c) => switch (c) {
        ColormapKind.viridis => 'Viridis',
        ColormapKind.magma => 'Magma',
        ColormapKind.turbo => 'Turbo',
        ColormapKind.grayscale => 'Grayscale',
      };

  static List<int> _hopOptions(int fft) {
    final opts = <int>{fft ~/ 8, fft ~/ 4, fft ~/ 2, fft}
        .where((h) => h > 0 && h <= fft)
        .toList()
      ..sort();
    return opts;
  }

  static int _validHop(AppSettings s) {
    final opts = _hopOptions(s.fftSize);
    if (opts.contains(s.hopSize)) return s.hopSize;
    return opts.contains(s.fftSize ~/ 4) ? s.fftSize ~/ 4 : opts.first;
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}

class _SliderTile extends StatelessWidget {
  const _SliderTile({
    required this.title,
    required this.valueLabel,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.divisions,
  });

  final String title;
  final String valueLabel;
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final v = value.clamp(min, max);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            title: Text(title),
            trailing: Text(
              valueLabel,
              style: const TextStyle(
                fontFeatures: [FontFeature.tabularFigures()],
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Slider(
            value: v,
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}
