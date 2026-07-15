import 'package:flutter/material.dart';
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
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 2, 4, 0),
                    child: _mode == PlotViewMode.spectrogram
                        ? SpectrogramView(
                            engine: engine,
                            crosshair: _crosshair,
                            onCrosshairChanged: (p) =>
                                setState(() => _crosshair = p),
                          )
                        : SpectrumView(
                            engine: engine,
                            crosshair: _crosshair,
                            onCrosshairChanged: (p) =>
                                setState(() => _crosshair = p),
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
                          if (value == 'settings') _openSettings();
                        },
                        itemBuilder: (context) => const [
                          PopupMenuItem(
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
          ],
        ),
      ),
    );
  }
}
