/// Adaptive layout breakpoints (aligned with Flowlog / Progressor).
abstract final class ShellBreakpoints {
  /// Below this width: bottom navigation bar (phone / narrow).
  static const double sidebar = 600;

  /// Below this height: prefer bottom bar even if wide.
  static const double minRailHeight = 320;
}
