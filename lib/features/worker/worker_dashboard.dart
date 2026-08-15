import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants.dart';
import '../../core/supabase_client.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../models/enums.dart';
import '../../models/report.dart';
import '../../router.dart';
import '../admin/status_style.dart';
import '../../core/widgets/bouncy_tap.dart';
import '../report/category_grid.dart';

/// The field worker's task list — body-only widget used inside [WorkerShell].
/// Shows only the reports assigned to this worker, fetched once then kept
/// live via a filtered Realtime stream. Tapping a task opens the detail screen.
class WorkerDashboard extends ConsumerStatefulWidget {
  const WorkerDashboard({super.key});

  @override
  ConsumerState<WorkerDashboard> createState() => _WorkerDashboardState();
}

class _WorkerDashboardState extends ConsumerState<WorkerDashboard> {
  final _tasks = <String, Report>{};
  StreamSubscription? _sub;
  bool _loaded = false;
  String? _error;
  String _filterKey = 'todo';

  String? get _uid => supabase.auth.currentUser?.id;

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
    final uid = _uid;
    if (uid == null) {
      setState(() => _loaded = true);
      return;
    }
    try {
      final rows = await supabase
          .from(kTableReports)
          .select()
          .eq('assigned_to', uid)
          .order('created_at', ascending: false);
      for (final r in rows) {
        try {
          final report = Report.fromMap(r);
          _tasks[report.id] = report;
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
    _subscribe(uid);
  }

  void _subscribe(String uid) {
    _sub = supabase
        .from(kTableReports)
        .stream(primaryKey: ['id'])
        .eq('assigned_to', uid)
        .listen(
          (rows) {
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
                _tasks
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

  _WorkerFilter get _selected => _kWorkerFilters.firstWhere(
    (f) => f.key == _filterKey,
    orElse: () => _kWorkerFilters.first,
  );

  List<Report> get _visible {
    final list = _tasks.values.where(_selected.test).toList()
      ..sort((a, b) {
        final byEmergency = (b.severity == Severity.emergency ? 1 : 0)
            .compareTo(a.severity == Severity.emergency ? 1 : 0);
        if (byEmergency != 0) return byEmergency;
        return b.createdAt.compareTo(a.createdAt);
      });
    return list;
  }

  Future<void> _openTask(Report r) async {
    final updated = await context.push<Report>(Routes.workerTask, extra: r);
    if (updated != null && mounted) {
      setState(() => _tasks[updated.id] = updated);
    }
  }


  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _FilterBar(
          tasks: _tasks.values,
          selectedKey: _filterKey,
          onSelect: (k) => setState(() => _filterKey = k),
        ),
        const SizedBox(height: 4),
        Expanded(child: _buildList()),
      ],
    );
  }

  Widget _buildList() {
    if (!_loaded) return const Center(child: CircularProgressIndicator());
    if (_error != null && _tasks.isEmpty) {
      return _Empty(
        icon: Icons.cloud_off,
        title: 'Could not load your tasks',
        subtitle: '$_error',
      );
    }
    final items = _visible;
    if (items.isEmpty) {
      return _Empty(
        icon: Icons.task_alt,
        title: _filterKey == 'todo' ? 'Nothing to do' : 'Nothing here',
        subtitle: _filterKey == 'todo'
            ? 'Tasks an official assigns to you show up here.'
            : 'No tasks match this filter yet.',
      );
    }
    return RefreshIndicator(
      color: NivaraColors.primary,
      backgroundColor: const Color(0xFF10161E),
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 110),
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (_, i) =>
            _TaskCard(report: items[i], onTap: () => _openTask(items[i])),
      ),
    );
  }
}

/// A worker-side filter: a label, colour, and the predicate that both counts
/// and narrows the task list.
class _WorkerFilter {
  const _WorkerFilter(this.key, this.label, this.color, this.test);
  final String key;
  final String label;
  final Color color;
  final bool Function(Report) test;
}

final List<_WorkerFilter> _kWorkerFilters = [
  _WorkerFilter(
    'todo',
    'To do',
    NivaraColors.accent,
    (r) => r.isOpen && r.status != ReportStatus.inProgress,
  ),
  _WorkerFilter(
    'progress',
    'In progress',
    NivaraColors.primary,
    (r) => r.status == ReportStatus.inProgress,
  ),
  _WorkerFilter('done', 'Done', NivaraColors.success, (r) => !r.isOpen),
  _WorkerFilter('all', 'All', Colors.blueGrey, (_) => true),
];

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.tasks,
    required this.selectedKey,
    required this.onSelect,
  });

  final Iterable<Report> tasks;
  final String selectedKey;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        children: [
          for (final f in _kWorkerFilters)
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: _Pill(
                label: f.label,
                count: tasks.where(f.test).length,
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

class _Pill extends StatelessWidget {
  const _Pill({
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

class _TaskCard extends StatelessWidget {
  const _TaskCard({required this.report, required this.onTap});
  final Report report;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sev = severityColor(report.severity);
    final title = report.title?.trim().isNotEmpty == true
        ? report.title!.trim()
        : report.category.label;

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
              color: Colors.black.withValues(alpha: isDark ? 0.15 : 0.03),
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
                          color: isDark ? Colors.white : const Color(0xFF111827),
                          fontWeight: FontWeight.w700,
                          fontSize: 14.5,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${report.category.label} · ${report.severity.label}',
                        style: TextStyle(
                          color: isDark ? Colors.white.withValues(alpha: 0.55) : const Color(0xFF6B7280),
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
                  Icons.place_outlined,
                  size: 14,
                  color: isDark ? Colors.white60 : const Color(0xFF6B7280),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    report.address?.trim().isNotEmpty == true
                        ? report.address!.trim()
                        : '${report.lat.toStringAsFixed(4)}, ${report.lng.toStringAsFixed(4)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isDark ? Colors.white.withValues(alpha: 0.6) : const Color(0xFF6B7280),
                      fontSize: 12,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  timeAgo(report.createdAt),
                  style: TextStyle(
                    color: isDark ? Colors.white.withValues(alpha: 0.4) : const Color(0xFF9CA3AF),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
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
