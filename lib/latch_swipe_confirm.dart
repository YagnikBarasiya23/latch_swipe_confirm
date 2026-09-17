/// Latch — a swipe-to-confirm button. MIT © 2026 Yagnik Barasiya.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Where the control is in its life.
enum LatchState { idle, dragging, confirming, done, failed }

/// How far along the track a drag of [dx] px puts the thumb (0–1).
double latchProgress(double dx, double trackWidth, double thumbSize) {
  final travel = trackWidth - thumbSize;
  if (travel <= 0) return 0;
  return (dx / travel).clamp(0.0, 1.0);
}

/// Resistance for the first part of a drag: the thumb follows the finger
/// slowly at first, then catches up, so a stray touch doesn't confirm.
double latchResistance(double progress, {double start = 0.12}) {
  if (progress <= 0) return 0;
  if (progress >= start) return progress;
  final t = progress / start;
  return start * (t * t * (3 - 2 * t)) * 0.6 + progress * 0.4;
}

/// Whether a released drag confirms: past the latch point, or flung
/// towards it hard enough from at least halfway.
bool shouldLatch(double progress, double velocity, {double threshold = 0.86}) =>
    progress >= threshold || (progress >= 0.5 && velocity > 1.6);

/// A track with a thumb that must be dragged to the end to confirm.
///
/// ```dart
/// LatchSwipeConfirm(
///   label: 'Swipe to pay ₹499',
///   doneLabel: 'Paid',
///   onConfirm: () async => api.pay(),
/// )
/// ```
class LatchSwipeConfirm extends StatefulWidget {
  const LatchSwipeConfirm({
    super.key,
    required this.label,
    required this.onConfirm,
    this.doneLabel = 'Done',
    this.failedLabel = 'Try again',
    this.height = 64,
    this.threshold = 0.86,
    this.enabled = true,
    this.resetAfter,
    this.trackColor = const Color(0xFF18181B),
    this.fillColor = const Color(0x33D9F99D),
    this.thumbColor = const Color(0xFFD9F99D),
    this.iconColor = const Color(0xFF0A0A0A),
    this.doneColor = const Color(0xFF86EFAC),
    this.failedColor = const Color(0xFFFCA5A5),
    this.textStyle = const TextStyle(color: Color(0xFFF4F4F5), fontSize: 16, fontWeight: FontWeight.w600),
    this.icon,
    this.haptics = true,
    this.onStateChanged,
  });

  /// Shown on the track before confirming, e.g. “Swipe to pay”.
  final String label;

  /// Runs when the thumb latches. Throw (or return `false`) to show the
  /// failed state and spring back.
  final FutureOr<bool?> Function() onConfirm;

  final String doneLabel;
  final String failedLabel;
  final double height;

  /// Share of the track the thumb must pass to latch.
  final double threshold;

  final bool enabled;

  /// Return to idle this long after success. `null` stays done until rebuilt with a new key.
  final Duration? resetAfter;

  final Color trackColor;
  final Color fillColor;
  final Color thumbColor;
  final Color iconColor;
  final Color doneColor;
  final Color failedColor;
  final TextStyle textStyle;

  /// Thumb content while idle; defaults to a chevron.
  final Widget? icon;

  final bool haptics;
  final ValueChanged<LatchState>? onStateChanged;

  @override
  State<LatchSwipeConfirm> createState() => _LatchSwipeConfirmState();
}

class _LatchSwipeConfirmState extends State<LatchSwipeConfirm> with TickerProviderStateMixin {
  late final AnimationController _pos = AnimationController.unbounded(vsync: this);
  late final AnimationController _shake = AnimationController(vsync: this, duration: const Duration(milliseconds: 460));
  late final AnimationController _spin = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
  LatchState _state = LatchState.idle;
  double _dragDx = 0;
  bool _pastPoint = false;
  // Only keyboard focus draws a ring; pointer focus doesn't.
  bool _highlight = false;
  Timer? _reset;

  bool get _reduced => MediaQuery.maybeDisableAnimationsOf(context) ?? false;
  bool get _busy => _state == LatchState.confirming || _state == LatchState.done;

  void _set(LatchState state) {
    if (_state == state) return;
    setState(() => _state = state);
    if (state == LatchState.confirming && !_reduced) {
      _spin.repeat();
    } else {
      _spin.stop();
    }
    widget.onStateChanged?.call(state);
  }

  void _springTo(double target, double velocity) {
    if (_reduced) {
      _pos.value = target;
      return;
    }
    _pos.animateWith(
      SpringSimulation(
        SpringDescription.withDampingRatio(mass: 1, stiffness: 420, ratio: target == 0 ? 0.72 : 0.9),
        _pos.value,
        target,
        velocity,
      ),
    );
  }

