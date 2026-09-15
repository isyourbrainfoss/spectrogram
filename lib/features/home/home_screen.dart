import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
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
  final _plotKey = GlobalKey();

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

  @override
  void initState() {
    super.initState();
    widget.engine.addListener(_onEngine);
    HardwareKeyboard.instance.addHandler(_onKey);
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
    HardwareKeyboard.instance.removeHandler(_onKey);
    widget.engine.removeListener(_onEngine);
    super.dispose();
  }

  void _onEngine() {
    if (mounted) setState(() {});
  }

  bool _onKey(KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return false;
    if (!mounted) return false;
    if (ModalRoute.of(context)?.isCurrent != true) return false;
    final editing = FocusManager.instance.primaryFocus?.context
        ?.findAncestorWidgetOfExactType<EditableText>();
    if (editing != null) return false;

    final key = event.logicalKey;
    final repeat = event is KeyRepeatEvent;
    final engine = widget.engine;

    if (!repeat) {
      if (key == LogicalKeyboardKey.space) {
        if (engine.isRunning) {
          engine.stop();
        } else {
          engine.start();
        }
        return true;
      }
      if (key == LogicalKeyboardKey.keyS) {
        _openSettings();
        return true;
      }
      if (key == LogicalKeyboardKey.keyF) {
        engine.toggleFreeze();
        return true;
      }
      if (key == LogicalKeyboardKey.keyH) {
        _togglePeakHold();
        return true;
      }
      if (key == LogicalKeyboardKey.keyP) {
        engine.resetPeakHold();
        return true;
      }
      if (key == LogicalKeyboardKey.keyR) {
        _toggleRecord();
        return true;
      }
      if (key == LogicalKeyboardKey.digit1 ||
          key == LogicalKeyboardKey.numpad1) {
        setState(() {
          _mode = PlotViewMode.spectrogram;
          _crosshair = null;
        });
        return true;
      }
      if (key == LogicalKeyboardKey.digit2 ||
          key == LogicalKeyboardKey.numpad2) {
        setState(() {
          _mode = PlotViewMode.spectrum;
          _crosshair = null;
        });
        return true;
      }
      if (key == LogicalKeyboardKey.escape) {
        if (_crosshair != null) {
          setState(() => _crosshair = null);
          return true;
        }
      }
      if (key == LogicalKeyboardKey.slash &&
          HardwareKeyboard.instance.isShiftPressed) {
        _showShortcutHelp();
        return true;
      }
      if (key == LogicalKeyboardKey.question) {
        _showShortcutHelp();
        return true;
      }
    }

    if (key == LogicalKeyboardKey.equal ||
        key == LogicalKeyboardKey.add ||
        key == LogicalKeyboardKey.numpadAdd) {
      if (engine.canZoom) engine.zoomViewport(1.15);
      return true;
    }
    if (key == LogicalKeyboardKey.minus ||
        key == LogicalKeyboardKey.numpadSubtract) {
      if (engine.canZoom) engine.zoomViewport(1 / 1.15);
      return true;
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      if (engine.canPan) {
        engine.panViewport(-engine.viewColumnCount ~/ 8);
      }
      return true;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      if (engine.canPan) {
        engine.panViewport(engine.viewColumnCount ~/ 8);
      }
      return true;
    }
    if (key == LogicalKeyboardKey.home) {
      engine.goToHistoryStart();
      return true;
    }
    if (key == LogicalKeyboardKey.end) {
      engine.followLiveEnd();
      return true;
    }
    return false;
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

  Future<void> _applySettings(AppSettings next) async {
    await widget.repository.save(next);
    await widget.engine.applySettings(next);
    widget.onSettingsChanged(next);
  }

  Future<void> _togglePeakHold() async {
    final s = widget.engine.settings;
    await _applySettings(s.copyWith(peakHold: !s.peakHold));
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
      await _saveNamedBytes(
        bytes: wav,
        fileName: _stampName('spectrogram', 'wav'),
        extensions: const ['wav'],
        dialogTitle: 'Save recording',
      );
      return;
    }
    if (!engine.isRunning) {
      await engine.start();
      if (!engine.isRunning) {
        _snack(engine.errorMessage ?? 'Could not start microphone');
        return;
      }
    }
    engine.startFileRecording();
    final pre = engine.recordingSeconds;
    _snack(
      pre > 0.5
          ? 'Recording (includes ~${pre.toStringAsFixed(0)}s pre-roll)…'
          : 'Recording…',
      short: true,
    );
  }

  Future<void> _exportHistory() async {
    final wav = widget.engine.exportHistoryAsWav();
    if (wav == null) {
      _snack('No history to export yet');
      return;
    }
    await _saveNamedBytes(
      bytes: wav,
      fileName: _stampName('spectrogram', 'wav'),
      extensions: const ['wav'],
      dialogTitle: 'Save recording',
    );
  }

  Future<void> _exportSpectrumCsv() async {
    final csv = widget.engine.exportSpectrumCsv();
    if (csv == null) {
      _snack('No spectrum to export yet');
      return;
    }
    await _saveNamedBytes(
      bytes: utf8.encode(csv),
      fileName: _stampName('spectrum', 'csv'),
      extensions: const ['csv'],
      dialogTitle: 'Save spectrum CSV',
    );
  }

  Future<void> _exportPlotPng() async {
    final ctx = _plotKey.currentContext;
    if (ctx == null) {
      _snack('Plot is not ready to export');
      return;
    }
    final boundary = ctx.findRenderObject();
    if (boundary is! RenderRepaintBoundary) {
      _snack('Plot is not ready to export');
      return;
    }
    try {
      final ratio = MediaQuery.maybeDevicePixelRatioOf(context) ?? 2.0;
      final image = await boundary.toImage(pixelRatio: ratio.clamp(1.5, 3.0));
      try {
        final bd = await image.toByteData(format: ui.ImageByteFormat.png);
        if (bd == null) {
          _snack('PNG encode failed');
          return;
        }
        final prefix = _mode == PlotViewMode.spectrogram
            ? 'spectrogram'
            : 'spectrum';
        await _saveNamedBytes(
          bytes: bd.buffer.asUint8List(),
          fileName: _stampName(prefix, 'png'),
          extensions: const ['png'],
          dialogTitle: 'Save plot PNG',
        );
      } finally {
        image.dispose();
      }
    } catch (e) {
      _snack('PNG export failed: $e');
    }
  }

  String _stampName(String prefix, String ext) {
    final stamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .split('.')
        .first;
    return '${prefix}_$stamp.$ext';
  }

  Future<void> _saveNamedBytes({
    required Uint8List bytes,
    required String fileName,
    required List<String> extensions,
    required String dialogTitle,
  }) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final out = File(p.join(dir.path, 'recordings', fileName));
      await out.parent.create(recursive: true);
      await out.writeAsBytes(bytes, flush: true);

      try {
        final savePath = await FilePicker.platform.saveFile(
          dialogTitle: dialogTitle,
          fileName: fileName,
          type: FileType.custom,
          allowedExtensions: extensions,
          bytes: bytes,
        );
        if (savePath != null &&
            savePath.isNotEmpty &&
            !savePath.startsWith('content:') &&
            (Platform.isLinux || Platform.isWindows || Platform.isMacOS)) {
          final ext = extensions.isNotEmpty ? '.${extensions.first}' : '';
          final f = File(
            ext.isEmpty || savePath.endsWith(ext) ? savePath : '$savePath$ext',
          );
          try {
            await f.parent.create(recursive: true);
            await f.writeAsBytes(bytes, flush: true);
            if (mounted) {
              _snack('Saved ${p.basename(f.path)}', short: true);
            }
            return;
          } catch (_) {}
        } else if (savePath != null && savePath.isNotEmpty) {
          if (mounted) {
            _snack('Saved ${p.basename(fileName)}', short: true);
          }
          return;
        }
      } catch (_) {}

      if (mounted) {
        _snack('Saved ${out.path}', short: true);
      }
    } catch (e) {
      _snack('Save failed: $e');
    }
  }

  void _showShortcutHelp() {
    showDialog<void>(
      context: context,
      builder: (context) {
        const rows = <(String, String)>[
          ('Space', 'Start / stop microphone'),
          ('F', 'Freeze spectrogram'),
          ('H', 'Toggle peak hold'),
          ('P', 'Reset peak hold'),
          ('R', 'Record / save WAV'),
          ('+ / −', 'Zoom time axis'),
          ('← / →', 'Pan time axis'),
          ('Home / End', 'Oldest / newest'),
          ('1 / 2', 'STFT / FFT view'),
          ('S', 'Settings'),
          ('Esc', 'Clear crosshair'),
          ('?', 'This list'),
        ];
        return AlertDialog(
          title: const Text('Keyboard shortcuts'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final row in rows)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 96,
                          child: Text(
                            row.$1,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                          ),
                        ),
                        Expanded(child: Text(row.$2)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
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
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 88),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final engine = widget.engine;
    final running = engine.isRunning;
    final showBanner =
        engine.status != EngineStatus.idle &&
        engine.status != EngineStatus.running;

    return Focus(
      autofocus: true,
      child: Scaffold(
        body: SafeArea(
          top: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (showBanner)
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
                  child: StatusBanner(engine: engine, onRetry: engine.start),
                ),
              Expanded(
                child: Stack(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 2, 4, 0),
                      child: RepaintBoundary(
                        key: _plotKey,
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
                    ),
                    Positioned(
                      top: 6,
                      left: 56,
                      child: _LiveDot(active: running, frozen: engine.isFrozen),
                    ),
                    Positioned(
                      top: 0,
                      right: 0,
                      child: Material(
                        color: Theme.of(
                          context,
                        ).colorScheme.surface.withValues(alpha: 0.82),
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
                              case 'export_history':
                                _exportHistory();
                              case 'export_png':
                                _exportPlotPng();
                              case 'export_csv':
                                _exportSpectrumCsv();
                              case 'shortcuts':
                                _showShortcutHelp();
                            }
                          },
                          itemBuilder: (context) => [
                            const PopupMenuItem(
                              value: 'settings',
                              child: ListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                leading: Icon(Icons.settings_outlined),
                                title: Text('Settings'),
                              ),
                            ),
                            if (_desktop)
                              const PopupMenuItem(
                                value: 'shortcuts',
                                child: ListTile(
                                  dense: true,
                                  contentPadding: EdgeInsets.zero,
                                  leading: Icon(Icons.keyboard_outlined),
                                  title: Text('Keyboard shortcuts'),
                                ),
                              ),
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
                            PopupMenuItem(
                              value: 'export_history',
                              enabled: engine.hasExportableHistory,
                              child: ListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                leading: const Icon(Icons.save_alt),
                                title: Text(
                                  engine.hasExportableHistory
                                      ? 'Save history WAV '
                                            '(~${engine.storedHistorySec.toStringAsFixed(0)}s)'
                                      : 'Save history WAV',
                                ),
                              ),
                            ),
                            const PopupMenuItem(
                              value: 'export_png',
                              child: ListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                leading: Icon(Icons.image_outlined),
                                title: Text('Export plot PNG'),
                              ),
                            ),
                            PopupMenuItem(
                              value: 'export_csv',
                              enabled: engine.filledColumns > 0,
                              child: const ListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                leading: Icon(Icons.table_chart_outlined),
                                title: Text('Export spectrum CSV'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
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
                onTogglePeakHold: _togglePeakHold,
                onResetPeakHold: engine.resetPeakHold,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LiveDot extends StatelessWidget {
  const _LiveDot({required this.active, required this.frozen});

  final bool active;
  final bool frozen;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = frozen
        ? scheme.tertiary
        : active
        ? scheme.secondary
        : scheme.outline.withValues(alpha: 0.7);
    final label = frozen
        ? 'HOLD'
        : active
        ? 'LIVE'
        : 'idle';
    return Material(
      color: scheme.surface.withValues(alpha: 0.75),
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
                boxShadow: active || frozen
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
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
