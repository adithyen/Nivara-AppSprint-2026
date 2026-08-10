import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../core/supabase_client.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../models/enums.dart';
import '../../models/report.dart';
import '../admin/status_style.dart';
import '../auth/auth_controller.dart';
import 'category_grid.dart';
import 'evidence_viewer.dart';

/// Citizen-facing detail for one report. Reached from the map sheet or the
/// home feed. Shows the full report, links into the [EvidenceViewerScreen] for
/// SensorWatch evidence, and — the build-order #7 piece — lets a nearby citizen
/// **confirm** the report ("I saw this too"), which writes a `confirmations`
/// row. A DB trigger recomputes `confirmation_count` and flips
/// `is_community_verified` at 5 confirmations.
class ReportDetailScreen extends ConsumerStatefulWidget {
  const ReportDetailScreen({super.key, required this.report});

  final Report report;

  @override
  ConsumerState<ReportDetailScreen> createState() => _ReportDetailScreenState();
}

class _ReportDetailScreenState extends ConsumerState<ReportDetailScreen> {
  late Report _report = widget.report;
  bool _confirming = false;
  bool _alreadyConfirmed = false;
  bool _isOwn = false;

  @override
  void initState() {
    super.initState();
    _refresh();
    _checkConfirmed();
  }

  /// Pull the latest row so counts/status reflect other people's votes.
  Future<void> _refresh() async {
    try {
      final row = await supabase
          .from(kTableReports)
          .select()
          .eq('id', widget.report.id)
          .maybeSingle();
      if (row != null && mounted) {
        setState(() => _report = Report.fromMap(row));
      }
    } catch (_) {
      /* keep the passed report */
    }
  }

  /// Has this user already confirmed? Also flags their own reports (you can't
  /// confirm your own).
  Future<void> _checkConfirmed() async {
    final uid = ref.read(authControllerProvider).asData?.value?.id;
    if (uid == null) return;
    final own = _report.userId != null && _report.userId == uid;
    var confirmed = false;
    if (!own) {
      try {
        final rows = await supabase
            .from(kTableConfirmations)
            .select('id')
            .eq('report_id', _report.id)
            .eq('user_id', uid)
            .eq('type', 'CONFIRM')
            .limit(1);
        confirmed = (rows as List).isNotEmpty;
      } catch (_) {
        /* tolerate — button just stays enabled */
      }
    }
    if (mounted) {
      setState(() {
        _isOwn = own;
        _alreadyConfirmed = confirmed;
      });
    }
  }

