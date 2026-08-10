import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/services/evidence_engine.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../models/evidence_package.dart';

/// Full view of a report's tamper-proof [EvidencePackage]. This is the "wow"
/// surface: it re-runs [EvidenceEngine.verify] on-device and shows, field by
/// field, exactly what was captured and the SHA-256 fingerprint that seals it.
///
/// The verdict is computed live from the package's own data — we recompute the
/// hash here and compare it to the stored one, so a viewer can trust the badge
/// rather than a server flag.
class EvidenceViewerScreen extends StatelessWidget {
  const EvidenceViewerScreen({super.key, required this.package});

  final EvidencePackage package;

  @override
  Widget build(BuildContext context) {
    final stored = package.evidenceHash;
    final sealed = stored != null && stored.isNotEmpty;
    final recomputed = EvidenceEngine.computeHash(package);
    final verified = sealed && stored == recomputed;

    return Scaffold(
      appBar: AppBar(title: const Text('Tamper-proof evidence')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        children: [
          _Verdict(sealed: sealed, verified: verified),
          const SizedBox(height: 16),
          _Explainer(sealed: sealed),
          const SizedBox(height: 16),
          _Section(
            title: 'Event',
            child: Column(
              children: [
                _Row('Type', package.eventType.label),
                _Row(
                  'Captured',
                  formatDateTime(
                    DateTime.fromMillisecondsSinceEpoch(
                      package.timestampDevice,
                    ),
                  ),
                ),
                _Row('App version', package.appVersion),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _Section(
            title: 'Motion (raw sensors)',
            child: Column(
              children: [
                _Row(
                  'Impact peak',
                  '${package.accelZPeak.toStringAsFixed(2)} g',
                ),
                _Row(
                  'Baseline',
                  '${package.accelZBaseline.toStringAsFixed(2)} g',
                ),
                _Row('Gyro X', package.gyroX.toStringAsFixed(3)),
                _Row('Gyro Y', package.gyroY.toStringAsFixed(3)),
                _Row('Gyro Z', package.gyroZ.toStringAsFixed(3)),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _Section(
            title: 'Location & motion',
            child: Column(
              children: [
                _Row(
                  'Coordinates',
                  '${package.lat.toStringAsFixed(6)}, '
                      '${package.lng.toStringAsFixed(6)}',
                ),
                _Row(
                  'GPS accuracy',
                  '±${package.gpsAccuracy.toStringAsFixed(1)} m',
                ),
                _Row('Speed', '${package.speedKmph.toStringAsFixed(1)} km/h'),
                _Row('Heading', '${package.heading.toStringAsFixed(0)}°'),
                _Row('Altitude', '${package.altitude.toStringAsFixed(1)} m'),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _HashCard(
            label: 'Device fingerprint (SHA-256)',
            value: package.deviceFingerprint,
            mono: true,
          ),
          const SizedBox(height: 12),
          _HashCard(
            label: 'Evidence hash (SHA-256)',
            value: sealed ? stored : '— not sealed —',
            mono: true,
            highlight: verified ? NivaraColors.success : NivaraColors.danger,
          ),
          if (sealed) ...[
            const SizedBox(height: 12),
            _RecomputeRow(
              stored: stored,
              recomputed: recomputed,
              verified: verified,
            ),
          ],
        ],
      ),
    );
  }
}

class _Verdict extends StatelessWidget {
  const _Verdict({required this.sealed, required this.verified});
  final bool sealed;
  final bool verified;

  @override
  Widget build(BuildContext context) {
    final (color, icon, title, body) = switch ((sealed, verified)) {
      (true, true) => (
        NivaraColors.success,
        Icons.verified_user,
        'Verified · untampered',
        'The stored fingerprint matches a fresh hash of this data. Nothing '
            'has been altered since capture.',
      ),
      (true, false) => (
        NivaraColors.danger,
        Icons.gpp_bad,
        'Hash mismatch',
        'The stored fingerprint does not match the data. This evidence may '
            'have been altered.',
      ),
      _ => (
        Theme.of(context).colorScheme.outline,
        Icons.help_outline,
        'Not sealed',
        'This package has no evidence hash, so it cannot be verified.',
      ),
    };
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 30),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 4),
                Text(body, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Explainer extends StatelessWidget {
  const _Explainer({required this.sealed});
  final bool sealed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.info_outline, size: 18, color: scheme.onSurfaceVariant),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'The SHA-256 fingerprint below was computed on the device the '
            'instant this event was detected, over the raw sensor + GPS values. '
            'Re-hashing that same data reproduces the fingerprint exactly — so '
            'any edit to a single value would break the match.',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ),
      ],
    );
  }
}

/// A monospace, copyable value card — used for both the fingerprint and hash.
class _HashCard extends StatelessWidget {
  const _HashCard({
    required this.label,
    required this.value,
    this.mono = false,
    this.highlight,
  });
  final String label;
  final String value;
  final bool mono;
  final Color? highlight;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final canCopy = value.isNotEmpty && !value.startsWith('—');
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: (highlight ?? scheme.surfaceContainerHighest).withValues(
          alpha: highlight != null ? 0.10 : 1,
        ),
        borderRadius: BorderRadius.circular(12),
        border: highlight != null
            ? Border.all(color: highlight!.withValues(alpha: 0.35))
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: highlight ?? scheme.onSurfaceVariant,
                  ),
                ),
              ),
              if (canCopy)
                InkWell(
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: value));
                    ScaffoldMessenger.of(context)
                      ..hideCurrentSnackBar()
                      ..showSnackBar(
                        const SnackBar(content: Text('Copied to clipboard')),
                      );
                  },
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      Icons.copy,
                      size: 18,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          SelectableText(
            value,
            style: TextStyle(
              fontFamily: mono ? 'monospace' : null,
              fontSize: 12.5,
              height: 1.4,
              color: scheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

/// Side-by-side stored vs recomputed hash — the proof, made explicit.
class _RecomputeRow extends StatelessWidget {
  const _RecomputeRow({
    required this.stored,
    required this.recomputed,
    required this.verified,
  });
  final String stored;
  final String recomputed;
  final bool verified;

  @override
  Widget build(BuildContext context) {
    final color = verified ? NivaraColors.success : NivaraColors.danger;
    return Row(
      children: [
        Icon(verified ? Icons.check_circle : Icons.cancel, color: color),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            verified
                ? 'Recomputed hash matches the stored fingerprint.'
                : 'Recomputed hash differs from the stored fingerprint.',
            style: TextStyle(color: color, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
