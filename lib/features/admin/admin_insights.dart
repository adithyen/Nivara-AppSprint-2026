import 'package:flutter/material.dart';

import '../../core/constants.dart';
import '../../core/supabase_client.dart';
import '../../core/theme.dart';
import '../../models/enums.dart';
import '../../models/report.dart';
import 'status_style.dart';

/// **Insights** — a live analytics view over every report in the system:
/// headline counts, how the queue is doing (resolution rate + average time to
/// resolve), where reports come from (SensorWatch vs manual), and breakdowns by
/// status, category and department.
///
/// Body-only (the [Scaffold]/[AppBar] belong to the admin shell). Everything is
/// computed client-side from a single fetch — pull-to-refresh re-runs it.
class AdminInsights extends StatefulWidget {
  const AdminInsights({super.key});

  @override
  State<AdminInsights> createState() => _AdminInsightsState();
}

class _AdminInsightsState extends State<AdminInsights> {
  List<Report> _reports = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await supabase
          .from(kTableReports)
          .select()
          .order('created_at', ascending: false);
      final list = <Report>[];
      for (final r in rows) {
        try {
          list.add(Report.fromMap(r));
        } catch (_) {
          /* skip malformed row */
        }
      }
      if (!mounted) return;
      setState(() {
        _reports = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null && _reports.isEmpty) {
      return _CenterMsg(
        icon: Icons.cloud_off,
        title: 'Could not load insights',
        subtitle: '$_error',
        onRetry: _load,
      );
    }
    final m = _Metrics.from(_reports);
    if (m.total == 0) {
      return _CenterMsg(
        icon: Icons.insights,
        title: 'No data yet',
        subtitle: 'Insights appear once citizens start filing reports.',
        onRetry: _load,
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        children: [
          _StatGrid(
            cards: [
              _StatData(
                'Total reports',
                '${m.total}',
                Icons.report,
                NivaraColors.primary,
              ),
              _StatData(
                'Open',
                '${m.open}',
                Icons.pending_actions,
                NivaraColors.accent,
              ),
              _StatData(
                'Resolved',
                '${m.resolved}',
                Icons.check_circle,
                NivaraColors.success,
              ),
              _StatData(
                'Emergencies',
                '${m.emergencyOpen}',
                Icons.warning_amber,
                NivaraColors.danger,
              ),
            ],
          ),
          const SizedBox(height: 16),
          _PerformanceCard(m: m),
          const SizedBox(height: 16),
          _SourceCard(m: m),
          const SizedBox(height: 16),
          _Breakdown(
            title: 'By status',
            icon: Icons.donut_large,
            rows: [
              for (final s in ReportStatus.values)
                if ((m.byStatus[s] ?? 0) > 0)
                  _BarRow(s.label, m.byStatus[s]!, statusColor(s)),
            ],
            total: m.total,
          ),
          const SizedBox(height: 16),
          _Breakdown(
            title: 'Top categories',
            icon: Icons.category_outlined,
            rows: [
              for (final e in m.topCategories)
                _BarRow(e.key.label, e.value, NivaraColors.primary),
            ],
            total: m.total,
          ),
          const SizedBox(height: 16),
          _Breakdown(
            title: 'By department',
            icon: Icons.apartment,
            rows: [
              for (final e in m.byDepartmentSorted)
                _BarRow(
                  e.key?.label ?? 'Unassigned',
                  e.value,
                  e.key == null ? Colors.blueGrey : NivaraColors.primary,
                ),
            ],
            total: m.total,
          ),
        ],
      ),
    );
  }
}

/// All the derived numbers, computed once from the report list.
class _Metrics {
  _Metrics({
    required this.total,
    required this.open,
    required this.resolved,
    required this.emergencyOpen,
    required this.communityVerified,
    required this.fromSensor,
    required this.withEvidence,
    required this.avgResolveMs,
    required this.byStatus,
    required this.topCategories,
    required this.byDepartmentSorted,
  });

