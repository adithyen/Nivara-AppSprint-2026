import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants.dart';
import '../../core/services/location_service.dart';
import '../../core/supabase_client.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../models/enums.dart';
import '../../models/report.dart';
import '../../router.dart';
import '../admin/status_style.dart';
import '../report/category_grid.dart';

/// The **Pulse** tab — the civic state of the neighbourhood around you.
///
/// Pulls reports within an adjustable radius of the viewer's GPS (default 5 km,
/// 1–100 km) via the `reports_near` PostGIS RPC, tallies them into
/// Open / In-progress / Resolved, and lists the most recent ones with their
/// distance. Changing the radius or pulling to refresh re-runs the query.
class PulseTab extends ConsumerStatefulWidget {
  const PulseTab({super.key});

  @override
  ConsumerState<PulseTab> createState() => _PulseTabState();
}

class _PulseTabState extends ConsumerState<PulseTab> {
  final _location = const LocationService();

  double _radiusKm = 5;
  Position? _pos;
  bool _locating = true;
  bool _loading = true;
  List<Report> _reports = const [];

  double get _lat => _pos?.latitude ?? kDefaultLat;
  double get _lng => _pos?.longitude ?? kDefaultLng;

  int get _openCount => _reports
      .where(
        (r) =>
            r.status == ReportStatus.submitted ||
            r.status == ReportStatus.acknowledged,
      )
      .length;
  int get _inProgressCount =>
      _reports.where((r) => r.status == ReportStatus.inProgress).length;
  int get _resolvedCount =>
      _reports.where((r) => r.status == ReportStatus.resolved).length;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final perm = await _location.ensurePermission();
    Position? pos;
    if (_location.isGranted(perm)) pos = await _location.current();
    if (!mounted) return;
    setState(() {
      _pos = pos;
      _locating = false;
    });
    await _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _loading = true);
    List<Report> reports = const [];
    try {
      final rows = await supabase.rpc(
        'reports_near',
        params: {
          'p_lat': _lat,
          'p_lng': _lng,
          'p_radius_km': _radiusKm,
          'p_limit': 300,
        },
      );
      reports = (rows as List)
          .map((e) => Report.fromMap(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      reports = const [];
    }
    if (!mounted) return;
    setState(() {
      _reports = reports;
      _loading = false;
    });
  }

  Future<void> _refresh() async {
    final perm = await _location.ensurePermission();
    if (_location.isGranted(perm)) {
      final pos = await _location.current();
      if (mounted && pos != null) setState(() => _pos = pos);
    }
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
        children: [
          _RadiusCard(
            radiusKm: _radiusKm,
            locating: _locating,
            usingDefault: _pos == null,
            onChanged: (v) => setState(() => _radiusKm = v),
            onChangeEnd: (_) => _load(),
          ),
          const SizedBox(height: 20),
          _SectionHeader('Issues within ${_radiusKm.round()} km'),
          const SizedBox(height: 10),
          _AreaStatsCard(
            loading: _loading,
            open: _openCount,
            inProgress: _inProgressCount,
            resolved: _resolvedCount,
            total: _reports.length,
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(child: _SectionHeader('Recent in your area')),
              if (_reports.isNotEmpty)
                TextButton(
                  onPressed: () => context.push(Routes.map),
                  child: const Text('View map'),
                ),
            ],
          ),
          const SizedBox(height: 4),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_reports.isEmpty)
            _EmptyArea(radiusKm: _radiusKm)
          else
            ..._reports
                .take(15)
                .map(
                  (r) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _AreaReportTile(
                      report: r,
                      distanceMeters: haversineMeters(
                        _lat,
                        _lng,
                        r.lat,
                        r.lng,
                      ),
                      onTap: () =>
                          context.push(Routes.reportDetail, extra: r),
                    ),
                  ),
                ),
        ],
      ),
    );
  }
}

/// Radius selector: a slider (1–100 km) plus quick presets. Value shown live;
/// the query re-runs on release (or preset tap).
class _RadiusCard extends StatelessWidget {
  const _RadiusCard({
    required this.radiusKm,
    required this.locating,
    required this.usingDefault,
    required this.onChanged,
    required this.onChangeEnd,
  });

  final double radiusKm;
  final bool locating;
  final bool usingDefault;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;

  static const _presets = <double>[1, 5, 10, 25, 50, 100];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.my_location, color: NivaraColors.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  locating
                      ? 'Locating you…'
                      : usingDefault
                      ? 'Using city default location'
                      : 'Around your location',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: NivaraColors.primary.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${radiusKm.round()} km',
                  style: const TextStyle(
                    color: NivaraColors.primary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          Slider(
            value: radiusKm,
            min: 1,
            max: 100,
            divisions: 99,
            label: '${radiusKm.round()} km',
            onChanged: onChanged,
            onChangeEnd: onChangeEnd,
          ),
          Wrap(
            spacing: 8,
            children: [
              for (final p in _presets)
                ChoiceChip(
                  label: Text('${p.round()} km'),
                  selected: radiusKm.round() == p.round(),
                  onSelected: (_) {
                    onChanged(p);
                    onChangeEnd(p);
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Open / In-progress / Resolved tallies for the current radius.
class _AreaStatsCard extends StatelessWidget {
  const _AreaStatsCard({
    required this.loading,
    required this.open,
    required this.inProgress,
    required this.resolved,
    required this.total,
  });

  final bool loading;
  final int open;
  final int inProgress;
  final int resolved;
  final int total;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 18),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Row(
            children: [
              _Stat(
                value: loading ? null : open,
                label: 'Open',
                color: NivaraColors.accent,
              ),
              _Stat(
                value: loading ? null : inProgress,
                label: 'In progress',
                color: NivaraColors.primary,
              ),
              _Stat(
                value: loading ? null : resolved,
                label: 'Resolved',
                color: NivaraColors.success,
              ),
            ],
          ),
          if (!loading) ...[
            const SizedBox(height: 12),
            Text(
              total == 0
                  ? 'No reports in this area yet'
                  : '$total ${total == 1 ? 'report' : 'reports'} in range',
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label, required this.color});

  final int? value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value == null ? '—' : '$value',
            style: TextStyle(
              color: color,
              fontSize: 28,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

/// A recent-report row with distance-from-you, taps through to detail.
class _AreaReportTile extends StatelessWidget {
  const _AreaReportTile({
    required this.report,
    required this.distanceMeters,
    required this.onTap,
  });

  final Report report;
  final double distanceMeters;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final sev = severityColor(report.severity);
    final status = statusColor(report.status);
    final title = report.title?.trim().isNotEmpty == true
        ? report.title!.trim()
        : report.category.label;

    return Material(
      color: scheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: sev.withValues(alpha: 0.15),
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
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${formatDistance(distanceMeters)} away · ${timeAgo(report.createdAt)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(
                  color: status.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  report.status.label,
                  style: TextStyle(
                    color: status,
                    fontWeight: FontWeight.w700,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyArea extends StatelessWidget {
  const _EmptyArea({required this.radiusKm});
  final double radiusKm;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Icon(Icons.location_off_outlined, size: 36, color: scheme.outline),
          const SizedBox(height: 8),
          Text(
            'Nothing within ${radiusKm.round()} km',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Widen the radius, or be the first to report here.',
            textAlign: TextAlign.center,
            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12.5),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);
  final String title;

  @override
  Widget build(BuildContext context) => Text(
    title,
    style: Theme.of(
      context,
    ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
  );
}
