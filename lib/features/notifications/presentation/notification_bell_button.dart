import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/bouncy_tap.dart';
import '../../../router.dart';
import '../data/notification_repository.dart';

/// 2026-Level Glassmorphic Notification Bell Button with live pulsing badge.
class NotificationBellButton extends ConsumerWidget {
  final Color? iconColor;
  final Color? backgroundColor;
  final double size;

  const NotificationBellButton({
    super.key,
    this.iconColor,
    this.backgroundColor,
    this.size = 42,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unreadCount = ref.watch(unreadNotificationCountProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = Theme.of(context).colorScheme.primary;

    return BouncyTap(
      onTap: () => context.push(Routes.notifications),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: backgroundColor ??
                  (isDark
                      ? const Color(0xFF141D28).withValues(alpha: 0.75)
                      : Colors.white.withValues(alpha: 0.85)),
              shape: BoxShape.circle,
              border: Border.all(
                color: isDark
                    ? (unreadCount > 0
                        ? primary.withValues(alpha: 0.4)
                        : Colors.white.withValues(alpha: 0.12))
                    : (unreadCount > 0
                        ? primary.withValues(alpha: 0.45)
                        : Colors.black.withValues(alpha: 0.08)),
                width: 1.2,
              ),
              boxShadow: [
                if (unreadCount > 0)
                  BoxShadow(
                    color: primary.withValues(alpha: isDark ? 0.3 : 0.2),
                    blurRadius: 12,
                    spreadRadius: 1,
                  ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.06),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(size / 2),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                child: Center(
                  child: Icon(
                    unreadCount > 0
                        ? Icons.notifications_active_rounded
                        : Icons.notifications_none_rounded,
                    color: iconColor ??
                        (unreadCount > 0
                            ? (isDark ? primary : primary)
                            : (isDark ? Colors.white70 : Colors.black87)),
                    size: size * 0.52,
                  ),
                ),
              ),
            ),
          ),
          if (unreadCount > 0)
            Positioned(
              top: -2,
              right: -2,
              child: AnimatedScale(
                scale: unreadCount > 0 ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 260),
                curve: Curves.elasticOut,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  constraints: const BoxConstraints(
                    minWidth: 18,
                    minHeight: 18,
                  ),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        const Color(0xFFFF1744),
                        const Color(0xFFFF5252),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isDark ? const Color(0xFF0D131A) : Colors.white,
                      width: 1.8,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFFF1744).withValues(alpha: 0.5),
                        blurRadius: 6,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                  child: Center(
                    child: Text(
                      unreadCount > 99 ? '99+' : '$unreadCount',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        height: 1.0,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
