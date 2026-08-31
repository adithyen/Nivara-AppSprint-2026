import 'dart:ui';
import 'package:flutter/material.dart';
import '../theme.dart';

/// 2026-Level Cyber-Civic Frosted Glass Card Container.
///
/// Features Gaussian backdrop blur, translucent dark base, and hairline glowing
/// borders for ultra-premium visual depth.
class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.borderRadius = 20.0,
    this.blur = 18.0,
    this.backgroundColor,
    this.borderColor,
    this.borderWidth = 1.0,
    this.accentGlow,
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double borderRadius;
  final double blur;
  final Color? backgroundColor;
  final Color? borderColor;
  final double borderWidth;
  final Color? accentGlow;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = backgroundColor ??
        (isDark
            ? NivaraColors.cardDark.withValues(alpha: 0.88)
            : Colors.white.withValues(alpha: 0.94));
    final border = borderColor ??
        (isDark
            ? Colors.white.withValues(alpha: 0.12)
            : const Color(0xFFCBD5E1));

    Widget content = ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          padding: padding ?? const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(borderRadius),
            border: Border.all(color: border, width: borderWidth),
            boxShadow: [
              BoxShadow(
                color: (accentGlow ?? (isDark ? Colors.black : const Color(0xFF64748B))).withValues(
                  alpha: accentGlow != null ? 0.3 : (isDark ? 0.4 : 0.08),
                ),
                blurRadius: accentGlow != null ? 20 : 16,
                spreadRadius: accentGlow != null ? 1 : 0,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );

    if (onTap != null) {
      content = Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(borderRadius),
        child: InkWell(
          borderRadius: BorderRadius.circular(borderRadius),
          onTap: onTap,
          child: content,
        ),
      );
    }

    if (margin != null) {
      return Padding(padding: margin!, child: content);
    }
    return content;
  }
}