  final int total;
  final int open;
  final int resolved;
  final int emergencyOpen;
  final int communityVerified;
  final int fromSensor;
  final int withEvidence;
  final int? avgResolveMs; // null if nothing resolved with timestamps
  final Map<ReportStatus, int> byStatus;
  final List<MapEntry<ReportCategory, int>> topCategories;
  final List<MapEntry<AdminDepartment?, int>> byDepartmentSorted;

  double get resolutionRate => total == 0 ? 0 : resolved / total;
  int get manual => total - fromSensor;

  factory _Metrics.from(List<Report> reports) {
    final byStatus = <ReportStatus, int>{};
    final byCategory = <ReportCategory, int>{};
    final byDept = <AdminDepartment?, int>{};
    var open = 0, resolved = 0, emergencyOpen = 0, verified = 0;
    var sensor = 0, evidence = 0;
    var resolveSum = 0, resolveN = 0;

    for (final r in reports) {
      byStatus.update(r.status, (v) => v + 1, ifAbsent: () => 1);
      byCategory.update(r.category, (v) => v + 1, ifAbsent: () => 1);
      byDept.update(r.assignedDepartment, (v) => v + 1, ifAbsent: () => 1);
      if (r.isOpen) open++;
      if (r.status == ReportStatus.resolved) resolved++;
      if (r.severity == Severity.emergency && r.isOpen) emergencyOpen++;
      if (r.isCommunityVerified) verified++;
      if (r.isFromSensor) sensor++;
      if (r.hasEvidence) evidence++;
      if (r.resolvedAt != null) {
        final ms = r.resolvedAt!.difference(r.createdAt).inMilliseconds;
        if (ms > 0) {
          resolveSum += ms;
          resolveN++;
        }
      }
    }

    final topCats = byCategory.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final depts = byDept.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return _Metrics(
      total: reports.length,
      open: open,
      resolved: resolved,
      emergencyOpen: emergencyOpen,
      communityVerified: verified,
      fromSensor: sensor,
      withEvidence: evidence,
      avgResolveMs: resolveN == 0 ? null : (resolveSum ~/ resolveN),
      byStatus: byStatus,
      topCategories: topCats.take(6).toList(),
      byDepartmentSorted: depts,
    );
  }
}

/// Compact human duration for average time-to-resolve, e.g. "2d 4h", "5h 12m".
String _fmtDuration(int? ms) {
  if (ms == null) return '—';
  final d = Duration(milliseconds: ms);
  if (d.inDays >= 1) {
    final h = d.inHours % 24;
    return h == 0 ? '${d.inDays}d' : '${d.inDays}d ${h}h';
  }
  if (d.inHours >= 1) {
    final m = d.inMinutes % 60;
    return m == 0 ? '${d.inHours}h' : '${d.inHours}h ${m}m';
  }
  if (d.inMinutes >= 1) return '${d.inMinutes}m';
  return '<1m';
}

class _StatData {
  const _StatData(this.label, this.value, this.icon, this.color);
  final String label;
  final String value;
  final IconData icon;
  final Color color;
}

class _StatGrid extends StatelessWidget {
  const _StatGrid({required this.cards});
  final List<_StatData> cards;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.7,
      children: [for (final c in cards) _StatCard(data: c)],
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.data});
  final _StatData data;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF10161E),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: data.color.withValues(alpha: 0.16),
                  shape: BoxShape.circle,
                ),
                child: Icon(data.icon, color: data.color, size: 20),
              ),
              const Spacer(),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                data.value,
                style: TextStyle(
                  color: data.color,
                  fontWeight: FontWeight.w900,
                  fontSize: 26,
                  fontFamily: 'monospace',
                ),
              ),
              Text(
                data.label,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.6),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Resolution rate (as a progress ring-style bar) + average time to resolve.
