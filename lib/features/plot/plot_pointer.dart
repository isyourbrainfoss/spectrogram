import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:spectrogram/features/plot/crosshair_overlay.dart';

/// Maps pointer events to a [CrosshairPoint] with touch offset + relative drag.
///
/// Touch/stylus: crosshair sits above the finger so the fingertip does not
/// cover the sample point. Long-press then drag moves the crosshair by the
/// same delta as the finger (relative grab), so edges stay reachable.
class PlotPointerController {
  /// Lift of crosshair above a touch point (logical pixels).
  static const touchLift = 72.0;

  Offset? fingerLocal;
  bool _dragging = false;
  bool _relativeMode = false;
  Offset? _grabFinger;
  Offset? _grabCrosshairPx;

  bool get isDragging => _dragging;

  void reset() {
    fingerLocal = null;
    _dragging = false;
    _relativeMode = false;
    _grabFinger = null;
    _grabCrosshairPx = null;
  }

  CrosshairPoint localToPoint(Offset local, Size size) {
    if (size.width <= 0 || size.height <= 0) {
      return const CrosshairPoint(nx: 0.5, ny: 0.5);
    }
    final nx = (local.dx / size.width).clamp(0.0, 1.0);
    final ny = (1.0 - local.dy / size.height).clamp(0.0, 1.0);
    return CrosshairPoint(nx: nx, ny: ny);
  }

  Offset pointToLocal(CrosshairPoint p, Size size) {
    return Offset(
      p.nx.clamp(0.0, 1.0) * size.width,
      (1.0 - p.ny.clamp(0.0, 1.0)) * size.height,
    );
  }

  /// Offset from finger → crosshair for touch (adaptive near edges).
  Offset touchOffset(Offset finger, Size size) {
    // Default: above the finger.
    var dx = 0.0;
    var dy = -touchLift;

    // Near top: place below instead so crosshair stays in-plot.
    if (finger.dy + dy < 12) {
      dy = touchLift;
    }
    // Bias horizontally away from left/right edges.
    if (finger.dx < size.width * 0.2) {
      dx = 28;
    } else if (finger.dx > size.width * 0.8) {
      dx = -28;
    }
    return Offset(dx, dy);
  }

  Offset _applyTouchLift(Offset finger, Size size, PointerDeviceKind kind) {
    if (kind == PointerDeviceKind.mouse || kind == PointerDeviceKind.trackpad) {
      return finger;
    }
    final off = touchOffset(finger, size);
    return Offset(
      (finger.dx + off.dx).clamp(0.0, size.width),
      (finger.dy + off.dy).clamp(0.0, size.height),
    );
  }

  /// Tap / simple drag (with touch lift).
  CrosshairPoint onPointerDown(
    Offset local,
    Size size,
    PointerDeviceKind kind, {
    CrosshairPoint? existing,
  }) {
    fingerLocal = local;
    _dragging = true;
    _relativeMode = false;
    final target = _applyTouchLift(local, size, kind);
    return localToPoint(target, size);
  }

  CrosshairPoint? onPointerMove(
    Offset local,
    Size size,
    PointerDeviceKind kind, {
    required CrosshairPoint current,
  }) {
    fingerLocal = local;
    if (!_dragging) return null;

    if (_relativeMode && _grabFinger != null && _grabCrosshairPx != null) {
      final delta = local - _grabFinger!;
      final next = _grabCrosshairPx! + delta;
      final clamped = Offset(
        next.dx.clamp(0.0, size.width),
        next.dy.clamp(0.0, size.height),
      );
      return localToPoint(clamped, size);
    }

    final target = _applyTouchLift(local, size, kind);
    return localToPoint(target, size);
  }

  void onPointerUp() {
    _dragging = false;
    _relativeMode = false;
    _grabFinger = null;
    _grabCrosshairPx = null;
    // Keep last fingerLocal briefly for readout placement; clear next frame ok.
  }

  /// Long-press: enter relative-drag mode from current (or place with lift).
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

    final CrosshairPoint start;
    if (existing != null) {
      start = existing;
    } else {
      start = localToPoint(_applyTouchLift(local, size, kind), size);
    }
    _grabCrosshairPx = pointToLocal(start, size);
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
    final delta = local - _grabFinger!;
    final next = _grabCrosshairPx! + delta;
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