  void _onDragStart(DragStartDetails details) {
    if (!widget.enabled || _busy) return;
    _pos.stop();
    _dragDx = _pos.value * _travel;
    _pastPoint = false;
    _set(LatchState.dragging);
  }

  double _travel = 1;

  void _onDragUpdate(DragUpdateDetails details) {
    if (_state != LatchState.dragging) return;
    _dragDx += details.delta.dx;
    final raw = latchProgress(_dragDx, _travel + widget.height, widget.height);
    _pos.value = latchResistance(raw);
    final past = raw >= widget.threshold;
    if (past != _pastPoint) {
      _pastPoint = past;
      if (widget.haptics && past) HapticFeedback.mediumImpact();
    }
  }

  void _onDragEnd(DragEndDetails details) {
    if (_state != LatchState.dragging) return;
    final velocity = details.velocity.pixelsPerSecond.dx / math.max(1, _travel);
    final raw = latchProgress(_dragDx, _travel + widget.height, widget.height);
    if (shouldLatch(raw, velocity, threshold: widget.threshold)) {
      _springTo(1, velocity);
      _confirm();
    } else {
      _springTo(0, velocity);
      _set(LatchState.idle);
    }
  }

  Future<void> _confirm() async {
    _set(LatchState.confirming);
    bool ok;
    try {
      ok = (await widget.onConfirm()) ?? true;
    } catch (_) {
      ok = false;
    }
    if (!mounted) return;
    if (ok) {
      if (widget.haptics) HapticFeedback.heavyImpact();
      _set(LatchState.done);
      if (widget.resetAfter != null) {
        _reset?.cancel();
        _reset = Timer(widget.resetAfter!, () {
          if (!mounted) return;
          _springTo(0, 0);
          _set(LatchState.idle);
        });
      }
    } else {
      if (widget.haptics) HapticFeedback.vibrate();
      _set(LatchState.failed);
      if (!_reduced) await _shake.forward(from: 0);
      if (!mounted) return;
      _springTo(0, 0);
      await Future<void>.delayed(const Duration(milliseconds: 900));
      if (mounted && _state == LatchState.failed) _set(LatchState.idle);
    }
  }

  /// Keyboard and screen reader users confirm without swiping.
  void _activate() {
    if (!widget.enabled || _busy) return;
    _springTo(1, 0);
    _confirm();
  }

