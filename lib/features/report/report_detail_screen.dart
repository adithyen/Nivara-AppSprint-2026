import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../core/supabase_client.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../core/widgets/bouncy_tap.dart';
import '../../models/enums.dart';
import '../../models/report.dart';
import '../admin/status_style.dart';
import '../auth/auth_controller.dart';
import 'category_grid.dart';
import 'evidence_viewer.dart';

/// 2026-Level Flagship Report Detail Screen.
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
    } catch (_) {}
  }

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
      } catch (_) {}
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
      setState(() => _alreadyConfirmed = true);
      await _refresh();
      if (mounted) _snack('Thank you — civic confirmation recorded.');
    } on Object catch (e) {
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sev = severityColor(r.severity);
    final title = r.title?.trim().isNotEmpty == true
        ? r.title!.trim()
        : r.category.label;

    return Scaffold(
      backgroundColor: isDark ? NivaraColors.canvasDark : const Color(0xFFF6F8FA),
      appBar: AppBar(
        title: const Text('Civic Report Detail'),
      ),
      body: RefreshIndicator(
        color: NivaraColors.primary,
        backgroundColor: isDark ? const Color(0xFF10161E) : Colors.white,
        onRefresh: () async {
          await _refresh();
          await _checkConfirmed();
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 32),
          children: [
            // Header card
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF10161E) : Colors.white,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: sev.withValues(alpha: isDark ? 0.35 : 0.45),
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
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: sev.withValues(alpha: 0.16),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(categoryIcon(r.category), color: sev, size: 28),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            color: isDark ? Colors.white : const Color(0xFF0F172A),
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.2,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            _StatusPill(status: r.status),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: sev.withValues(alpha: 0.14),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: sev.withValues(alpha: 0.4)),
                              ),
                              child: Text(
                                r.severity.label,
                                style: TextStyle(
                                  color: sev,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Tamper-proof evidence entry
            if (r.hasEvidence && r.evidencePackage != null) ...[
              _EvidenceTile(
                verified: r.isCommunityVerified,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => EvidenceViewerScreen(package: r.evidencePackage!),
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ] else if (r.hasEvidence) ...[
              _EvidenceHashOnly(hash: r.evidenceHash!),
              const SizedBox(height: 16),
            ],

            // Photo Evidence Strip
            if (r.photoUrls != null && r.photoUrls!.isNotEmpty) ...[
              _PhotoStrip(urls: r.photoUrls!),
              const SizedBox(height: 16),
            ],

            // Community verification card
            _CommunityCard(
              count: r.confirmationCount,
              verified: r.isCommunityVerified,
              isOwn: _isOwn,
              alreadyConfirmed: _alreadyConfirmed,
              confirming: _confirming,
              onConfirm: _confirm,
            ),

            const SizedBox(height: 16),

            // Description
            if (r.description?.trim().isNotEmpty == true) ...[
              _GlassSection(
                title: 'Description',
                child: Text(
                  r.description!.trim(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    height: 1.4,
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Location & Landmark
            _GlassSection(
              title: 'Incident Location',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (r.address?.trim().isNotEmpty == true)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(
                        r.address!.trim(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  Text(
                    'GPS: ${r.lat.toStringAsFixed(5)}, ${r.lng.toStringAsFixed(5)}',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.5),
                      fontSize: 12,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Details metadata
            _GlassSection(
              title: 'Complaint Overview',
              child: Column(
                children: [
                  _MetaRow('Category', r.category.label),
                  _MetaRow('Severity', r.severity.label),
                  _MetaRow(
                    'Source',
                    r.isFromSensor ? 'SensorWatch (passive sensor)' : 'Manual Citizen Report',
                  ),
                  if (r.assignedDepartment != null)
                    _MetaRow('Department', r.assignedDepartment!.label),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Timeline
            _GlassSection(
              title: 'Status Timeline',
              child: Column(
                children: [
                  _MetaRow('Reported At', formatDateTime(r.createdAt)),
                  if (r.acknowledgedAt != null)
                    _MetaRow('Acknowledged', formatDateTime(r.acknowledgedAt!)),
                  if (r.resolvedAt != null)
                    _MetaRow('Resolved', formatDateTime(r.resolvedAt!)),
                ],
              ),
            ),

            if (r.resolutionNotes?.trim().isNotEmpty == true) ...[
              const SizedBox(height: 16),
              _GlassSection(
                title: 'Field Worker Resolution Note',
                child: Text(
                  r.resolutionNotes!.trim(),
                  style: const TextStyle(color: Colors.white70, fontSize: 13.5),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = verified ? NivaraColors.success : NivaraColors.primary;
    final remaining = (5 - count).clamp(0, 5);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF10161E) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: accent.withValues(alpha: isDark ? 0.35 : 0.45), width: 1.2),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.16),
                  shape: BoxShape.circle,
                ),
                child: Icon(verified ? Icons.verified_rounded : Icons.groups_rounded, color: accent, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  verified
                      ? 'Community-Verified Issue'
                      : '$count Citizen${count == 1 ? '' : 's'} Confirmed',
                  style: TextStyle(
                    color: accent,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: accent.withValues(alpha: 0.6)),
                ),
                child: Text(
                  '$count / 5',
                  style: TextStyle(
                    color: accent,
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            verified
                ? 'Enough citizens have confirmed this report. Prioritized in municipal dispatch.'
                : isOwn
                    ? 'This is your report. Other citizens in your ward can confirm it.'
                    : remaining > 0
                        ? '$remaining more confirmation${remaining == 1 ? '' : 's'} needed for community-verified badge.'
                        : 'Awaiting municipal verification.',
            style: TextStyle(
              color: isDark ? Colors.white.withValues(alpha: 0.6) : const Color(0xFF64748B),
              fontSize: 12.5,
            ),
          ),
          const SizedBox(height: 14),
          _ConfirmButton(
            isOwn: isOwn,
            alreadyConfirmed: alreadyConfirmed,
            confirming: confirming,
            onConfirm: onConfirm,
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (isOwn) {
      return Container(
        height: 46,
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withValues(alpha: 0.06) : const Color(0xFFE2E8F0),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Center(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.person_outline_rounded, size: 18, color: isDark ? Colors.white60 : const Color(0xFF64748B)),
              const SizedBox(width: 8),
              Text(
                'You filed this report',
                style: TextStyle(
                  color: isDark ? Colors.white70 : const Color(0xFF475569),
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      );
    }
    if (alreadyConfirmed) {
      return Container(
        height: 46,
        decoration: BoxDecoration(
          color: NivaraColors.success.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: NivaraColors.success.withValues(alpha: 0.45)),
        ),
        child: const Center(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.check_circle_rounded, color: NivaraColors.success, size: 18),
              SizedBox(width: 8),
              Text('You Confirmed This Issue', style: TextStyle(color: NivaraColors.success, fontWeight: FontWeight.w800, fontSize: 13)),
            ],
          ),
        ),
      );
    }
    return BouncyTap(
      onTap: confirming ? null : onConfirm,
      child: Container(
        height: 46,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF00E676), Color(0xFF00B0FF)],
          ),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF00E676).withValues(alpha: 0.35),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Center(
          child: confirming
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                )
              : const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.thumb_up_alt_rounded, color: Colors.black, size: 18),
                    SizedBox(width: 8),
                    Text(
                      'I Saw This Too (Confirm)',
                      style: TextStyle(color: Colors.black, fontWeight: FontWeight.w900, fontSize: 14),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _EvidenceTile extends StatelessWidget {
  const _EvidenceTile({required this.verified, required this.onTap});
  final bool verified;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return BouncyTap(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF10161E) : Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: NivaraColors.primary.withValues(alpha: isDark ? 0.35 : 0.5),
            width: 1.2,
          ),
          boxShadow: isDark
              ? null
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.03),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
        ),
        child: Row(
          children: [
            const Icon(Icons.verified_user_rounded, color: NivaraColors.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Tamper-Proof Evidence Record',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: NivaraColors.primary,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'SHA-256 sensor snapshot · tap to verify integrity',
                    style: TextStyle(
                      color: isDark ? Colors.white60 : const Color(0xFF64748B),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: NivaraColors.primary),
          ],
        ),
      ),
    );
  }
}

class _EvidenceHashOnly extends StatelessWidget {
  const _EvidenceHashOnly({required this.hash});
  final String hash;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final short = hash.length > 20
        ? '${hash.substring(0, 10)}…${hash.substring(hash.length - 8)}'
        : hash;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF10161E) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: isDark ? Colors.white.withValues(alpha: 0.1) : const Color(0xFFCBD5E1)),
      ),
      child: Row(
        children: [
          const Icon(Icons.verified_user_rounded, color: NivaraColors.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Tamper-Proof Evidence Record',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: NivaraColors.primary,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'SHA-256 · $short',
                  style: TextStyle(
                    fontFamily: 'monospace',
                    color: isDark ? Colors.white60 : const Color(0xFF64748B),
                    fontSize: 12,
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SizedBox(
      height: 120,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: urls.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (_, i) => ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Image.network(
            urls[i],
            width: 120,
            height: 120,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) => Container(
              width: 120,
              height: 120,
              color: isDark ? const Color(0xFF10161E) : const Color(0xFFE2E8F0),
              child: Icon(Icons.broken_image_rounded, color: isDark ? Colors.white38 : const Color(0xFF94A3B8)),
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
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        status.label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w800,
          fontSize: 11,
        ),
      ),
    );
  }
}

class _GlassSection extends StatelessWidget {
  const _GlassSection({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF10161E) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: isDark ? Colors.white.withValues(alpha: 0.08) : const Color(0xFFE2E8F0)),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: isDark ? Colors.white.withValues(alpha: 0.6) : const Color(0xFF64748B),
              fontSize: 12,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 10),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: TextStyle(
                color: isDark ? Colors.white.withValues(alpha: 0.55) : const Color(0xFF64748B),
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.white : const Color(0xFF0F172A),
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