class _PerformanceCard extends StatelessWidget {
  const _PerformanceCard({required this.m});
  final _Metrics m;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final pct = (m.resolutionRate * 100).round();
    return _Panel(
      title: 'Performance',
      icon: Icons.speed,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '$pct%',
                style: const TextStyle(
                  color: NivaraColors.success,
                  fontWeight: FontWeight.w900,
                  fontSize: 22,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'resolved',
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
              const Spacer(),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _fmtDuration(m.avgResolveMs),
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 18,
                    ),
                  ),
                  Text(
                    'avg. time to resolve',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: m.resolutionRate,
              minHeight: 10,
              backgroundColor: scheme.surfaceContainerHighest,
              valueColor: const AlwaysStoppedAnimation(NivaraColors.success),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${m.resolved} of ${m.total} reports resolved · '
            '${m.communityVerified} community-verified',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

/// SensorWatch vs manual split — the "wow" metric of passive detection.
class _SourceCard extends StatelessWidget {
  const _SourceCard({required this.m});
  final _Metrics m;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      title: 'Where reports come from',
      icon: Icons.sensors,
      child: Column(
        children: [
          _BarLine(
            label: 'SensorWatch (auto)',
            icon: Icons.radar,
            count: m.fromSensor,
            total: m.total,
            color: NivaraColors.primary,
          ),
          const SizedBox(height: 10),
          _BarLine(
            label: 'Manual',
            icon: Icons.edit_note,
            count: m.manual,
            total: m.total,
            color: NivaraColors.accent,
          ),
          const SizedBox(height: 10),
          _BarLine(
            label: 'Tamper-proof evidence',
            icon: Icons.verified_user,
            count: m.withEvidence,
            total: m.total,
            color: NivaraColors.success,
          ),
        ],
      ),
    );
  }
}

class _BarLine extends StatelessWidget {
  const _BarLine({
    required this.label,
    required this.icon,
    required this.count,
    required this.total,
    required this.color,
  });

  final String label;
  final IconData icon;
  final int count;
  final int total;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final frac = total == 0 ? 0.0 : count / total;
    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      label,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                  Text(
                    '$count · ${(frac * 100).round()}%',
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.w700,
                      fontSize: 12.5,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: frac,
                  minHeight: 7,
                  backgroundColor: scheme.surfaceContainerHighest,
                  valueColor: AlwaysStoppedAnimation(color),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _BarRow {
  const _BarRow(this.label, this.count, this.color);
  final String label;
  final int count;
  final Color color;
}

class _Breakdown extends StatelessWidget {
  const _Breakdown({
    required this.title,
    required this.icon,
    required this.rows,
    required this.total,
  });

  final String title;
  final IconData icon;
  final List<_BarRow> rows;
  final int total;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return const SizedBox.shrink();
    final max = rows.map((r) => r.count).reduce((a, b) => a > b ? a : b);
    return _Panel(
      title: title,
      icon: icon,
      child: Column(
        children: [
          for (final r in rows) ...[
            _RankBar(row: r, max: max, total: total),
            if (r != rows.last) const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}

class _RankBar extends StatelessWidget {
  const _RankBar({required this.row, required this.max, required this.total});
  final _BarRow row;
  final int max;
  final int total;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Bar length is relative to the biggest row so small counts stay visible.
    final frac = max == 0 ? 0.0 : row.count / max;
    final pctOfTotal = total == 0 ? 0 : (row.count / total * 100).round();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                row.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
            Text(
              '${row.count}  ·  $pctOfTotal%',
              style: TextStyle(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: frac,
            minHeight: 8,
            backgroundColor: scheme.surfaceContainerHighest,
            valueColor: AlwaysStoppedAnimation(row.color),
          ),
        ),
      ],
    );
  }
}

/// Shared titled container used by the insight sections.
class _Panel extends StatelessWidget {
  const _Panel({required this.title, required this.icon, required this.child});
  final String title;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF10161E),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: NivaraColors.primary),
              const SizedBox(width: 8),
              Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _CenterMsg extends StatelessWidget {
  const _CenterMsg({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onRetry,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return RefreshIndicator(
      onRefresh: () async => onRetry(),
      child: ListView(
        padding: const EdgeInsets.all(32),
        children: [
          const SizedBox(height: 80),
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
          const SizedBox(height: 16),
          Center(
            child: OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ),
        ],
      ),
    );
  }
}
