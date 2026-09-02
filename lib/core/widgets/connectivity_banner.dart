import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/connectivity_service.dart';
import '../services/offline_queue_service.dart';
import '../theme.dart';

/// An animated connectivity & sync banner that slides in at the bottom of any screen.
/// Shows:
///   • Amber "offline" strip when no internet is detected.
///   • Blue/Green "Syncing X items..." animated progress when background queue drain is active.
///   • Green "✓ All synced" confirmation after background sync completes.
class ConnectivityBanner extends ConsumerStatefulWidget {
  const ConnectivityBanner({super.key, this.onlineDuration = 3});

  /// How many seconds the "back online / sync complete" green banner stays visible.
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

    return ValueListenableBuilder<SyncEvent>(
      valueListenable: syncNotifier,
      builder: (context, syncEvent, child) {
        final isSyncing = syncEvent.state == SyncStatusState.syncing;
        final isSyncCompleted = syncEvent.state == SyncStatusState.completed;
        final visible = !isOnline || _showOnlineFlash || isSyncing || isSyncCompleted;

        return AnimatedSize(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
          child: visible
              ? _buildBanner(isOnline, isSyncing, isSyncCompleted, syncEvent)
              : const SizedBox.shrink(),
        );
      },
    );
  }

  Widget _buildBanner(
    bool isOnline,
    bool isSyncing,
    bool isSyncCompleted,
    SyncEvent syncEvent,
  ) {
    Color bgColor;
    Widget leadingWidget;
    String message;

    if (isSyncing) {
      bgColor = const Color(0xFF0284C7); // Sky-600
      leadingWidget = const SizedBox(
        width: 16,
        height: 16,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
        ),
      );
      message = syncEvent.message ?? 'Syncing offline queue to cloud...';
    } else if (isSyncCompleted) {
      bgColor = NivaraColors.success;
      leadingWidget = const Icon(Icons.check_circle_outline, color: Colors.white, size: 18);
      message = syncEvent.message ?? '✓ Offline items synced to cloud';
    } else if (isOnline && _showOnlineFlash) {
      bgColor = NivaraColors.success;
      leadingWidget = const Icon(Icons.wifi, color: Colors.white, size: 18);
      message = '✓ Back online — syncing pending submissions…';
    } else {
      bgColor = const Color(0xFFB45309); // Amber-700
      leadingWidget = const Icon(Icons.wifi_off, color: Colors.white, size: 18);
      message = '⚡ You\'re offline — submissions will auto-sync when online';
    }

    return Container(
      width: double.infinity,
      color: bgColor,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            leadingWidget,
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
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
