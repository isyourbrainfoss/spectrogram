import 'package:flutter/material.dart';
import 'package:spectrogram/core/constants.dart';
import 'package:spectrogram/features/home/view_mode.dart';
import 'package:spectrogram/features/plot/crosshair_overlay.dart';
import 'package:spectrogram/features/plot/spectrogram_view.dart';
import 'package:spectrogram/features/plot/spectrum_view.dart';
import 'package:spectrogram/services/spectrogram_engine.dart';
import 'package:spectrogram/widgets/live_controls.dart';
import 'package:spectrogram/widgets/permission_banner.dart';

/// Plot-first home screen.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.engine});

  final SpectrogramEngine engine;

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

  @override
  Widget build(BuildContext context) {
    final engine = widget.engine;
    final running = engine.isRunning;

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth >= 480;
                  final titleRow = Row(
                    children: [
                      Flexible(
                        child: Text(
                          AppConstants.appName,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      _LiveDot(active: running),
                    ],
                  );
                  final modeToggle = SegmentedButton<PlotViewMode>(
                    segments: [
                      ButtonSegment(
                        value: PlotViewMode.spectrogram,
                        label: wide ? const Text('Spectrogram') : const Text('STFT'),
                        icon: const Icon(Icons.waterfall_chart_rounded, size: 18),
                      ),
                      ButtonSegment(
                        value: PlotViewMode.spectrum,
                        label: wide ? const Text('Spectrum') : const Text('FFT'),
                        icon: const Icon(Icons.show_chart_rounded, size: 18),
                      ),
                    ],
                    selected: {_mode},
                    onSelectionChanged: (s) {
                      setState(() {
                        _mode = s.first;
                        _crosshair = null;
                      });
                    },
                    style: const ButtonStyle(
                      visualDensity: VisualDensity.compact,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  );
                  if (wide) {
                    return Row(
                      children: [
                        Expanded(child: titleRow),
                        const SizedBox(width: 12),
                        modeToggle,
                      ],
                    );
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      titleRow,
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerRight,
                        child: modeToggle,
                      ),
                    ],
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: StatusBanner(
                engine: engine,
                onRetry: engine.start,
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 12, 0),
                child: _mode == PlotViewMode.spectrogram
                    ? SpectrogramView(
                        engine: engine,
                        crosshair: _crosshair,
                        onCrosshairChanged: (p) => setState(() => _crosshair = p),
                      )
                    : SpectrumView(
                        engine: engine,
                        crosshair: _crosshair,
                        onCrosshairChanged: (p) => setState(() => _crosshair = p),
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
        : Theme.of(context).colorScheme.outline;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            boxShadow: active
                ? [
                    BoxShadow(
                      color: color.withValues(alpha: 0.6),
                      blurRadius: 6,
                    ),
                  ]
                : null,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          active ? 'LIVE' : 'idle',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
            color: color,
          ),
        ),
      ],
    );
  }
}
