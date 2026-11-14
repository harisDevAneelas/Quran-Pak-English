import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// While true, the mushaf list should not scroll (two-finger pinch active).
class MushafPinchLock extends InheritedWidget {
  const MushafPinchLock({
    super.key,
    required this.locked,
    required super.child,
  });

  final bool locked;

  static bool of(BuildContext context) {
    return context
            .dependOnInheritedWidgetOfExactType<MushafPinchLock>()
            ?.locked ??
        false;
  }

  @override
  bool updateShouldNotify(MushafPinchLock oldWidget) =>
      locked != oldWidget.locked;
}

/// Focal point of a pinch in the zoom child's local coordinates.
typedef MushafPinchFocalCallback = void Function(Offset localFocal);

/// Two-finger pinch that changes real mushaf [fontSize] (text reflows).
///
/// Tracks finger-span distance so size follows the fingers tightly. Scroll is
/// locked while two pointers are down ([MushafPinchLock]).
class MushafPinchZoom extends StatefulWidget {
  const MushafPinchZoom({
    super.key,
    required this.fontSize,
    required this.onFontSizeChanged,
    required this.child,
    this.onPinchStarted,
    this.onPinchEnded,
    this.minFontSize = 18,
    this.maxFontSize = 56,
    /// How strongly finger span maps to font size (>1 = snappier).
    this.sensitivity = 2.4,
  });

  final double fontSize;
  final ValueChanged<double> onFontSizeChanged;
  final MushafPinchFocalCallback? onPinchStarted;
  final VoidCallback? onPinchEnded;
  final Widget child;
  final double minFontSize;
  final double maxFontSize;
  final double sensitivity;

  @override
  State<MushafPinchZoom> createState() => _MushafPinchZoomState();
}

class _MushafPinchZoomState extends State<MushafPinchZoom> {
  final Map<int, Offset> _points = <int, Offset>{};
  bool _pinching = false;
  double _baseFontSize = 40;
  double _startSpan = 0;
  double _pendingSize = 40;
  bool _frameScheduled = false;

  @override
  void initState() {
    super.initState();
    _baseFontSize = widget.fontSize;
    _pendingSize = widget.fontSize;
  }

  @override
  void didUpdateWidget(covariant MushafPinchZoom oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_pinching && oldWidget.fontSize != widget.fontSize) {
      _baseFontSize = widget.fontSize;
      _pendingSize = widget.fontSize;
    }
  }

  Offset? get _focal {
    if (_points.length < 2) return null;
    final pts = _points.values.toList(growable: false);
    return Offset(
      (pts[0].dx + pts[1].dx) / 2,
      (pts[0].dy + pts[1].dy) / 2,
    );
  }

  double? get _span {
    if (_points.length < 2) return null;
    final pts = _points.values.toList(growable: false);
    return (pts[0] - pts[1]).distance;
  }

  void _onPointerDown(PointerDownEvent e) {
    _points[e.pointer] = e.localPosition;
    if (_points.length == 2 && !_pinching) {
      final span = _span;
      if (span == null || span < 12) return;
      setState(() => _pinching = true);
      _baseFontSize = widget.fontSize;
      _pendingSize = widget.fontSize;
      _startSpan = span;
      final focal = _focal;
      if (focal != null) widget.onPinchStarted?.call(focal);
    }
  }

  void _onPointerMove(PointerMoveEvent e) {
    if (!_points.containsKey(e.pointer)) return;
    _points[e.pointer] = e.localPosition;
    if (!_pinching || _points.length < 2) return;

    final span = _span;
    if (span == null || _startSpan < 12) return;

    final rawScale = span / _startSpan;
    final amplified = 1.0 + (rawScale - 1.0) * widget.sensitivity;
    final raw = (_baseFontSize * amplified)
        .clamp(widget.minFontSize, widget.maxFontSize);
    final next = (raw * 2).roundToDouble() / 2;
    if (next == _pendingSize) return;
    _pendingSize = next;
    _scheduleApply();
  }

  void _onPointerUp(PointerEvent e) {
    _points.remove(e.pointer);
    if (_pinching && _points.length < 2) {
      _finishPinch();
    }
  }

  void _scheduleApply() {
    if (_frameScheduled) return;
    _frameScheduled = true;
    SchedulerBinding.instance.scheduleFrameCallback((_) {
      _frameScheduled = false;
      if (!mounted || !_pinching) return;
      if ((_pendingSize - widget.fontSize).abs() < 0.01) return;
      widget.onFontSizeChanged(_pendingSize);
    });
  }

  void _finishPinch() {
    if (!_pinching) return;
    setState(() => _pinching = false);
    _frameScheduled = false;
    final next =
        _pendingSize.clamp(widget.minFontSize, widget.maxFontSize);
    if ((next - widget.fontSize).abs() >= 0.01) {
      widget.onFontSizeChanged(next);
    }
    _baseFontSize = next;
    _pendingSize = next;
    widget.onPinchEnded?.call();
  }

  @override
  Widget build(BuildContext context) {
    return MushafPinchLock(
      locked: _pinching,
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: _onPointerDown,
        onPointerMove: _onPointerMove,
        onPointerUp: _onPointerUp,
        onPointerCancel: _onPointerUp,
        child: widget.child,
      ),
    );
  }
}