  @override
  void dispose() {
    _reset?.cancel();
    _pos.dispose();
    _shake.dispose();
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final h = widget.height;
    final label = switch (_state) {
      LatchState.done => widget.doneLabel,
      LatchState.failed => widget.failedLabel,
      _ => widget.label,
    };
    return Semantics(
      button: true,
      enabled: widget.enabled,
      label: _state == LatchState.confirming ? '${widget.label}, working' : label,
      onTap: _busy ? null : _activate,
      child: FocusableActionDetector(
        enabled: widget.enabled && !_busy,
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
        },
        actions: {ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) => _activate())},
        onShowFocusHighlight: (value) => setState(() => _highlight = value),
        child: Builder(
          builder: (context) {
            final focused = _highlight;
            return LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth.isFinite ? constraints.maxWidth : 320.0;
                _travel = math.max(1, width - h);
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  // Screen readers use the button's tap action instead of a scroll gesture.
                  excludeFromSemantics: true,
                  onHorizontalDragStart: _onDragStart,
                  onHorizontalDragUpdate: _onDragUpdate,
                  onHorizontalDragEnd: _onDragEnd,
                  child: AnimatedBuilder(
                    animation: Listenable.merge([_pos, _shake, _spin]),
                    builder: (context, _) {
                      final p = _pos.value.clamp(-0.05, 1.05);
                      final shake = math.sin(_shake.value * 5 * math.pi) * 10 * (1 - _shake.value);
                      final done = _state == LatchState.done;
                      final failed = _state == LatchState.failed;
                      final accent = done
                          ? widget.doneColor
                          : failed
                          ? widget.failedColor
                          : widget.thumbColor;
                      return Transform.translate(
                        offset: Offset(shake, 0),
                        child: SizedBox(
                          height: h,
                          width: width,
                          child: CustomPaint(
                            painter: _TrackPainter(
                              progress: p,
                              thumb: h,
                              track: widget.trackColor,
                              fill: done
                                  ? widget.doneColor.withValues(alpha: 0.22)
                                  : failed
                                  ? widget.failedColor.withValues(alpha: 0.18)
                                  : widget.fillColor,
                              focused: focused,
                              focusColor: widget.thumbColor,
                            ),
                            child: Stack(
                              children: [
                                // The label fades as the thumb covers it; state labels swap in with a fade.
                                Positioned.fill(
                                  child: Padding(
                                    padding: EdgeInsets.only(left: h * 0.9, right: h * 0.4),
                                    child: Center(
                                      child: Opacity(
                                        opacity: _busy || failed ? 1 : (1 - p * 1.6).clamp(0.0, 1.0),
                                        child: AnimatedSwitcher(
                                          duration: _reduced ? Duration.zero : const Duration(milliseconds: 220),
                                          child: ExcludeSemantics(
                                            key: ValueKey(label + _state.name),
                                            child: Text(
                                              _state == LatchState.confirming ? '' : label,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: widget.textStyle.copyWith(
                                                color: done
                                                    ? widget.doneColor
                                                    : failed
                                                    ? widget.failedColor
                                                    : null,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                Positioned(
                                  left: p.clamp(0.0, 1.0) * (width - h),
                                  top: 0,
                                  child: Padding(
                                    padding: EdgeInsets.all(h * 0.08),
                                    child: Container(
                                      width: h * 0.84,
                                      height: h * 0.84,
                                      decoration: BoxDecoration(
                                        color: accent,
                                        shape: BoxShape.circle,
                                        boxShadow: [BoxShadow(color: accent.withValues(alpha: 0.35), blurRadius: 16 * (0.4 + p))],
                                      ),
                                      child: Center(child: _thumbContent(h, done, failed)),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  Widget _thumbContent(double h, bool done, bool failed) {
    final size = h * 0.36;
    if (_state == LatchState.confirming) {
      return Transform.rotate(
        angle: _spin.value * 2 * math.pi,
        child: CustomPaint(size: Size.square(size), painter: _SpinnerPainter(widget.iconColor)),
      );
    }
    if (done) return CustomPaint(size: Size.square(size), painter: _CheckPainter(widget.iconColor));
    if (failed) return CustomPaint(size: Size.square(size), painter: _CrossPainter(widget.iconColor));
    return widget.icon ?? CustomPaint(size: Size.square(size), painter: _ChevronPainter(widget.iconColor));
  }
}

class _TrackPainter extends CustomPainter {
  _TrackPainter({
    required this.progress,
    required this.thumb,
    required this.track,
    required this.fill,
    required this.focused,
    required this.focusColor,
  });

  final double progress;
  final double thumb;
  final Color track;
  final Color fill;
  final bool focused;
  final Color focusColor;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = Radius.circular(size.height / 2);
    final rrect = RRect.fromRectAndRadius(Offset.zero & size, radius);
    canvas.drawRRect(rrect, Paint()..color = track);
    // The fill trails the thumb so the distance covered is visible.
    final fillWidth = thumb + progress.clamp(0.0, 1.0) * (size.width - thumb);
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, fillWidth, size.height), radius), Paint()..color = fill);
    if (focused) {
      canvas.drawRRect(
        rrect.inflate(3),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = focusColor,
      );
    }
  }

  @override
  bool shouldRepaint(_TrackPainter old) =>
      old.progress != progress || old.fill != fill || old.track != track || old.focused != focused || old.thumb != thumb;
}

Paint _stroke(Color color, double width) => Paint()
  ..color = color
  ..style = PaintingStyle.stroke
  ..strokeWidth = width
  ..strokeCap = StrokeCap.round
  ..strokeJoin = StrokeJoin.round;

class _ChevronPainter extends CustomPainter {
  _ChevronPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size s) {
    final w = s.width;
    final path = Path()
      ..moveTo(w * .22, w * .2)
      ..lineTo(w * .52, w * .5)
      ..lineTo(w * .22, w * .8)
      ..moveTo(w * .52, w * .2)
      ..lineTo(w * .82, w * .5)
      ..lineTo(w * .52, w * .8);
    canvas.drawPath(path, _stroke(color, w * .12));
  }

  @override
  bool shouldRepaint(_ChevronPainter old) => old.color != color;
}

class _CheckPainter extends CustomPainter {
  _CheckPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size s) {
    final w = s.width;
    canvas.drawPath(
      Path()
        ..moveTo(w * .14, w * .52)
        ..lineTo(w * .4, w * .78)
        ..lineTo(w * .88, w * .24),
      _stroke(color, w * .14),
    );
  }

  @override
  bool shouldRepaint(_CheckPainter old) => old.color != color;
}

class _CrossPainter extends CustomPainter {
  _CrossPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size s) {
    final w = s.width;
    canvas.drawPath(
      Path()
        ..moveTo(w * .22, w * .22)
        ..lineTo(w * .78, w * .78)
        ..moveTo(w * .78, w * .22)
        ..lineTo(w * .22, w * .78),
      _stroke(color, w * .13),
    );
  }

  @override
  bool shouldRepaint(_CrossPainter old) => old.color != color;
}

class _SpinnerPainter extends CustomPainter {
  _SpinnerPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size s) {
    canvas.drawArc(Offset.zero & s, 0, math.pi * 1.4, false, _stroke(color, s.width * .13));
  }

  @override
  bool shouldRepaint(_SpinnerPainter old) => old.color != color;
}
