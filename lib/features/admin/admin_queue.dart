import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants.dart';
import '../../core/supabase_client.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../core/widgets/bouncy_tap.dart';
import '../../models/enums.dart';
import '../../models/report.dart';
import '../../router.dart';
import '../report/category_grid.dart';
import '../worker/worker_repo.dart';
import 'status_style.dart';

/// The municipal report queue. Fetches `reports` once (so it populates even if
/// Realtime is off), then subscribes for live updates. A row of metric pills
/// doubles as the live counts *and* the status filter; below it, power tools let
/// staff search, filter by department, and re-sort. Assigned worker names are
/// resolved in the background and shown on each card. Tapping a report opens the
/// detail screen where staff advance status.
class AdminQueue extends StatefulWidget {
  const AdminQueue({super.key});

  @override
  State<AdminQueue> createState() => _AdminQueueState();
}

class _AdminQueueState extends State<AdminQueue> {
  final _reports = <String, Report>{};
  final _assigneeNames = <String, String>{}; // user id → display name
  final _searchCtrl = TextEditingController();
  StreamSubscription? _sub;
  bool _loaded = false;
  String? _error;
  String _filterKey = 'open'; // key into _kQueueFilters; 'open' is the default
  AdminDepartment? _dept; // department filter; null = all departments
  _QueueSort _sort = _QueueSort.smart;

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() => setState(() {}));
    _load();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _searchCtrl.dispose();
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
    _resolveAssignees();
    _subscribe();
  }

  /// Look up display names for every assigned worker so cards can show who's on
  /// it. Best-effort — a failure just leaves the assignee chip off.
  Future<void> _resolveAssignees() async {
    final ids = _reports.values
        .map((r) => r.assignedTo)
        .whereType<String>()
        .where((id) => !_assigneeNames.containsKey(id))
        .toSet();
    if (ids.isEmpty) return;
    try {
      final names = await WorkerRepo.displayNamesByIds(ids);
      if (mounted) setState(() => _assigneeNames.addAll(names));
    } catch (_) {
      /* leave assignee names unresolved */
    }
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
              _resolveAssignees();
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

  /// Departments actually present in the queue, for the filter dropdown.
  List<AdminDepartment> get _departmentsInUse {
    final set = <AdminDepartment>{};
    for (final r in _reports.values) {
      if (r.assignedDepartment != null) set.add(r.assignedDepartment!);
    }
    final list = set.toList()..sort((a, b) => a.label.compareTo(b.label));
    return list;
  }

  bool _matchesSearch(Report r) {
    final q = _searchCtrl.text.trim().toLowerCase();
    if (q.isEmpty) return true;
    final assignee = r.assignedTo == null
        ? ''
        : (_assigneeNames[r.assignedTo] ?? '');
    final hay = [
      r.title ?? '',
      r.category.label,
      r.address ?? '',
      r.city ?? '',
      r.ward ?? '',
      assignee,
    ].join(' ').toLowerCase();
    return hay.contains(q);
  }

  List<Report> get _visible {
    final list = _reports.values.where((r) {
      if (!_selectedFilter.test(r)) return false;
      if (_dept != null && r.assignedDepartment != _dept) return false;
      if (!_matchesSearch(r)) return false;
      return true;
    }).toList()..sort(_sort.compare);
    return list;
  }

  Future<void> _openDetail(Report r) async {
    final updated = await context.push<Report>(
      Routes.adminReportDetail,
      extra: r,
    );
    // If Realtime is off, fold the RPC's returned row back in so the queue
    // reflects the new status immediately.
    if (updated != null && mounted) {
      setState(() => _reports[updated.id] = updated);
      _resolveAssignees();
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
        _PowerTools(
          controller: _searchCtrl,
          dept: _dept,
          departments: _departmentsInUse,
          sort: _sort,
          onDept: (d) => setState(() => _dept = d),
          onSort: (s) => setState(() => _sort = s),
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
      final filtered = _searchCtrl.text.trim().isNotEmpty || _dept != null;
      return _Empty(
        icon: filtered ? Icons.filter_alt_off : Icons.inbox,
        title: filtered
            ? 'No matches'
            : (isOpenDefault ? 'Queue is clear' : 'Nothing in this view'),
        subtitle: filtered
            ? 'No reports match your search and filters.'
            : (isOpenDefault
                  ? 'No open reports right now. New citizen reports appear here live.'
                  : 'No reports match this filter yet.'),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 110),
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (_, i) => _QueueCard(
          report: items[i],
          assigneeName: items[i].assignedTo == null
              ? null
              : _assigneeNames[items[i].assignedTo],
          onTap: () => _openDetail(items[i]),
        ),
      ),
    );
  }
}

/// Sort orders for the queue. `smart` is the default — emergencies first, then
/// most recent — matching the old built-in ordering.
enum _QueueSort {
  smart('Priority'),
  newest('Newest'),
  oldest('Oldest'),
  confirmations('Most confirmed');

  const _QueueSort(this.label);
  final String label;

