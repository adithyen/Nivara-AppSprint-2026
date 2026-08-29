import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/categorize.dart';
import '../../core/constants.dart';
import '../../core/services/evidence_engine.dart';
import '../../core/services/offline_queue_service.dart';
import '../../core/services/sensor_watch_service.dart';
import '../../core/services/shortcut_service.dart';
import '../../core/supabase_client.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../core/widgets/bouncy_tap.dart';
import '../../core/widgets/connectivity_banner.dart';
import '../../core/widgets/pulsing_badge.dart';
import '../../models/enums.dart';
import '../../models/evidence_package.dart';
import '../../models/report.dart';

/// 2026-Level Cyber-Civic SensorWatch Telemetry HUD.
///
/// Features passive road monitoring for highways and city roads,
/// crowdsourced multi-user consensus verification, 1-tap home screen widget pinning,
/// and tamper-evident cryptographic evidence packages.
class SensorWatchScreen extends ConsumerStatefulWidget {
  const SensorWatchScreen({super.key, this.autoStart = false});

  final bool autoStart;

  @override
  ConsumerState<SensorWatchScreen> createState() => _SensorWatchScreenState();
}

class _SensorWatchScreenState extends ConsumerState<SensorWatchScreen> {
  final List<SensorDetection> _detections = [];
  StreamSubscription<SensorDetection>? _sub;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final svc = ref.read(sensorWatchServiceProvider);
    _sub = svc.detections.listen((d) {
      if (!mounted) return;
      HapticFeedback.heavyImpact();
      setState(() => _detections.insert(0, d));
    });

    ShortcutService.instance.setShortcutListener((route) {
      if (route.contains('autoStart=true') && mounted) {
        final currentSvc = ref.read(sensorWatchServiceProvider);
        if (!currentSvc.isMonitoring) {
          _toggle();
        }
      }
    });

