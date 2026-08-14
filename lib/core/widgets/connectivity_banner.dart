import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/connectivity_service.dart';
import '../theme.dart';

/// An animated connectivity banner that slides in at the bottom of any posting
/// screen. Shows:
///   • Amber "offline" strip when no internet is detected.
///   • Green "back online — syncing" strip for [onlineDuration] when connectivity
///     is restored.
///
/// Usage — wrap your Scaffold body or add at the bottom of a Column:
/// ```dart
/// Column(children: [
///   Expanded(child: yourBody),
///   const ConnectivityBanner(),
/// ])
/// ```
class ConnectivityBanner extends ConsumerStatefulWidget {
  const ConnectivityBanner({super.key, this.onlineDuration = 3});

  /// How many seconds the "back online" green banner stays visible.
  final int onlineDuration;

  @override
  ConsumerState<ConnectivityBanner> createState() => _ConnectivityBannerState();
}

class _ConnectivityBannerState extends ConsumerState<ConnectivityBanner> {
  bool _wasOnline = true;
  bool _showOnlineFlash = false;

  @override
  Widget build(BuildContext context) {
    final isOnline = ref.watch(isOnlineProvider);

    // Detect offline→online transition to flash green banner briefly
    if (isOnline && !_wasOnline && !_showOnlineFlash) {
      _showOnlineFlash = true;
      Future.delayed(Duration(seconds: widget.onlineDuration), () {
        if (mounted) setState(() => _showOnlineFlash = false);
      });
    }
    _wasOnline = isOnline;

    final visible = !isOnline || _showOnlineFlash;

    return AnimatedSize(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
      child: visible ? _buildBanner(isOnline) : const SizedBox.shrink(),
    );
  }

  Widget _buildBanner(bool isOnline) {
    final isFlash = isOnline && _showOnlineFlash;

    final bgColor = isFlash
        ? NivaraColors.success
        : const Color(0xFFB45309); // Amber-700
    final icon = isFlash ? Icons.wifi : Icons.wifi_off;
    final message = isFlash
        ? '✓ Back online — syncing your pending posts…'
        : '⚡ You\'re offline — posts will sync when you reconnect';

    return Container(
      width: double.infinity,
      color: bgColor,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Icon(icon, color: Colors.white, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Convenience wrapper that adds the connectivity banner below any scaffold body.
/// Replaces `body: yourWidget` with `body: WithConnectivityBanner(child: yourWidget)`.
class WithConnectivityBanner extends StatelessWidget {
  const WithConnectivityBanner({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(child: child),
        const ConnectivityBanner(),
      ],
    );
  }
}
