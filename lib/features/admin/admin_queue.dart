import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants.dart';
import '../../core/supabase_client.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../models/enums.dart';
import '../../models/report.dart';
import '../../router.dart';
import '../report/category_grid.dart';
import 'status_style.dart';

/// The municipal report queue. Fetches `reports` once (so it populates even if
/// Realtime is off), then subscribes for live updates. Filter by status;
/// tapping a report opens the detail screen where staff advance its status.
class AdminQueue extends StatefulWidget {
  const AdminQueue({super.key});

  @override
  State<AdminQueue> createState() => _AdminQueueState();
}

/// null = "Open" (everything still needing attention); otherwise an exact status.
class _AdminQueueState extends State<AdminQueue> {
  final _reports = <String, Report>{};
  StreamSubscription? _sub;
  bool _loaded = false;
  String? _error;
  ReportStatus? _statusFilter; // null → open bucket
  bool _allStatuses = false; // "All" chip overrides the open bucket

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final rows = await supabase
          .from(kTableReports)
          .select()
          .order('created_at', ascending: false);
      for (final r in rows) {
        try {
          final report = Report.fromMap(r);
          _reports[report.id] = report;
        } catch (_) {
          /* skip malformed row */
        }
      }
      if (mounted) setState(() => _loaded = true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _loaded = true;
          _error = '$e';
        });
      }
    }
    _subscribe();
  }

  void _subscribe() {
    _sub = supabase
        .from(kTableReports)
        .stream(primaryKey: ['id'])
        .order('created_at')
        .listen(
          (rows) {
            // A stream event carries the full matching set — rebuild wholesale so
            // status changes and removals are reflected exactly.
            final next = <String, Report>{};
            for (final r in rows) {
              try {
                final report = Report.fromMap(r);
                next[report.id] = report;
              } catch (_) {
                /* skip malformed row */
              }
            }
            if (mounted) {
              setState(() {
                _reports
                  ..clear()
                  ..addAll(next);
                _error = null;
              });
            }
          },
          onError: (_) {
            /* Realtime off — keep the fetched rows */
          },
        );
  }

  List<Report> get _visible {
    bool match(Report r) {
      if (_allStatuses) return true;
      if (_statusFilter != null) return r.status == _statusFilter;
      return r.isOpen; // default "Open" bucket
    }

    final list = _reports.values.where(match).toList()
      ..sort((a, b) {
        // Emergencies bubble up, then most recent first.
        final byEmergency = _emergencyRank(b).compareTo(_emergencyRank(a));
        if (byEmergency != 0) return byEmergency;
        return b.createdAt.compareTo(a.createdAt);
      });
    return list;
  }

  int _emergencyRank(Report r) => r.severity == Severity.emergency ? 1 : 0;

  Future<void> _openDetail(Report r) async {
    final updated = await context.push<Report>(
      Routes.adminReportDetail,
      extra: r,
    );
    // If Realtime is off, fold the RPC's returned row back in so the queue
    // reflects the new status immediately.
    if (updated != null && mounted) {
      setState(() => _reports[updated.id] = updated);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _StatsStrip(reports: _reports.values),
        _FilterBar(
          allStatuses: _allStatuses,
          statusFilter: _statusFilter,
          onSelect: (all, status) => setState(() {
            _allStatuses = all;
            _statusFilter = status;
          }),
        ),
        const SizedBox(height: 4),
        Expanded(child: _buildList()),
      ],
    );
  }

  Widget _buildList() {
    if (!_loaded) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _reports.isEmpty) {
      return _Empty(
        icon: Icons.cloud_off,
        title: 'Could not load the queue',
        subtitle: '$_error',
      );
    }
    final items = _visible;
    if (items.isEmpty) {
      return _Empty(
        icon: Icons.inbox,
        title: _allStatuses || _statusFilter != null
            ? 'Nothing in this view'
            : 'Queue is clear',
        subtitle: _allStatuses || _statusFilter != null
            ? 'No reports match this filter yet.'
            : 'No open reports right now. New citizen reports appear here live.',
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (_, i) =>
            _QueueCard(report: items[i], onTap: () => _openDetail(items[i])),
      ),
    );
  }
}

