import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Emil Kowalski-inspired physical spring touch wrapper with full accessibility support.
///
/// Gives any interactive widget a tactile scale dip (`0.96`) with subtle
/// haptic feedback on press down, and snaps back with an organic spring bounce on release.
/// Automatically respects system & app-level `reduceMotion` preferences and applies button semantics.
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

  void _handleTapDown(TapDownDetails _) {
    if (widget.onTap == null && widget.onLongPress == null) return;
    if (widget.enableHaptics) {
      HapticFeedback.lightImpact();
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

  @override
  Widget build(BuildContext context) {
    final disableAnimations = MediaQuery.disableAnimationsOf(context);
    final isInteractive = widget.onTap != null || widget.onLongPress != null;

    final content = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: _handleTapDown,
      onTapUp: _handleTapUp,
      onTapCancel: _handleTapCancel,
      onTap: widget.onTap,
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
