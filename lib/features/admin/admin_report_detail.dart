import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/supabase_client.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../models/enums.dart';
import '../../models/report.dart';
import '../report/category_grid.dart';
import 'status_style.dart';

/// Municipal detail view for a single report. Staff read the full context —
/// evidence, photos, location, community confirmations — and advance the
/// status (Acknowledged → In Progress → Resolved) through the
/// `admin_set_report_status` RPC, which enforces the admin role server-side and
/// writes the audit trail. Pops the updated [Report] back to the queue.
class AdminReportDetailScreen extends StatefulWidget {
  const AdminReportDetailScreen({super.key, required this.report});

  final Report report;

  @override
  State<AdminReportDetailScreen> createState() =>
      _AdminReportDetailScreenState();
}

class _AdminReportDetailScreenState extends State<AdminReportDetailScreen> {
  late Report _report = widget.report;
  bool _working = false;

  /// The status transitions offered from the current status.
  List<_Action> get _actions {
    switch (_report.status) {
      case ReportStatus.submitted:
        return const [
          _Action(ReportStatus.acknowledged, 'Acknowledge', Icons.visibility),
          _Action(
            ReportStatus.inProgress,
            'Start work',
            Icons.engineering,
            primary: true,
          ),
        ];
      case ReportStatus.acknowledged:
        return const [
          _Action(
            ReportStatus.inProgress,
            'Start work',
            Icons.engineering,
            primary: true,
          ),
        ];
      case ReportStatus.inProgress:
        return const [
          _Action(
            ReportStatus.resolved,
            'Mark resolved',
            Icons.check_circle,
            primary: true,
          ),
        ];
      case ReportStatus.resolved:
      case ReportStatus.closed:
      case ReportStatus.duplicate:
        return const [];
    }
  }

  Future<void> _apply(ReportStatus target) async {
    // Resolving asks for an optional note; other transitions are one-tap.
    String? note;
    if (target == ReportStatus.resolved) {
      note = await _promptNote();
      if (note == null) return; // cancelled
    }

    setState(() => _working = true);
    try {
      final res = await supabase.rpc(
        'admin_set_report_status',
        params: {
          'p_report_id': _report.id,
          'p_new_status': target.wire,
          if (note != null && note.trim().isNotEmpty) 'p_note': note.trim(),
        },
      );
      final row = res is List ? res.first : res;
      final updated = Report.fromMap(row as Map<String, dynamic>);
      if (!mounted) return;
      setState(() {
        _report = updated;
        _working = false;
      });
      _snack('Marked ${target.label}.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _working = false);
      _snack('Could not update: $e');
    }
  }

  Future<String?> _promptNote() {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Resolve report'),
        content: TextField(
          controller: ctrl,
          maxLines: 3,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Resolution note (optional)',
            hintText: 'What was done to fix it?',
            alignLabelWithHint: true,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            child: const Text('Mark resolved'),
          ),
        ],
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
    final r = _report;
    final scheme = Theme.of(context).colorScheme;
    final title = r.title?.trim().isNotEmpty == true
        ? r.title!.trim()
        : r.category.label;
    return Scaffold(
      appBar: AppBar(title: const Text('Report detail')),
      // Return the (possibly updated) report to the queue so it reflects the
      // new status even when Realtime is off. canPop:false lets us intercept
      // the back button / gesture and pop with the result.
      body: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) context.pop(_report);
        },
        child: AbsorbPointer(
          absorbing: _working,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: severityColor(
                      r.severity,
                    ).withValues(alpha: 0.15),
                    child: Icon(
                      categoryIcon(r.category),
                      color: severityColor(r.severity),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 4),
                        StatusChip(r.status),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (r.hasEvidence) _EvidenceCard(report: r),
              if (r.photoUrls != null && r.photoUrls!.isNotEmpty)
                _PhotoStrip(urls: r.photoUrls!),
              if (r.description?.trim().isNotEmpty == true) ...[
                const SizedBox(height: 8),
                _Section(
                  title: 'Description',
                  child: Text(r.description!.trim()),
                ),
              ],
              const SizedBox(height: 8),
              _Section(
                title: 'Details',
                child: Column(
                  children: [
                    _MetaRow('Category', r.category.label),
                    _MetaRow('Severity', r.severity.label),
                    _MetaRow(
                      'Source',
                      r.isFromSensor ? 'SensorWatch (passive)' : 'Manual',
                    ),
                    if (r.assignedDepartment != null)
                      _MetaRow('Department', r.assignedDepartment!.label),
                    _MetaRow('Confirmations', '${r.confirmationCount}'),
                    if (r.isCommunityVerified)
                      _MetaRow('Community', 'Verified by nearby citizens'),
                  ],
                ),
              ),
              const SizedBox(height: 8),
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
              const SizedBox(height: 8),
              _Section(
                title: 'Timeline',
                child: Column(
                  children: [
                    _MetaRow('Reported', formatDateTime(r.createdAt)),
                    if (r.acknowledgedAt != null)
                      _MetaRow(
                        'Acknowledged',
                        formatDateTime(r.acknowledgedAt!),
                      ),
                    if (r.resolvedAt != null)
                      _MetaRow('Resolved', formatDateTime(r.resolvedAt!)),
                  ],
                ),
              ),
              if (r.resolutionNotes?.trim().isNotEmpty == true) ...[
                const SizedBox(height: 8),
                _Section(
                  title: 'Resolution note',
                  child: Text(r.resolutionNotes!.trim()),
                ),
              ],
              const SizedBox(height: 20),
              _ActionBar(
                actions: _actions,
                working: _working,
                onApply: _apply,
                resolved: !r.isOpen,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Action {
  const _Action(this.target, this.label, this.icon, {this.primary = false});
  final ReportStatus target;
  final String label;
  final IconData icon;
  final bool primary;
}

class _ActionBar extends StatelessWidget {
  const _ActionBar({
    required this.actions,
    required this.working,
    required this.onApply,
    required this.resolved,
  });

  final List<_Action> actions;
  final bool working;
  final ValueChanged<ReportStatus> onApply;
  final bool resolved;

  @override
  Widget build(BuildContext context) {
    if (actions.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: NivaraColors.success.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            const Icon(Icons.check_circle, color: NivaraColors.success),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                resolved
                    ? 'This report is closed out. No further action needed.'
                    : 'No actions available.',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      );
    }
    return Column(
      children: [
        for (final a in actions)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: a.primary
                ? FilledButton.icon(
                    onPressed: working ? null : () => onApply(a.target),
                    icon: working
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Colors.white,
                            ),
                          )
                        : Icon(a.icon),
                    label: Text(a.label),
                  )
                : OutlinedButton.icon(
                    onPressed: working ? null : () => onApply(a.target),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                    ),
                    icon: Icon(a.icon),
                    label: Text(a.label),
                  ),
          ),
      ],
    );
  }
}

class _EvidenceCard extends StatelessWidget {
  const _EvidenceCard({required this.report});
  final Report report;

  @override
  Widget build(BuildContext context) {
    final hash = report.evidenceHash ?? '';
    final short = hash.length > 20
        ? '${hash.substring(0, 10)}…${hash.substring(hash.length - 8)}'
        : hash;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
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
                    color: Theme.of(c).colorScheme.surfaceContainerHighest,
                    child: const Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  ),
            errorBuilder: (c, _, _) => Container(
              width: 120,
              height: 120,
              color: Theme.of(c).colorScheme.surfaceContainerHighest,
              child: Icon(
                Icons.broken_image,
                color: Theme.of(c).colorScheme.outline,
              ),
            ),
          ),
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
