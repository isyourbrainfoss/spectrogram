import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:spectrogram/features/home/view_mode.dart';
import 'package:spectrogram/features/plot/crosshair_overlay.dart';
import 'package:spectrogram/features/plot/spectrogram_view.dart';
import 'package:spectrogram/features/plot/spectrum_view.dart';
import 'package:spectrogram/features/settings/settings_screen.dart';
import 'package:spectrogram/models/app_settings.dart';
import 'package:spectrogram/services/settings_repository.dart';
import 'package:spectrogram/services/spectrogram_engine.dart';
import 'package:spectrogram/widgets/live_controls.dart';
import 'package:spectrogram/widgets/permission_banner.dart';

/// Single plot-first screen — no tabs. Settings via ⋮ menu.
class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.engine,
    required this.repository,
    required this.onSettingsChanged,
  });

  final SpectrogramEngine engine;
  final SettingsRepository repository;
  final ValueChanged<AppSettings> onSettingsChanged;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  PlotViewMode _mode = PlotViewMode.spectrogram;
  CrosshairPoint? _crosshair;

  @override
  void initState() {
    super.initState();
    widget.engine.addListener(_onEngine);
  }

  @override
  void didUpdateWidget(covariant HomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.engine != widget.engine) {
      oldWidget.engine.removeListener(_onEngine);
      widget.engine.addListener(_onEngine);
    }
  }

  @override
  void dispose() {
    widget.engine.removeListener(_onEngine);
    super.dispose();
  }

  void _onEngine() {
    if (mounted) setState(() {});
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => SettingsScreen(
          engine: widget.engine,
          repository: widget.repository,
          onSettingsChanged: widget.onSettingsChanged,
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _importWav() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['wav', 'WAV'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;
      final file = result.files.single;
      Uint8List? bytes = file.bytes;
      if (bytes == null && file.path != null) {
        bytes = await File(file.path!).readAsBytes();
      }
      if (bytes == null) {
        _snack('Could not read file');
        return;
      }
      final name = file.name;
      await widget.engine.importWavBytes(bytes, label: name);
      if (!mounted) return;
      setState(() => _crosshair = null);
      _snack('Imported $name');
    } catch (e) {
      _snack('Import failed: $e');
    }
  }

  Future<void> _toggleRecord() async {
    final engine = widget.engine;
    if (engine.isRecordingToFile) {
      final wav = engine.stopFileRecordingAsWav();
      if (wav == null) {
        _snack('Nothing recorded');
        return;
      }
      await _saveWavBytes(wav);
      return;
    }
    if (!engine.isRunning) {
      // Start mic then arm recording.
      await engine.start();
      if (!engine.isRunning) {
        _snack(engine.errorMessage ?? 'Could not start microphone');
        return;
      }
    }
    engine.startFileRecording();
    _snack('Recording… tap again to save WAV');
  }

  Future<void> _saveWavBytes(Uint8List wav) async {
    final stamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .split('.')
        .first;
    final fileName = 'spectrogram_$stamp.wav';

    // Always write to a known-good local path first (never fails on SAF quirks).
    try {
      final dir = await getApplicationDocumentsDirectory();
      final out = File(p.join(dir.path, 'recordings', fileName));
      await out.parent.create(recursive: true);
      await out.writeAsBytes(wav, flush: true);

      // Optional: also offer a user-chosen location. On Android, [bytes] is
      // written via Storage Access Framework; the returned path may not be a
      // normal filesystem path — do not File() it.
      try {
        final savePath = await FilePicker.platform.saveFile(
          dialogTitle: 'Save recording',
          fileName: fileName,
          type: FileType.custom,
          allowedExtensions: const ['wav'],
          bytes: wav,
        );
        if (savePath != null &&
            savePath.isNotEmpty &&
            !savePath.startsWith('content:') &&
            (Platform.isLinux || Platform.isWindows || Platform.isMacOS)) {
          final f =
              File(savePath.endsWith('.wav') ? savePath : '$savePath.wav');
          try {
            await f.parent.create(recursive: true);
            await f.writeAsBytes(wav, flush: true);
            if (mounted) {
              _snack('Saved ${p.basename(f.path)}', short: true);
            }
            return;
          } catch (_) {
            // Fall through to local copy message.
          }
        } else if (savePath != null && savePath.isNotEmpty) {
          if (mounted) {
            _snack('Saved recording', short: true);
          }
          return;
        }
      } catch (_) {
        // User cancelled picker or platform threw after write — local copy ok.
      }

      if (mounted) {
        _snack('Saved ${out.path}', short: true);
      }
    } catch (e) {
      _snack('Save failed: $e');
    }
  }

  void _snack(String msg, {bool short = false}) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        content: Text(msg),
        duration: Duration(seconds: short ? 2 : 2),
        behavior: SnackBarBehavior.floating,
        // Keep clear of Start/Stop row.
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 88),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final engine = widget.engine;
    final running = engine.isRunning;
    final showBanner = engine.status != EngineStatus.idle &&
        engine.status != EngineStatus.running;

    return Scaffold(
      body: SafeArea(
        // Keep bottom padding for system nav; plot can use top edge more.
        top: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (showBanner)
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
                child: StatusBanner(
                  engine: engine,
                  onRetry: engine.start,
                ),
              ),
            Expanded(
              child: Stack(
                children: [
                  // Keep both plots mounted so STFT/FFT toggle and rotation
                  // do not dispose the spectrogram bitmap / spectrum state.
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 2, 4, 0),
                    child: IndexedStack(
                      index: _mode == PlotViewMode.spectrogram ? 0 : 1,
                      sizing: StackFit.expand,
                      children: [
                        SpectrogramView(
                          key: const ValueKey('plot-stft'),
                          engine: engine,
                          crosshair: _mode == PlotViewMode.spectrogram
                              ? _crosshair
                              : null,
                          onCrosshairChanged: (p) =>
                              setState(() => _crosshair = p),
                        ),
                        SpectrumView(
                          key: const ValueKey('plot-fft'),
                          engine: engine,
                          crosshair: _mode == PlotViewMode.spectrum
                              ? _crosshair
                              : null,
                          onCrosshairChanged: (p) =>
                              setState(() => _crosshair = p),
                        ),
                      ],
                    ),
                  ),
                  // Minimal chrome overlaid on the plot.
                  Positioned(
                    top: 6,
                    left: 56,
                    child: _LiveDot(active: running),
                  ),
                  Positioned(
                    top: 0,
                    right: 0,
                    child: Material(
                      color: Theme.of(context)
                          .colorScheme
                          .surface
                          .withValues(alpha: 0.82),
                      borderRadius: const BorderRadius.only(
                        bottomLeft: Radius.circular(10),
                      ),
                      child: PopupMenuButton<String>(
                        tooltip: 'Menu',
                        icon: const Icon(Icons.more_vert, size: 22),
                        padding: EdgeInsets.zero,
                        onSelected: (value) {
                          switch (value) {
                            case 'settings':
                              _openSettings();
                            case 'import':
                              _importWav();
                            case 'record':
                              _toggleRecord();
                          }
                        },
                        itemBuilder: (context) => [
                          const PopupMenuItem(
                            value: 'import',
                            child: ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              leading: Icon(Icons.folder_open_outlined),
                              title: Text('Import WAV…'),
                            ),
                          ),
                          PopupMenuItem(
                            value: 'record',
                            child: ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              leading: Icon(
                                engine.isRecordingToFile
                                    ? Icons.stop_circle_outlined
                                    : Icons.fiber_manual_record,
                              ),
                              title: Text(
                                engine.isRecordingToFile
                                    ? 'Stop & save recording'
                                    : 'Record to WAV',
                              ),
                            ),
                          ),
                          const PopupMenuItem(
                            value: 'settings',
                            child: ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              leading: Icon(Icons.settings_outlined),
                              title: Text('Settings'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Compact mode toggle under the plot.
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
              child: Center(
                child: SegmentedButton<PlotViewMode>(
                  segments: const [
                    ButtonSegment(
                      value: PlotViewMode.spectrogram,
                      label: Text('STFT'),
                      icon: Icon(Icons.waterfall_chart_rounded, size: 14),
                    ),
                    ButtonSegment(
                      value: PlotViewMode.spectrum,
                      label: Text('FFT'),
                      icon: Icon(Icons.show_chart_rounded, size: 14),
                    ),
                  ],
                  selected: {_mode},
                  onSelectionChanged: (s) {
                    setState(() {
                      _mode = s.first;
                      _crosshair = null;
                    });
                  },
                  style: ButtonStyle(
                    visualDensity: const VisualDensity(
                      horizontal: -3,
                      vertical: -3,
                    ),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    textStyle: WidgetStateProperty.all(
                      const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    padding: WidgetStateProperty.all(
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                    ),
                  ),
                ),
              ),
            ),
            LiveControls(
              engine: engine,
              hasCrosshair: _crosshair != null,
              onClearCrosshair: () => setState(() => _crosshair = null),
              onToggleRecord: _toggleRecord,
              onImport: _importWav,
            ),
          ],
        ),
      ),
    );
  }
}

class _LiveDot extends StatelessWidget {
  const _LiveDot({required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    final color = active
        ? Theme.of(context).colorScheme.secondary
        : Theme.of(context).colorScheme.outline.withValues(alpha: 0.7);
    return Material(
      color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.75),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                boxShadow: active
                    ? [
                        BoxShadow(
                          color: color.withValues(alpha: 0.55),
                          blurRadius: 5,
                        ),
                      ]
                    : null,
              ),
            ),
            const SizedBox(width: 5),
            Text(
              active ? 'LIVE' : 'idle',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
                color: color,
              ),
            ),
            // Note: file-import mode shows a chip under the plot instead.
          ],
        ),
      ),
    );
  }
}