  int compare(Report a, Report b) => switch (this) {
    _QueueSort.smart =>
      _smartRank(b).compareTo(_smartRank(a)) != 0
          ? _smartRank(b).compareTo(_smartRank(a))
          : b.createdAt.compareTo(a.createdAt),
    _QueueSort.newest => b.createdAt.compareTo(a.createdAt),
    _QueueSort.oldest => a.createdAt.compareTo(b.createdAt),
    _QueueSort.confirmations =>
      b.confirmationCount.compareTo(a.confirmationCount) != 0
          ? b.confirmationCount.compareTo(a.confirmationCount)
          : b.createdAt.compareTo(a.createdAt),
  };

  static int _smartRank(Report r) => r.severity == Severity.emergency ? 1 : 0;
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final f in _kQueueFilters)
            _MetricPill(
              label: f.label,
              count: reports.where(f.test).length,
              color: f.color,
              selected: f.key == selectedKey,
              onTap: () => onSelect(f.key),
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

/// A search box, a department filter, and a sort selector — the queue's power
/// tools, sitting just under the status pills.
class _PowerTools extends StatelessWidget {
  const _PowerTools({
    required this.controller,
    required this.dept,
    required this.departments,
    required this.sort,
    required this.onDept,
    required this.onSort,
  });

  final TextEditingController controller;
  final AdminDepartment? dept;
  final List<AdminDepartment> departments;
  final _QueueSort sort;
  final ValueChanged<AdminDepartment?> onDept;
  final ValueChanged<_QueueSort> onSort;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: Column(
        children: [
          TextField(
            controller: controller,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Search title, category, area, worker…',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: controller.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: controller.clear,
                    ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _FilterDropdown<AdminDepartment?>(
                  icon: Icons.apartment,
                  value: dept,
                  items: [
                    const DropdownMenuItem(
                      value: null,
                      child: Text('All depts'),
                    ),
                    for (final d in departments)
                      DropdownMenuItem(value: d, child: Text(d.label)),
                  ],
                  onChanged: onDept,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _FilterDropdown<_QueueSort>(
                  icon: Icons.sort,
                  value: sort,
                  items: [
                    for (final s in _QueueSort.values)
                      DropdownMenuItem(value: s, child: Text(s.label)),
                  ],
                  onChanged: (s) => onSort(s ?? _QueueSort.smart),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A compact, boxed dropdown used for the department + sort selectors.
class _FilterDropdown<T> extends StatelessWidget {
  const _FilterDropdown({
    required this.icon,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final IconData icon;
  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: scheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<T>(
                value: value,
                isExpanded: true,
                isDense: true,
                items: items,
                onChanged: onChanged,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _QueueCard extends StatelessWidget {
  const _QueueCard({
    required this.report,
    required this.assigneeName,
    required this.onTap,
  });
  final Report report;
  final String? assigneeName;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sev = severityColor(report.severity);
    final title = report.title?.trim().isNotEmpty == true
        ? report.title!.trim()
        : report.category.label;
    final primaryText = isDark ? Colors.white : const Color(0xFF0F172A);
    final secondaryText = isDark ? Colors.white.withValues(alpha: 0.55) : const Color(0xFF64748B);
    final iconMuted = isDark ? Colors.white60 : const Color(0xFF64748B);
    final timeColor = isDark ? Colors.white.withValues(alpha: 0.4) : const Color(0xFF94A3B8);

    return BouncyTap(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF10161E) : Colors.white,
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: sev.withValues(alpha: isDark ? 0.16 : 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(categoryIcon(report.category), color: sev, size: 20),
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
                        style: TextStyle(
                          color: primaryText,
                          fontWeight: FontWeight.w700,
                          fontSize: 14.5,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${report.category.label} · ${report.severity.label}',
                        style: TextStyle(
                          color: secondaryText,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                StatusChip(report.status, dense: true),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(
                  report.isFromSensor ? Icons.radar_rounded : Icons.edit_note_rounded,
                  size: 15,
                  color: iconMuted,
                ),
                const SizedBox(width: 4),
                Text(
                  report.isFromSensor ? 'SensorWatch' : 'Manual',
                  style: TextStyle(
                    color: secondaryText,
                    fontSize: 12,
                  ),
                ),
                if (report.hasEvidence) ...[
                  const SizedBox(width: 8),
                  const Icon(
                    Icons.verified_user_rounded,
                    size: 15,
                    color: NivaraColors.primary,
                  ),
                  const SizedBox(width: 3),
                  const Text(
                    'Evidence',
                    style: TextStyle(
                      color: NivaraColors.primary,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ],
                if (report.confirmationCount > 0) ...[
                  const SizedBox(width: 8),
                  Icon(Icons.group_rounded, size: 15, color: iconMuted),
                  const SizedBox(width: 3),
                  Text(
                    '${report.confirmationCount}',
                    style: TextStyle(
                      color: secondaryText,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                const Spacer(),
                Text(
                  timeAgo(report.createdAt),
                  style: TextStyle(
                    color: timeColor,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
            if (report.assignedTo != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(
                    Icons.engineering_rounded,
                    size: 15,
                    color: NivaraColors.primary,
                  ),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      'Assigned · ${assigneeName ?? 'worker'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: NivaraColors.primary,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
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