  Future<void> _confirm() async {
    final uid = ref.read(authControllerProvider).asData?.value?.id;
    if (uid == null) {
      _snack('Sign in to confirm reports.');
      return;
    }
    setState(() => _confirming = true);
    try {
      await supabase.from(kTableConfirmations).insert({
        'report_id': _report.id,
        'user_id': uid,
        'type': 'CONFIRM',
      });
      // Flip the button immediately, then re-fetch the trigger-updated row so
      // the count/verified badge reflect the DB's recomputation.
      setState(() => _alreadyConfirmed = true);
      await _refresh();
      if (mounted) _snack('Thanks — your confirmation was recorded.');
    } on Object catch (e) {
      // A duplicate (unique violation) means they already confirmed elsewhere.
      final dup = e.toString().contains('23505');
      if (mounted) {
        setState(() => _alreadyConfirmed = dup || _alreadyConfirmed);
        _snack(
          dup ? 'You already confirmed this report.' : 'Could not confirm: $e',
        );
      }
    } finally {
      if (mounted) setState(() => _confirming = false);
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final r = _report;
    final scheme = Theme.of(context).colorScheme;
    final sev = severityColor(r.severity);
    final title = r.title?.trim().isNotEmpty == true
        ? r.title!.trim()
        : r.category.label;
    return Scaffold(
      appBar: AppBar(title: const Text('Report')),
      body: RefreshIndicator(
        onRefresh: () async {
          await _refresh();
          await _checkConfirmed();
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: sev.withValues(alpha: 0.15),
                  child: Icon(categoryIcon(r.category), color: sev),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      _StatusPill(status: r.status),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (r.hasEvidence && r.evidencePackage != null)
              _EvidenceTile(
                verified: r.isCommunityVerified,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        EvidenceViewerScreen(package: r.evidencePackage!),
                  ),
                ),
              )
            else if (r.hasEvidence)
              // Evidence hash present but the full package didn't come down.
              _EvidenceHashOnly(hash: r.evidenceHash!),
            if (r.photoUrls != null && r.photoUrls!.isNotEmpty) ...[
              const SizedBox(height: 12),
              _PhotoStrip(urls: r.photoUrls!),
            ],
            const SizedBox(height: 12),
            _CommunityCard(
              count: r.confirmationCount,
              verified: r.isCommunityVerified,
              isOwn: _isOwn,
              alreadyConfirmed: _alreadyConfirmed,
              confirming: _confirming,
              onConfirm: _confirm,
            ),
            if (r.description?.trim().isNotEmpty == true) ...[
              const SizedBox(height: 12),
              _Section(
                title: 'Description',
                child: Text(r.description!.trim()),
              ),
            ],
            const SizedBox(height: 12),
            _Section(
              title: 'Details',
              child: Column(
                children: [
                  _MetaRow('Category', r.category.label),
                  _MetaRow('Severity', r.severity.label),
                  _MetaRow(
                    'Source',
                    r.isFromSensor ? 'SensorWatch (passive)' : 'Manual report',
                  ),
                  if (r.assignedDepartment != null)
                    _MetaRow('Department', r.assignedDepartment!.label),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _Section(
              title: 'Location',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (r.address?.trim().isNotEmpty == true)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(r.address!.trim()),
                    ),
                  Text(
                    '${r.lat.toStringAsFixed(5)}, ${r.lng.toStringAsFixed(5)}',
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _Section(
              title: 'Timeline',
              child: Column(
                children: [
                  _MetaRow('Reported', formatDateTime(r.createdAt)),
                  if (r.acknowledgedAt != null)
                    _MetaRow('Acknowledged', formatDateTime(r.acknowledgedAt!)),
                  if (r.resolvedAt != null)
                    _MetaRow('Resolved', formatDateTime(r.resolvedAt!)),
                ],
              ),
            ),
            if (r.resolutionNotes?.trim().isNotEmpty == true) ...[
              const SizedBox(height: 12),
              _Section(
                title: 'Resolution note',
                child: Text(r.resolutionNotes!.trim()),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The community-confirmation card + button — the build-order #7 interaction.
class _CommunityCard extends StatelessWidget {
  const _CommunityCard({
    required this.count,
    required this.verified,
    required this.isOwn,
    required this.alreadyConfirmed,
    required this.confirming,
    required this.onConfirm,
  });

  final int count;
  final bool verified;
  final bool isOwn;
  final bool alreadyConfirmed;
  final bool confirming;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = verified ? NivaraColors.success : NivaraColors.primary;
    final remaining = (5 - count).clamp(0, 5);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(verified ? Icons.verified : Icons.groups, color: accent),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  verified
                      ? 'Community-verified'
                      : '$count ${count == 1 ? 'person has' : 'people have'} '
                            'confirmed this',
                  style: TextStyle(
                    color: accent,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
              ),
              _CountBadge(count: count, color: accent),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            verified
                ? 'Enough nearby citizens have vouched for this report. '
                      'Verified reports get priority attention.'
                : isOwn
                ? "This is your report. Others nearby can confirm they've seen "
                      'it too.'
                : remaining > 0
                ? '$remaining more ${remaining == 1 ? 'confirmation' : 'confirmations'} '
                      'to reach community-verified status.'
                : 'Awaiting verification.',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: _ConfirmButton(
              isOwn: isOwn,
              alreadyConfirmed: alreadyConfirmed,
              confirming: confirming,
              onConfirm: onConfirm,
            ),
          ),
        ],
      ),
    );
  }
}

class _ConfirmButton extends StatelessWidget {
  const _ConfirmButton({
    required this.isOwn,
    required this.alreadyConfirmed,
    required this.confirming,
    required this.onConfirm,
  });
  final bool isOwn;
  final bool alreadyConfirmed;
  final bool confirming;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    if (isOwn) {
      return OutlinedButton.icon(
        onPressed: null,
        style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
        icon: const Icon(Icons.person_outline),
        label: const Text('Your report'),
      );
    }
    if (alreadyConfirmed) {
      return OutlinedButton.icon(
        onPressed: null,
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
          foregroundColor: NivaraColors.success,
        ),
        icon: const Icon(Icons.check_circle, color: NivaraColors.success),
        label: const Text('You confirmed this'),
      );
    }
    return FilledButton.icon(
      onPressed: confirming ? null : onConfirm,
      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
      icon: confirming
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2.4,
                color: Colors.white,
              ),
            )
          : const Icon(Icons.thumb_up_alt_outlined),
      label: Text(confirming ? 'Recording…' : 'I saw this too'),
    );
  }
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count, required this.color});
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        '$count',
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

/// SensorWatch evidence entry point — tap to open the full verifier.
class _EvidenceTile extends StatelessWidget {
  const _EvidenceTile({required this.verified, required this.onTap});
  final bool verified;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: NivaraColors.primary.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: NivaraColors.primary.withValues(alpha: 0.3),
            ),
          ),
          child: Row(
            children: [
              const Icon(Icons.verified_user, color: NivaraColors.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Tamper-proof evidence',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: NivaraColors.primary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'SHA-256 sensor snapshot · tap to verify',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: NivaraColors.primary),
            ],
          ),
        ),
      ),
    );
  }
}

/// Fallback when only the hash (not the full package) is available.
class _EvidenceHashOnly extends StatelessWidget {
  const _EvidenceHashOnly({required this.hash});
  final String hash;

  @override
  Widget build(BuildContext context) {
    final short = hash.length > 20
        ? '${hash.substring(0, 10)}…${hash.substring(hash.length - 8)}'
        : hash;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: NivaraColors.primary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: NivaraColors.primary.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.verified_user, color: NivaraColors.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Tamper-proof evidence',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: NivaraColors.primary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'SHA-256 · $short',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
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

class _PhotoStrip extends StatelessWidget {
  const _PhotoStrip({required this.urls});
  final List<String> urls;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 120,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: urls.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (_, i) => ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.network(
            urls[i],
            width: 120,
            height: 120,
            fit: BoxFit.cover,
            loadingBuilder: (c, child, progress) => progress == null
                ? child
                : Container(
                    width: 120,
                    height: 120,
                    color: scheme.surfaceContainerHighest,
                  ),
            errorBuilder: (c, _, _) => Container(
              width: 120,
              height: 120,
              color: scheme.surfaceContainerHighest,
              child: Icon(Icons.broken_image, color: scheme.outline),
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status});
  final ReportStatus status;

  @override
  Widget build(BuildContext context) {
    final color = statusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        status.label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: 11.5,
        ),
      ),
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

class _MetaRow extends StatelessWidget {
  const _MetaRow(this.label, this.value);
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
            width: 110,
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
