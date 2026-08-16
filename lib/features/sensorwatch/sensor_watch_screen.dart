import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/categorize.dart';
import '../../core/constants.dart';
import '../../core/services/evidence_engine.dart';
import '../../core/services/offline_queue_service.dart';
import '../../core/services/sensor_watch_service.dart';
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
class SensorWatchScreen extends ConsumerStatefulWidget {
  const SensorWatchScreen({super.key});

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
      await svc.stop();
      return;
    }
    setState(() => _busy = true);
    final result = await svc.start();
    if (!mounted) return;
    setState(() => _busy = false);
    if (result == StartResult.startedWithoutLocation) {
      _snack(
        'Monitoring active without GPS fix — desk testing mode enabled.',
      );
    }
  }

  Future<void> _simulate() async {
    HapticFeedback.mediumImpact();
    await ref.read(sensorWatchServiceProvider).simulateImpact();
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
                onSimulate: _simulate,
              ),
            ),
            Divider(height: 1, color: isDark ? Colors.white12 : const Color(0xFFE2E8F0)),
            Expanded(
              child: _detections.isEmpty
                  ? const _EmptyState()
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
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
    required this.onSimulate,
  });

  final SensorSnapshot snap;
  final bool busy;
  final VoidCallback onToggle;
  final VoidCallback onSimulate;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final over = snap.impactG >= kDetectionThresholdG;
    final meterColor = over ? NivaraColors.danger : NivaraColors.primary;
    final meter = (snap.impactG / (kDetectionThresholdG * 1.5)).clamp(0.0, 1.0);

    return Container(
      margin: const EdgeInsets.all(16),
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
                .withValues(alpha: isDark ? (snap.monitoring ? 0.15 : 0.3) : 0.12),
            blurRadius: 24,
            offset: const Offset(0, 6),
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
          Row(
            children: [
              Expanded(
                child: BouncyTap(
                  onTap: busy ? null : onToggle,
                  child: Container(
                    height: 48,
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
                          color: (snap.monitoring ? NivaraColors.danger : NivaraColors.primary)
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
                            size: 22,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            snap.monitoring ? 'Stop Engine' : 'Start Monitor',
                            style: const TextStyle(
                              color: Colors.black,
                              fontWeight: FontWeight.w900,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: BouncyTap(
                  onTap: busy ? null : onSimulate,
                  child: Container(
                    height: 48,
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF131A24) : const Color(0xFFFFFBEB),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: NivaraColors.accent.withValues(alpha: 0.5),
                        width: 1.2,
                      ),
                    ),
                    child: const Center(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.bolt_rounded,
                            color: NivaraColors.accent,
                            size: 20,
                          ),
                          SizedBox(width: 6),
                          Text(
                            'Simulate Impact',
                            style: TextStyle(
                              color: NivaraColors.accent,
                              fontWeight: FontWeight.w800,
                              fontSize: 13.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
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
              'No Road Detections Yet',
              style: TextStyle(
                color: isDark ? Colors.white : const Color(0xFF0F172A),
                fontWeight: FontWeight.w800,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Start monitoring and drive over a road jolt or tap Simulate Impact.',
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
