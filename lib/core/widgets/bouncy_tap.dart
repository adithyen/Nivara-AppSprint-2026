import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app.dart';

/// Emil Kowalski-inspired physical spring touch wrapper with full accessibility support.
///
/// Gives any interactive widget a tactile scale dip (`0.96`) with subtle
/// haptic feedback on press down, and snaps back with an organic spring bounce on release.
/// Automatically respects system & app-level `removeAnimations` preferences and applies button semantics.
/// Supports tap debounce via [NivaraA11yData.ignoreRepeatedTaps].
class BouncyTap extends StatefulWidget {
  const BouncyTap({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.scaleFactor = 0.96,
    this.enableHaptics = true,
    this.duration = const Duration(milliseconds: 140),
    this.semanticsLabel,
    this.semanticsHint,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double scaleFactor;
  final bool enableHaptics;
  final Duration duration;
  final String? semanticsLabel;
  final String? semanticsHint;

  @override
  State<BouncyTap> createState() => _BouncyTapState();
}

class _BouncyTapState extends State<BouncyTap> {
  bool _pressed = false;
  DateTime? _lastTapTime;

  bool _shouldDebounce(NivaraA11yData? a11yData) {
    if (a11yData == null || !a11yData.ignoreRepeatedTaps) return false;
    if (_lastTapTime == null) return false;
    final elapsed = DateTime.now().difference(_lastTapTime!);
    return elapsed < a11yData.ignoreRepeatDuration;
  }

  void _handleTapDown(TapDownDetails _) {
    if (widget.onTap == null && widget.onLongPress == null) return;
    final a11yData = NivaraA11yData.maybeOf(context);
    final haptics = a11yData?.hapticsEnabled ?? false;
    if (widget.enableHaptics && haptics) {
      HapticFeedback.selectionClick();
    }
    setState(() => _pressed = true);
  }

  void _handleTapUp(TapUpDetails _) {
    if (_pressed) {
      setState(() => _pressed = false);
    }
  }

  void _handleTapCancel() {
    if (_pressed) {
      setState(() => _pressed = false);
    }
  }

  void _handleTap() {
    final a11yData = NivaraA11yData.maybeOf(context);
    if (_shouldDebounce(a11yData)) return;
    _lastTapTime = DateTime.now();
    widget.onTap?.call();
  }

  @override
  Widget build(BuildContext context) {
    final disableAnimations = MediaQuery.disableAnimationsOf(context);
    final isInteractive = widget.onTap != null || widget.onLongPress != null;

    final content = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: _handleTapDown,
      onTapUp: _handleTapUp,
      onTapCancel: _handleTapCancel,
      onTap: widget.onTap != null ? _handleTap : null,
      onLongPress: widget.onLongPress,
      child: disableAnimations
          ? Opacity(
              opacity: _pressed ? 0.75 : 1.0,
              child: widget.child,
            )
          : AnimatedScale(
              scale: _pressed ? widget.scaleFactor : 1.0,
              duration: widget.duration,
              curve: _pressed ? Curves.easeOutCubic : Curves.easeOutBack,
              child: widget.child,
            ),
    );

    if (isInteractive || widget.semanticsLabel != null) {
      return Semantics(
        button: isInteractive,
        enabled: isInteractive,
        label: widget.semanticsLabel,
        hint: widget.semanticsHint,
        child: content,
      );
    }

    return content;
  }
}
