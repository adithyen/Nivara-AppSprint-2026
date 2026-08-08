import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/categorize.dart';
import '../../core/constants.dart';
import '../../core/services/evidence_engine.dart';
import '../../core/services/sensor_watch_service.dart';
import '../../core/supabase_client.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../models/enums.dart';
import '../../models/evidence_package.dart';
import '../../models/report.dart';

/// SensorWatch demo + control surface. Start monitoring to detect road jolts
/// passively, or "Simulate impact" to show the tamper-proof evidence flow at a
/// desk. Each detection can be inspected, cryptographically verified, and filed
/// as a civic report.
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
      setState(() => _detections.insert(0, d));
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    // Stop the engine when leaving the screen to spare the battery.
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
        'Monitoring without location — speed-gated detection is off. '
        'Enable location, or use "Simulate impact".',
      );
    }
  }

  Future<void> _simulate() async {
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
    return Scaffold(
      appBar: AppBar(title: const Text('SensorWatch')),
      body: Column(
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
          const Divider(height: 1),
          Expanded(
            child: _detections.isEmpty
                ? const _EmptyState()
                : ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: _detections.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, i) => _DetectionTile(
                      detection: _detections[i],
                      onTap: () => _openEvidence(_detections[i]),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  void _openEvidence(SensorDetection d) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
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
    final over = snap.impactG >= kDetectionThresholdG;
    final meterColor = over ? NivaraColors.danger : NivaraColors.primary;
    // Normalise the impact against 1.5× the threshold for a lively bar.
    final meter = (snap.impactG / (kDetectionThresholdG * 1.5)).clamp(0.0, 1.0);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                snap.monitoring ? Icons.sensors : Icons.sensors_off,
                color: snap.monitoring ? NivaraColors.success : Colors.grey,
              ),
              const SizedBox(width: 8),
              Text(
                snap.monitoring
                    ? (snap.warmingUp ? 'Warming up sensor…' : 'Monitoring — live')
                    : 'Idle',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const Spacer(),
              Text('${snap.detectionCount} detected',
                  style: Theme.of(context).textTheme.labelLarge),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                snap.impactG.toStringAsFixed(2),
                style: Theme.of(context).textTheme.displaySmall?.copyWith(
                      color: meterColor,
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(width: 6),
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text('g impact force (live)',
                    style: Theme.of(context).textTheme.bodySmall),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: meter,
              minHeight: 10,
              backgroundColor: meterColor.withValues(alpha: 0.15),
              color: meterColor,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _Stat(label: 'Peak', value: '${snap.peakG.toStringAsFixed(2)} g'),
              _Stat(label: 'Speed', value: '${snap.speedKmph.toStringAsFixed(0)} km/h'),
              _Stat(
                label: 'GPS',
                value: snap.hasFix ? 'Fix' : '—',
                valueColor: snap.hasFix ? NivaraColors.success : null,
              ),
              _Stat(
                label: 'Trigger',
                value: '${kDetectionThresholdG.toStringAsFixed(1)} g',
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: busy ? null : onToggle,
                  icon: Icon(snap.monitoring ? Icons.stop : Icons.play_arrow),
                  style: snap.monitoring
                      ? FilledButton.styleFrom(
                          backgroundColor: NivaraColors.danger)
                      : null,
                  label: Text(snap.monitoring ? 'Stop' : 'Start monitoring'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: busy ? null : onSimulate,
                  icon: const Icon(Icons.bolt),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                  ),
                  label: const Text('Simulate impact'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline,
                  size: 16, color: Theme.of(context).colorScheme.outline),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Tip: shake the phone hard to test — any impact above '
                  '${kDetectionThresholdG.toStringAsFixed(1)} g is captured '
                  'automatically. In a vehicle it triggers on potholes and '
                  'speed breakers on its own.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.outline,
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
    return Expanded(
      child: Column(
        children: [
          Text(value,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(color: valueColor, fontWeight: FontWeight.w600)),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.radar, size: 56, color: Colors.grey.withValues(alpha: 0.5)),
            const SizedBox(height: 12),
            Text('No detections yet',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              'Start monitoring, then shake the phone hard (or drive over '
              'rough road) — or tap "Simulate impact" to generate a '
              'tamper-proof evidence package.',
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: Theme.of(context).colorScheme.outline),
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
      DetectionType.manual => Colors.grey,
    };

IconData detectionIcon(DetectionType t) => switch (t) {
      DetectionType.pothole => Icons.dangerous,
      DetectionType.speedBreaker => Icons.speed,
      DetectionType.badRoad => Icons.warning_amber,
      DetectionType.manual => Icons.edit_location_alt,
    };

class _DetectionTile extends StatelessWidget {
  const _DetectionTile({required this.detection, required this.onTap});

  final SensorDetection detection;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = detectionColor(detection.type);
    final hash = detection.evidence.evidenceHash ?? '';
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.15),
          child: Icon(detectionIcon(detection.type), color: color),
        ),
        title: Text(
          '${detection.type.label} • ${detection.gAboveBaseline.toStringAsFixed(1)} g',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          '${timeAgo(detection.at)}  ·  '
          '#${hash.isEmpty ? '—' : hash.substring(0, 12)}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }
}

/// Full evidence inspector: every hashed field, the SHA-256, a live tamper
/// check, and a one-tap "file this as a civic report".
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
      _snack('Report filed — routed to the municipal queue.');
    } catch (e) {
      if (!mounted) return;
      _snack('Could not file report: $e');
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
                  CircleAvatar(
                    backgroundColor: color.withValues(alpha: 0.15),
                    child: Icon(detectionIcon(_pkg.eventType), color: color),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_pkg.eventType.label,
                            style: Theme.of(context).textTheme.titleLarge),
                        Text('Evidence package',
                            style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // Tamper-verify banner.
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: (verified ? NivaraColors.success : NivaraColors.danger)
                      .withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(verified ? Icons.verified : Icons.gpp_bad,
                        color: verified
                            ? NivaraColors.success
                            : NivaraColors.danger),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        verified
                            ? 'SHA-256 verified — evidence is intact.'
                            : 'Hash mismatch — evidence was altered.',
                        style: TextStyle(
                          color: verified
                              ? NivaraColors.success
                              : NivaraColors.danger,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _HashRow(hash: hash),
              const SizedBox(height: 8),
              _kv('Impact', '${_pkg.accelZPeak.toStringAsFixed(2)} g'),
              _kv('Noise floor', '${_pkg.accelZBaseline.toStringAsFixed(2)} g'),
              _kv('Location', '${_pkg.lat.toStringAsFixed(5)}, ${_pkg.lng.toStringAsFixed(5)}'),
              _kv('GPS accuracy', '±${_pkg.gpsAccuracy.toStringAsFixed(0)} m'),
              _kv('Speed', '${_pkg.speedKmph.toStringAsFixed(0)} km/h'),
              _kv('Gyro (x,y,z)',
                  '${_pkg.gyroX.toStringAsFixed(2)}, ${_pkg.gyroY.toStringAsFixed(2)}, ${_pkg.gyroZ.toStringAsFixed(2)}'),
              _kv('Device', '${_pkg.deviceFingerprint.substring(0, _pkg.deviceFingerprint.length.clamp(0, 16))}…'),
              _kv('App version', _pkg.appVersion),
              _kv('Captured', formatDateTime(
                  DateTime.fromMillisecondsSinceEpoch(_pkg.timestampDevice))),
              const SizedBox(height: 16),
              if (_submittedId != null)
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.check_circle,
                        color: NivaraColors.success, size: 20),
                    const SizedBox(width: 8),
                    Text('Filed as report',
                        style: Theme.of(context).textTheme.titleMedium),
                  ],
                )
              else
                FilledButton.icon(
                  onPressed: _submitting ? null : _submit,
                  icon: _submitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2.5, color: Colors.white))
                      : const Icon(Icons.send),
                  label: const Text('File as civic report'),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 130,
              child: Text(k,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: Theme.of(context).colorScheme.outline)),
            ),
            Expanded(
              child: Text(v,
                  style: const TextStyle(fontWeight: FontWeight.w500)),
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
    return InkWell(
      onTap: () {
        Clipboard.setData(ClipboardData(text: hash));
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(content: Text('Hash copied')));
      },
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.tag, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('SHA-256',
                      style: Theme.of(context).textTheme.labelMedium),
                  const SizedBox(height: 2),
                  Text(
                    hash,
                    style: const TextStyle(
                        fontFamily: 'monospace', fontSize: 12, height: 1.3),
                  ),
                ],
              ),
            ),
            const Icon(Icons.copy, size: 16),
          ],
        ),
      ),
    );
  }
}