class _StatsStrip extends StatelessWidget {
  const _StatsStrip({required this.reports});
  final Iterable<Report> reports;

  @override
  Widget build(BuildContext context) {
    var open = 0, progress = 0, resolved = 0, emergency = 0;
    for (final r in reports) {
      if (r.isOpen) open++;
      if (r.status == ReportStatus.inProgress) progress++;
      if (r.status == ReportStatus.resolved) resolved++;
      if (r.severity == Severity.emergency && r.isOpen) emergency++;
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        children: [
          _Stat(label: 'Open', value: open, color: NivaraColors.accent),
          _Stat(
            label: 'In progress',
            value: progress,
            color: NivaraColors.primary,
          ),
          _Stat(
            label: 'Resolved',
            value: resolved,
            color: NivaraColors.success,
          ),
          _Stat(
            label: 'Emergency',
            value: emergency,
            color: NivaraColors.danger,
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, required this.color});
  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(right: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$value',
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w800,
              fontSize: 20,
            ),
          ),
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.allStatuses,
    required this.statusFilter,
    required this.onSelect,
  });

  final bool allStatuses;
  final ReportStatus? statusFilter;
  final void Function(bool allStatuses, ReportStatus? status) onSelect;

  @override
  Widget build(BuildContext context) {
    Widget chip(String label, {bool all = false, ReportStatus? status}) {
      final selected = all
          ? allStatuses
          : (!allStatuses && statusFilter == status);
      return Padding(
        padding: const EdgeInsets.only(right: 6),
        child: ChoiceChip(
          label: Text(label),
          selected: selected,
          visualDensity: VisualDensity.compact,
          onSelected: (_) => onSelect(all, status),
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          chip('Open'), // all=false, status=null
          chip('Submitted', status: ReportStatus.submitted),
          chip('Acknowledged', status: ReportStatus.acknowledged),
          chip('In Progress', status: ReportStatus.inProgress),
          chip('Resolved', status: ReportStatus.resolved),
          chip('All', all: true),
        ],
      ),
    );
  }
}

class _QueueCard extends StatelessWidget {
  const _QueueCard({required this.report, required this.onTap});
  final Report report;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final sev = severityColor(report.severity);
    final title = report.title?.trim().isNotEmpty == true
        ? report.title!.trim()
        : report.category.label;
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: sev.withValues(alpha: 0.15),
                    child: Icon(categoryIcon(report.category), color: sev),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${report.category.label} · ${report.severity.label}',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  StatusChip(report.status, dense: true),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(
                    report.isFromSensor ? Icons.radar : Icons.edit_note,
                    size: 15,
                    color: scheme.outline,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    report.isFromSensor ? 'SensorWatch' : 'Manual',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  if (report.hasEvidence) ...[
                    const SizedBox(width: 8),
                    Icon(
                      Icons.verified_user,
                      size: 15,
                      color: NivaraColors.primary,
                    ),
                    const SizedBox(width: 2),
                    Text(
                      'Evidence',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: NivaraColors.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  if (report.confirmationCount > 0) ...[
                    const SizedBox(width: 8),
                    Icon(Icons.group, size: 15, color: scheme.outline),
                    const SizedBox(width: 2),
                    Text(
                      '${report.confirmationCount}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                  const Spacer(),
                  Text(
                    timeAgo(report.createdAt),
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: scheme.outline),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({
    required this.icon,
    required this.title,
    required this.subtitle,
  });
  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.all(32),
      children: [
        const SizedBox(height: 60),
        Icon(icon, size: 56, color: scheme.outline),
        const SizedBox(height: 12),
        Text(
          title,
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}
