import 'package:flutter/material.dart';
import 'package:spectrogram/core/breakpoints.dart';
import 'package:spectrogram/features/home/home_screen.dart';
import 'package:spectrogram/features/settings/settings_screen.dart';
import 'package:spectrogram/models/app_settings.dart';
import 'package:spectrogram/services/settings_repository.dart';
import 'package:spectrogram/services/spectrogram_engine.dart';

/// Adaptive shell: NavigationRail on wide screens, NavigationBar on narrow.
class AdaptiveShell extends StatefulWidget {
  const AdaptiveShell({
    super.key,
    required this.engine,
    required this.repository,
    required this.onSettingsChanged,
  });

  final SpectrogramEngine engine;
  final SettingsRepository repository;
  final ValueChanged<AppSettings> onSettingsChanged;

  @override
  State<AdaptiveShell> createState() => _AdaptiveShellState();
}

class _AdaptiveShellState extends State<AdaptiveShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final useRail =
        size.width >= ShellBreakpoints.sidebar &&
        size.height >= ShellBreakpoints.minRailHeight;

    final pages = [
      HomeScreen(engine: widget.engine),
      SettingsScreen(
        engine: widget.engine,
        repository: widget.repository,
        onSettingsChanged: widget.onSettingsChanged,
      ),
    ];

    if (useRail) {
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: _index,
              onDestinationSelected: (i) => setState(() => _index = i),
              labelType: NavigationRailLabelType.all,
              destinations: const [
                NavigationRailDestination(
                  icon: Icon(Icons.graphic_eq_outlined),
                  selectedIcon: Icon(Icons.graphic_eq),
                  label: Text('Live'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.settings_outlined),
                  selectedIcon: Icon(Icons.settings),
                  label: Text('Settings'),
                ),
              ],
            ),
            const VerticalDivider(width: 1),
            Expanded(child: pages[_index]),
          ],
        ),
      );
    }

    return Scaffold(
      body: pages[_index],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.graphic_eq_outlined),
            selectedIcon: Icon(Icons.graphic_eq),
            label: 'Live',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
