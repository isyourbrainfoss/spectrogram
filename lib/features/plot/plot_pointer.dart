import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:spectrogram/features/plot/crosshair_overlay.dart';

/// Maps pointer events to a [CrosshairPoint].
///
/// * Normal tap/drag: crosshair sits **exactly** under the finger/cursor.
/// * Long-press drag: **relative** grab — crosshair moves by the same delta as
///   the finger from the press point (optional lift above finger on long-press
///   start so the sample stays visible). Full range including right edge.
class PlotPointerController {
  /// Vertical lift only while long-pressing (logical pixels).
  static const longPressLift = 64.0;

  Offset? fingerLocal;
  bool _dragging = false;
  bool _relativeMode = false;
  Offset? _grabFinger;
  Offset? _grabCrosshairPx;

  bool get isDragging => _dragging;
  bool get isRelativeMode => _relativeMode;

  void reset() {
    fingerLocal = null;
    _dragging = false;
    _relativeMode = false;
    _grabFinger = null;
    _grabCrosshairPx = null;
  }

  /// Inclusive mapping so x==width / y==0 reach the true edges (nx/ny = 0 or 1).
  CrosshairPoint localToPoint(Offset local, Size size) {
    if (size.width <= 0 || size.height <= 0) {
      return const CrosshairPoint(nx: 0.5, ny: 0.5);
    }
    final x = local.dx.clamp(0.0, size.width);
    final y = local.dy.clamp(0.0, size.height);
    final nx = size.width == 0 ? 0.0 : (x / size.width).clamp(0.0, 1.0);
    final ny = size.height == 0 ? 0.0 : (1.0 - y / size.height).clamp(0.0, 1.0);
    return CrosshairPoint(nx: nx, ny: ny);
  }

  Offset pointToLocal(CrosshairPoint p, Size size) {
    final nx = p.nx.clamp(0.0, 1.0);
    final ny = p.ny.clamp(0.0, 1.0);
    return Offset(nx * size.width, (1.0 - ny) * size.height);
  }

  /// Lift used only for long-press precision mode (above finger, adapt near top).
  Offset _longPressLift(Offset finger, Size size) {
    var dy = -longPressLift;
    if (finger.dy + dy < 8) {
      dy = longPressLift; // flip below near top
    }
    // No horizontal shift — that blocked the rightmost (newest) columns.
    return Offset(
      finger.dx.clamp(0.0, size.width),
      (finger.dy + dy).clamp(0.0, size.height),
    );
  }

  /// Normal tap / drag: exact placement under the pointer.
  CrosshairPoint onPointerDown(
    Offset local,
    Size size,
    PointerDeviceKind kind, {
    CrosshairPoint? existing,
  }) {
    fingerLocal = local;
    _dragging = true;
    // Do not clear relative mode here if long-press may follow the same down.
    // Relative mode is entered only via [onLongPressStart].
    if (!_relativeMode) {
      _grabFinger = null;
      _grabCrosshairPx = null;
    }
    return localToPoint(local, size);
  }

  CrosshairPoint? onPointerMove(
    Offset local,
    Size size,
    PointerDeviceKind kind, {
    required CrosshairPoint current,
  }) {
    fingerLocal = local;
    if (!_dragging) return null;

    // Once long-press has engaged relative mode, keep using relative deltas
    // (Listener also gets move events during long-press).
    if (_relativeMode && _grabFinger != null && _grabCrosshairPx != null) {
      return _relativePoint(local, size);
    }

    // Normal drag: exact under finger.
    return localToPoint(local, size);
  }

  void onPointerUp() {
    _dragging = false;
    _relativeMode = false;
    _grabFinger = null;
    _grabCrosshairPx = null;
  }

  /// Long-press: lift crosshair above finger, then drag relatively.
  CrosshairPoint onLongPressStart(
    Offset local,
    Size size,
    PointerDeviceKind kind, {
    CrosshairPoint? existing,
  }) {
    fingerLocal = local;
    _dragging = true;
    _relativeMode = true;
    _grabFinger = local;

    // Start from lifted position so the sample is visible above the fingertip.
    // Relative deltas still reach every edge including the rightmost column.
    final startPx = _longPressLift(local, size);
    final start = localToPoint(startPx, size);
    _grabCrosshairPx = startPx;
    return start;
  }

  CrosshairPoint? onLongPressMove(
    Offset local,
    Size size, {
    required CrosshairPoint current,
  }) {
    fingerLocal = local;
    if (!_relativeMode || _grabFinger == null || _grabCrosshairPx == null) {
      return null;
    }
    return _relativePoint(local, size);
  }

  CrosshairPoint _relativePoint(Offset local, Size size) {
    final delta = local - _grabFinger!;
    final next = _grabCrosshairPx! + delta;
    // Inclusive clamp so we can hit exactly the right/bottom edges.
    final clamped = Offset(
      next.dx.clamp(0.0, size.width),
      next.dy.clamp(0.0, size.height),
    );
    return localToPoint(clamped, size);
  }

  void onLongPressEnd() {
    onPointerUp();
  }
}
