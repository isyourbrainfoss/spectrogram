import 'package:flutter/material.dart';

/// Dark-first scientific palette with optional light theme.
abstract final class SpectrogramTheme {
  // Dark
  static const _darkBg = Color(0xFF0D1117);
  static const _darkSurface = Color(0xFF161B22);
  static const _darkCard = Color(0xFF21262D);
  static const _darkPrimary = Color(0xFF58A6FF);
  static const _darkSecondary = Color(0xFF3FB950);
  static const _darkTertiary = Color(0xFFF0883E);
  static const _darkOnSurface = Color(0xFFE6EDF3);
  static const _darkOutline = Color(0xFF484F58);

  // Light
  static const _lightBg = Color(0xFFF6F8FA);
  static const _lightSurface = Color(0xFFFFFFFF);
  static const _lightPrimary = Color(0xFF0969DA);
  static const _lightSecondary = Color(0xFF1A7F37);
  static const _lightTertiary = Color(0xFFBF4B00);
  static const _lightOnSurface = Color(0xFF1F2328);
  static const _lightOutline = Color(0xFFD0D7DE);

  static ThemeData dark() {
    final scheme = ColorScheme.dark(
      primary: _darkPrimary,
      secondary: _darkSecondary,
      tertiary: _darkTertiary,
      surface: _darkSurface,
      onSurface: _darkOnSurface,
      onPrimary: _darkBg,
      outline: _darkOutline,
      surfaceContainerHighest: _darkCard,
      surfaceContainerHigh: _darkCard,
      surfaceContainer: _darkSurface,
      error: const Color(0xFFF85149),
    );
    return _build(scheme, _darkBg);
  }

  static ThemeData light() {
    final scheme = ColorScheme.light(
      primary: _lightPrimary,
      secondary: _lightSecondary,
      tertiary: _lightTertiary,
      surface: _lightSurface,
      onSurface: _lightOnSurface,
      onPrimary: Colors.white,
      outline: _lightOutline,
      surfaceContainerHighest: const Color(0xFFEEF2F6),
      surfaceContainerHigh: const Color(0xFFF3F5F7),
      surfaceContainer: _lightSurface,
      error: const Color(0xFFCF222E),
    );
    return _build(scheme, _lightBg);
  }

  static ThemeData _build(ColorScheme scheme, Color scaffoldBg) {
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scaffoldBg,
      appBarTheme: AppBarTheme(
        backgroundColor: scaffoldBg,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: scheme.onSurface,
        ),
      ),
      cardTheme: CardThemeData(
        color: scheme.surfaceContainerHighest,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: scheme.surface,
        selectedIconTheme: IconThemeData(color: scheme.primary, size: 26),
        unselectedIconTheme: IconThemeData(
          color: scheme.onSurface.withValues(alpha: 0.6),
          size: 24,
        ),
        selectedLabelTextStyle: TextStyle(
          color: scheme.primary,
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
        unselectedLabelTextStyle: TextStyle(
          color: scheme.onSurface.withValues(alpha: 0.6),
          fontSize: 12,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surface,
        indicatorColor: scheme.primary.withValues(alpha: 0.18),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            color: selected
                ? scheme.primary
                : scheme.onSurface.withValues(alpha: 0.65),
          );
        }),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          visualDensity: VisualDensity.compact,
          textStyle: WidgetStatePropertyAll(
            const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
          ),
        ),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: scheme.primary,
        thumbColor: scheme.primary,
        inactiveTrackColor: scheme.outline.withValues(alpha: 0.4),
      ),
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        titleTextStyle: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w500,
          color: scheme.onSurface,
        ),
        subtitleTextStyle: TextStyle(
          fontSize: 13,
          color: scheme.onSurface.withValues(alpha: 0.65),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 44),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(44, 44),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
    );
  }
}
