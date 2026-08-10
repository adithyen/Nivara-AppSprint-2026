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
/// Realtime is off), then subscribes for live updates. A single row of metric
/// pills doubles as the live counts *and* the filter — tapping one narrows the
/// list. Tapping a report opens the detail screen where staff advance status.
class AdminQueue extends StatefulWidget {
  const AdminQueue({super.key});

  @override
  State<AdminQueue> createState() => _AdminQueueState();
}

class _AdminQueueState extends State<AdminQueue> {
  final _reports = <String, Report>{};
  StreamSubscription? _sub;
  bool _loaded = false;
  String? _error;
  String _filterKey = 'open'; // key into _kQueueFilters; 'open' is the default

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

  _QueueFilter get _selectedFilter => _kQueueFilters.firstWhere(
    (f) => f.key == _filterKey,
    orElse: () => _kQueueFilters.first,
  );

  List<Report> get _visible {
    final list = _reports.values.where(_selectedFilter.test).toList()
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
        _MetricFilterBar(
          reports: _reports.values,
          selectedKey: _filterKey,
          onSelect: (k) => setState(() => _filterKey = k),
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
      final isOpenDefault = _filterKey == 'open';
      return _Empty(
        icon: Icons.inbox,
        title: isOpenDefault ? 'Queue is clear' : 'Nothing in this view',
        subtitle: isOpenDefault
            ? 'No open reports right now. New citizen reports appear here live.'
            : 'No reports match this filter yet.',
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

/// One filter option: a label, an accent colour, and the predicate that both
/// counts matching reports (the pill's number) and narrows the list when
/// selected. Order defines the pill row, left to right.
class _QueueFilter {
  const _QueueFilter(this.key, this.label, this.color, this.test);
  final String key;
  final String label;
  final Color color;
  final bool Function(Report) test;
}

final List<_QueueFilter> _kQueueFilters = [
  _QueueFilter('open', 'Open', NivaraColors.accent, (r) => r.isOpen),
  _QueueFilter(
    'new',
    'New',
    NivaraColors.accent,
    (r) => r.status == ReportStatus.submitted,
  ),
  _QueueFilter(
    'ack',
    'Acknowledged',
    NivaraColors.primary,
    (r) => r.status == ReportStatus.acknowledged,
  ),
  _QueueFilter(
    'progress',
    'In progress',
    NivaraColors.primary,
    (r) => r.status == ReportStatus.inProgress,
  ),
  _QueueFilter(
    'resolved',
    'Resolved',
    NivaraColors.success,
    (r) => r.status == ReportStatus.resolved,
  ),
  _QueueFilter(
    'emergency',
    'Emergency',
    NivaraColors.danger,
    (r) => r.severity == Severity.emergency && r.isOpen,
  ),
  _QueueFilter('all', 'All', Colors.blueGrey, (_) => true),
];

/// The one control at the top of the queue: live counts that are *also* the
/// filter. Each pill shows how many reports match and, when tapped, filters the
/// list to them. This replaces the old split of a (non-interactive) stats strip
/// above a separate chip row with the same labels.
class _MetricFilterBar extends StatelessWidget {
  const _MetricFilterBar({
    required this.reports,
    required this.selectedKey,
    required this.onSelect,
  });

  final Iterable<Report> reports;
  final String selectedKey;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        children: [
          for (final f in _kQueueFilters)
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: _MetricPill(
                label: f.label,
                count: reports.where(f.test).length,
                color: f.color,
                selected: f.key == selectedKey,
                onTap: () => onSelect(f.key),
              ),
            ),
        ],
      ),
    );
  }
}

class _MetricPill extends StatelessWidget {
  const _MetricPill({
    required this.label,
    required this.count,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int count;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bg = selected ? color : color.withValues(alpha: 0.12);
    final fg = selected ? Colors.white : color;
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          constraints: const BoxConstraints(minWidth: 76),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$count',
                style: TextStyle(
                  color: fg,
                  fontWeight: FontWeight.w800,
                  fontSize: 20,
                ),
              ),
              Text(
                label,
                style: TextStyle(
                  color: fg,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
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
