import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants.dart';
import '../../core/services/location_service.dart';
import '../../core/supabase_client.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../core/widgets/bouncy_tap.dart';
import '../../core/widgets/glass_card.dart';
import '../../models/enums.dart';
import '../../models/report.dart';
import '../../router.dart';
import '../admin/status_style.dart';
import '../report/category_grid.dart';

/// 2026-Level Neighborhood City Pulse Dashboard.
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
      color: NivaraColors.primary,
      backgroundColor: const Color(0xFF10161E),
      onRefresh: _refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 110),
        children: [
          _RadiusCard(
            radiusKm: _radiusKm,
            locating: _locating,
            usingDefault: _pos == null,
            onChanged: (v) => setState(() => _radiusKm = v),
            onChangeEnd: (_) => _load(),
          ),
          const SizedBox(height: 20),

          _SectionHeader('Live Telemetry within ${_radiusKm.round()} km'),
          const SizedBox(height: 10),
          _AreaStatsCard(
            loading: _loading,
            open: _openCount,
            inProgress: _inProgressCount,
            resolved: _resolvedCount,
            total: _reports.length,
          ),
          const SizedBox(height: 24),

          Row(
            children: [
              Expanded(child: _SectionHeader('Recent Nearby Issues')),
              if (_reports.isNotEmpty)
                BouncyTap(
                  onTap: () => context.push(Routes.map),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: NivaraColors.primary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: NivaraColors.primary.withValues(alpha: 0.4)),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.map_rounded, size: 14, color: NivaraColors.primary),
                        SizedBox(width: 4),
                        Text(
                          'View on Map',
                          style: TextStyle(
                            color: NivaraColors.primary,
                            fontWeight: FontWeight.w800,
                            fontSize: 11.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),

          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Center(
                child: CircularProgressIndicator(color: NivaraColors.primary),
              ),
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
                      distanceMeters: haversineMeters(_lat, _lng, r.lat, r.lng),
                      onTap: () => context.push(Routes.reportDetail, extra: r),
                    ),
                  ),
                ),
        ],
      ),
    );
  }
}

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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = Theme.of(context).colorScheme.primary;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF10161E) : Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: isDark ? Colors.white.withValues(alpha: 0.1) : const Color(0xFFE2E8F0),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.15 : 0.03),
            blurRadius: 12,
            offset: const Offset(0, 3),
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
                  color: primary.withValues(alpha: isDark ? 0.16 : 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.radar_rounded, color: primary, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  locating
                      ? 'Acquiring GPS fix…'
                      : usingDefault
                          ? 'Using city center'
                          : 'Proximity Filter',
                  style: TextStyle(
                    color: isDark ? Colors.white : const Color(0xFF111827),
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: primary.withValues(alpha: isDark ? 0.16 : 0.12),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: primary.withValues(alpha: 0.5)),
                ),
                child: Text(
                  '${radiusKm.round()} km radius',
                  style: TextStyle(
                    color: primary,
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: primary,
              thumbColor: primary,
              overlayColor: primary.withValues(alpha: 0.2),
            ),
            child: Slider(
              value: radiusKm,
              min: 1,
              max: 100,
              divisions: 99,
              label: '${radiusKm.round()} km',
              onChanged: onChanged,
              onChangeEnd: onChangeEnd,
            ),
          ),
          Wrap(
            spacing: 8,
            children: [
              for (final p in _presets)
                BouncyTap(
                  onTap: () {
                    onChanged(p);
                    onChangeEnd(p);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: radiusKm.round() == p.round()
                          ? primary.withValues(alpha: isDark ? 0.2 : 0.15)
                          : (isDark ? const Color(0xFF16202C) : const Color(0xFFF1F5F9)),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: radiusKm.round() == p.round()
                            ? primary
                            : (isDark ? Colors.white.withValues(alpha: 0.08) : const Color(0xFFE2E8F0)),
                      ),
                    ),
                    child: Text(
                      '${p.round()} km',
                      style: TextStyle(
                        color: radiusKm.round() == p.round()
                            ? primary
                            : (isDark ? Colors.white70 : const Color(0xFF4B5563)),
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF10161E) : Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: isDark ? Colors.white10 : const Color(0xFFE2E8F0),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.15 : 0.03),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              _Stat(
                value: loading ? null : open,
                label: 'Active',
                color: NivaraColors.accent,
                isDark: isDark,
              ),
              _Stat(
                value: loading ? null : inProgress,
                label: 'In Progress',
                color: NivaraColors.primaryBlue,
                isDark: isDark,
              ),
              _Stat(
                value: loading ? null : resolved,
                label: 'Resolved',
                color: NivaraColors.success,
                isDark: isDark,
              ),
            ],
          ),
          if (!loading) ...[
            const SizedBox(height: 10),
            Text(
              total == 0
                  ? 'No reports in this area'
                  : '$total total issue${total == 1 ? '' : 's'} recorded',
              style: TextStyle(
                color: isDark ? Colors.white.withValues(alpha: 0.5) : const Color(0xFF6B7280),
                fontSize: 11.5,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({
    required this.value,
    required this.label,
    required this.color,
    required this.isDark,
  });

  final int? value;
  final String label;
  final Color color;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value == null ? '—' : '$value',
            style: TextStyle(
              color: color,
              fontSize: 26,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isDark ? Colors.white.withValues(alpha: 0.6) : const Color(0xFF6B7280),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sev = severityColor(report.severity);
    final status = statusColor(report.status);
    final title = report.title?.trim().isNotEmpty == true
        ? report.title!.trim()
        : report.category.label;

    return BouncyTap(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF10161E) : Colors.white,
          borderRadius: BorderRadius.circular(18),
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
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: sev.withValues(alpha: isDark ? 0.16 : 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                categoryIcon(report.category),
                color: sev,
                size: 20,
              ),
            ),
            const SizedBox(width: 14),
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
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${formatDistance(distanceMeters)} away · ${timeAgo(report.createdAt)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isDark ? Colors.white.withValues(alpha: 0.55) : const Color(0xFF6B7280),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
              decoration: BoxDecoration(
                color: status.withValues(alpha: isDark ? 0.15 : 0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: status.withValues(alpha: 0.5)),
              ),
              child: Text(
                report.status.label,
                style: TextStyle(
                  color: status,
                  fontWeight: FontWeight.w800,
                  fontSize: 11,
                ),
              ),
            ),
          ],
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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF10161E) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? Colors.white.withValues(alpha: 0.08) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Column(
        children: [
          Icon(
            Icons.location_off_rounded,
            size: 36,
            color: isDark ? Colors.white38 : Colors.black26,
          ),
          const SizedBox(height: 10),
          Text(
            'No issues reported within ${radiusKm.round()} km',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white : const Color(0xFF111827),
              fontSize: 14.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Widen the radius or be the first to report an issue in your area.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isDark ? Colors.white.withValues(alpha: 0.55) : const Color(0xFF6B7280),
              fontSize: 12.5,
            ),
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
    style: TextStyle(
      color: Theme.of(context).colorScheme.onSurface,
      fontWeight: FontWeight.w800,
      fontSize: 16,
      letterSpacing: -0.2,
    ),
  );
}