    if (widget.autoStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !svc.isMonitoring) {
          _toggle();
        }
      });
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    ref.read(sensorWatchServiceProvider).stop();
    super.dispose();
  }

  Future<void> _toggle() async {
    final svc = ref.read(sensorWatchServiceProvider);
    if (svc.isMonitoring) {
      HapticFeedback.mediumImpact();
      await svc.stop();
      return;
    }
    setState(() => _busy = true);
    HapticFeedback.selectionClick();
    final result = await svc.start();
    if (!mounted) return;
    setState(() => _busy = false);
    if (result == StartResult.startedWithoutLocation) {
      _snack('Monitoring active without GPS fix — desk testing mode enabled.');
    } else if (result == StartResult.started) {
      _snack('SensorWatch active. All highway & road impacts will be logged.');
    }
  }

  Future<void> _pinWidget() async {
    HapticFeedback.selectionClick();
    final success = await ShortcutService.instance.pinSensorWatchShortcut();
    if (!mounted) return;
    if (success) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('SensorWatch 1-Tap Widget pinned to Home Screen!'),
            backgroundColor: Color(0xFF00E676),
          ),
        );
    } else {
      _showWidgetInstructionsDialog();
    }
  }

  void _showWidgetInstructionsDialog() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF10161E) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Row(
          children: [
            Icon(Icons.widgets_rounded, color: NivaraColors.primary),
            SizedBox(width: 10),
            Text('1-Tap Home Widget', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
          ],
        ),
        content: const Text(
          'To start road monitoring instantly without multiple taps, you can add the '
          'SensorWatch shortcut directly to your device home screen launcher.',
          style: TextStyle(fontSize: 13.5, height: 1.4),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showCrowdsourceInfoSheet() {
    HapticFeedback.selectionClick();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? const Color(0xFF10161E) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      showDragHandle: true,
      builder: (_) => _CrowdsourceInfoSheet(
        onStartMonitoring: () {
          Navigator.pop(context);
          final svc = ref.read(sensorWatchServiceProvider);
          if (!svc.isMonitoring) _toggle();
        },
      ),
    );
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final svc = ref.watch(sensorWatchServiceProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? NivaraColors.canvasDark : const Color(0xFFF6F8FA),
      appBar: AppBar(
        title: const Text('SensorWatch HUD'),
        actions: [
          IconButton(
            tooltip: 'Autonomous Monitoring Info',
            icon: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isDark ? Colors.white.withValues(alpha: 0.08) : const Color(0xFFE2E8F0),
              ),
              child: const Icon(Icons.info_outline_rounded, size: 20),
            ),
            onPressed: _showCrowdsourceInfoSheet,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: WithConnectivityBanner(
        child: Column(
          children: [
            ValueListenableBuilder<SensorSnapshot>(
              valueListenable: svc.snapshot,
              builder: (context, snap, _) => _StatusPanel(
                snap: snap,
                busy: _busy,
                onToggle: _toggle,
                onInfoTap: _showCrowdsourceInfoSheet,
              ),
            ),
            _HomeScreenWidgetCard(onPinTap: _pinWidget),
            const SizedBox(height: 8),
            Divider(height: 1, color: isDark ? Colors.white12 : const Color(0xFFE2E8F0)),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 4),
              child: Row(
                children: [
                  Text(
                    'Recorded Defect Shockwaves',
                    style: TextStyle(
                      color: isDark ? Colors.white : const Color(0xFF0F172A),
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                    ),
                  ),
                  const Spacer(),
                  if (_detections.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: NivaraColors.primary.withValues(alpha: isDark ? 0.15 : 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${_detections.length} log${_detections.length == 1 ? '' : 's'}',
                        style: const TextStyle(
                          color: NivaraColors.primary,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: _detections.isEmpty
                  ? const _EmptyState()
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                      itemCount: _detections.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, i) => _DetectionTile(
                        detection: _detections[i],
                        onTap: () => _openEvidence(_detections[i]),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  void _openEvidence(SensorDetection d) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? const Color(0xFF10161E) : Colors.white,
      showDragHandle: true,
      builder: (_) => _EvidenceSheet(detection: d),
    );
  }
}

class _StatusPanel extends StatelessWidget {
  const _StatusPanel({
    required this.snap,
    required this.busy,
    required this.onToggle,
    required this.onInfoTap,
  });

  final SensorSnapshot snap;
  final bool busy;
  final VoidCallback onToggle;
  final VoidCallback onInfoTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final over = snap.impactG >= kDetectionThresholdG;
    final meterColor = over ? NivaraColors.danger : NivaraColors.primary;
    final meter = (snap.impactG / (kDetectionThresholdG * 1.5)).clamp(0.0, 1.0);

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF10161E) : Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: (snap.monitoring ? NivaraColors.primary : (isDark ? Colors.white : const Color(0xFFCBD5E1)))
              .withValues(alpha: snap.monitoring ? 0.4 : (isDark ? 0.1 : 0.6)),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: (snap.monitoring ? NivaraColors.primary : (isDark ? Colors.black : const Color(0xFF94A3B8)))
                .withValues(alpha: isDark ? (snap.monitoring ? 0.15 : 0.3) : 0.08),
            blurRadius: 20,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              if (snap.monitoring)
                const PulsingBadge(label: 'LIVE SENSOR HUD')
              else
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white.withValues(alpha: 0.1) : const Color(0xFFE2E8F0),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'IDLE',
                    style: TextStyle(
                      color: isDark ? Colors.white60 : const Color(0xFF64748B),
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              const Spacer(),
              Text(
                '${snap.detectionCount} Captured',
                style: TextStyle(
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                snap.impactG.toStringAsFixed(2),
                style: TextStyle(
                  color: meterColor,
                  fontSize: 44,
                  fontWeight: FontWeight.w900,
                  fontFamily: 'monospace',
                  letterSpacing: -1,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'g Impact Force',
                style: TextStyle(
                  color: isDark ? Colors.white70 : const Color(0xFF64748B),
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: meter,
              minHeight: 12,
              backgroundColor: meterColor.withValues(alpha: 0.15),
              color: meterColor,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _Stat(label: 'Peak', value: '${snap.peakG.toStringAsFixed(2)} g'),
              _Stat(
                label: 'Speed',
                value: '${snap.speedKmph.toStringAsFixed(0)} km/h',
              ),
              _Stat(
                label: 'GPS Fix',
                value: snap.hasFix ? 'Active' : 'No Fix',
                valueColor: snap.hasFix ? NivaraColors.success : (isDark ? Colors.white60 : const Color(0xFF64748B)),
              ),
              _Stat(
                label: 'Threshold',
                value: '${kDetectionThresholdG.toStringAsFixed(1)} g',
              ),
            ],
          ),
          const SizedBox(height: 18),
          BouncyTap(
            onTap: busy ? null : onToggle,
            child: Container(
              height: 52,
              decoration: BoxDecoration(
                gradient: snap.monitoring
                    ? const LinearGradient(
                        colors: [NivaraColors.danger, Color(0xFFFF8A80)],
                      )
                    : const LinearGradient(
                        colors: [Color(0xFF00E676), Color(0xFF00B0FF)],
                      ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: (snap.monitoring ? NivaraColors.danger : const Color(0xFF00E676))
                        .withValues(alpha: 0.35),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Center(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      snap.monitoring ? Icons.stop_rounded : Icons.play_arrow_rounded,
                      color: Colors.black,
                      size: 24,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      snap.monitoring ? 'Stop Monitoring' : 'Start Monitoring',
                      style: const TextStyle(
                        color: Colors.black,
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 1-Tap Home Screen Widget & Shortcut Card
class _HomeScreenWidgetCard extends StatelessWidget {
  const _HomeScreenWidgetCard({required this.onPinTap});

  final VoidCallback onPinTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryText = isDark ? Colors.white : const Color(0xFF0F172A);
    final secondaryText = isDark ? Colors.white.withValues(alpha: 0.55) : const Color(0xFF64748B);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF131A24) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isDark ? Colors.white.withValues(alpha: 0.08) : const Color(0xFFE2E8F0),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  colors: [Color(0xFF00E676), Color(0xFF00B0FF)],
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF00E676).withValues(alpha: 0.3),
                    blurRadius: 10,
                  ),
                ],
              ),
              child: const Icon(Icons.widgets_rounded, color: Colors.black, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '1-Tap Home Screen Widget',
                    style: TextStyle(
                      color: primaryText,
                      fontWeight: FontWeight.w800,
                      fontSize: 13.5,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Start monitoring instantly with zero extra taps.',
                    style: TextStyle(
                      color: secondaryText,
                      fontSize: 11.5,
                    ),
                  ),
                ],
              ),
            ),
            BouncyTap(
              onTap: onPinTap,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: NivaraColors.primary.withValues(alpha: isDark ? 0.16 : 0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: NivaraColors.primary.withValues(alpha: 0.4)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.add_to_home_screen_rounded, size: 15, color: NivaraColors.primary),
                    SizedBox(width: 4),
                    Text(
                      'Add',
                      style: TextStyle(
                        color: NivaraColors.primary,
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Educational bottom sheet explaining passive highway monitoring & consensus verification.
class _CrowdsourceInfoSheet extends StatelessWidget {
  const _CrowdsourceInfoSheet({required this.onStartMonitoring});

  final VoidCallback onStartMonitoring;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryText = isDark ? Colors.white : const Color(0xFF0F172A);
    final secondaryText = isDark ? Colors.white.withValues(alpha: 0.6) : const Color(0xFF64748B);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header with glowing icon
              Center(
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      colors: [Color(0xFF00E676), Color(0xFF00B0FF)],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF00E676).withValues(alpha: 0.35),
                        blurRadius: 18,
                      ),
                    ],
                  ),
                  child: const Icon(Icons.sensors_rounded, size: 36, color: Colors.black),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Autonomous Road Telemetry',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: primaryText,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Zero-Touch Highway Intelligence & Consensus Verification',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: secondaryText,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 20),

              _InfoCard(
                icon: Icons.directions_car_filled_rounded,
                iconColor: const Color(0xFF00E676),
                title: 'Start When Travelling Highways & State Roads',
                description:
                    'Turn on SensorWatch whenever you drive on arterial roads or highways. '
                    'All pothole shocks, crater jolts, and damaged road surfaces are recorded continuously in the background.',
              ),
              const SizedBox(height: 10),
              _InfoCard(
                icon: Icons.shield_rounded,
                iconColor: const Color(0xFF00B0FF),
                title: 'Zero-Hazard Reporting (No Photo Required)',
                description:
                    'Stopping your vehicle in the middle of busy traffic to take a photo is dangerous and impractical. '
                    'SensorWatch logs high-precision accelerometer and GPS telemetry automatically without stopping.',
              ),
              const SizedBox(height: 10),
              _InfoCard(
                icon: Icons.group_work_rounded,
                iconColor: const Color(0xFFFF9100),
                title: 'Multi-User Consensus Verification',
                description:
                    'To prevent accidental phone drops or deliberate shaking from raising false alarms, road defects are only '
                    'escalated as official civic reports once a statistically convincing threshold of impacts is logged by multiple independent users at the same location.',
              ),
              const SizedBox(height: 10),
              _InfoCard(
                icon: Icons.lock_outline_rounded,
                iconColor: const Color(0xFF7B4BC4),
                title: 'Tamper-Proof Cryptographic Record',
                description:
                    'Each road jolt is cryptographically signed with a SHA-256 seal containing peak g-force, 3-axis gyroscope data, Doppler speed, and GPS timestamp.',
              ),
              const SizedBox(height: 22),

              BouncyTap(
                onTap: onStartMonitoring,
                child: Container(
                  height: 50,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF00E676), Color(0xFF00B0FF)],
                    ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF00E676).withValues(alpha: 0.35),
                        blurRadius: 14,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: const Center(
                    child: Text(
                      'Got It • Start Monitoring',
                      style: TextStyle(
                        color: Colors.black,
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryText = isDark ? Colors.white : const Color(0xFF0F172A);
    final secondaryText = isDark ? Colors.white.withValues(alpha: 0.75) : const Color(0xFF475569);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF141C26) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.white.withValues(alpha: 0.08) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: isDark ? 0.18 : 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: primaryText,
                    fontWeight: FontWeight.w800,
                    fontSize: 13.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: TextStyle(
                    color: secondaryText,
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, this.valueColor});

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              color: valueColor ?? (isDark ? Colors.white : const Color(0xFF0F172A)),
              fontWeight: FontWeight.w800,
              fontSize: 14,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              color: isDark ? Colors.white.withValues(alpha: 0.5) : const Color(0xFF64748B),
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isDark ? Colors.white.withValues(alpha: 0.05) : const Color(0xFFE2E8F0),
              ),
              child: Icon(
                Icons.sensors_rounded,
                size: 48,
                color: isDark ? Colors.white38 : const Color(0xFF94A3B8),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Ready for Highway & Road Drives',
              style: TextStyle(
                color: isDark ? Colors.white : const Color(0xFF0F172A),
                fontWeight: FontWeight.w800,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Tap "Start Monitoring" before driving. Potholes and road jolts will be logged and verified with multi-user consensus.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: isDark ? Colors.white.withValues(alpha: 0.55) : const Color(0xFF64748B),
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Color detectionColor(DetectionType t) => switch (t) {
  DetectionType.pothole => NivaraColors.danger,
  DetectionType.speedBreaker => NivaraColors.accent,
  DetectionType.badRoad => NivaraColors.primary,
  DetectionType.manual => Colors.white60,
};

IconData detectionIcon(DetectionType t) => switch (t) {
  DetectionType.pothole => Icons.dangerous_rounded,
  DetectionType.speedBreaker => Icons.speed_rounded,
  DetectionType.badRoad => Icons.warning_amber_rounded,
  DetectionType.manual => Icons.edit_location_alt_rounded,
};

class _DetectionTile extends StatelessWidget {
  const _DetectionTile({required this.detection, required this.onTap});

  final SensorDetection detection;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = detectionColor(detection.type);
    final hash = detection.evidence.evidenceHash ?? '';
    return BouncyTap(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF10161E) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: color.withValues(alpha: isDark ? 0.35 : 0.45),
            width: 1.2,
          ),
          boxShadow: isDark
              ? null
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.16),
                shape: BoxShape.circle,
              ),
              child: Icon(detectionIcon(detection.type), color: color, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${detection.type.label} • ${detection.gAboveBaseline.toStringAsFixed(1)} g Impact',
                    style: TextStyle(
                      color: isDark ? Colors.white : const Color(0xFF0F172A),
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${timeAgo(detection.at)}  ·  #${hash.isEmpty ? '—' : hash.substring(0, 10)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isDark ? Colors.white.withValues(alpha: 0.55) : const Color(0xFF64748B),
                      fontSize: 11.5,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: isDark ? Colors.white38 : const Color(0xFF94A3B8)),
          ],
        ),
      ),
    );
  }
}

class _EvidenceSheet extends ConsumerStatefulWidget {
  const _EvidenceSheet({required this.detection});

  final SensorDetection detection;

  @override
  ConsumerState<_EvidenceSheet> createState() => _EvidenceSheetState();
}

class _EvidenceSheetState extends ConsumerState<_EvidenceSheet> {
  bool _submitting = false;
  String? _submittedId;

  EvidencePackage get _pkg => widget.detection.evidence;

  Future<void> _submit() async {
    final uid = currentUserId;
    if (uid == null) {
      _snack('Sign in to file a report.');
      return;
    }
    setState(() => _submitting = true);
    try {
      final impact = _pkg.accelZPeak - _pkg.accelZBaseline;
      final report = Report(
        id: '',
        userId: uid,
        category: categoryForDetection(_pkg.eventType),
        severity: severityForImpact(impact),
        lat: _pkg.lat,
        lng: _pkg.lng,
        source: 'SENSORWATCH',
        detectionType: _pkg.eventType,
        evidencePackage: _pkg,
        evidenceHash: _pkg.evidenceHash,
        createdAt: DateTime.now(),
      );
      final inserted = await supabase
          .from(kTableReports)
          .insert(report.toInsertMap())
          .select('id')
          .single();
      if (!mounted) return;
      setState(() => _submittedId = inserted['id'] as String);
      _snack('Report filed & verified in municipal queue.');
    } catch (e) {
      try {
        final impact = _pkg.accelZPeak - _pkg.accelZBaseline;
        final report = Report(
          id: '',
          userId: uid,
          category: categoryForDetection(_pkg.eventType),
          severity: severityForImpact(impact),
          lat: _pkg.lat,
          lng: _pkg.lng,
          source: 'SENSORWATCH',
          detectionType: _pkg.eventType,
          evidencePackage: _pkg,
          evidenceHash: _pkg.evidenceHash,
          createdAt: DateTime.now(),
        );
        await OfflineQueueService.enqueueReport(payload: report.toInsertMap());
        if (!mounted) return;
        setState(() => _submittedId = 'offline_queued');
        _snack('Saved to Offline Queue (Pending Sync) — will sync when online.');
      } catch (queueErr) {
        if (!mounted) return;
        _snack('Could not file report: $e');
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final verified = EvidenceEngine.verify(_pkg);
    final color = detectionColor(_pkg.eventType);
    final hash = _pkg.evidenceHash ?? '—';

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.16),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(detectionIcon(_pkg.eventType), color: color, size: 22),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _pkg.eventType.label,
                          style: TextStyle(
                            color: isDark ? Colors.white : const Color(0xFF0F172A),
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          'Tamper-Proof Evidence Record',
                          style: TextStyle(
                            color: isDark ? Colors.white.withValues(alpha: 0.55) : const Color(0xFF64748B),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: (verified ? NivaraColors.success : NivaraColors.danger)
                      .withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: (verified ? NivaraColors.success : NivaraColors.danger)
                        .withValues(alpha: 0.4),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      verified ? Icons.verified_rounded : Icons.gpp_bad_rounded,
                      color: verified ? NivaraColors.success : NivaraColors.danger,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        verified
                            ? 'SHA-256 Verified — cryptographic seal intact.'
                            : 'Integrity mismatch — data has been modified.',
                        style: TextStyle(
                          color: verified ? NivaraColors.success : NivaraColors.danger,
                          fontWeight: FontWeight.w700,
                          fontSize: 12.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _HashRow(hash: hash),
              const SizedBox(height: 8),
              _kv('Impact Force', '${_pkg.accelZPeak.toStringAsFixed(2)} g', isDark),
              _kv('Noise Baseline', '${_pkg.accelZBaseline.toStringAsFixed(2)} g', isDark),
              _kv('Coordinates', '${_pkg.lat.toStringAsFixed(5)}, ${_pkg.lng.toStringAsFixed(5)}', isDark),
              _kv('GPS Accuracy', '±${_pkg.gpsAccuracy.toStringAsFixed(0)} m', isDark),
              _kv('Speed', '${_pkg.speedKmph.toStringAsFixed(0)} km/h', isDark),
              _kv('App Version', _pkg.appVersion, isDark),
              const SizedBox(height: 18),
              if (_submittedId != null)
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: NivaraColors.success.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: NivaraColors.success.withValues(alpha: 0.5)),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.check_circle_rounded, color: NivaraColors.success, size: 20),
                      SizedBox(width: 8),
                      Text(
                        'Filed as Civic Report',
                        style: TextStyle(
                          color: NivaraColors.success,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                )
              else
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: FilledButton.icon(
                    onPressed: _submitting ? null : _submit,
                    icon: _submitting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                          )
                        : const Icon(Icons.send_rounded, color: Colors.black),
                    label: const Text(
                      'File as Official Civic Report',
                      style: TextStyle(color: Colors.black, fontWeight: FontWeight.w900),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _kv(String k, String v, bool isDark) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        SizedBox(
          width: 120,
          child: Text(
            k,
            style: TextStyle(
              color: isDark ? Colors.white.withValues(alpha: 0.55) : const Color(0xFF64748B),
              fontSize: 12.5,
            ),
          ),
        ),
        Expanded(
          child: Text(
            v,
            style: TextStyle(
              color: isDark ? Colors.white : const Color(0xFF0F172A),
              fontWeight: FontWeight.w600,
              fontSize: 13,
              fontFamily: 'monospace',
            ),
          ),
        ),
      ],
    ),
  );
}

class _HashRow extends StatelessWidget {
  const _HashRow({required this.hash});
  final String hash;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return BouncyTap(
      onTap: () {
        Clipboard.setData(ClipboardData(text: hash));
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(content: Text('Cryptographic SHA-256 hash copied.')));
      },
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF131A24) : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isDark ? Colors.white.withValues(alpha: 0.08) : const Color(0xFFCBD5E1),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.tag_rounded, size: 18, color: NivaraColors.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'SHA-256 Hash',
                    style: TextStyle(
                      color: isDark ? Colors.white60 : const Color(0xFF64748B),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    hash,
                    style: TextStyle(
                      color: isDark ? Colors.white : const Color(0xFF0F172A),
                      fontFamily: 'monospace',
                      fontSize: 11.5,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.copy_rounded, size: 16, color: isDark ? Colors.white60 : const Color(0xFF64748B)),
          ],
        ),
      ),
    );
  }
}
