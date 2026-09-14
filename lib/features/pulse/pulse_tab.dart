import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants.dart';
import '../../core/localization/app_localizations.dart';
import '../../core/services/location_service.dart';
import '../../core/supabase_client.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../core/widgets/bouncy_tap.dart';
import '../../models/enums.dart';
import '../../models/report.dart';
import '../../router.dart';
import '../admin/status_style.dart';
import '../report/category_grid.dart';
import '../settings/language_controller.dart';

/// 2026-Level Neighborhood City Pulse Dashboard.
class PulseTab extends ConsumerStatefulWidget {
  const PulseTab({super.key});

  @override
  ConsumerState<PulseTab> createState() => _PulseTabState();
}

class _PulseTabState extends ConsumerState<PulseTab> with WidgetsBindingObserver {
  final _location = const LocationService();

  double _radiusKm = 5;
  Position? _pos;
  bool _locating = true;
  bool _loading = true;
  bool _locationServiceOff = false;
  bool _permissionDenied = false;
  StreamSubscription<ServiceStatus>? _serviceStatusSub;
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
    WidgetsBinding.instance.addObserver(this);
    _listenServiceStatus();
    _init();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _serviceStatusSub?.cancel();
    super.dispose();
  }

  void _listenServiceStatus() {
    _serviceStatusSub = _location.serviceStatusStream.listen((status) {
      if (status == ServiceStatus.enabled) {
        if (mounted) {
          setState(() {
            _locationServiceOff = false;
            _locating = true;
          });
          _refresh();
        }
      } else if (status == ServiceStatus.disabled) {
        if (mounted) {
          setState(() => _locationServiceOff = true);
        }
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkLocationAndReload();
    }
  }

  Future<void> _checkLocationAndReload() async {
    final enabled = await _location.isServiceEnabled();
    if (enabled && _locationServiceOff) {
      if (mounted) {
        setState(() {
          _locationServiceOff = false;
          _locating = true;
        });
        await _refresh();
      }
    } else if (!enabled && !_locationServiceOff) {
      if (mounted) {
        setState(() => _locationServiceOff = true);
      }
    }
  }

  Future<void> _init() async {
    final serviceOn = await _location.isServiceEnabled();
    if (!serviceOn) {
      if (!mounted) return;
      setState(() {
        _locationServiceOff = true;
        _locating = false;
      });
      await _load();
      return;
    }

    final perm = await _location.ensurePermission();
    final granted = _location.isGranted(perm);
    Position? pos;
    if (granted) pos = await _location.current();

    if (!mounted) return;
    setState(() {
      _locationServiceOff = false;
      _permissionDenied = !granted;
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
      ).timeout(const Duration(seconds: 4));
      reports = (rows as List)
          .map((e) => Report.fromMap(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      // Graceful fallback to direct query if RPC times out or offline
      try {
        final fallbackRows = await supabase
            .from(kTableReports)
            .select()
            .order('created_at', ascending: false)
            .limit(100)
            .timeout(const Duration(seconds: 3));
        reports = (fallbackRows as List)
            .map((e) => Report.fromMap(e as Map<String, dynamic>))
            .where((r) => haversineMeters(_lat, _lng, r.lat, r.lng) <= _radiusKm * 1000)
            .toList();
      } catch (_) {
        reports = const [];
      }
    }
    if (!mounted) return;
    setState(() {
      _reports = reports;
      _loading = false;
    });
  }

  Future<void> _refresh() async {
    final serviceOn = await _location.isServiceEnabled();
    if (!serviceOn) {
      if (mounted) {
        setState(() {
          _locationServiceOff = true;
          _locating = false;
        });
      }
      await _load();
      return;
    }

    final perm = await _location.ensurePermission();
    final granted = _location.isGranted(perm);
    Position? pos;
    if (granted) {
      pos = await _location.current();
      if (mounted && pos != null) setState(() => _pos = pos);
    }
    if (mounted) {
      setState(() {
        _locationServiceOff = false;
        _permissionDenied = !granted;
        _locating = false;
      });
    }
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final currentLang = ref.watch(languageControllerProvider);

    return RefreshIndicator(
      color: NivaraColors.primary,
      backgroundColor: const Color(0xFF10161E),
      onRefresh: _refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 110),
        children: [
          if (_locationServiceOff) ...[
            _LocationServiceDisabledCard(
              currentLang: currentLang,
              onEnablePressed: () async {
                await _location.openLocationSettings();
              },
            ),
            const SizedBox(height: 14),
          ] else if (_permissionDenied) ...[
            _LocationPermissionDeniedCard(
              currentLang: currentLang,
              onGrantPressed: () async {
                await Geolocator.requestPermission();
                _refresh();
              },
            ),
            const SizedBox(height: 14),
          ],
          _RadiusCard(
            radiusKm: _radiusKm,
            locating: _locating,
            usingDefault: _pos == null,
            currentLang: currentLang,
            onChanged: (v) => setState(() => _radiusKm = v),
            onChangeEnd: (_) => _load(),
          ),
          const SizedBox(height: 20),

          _SectionHeader('${NivaraStrings.tr('live_telemetry_within', currentLang)} ${_radiusKm.round()} km'),
          const SizedBox(height: 10),
          _AreaStatsCard(
            loading: _loading,
            open: _openCount,
            inProgress: _inProgressCount,
            resolved: _resolvedCount,
            total: _reports.length,
            currentLang: currentLang,
          ),
          const SizedBox(height: 24),

          Row(
            children: [
              Expanded(child: _SectionHeader(NivaraStrings.tr('recent_nearby_issues', currentLang))),
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
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.map_rounded, size: 14, color: NivaraColors.primary),
                        const SizedBox(width: 4),
                        Text(
                          NivaraStrings.tr('view_on_map', currentLang),
                          style: const TextStyle(
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
                      currentLang: currentLang,
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
    required this.currentLang,
    required this.onChanged,
    required this.onChangeEnd,
  });

  final double radiusKm;
  final bool locating;
  final bool usingDefault;
  final AppLanguage currentLang;
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
                          : NivaraStrings.tr('proximity_filter', currentLang),
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
                  '${radiusKm.round()} km ${NivaraStrings.tr('radius_label', currentLang)}',
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
    required this.currentLang,
  });

  final bool loading;
  final int open;
  final int inProgress;
  final int resolved;
  final int total;
  final AppLanguage currentLang;

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
                label: NivaraStrings.tr('active', currentLang),
                color: NivaraColors.accent,
                isDark: isDark,
              ),
              _Stat(
                value: loading ? null : inProgress,
                label: NivaraStrings.tr('status_in_progress', currentLang),
                color: NivaraColors.primaryBlue,
                isDark: isDark,
              ),
              _Stat(
                value: loading ? null : resolved,
                label: NivaraStrings.tr('status_resolved', currentLang),
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
                  : '$total ${NivaraStrings.tr('total_issues_recorded', currentLang)}',
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
    required this.currentLang,
    required this.onTap,
  });

  final Report report;
  final double distanceMeters;
  final AppLanguage currentLang;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sev = severityColor(report.severity);
    final status = statusColor(report.status);
    final title = report.title?.trim().isNotEmpty == true
        ? report.title!.trim()
        : report.category.localizedName(currentLang);

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
                    '${formatLocalizedDistance(distanceMeters, currentLang)} · ${timeAgo(report.createdAt)}',
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
                report.status.localizedName(currentLang),
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

class _LocationServiceDisabledCard extends StatelessWidget {
  final AppLanguage currentLang;
  final VoidCallback onEnablePressed;

  const _LocationServiceDisabledCard({
    required this.currentLang,
    required this.onEnablePressed,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E170C) : const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.amber.withValues(alpha: isDark ? 0.4 : 0.6),
          width: 1.2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.18),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.location_off_rounded,
                  color: Colors.amber,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      NivaraStrings.tr('pulse_gps_disabled_title', currentLang),
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14.5,
                        color: Colors.amber,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      NivaraStrings.tr('pulse_gps_disabled_sub', currentLang),
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.white70 : const Color(0xFF78350F),
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              BouncyTap(
                onTap: onEnablePressed,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.amber,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.settings_outlined, color: Colors.black, size: 16),
                      const SizedBox(width: 6),
                      Text(
                        NivaraStrings.tr('pulse_btn_turn_on_gps', currentLang),
                        style: const TextStyle(
                          color: Colors.black,
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Row(
                  children: [
                    const Icon(Icons.sync_rounded, size: 13, color: Colors.amber),
                    const SizedBox(width: 4),
                    Text(
                      'Auto-reloads when enabled',
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark ? Colors.amber.shade200 : Colors.amber.shade900,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LocationPermissionDeniedCard extends StatelessWidget {
  final AppLanguage currentLang;
  final VoidCallback onGrantPressed;

  const _LocationPermissionDeniedCard({
    required this.currentLang,
    required this.onGrantPressed,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1F1115) : const Color(0xFFFFF1F2),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.redAccent.withValues(alpha: isDark ? 0.35 : 0.5),
          width: 1.2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.redAccent.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.near_me_disabled_rounded,
                  color: Colors.redAccent,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      NivaraStrings.tr('pulse_permission_denied_title', currentLang),
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14.5,
                        color: Colors.redAccent,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      NivaraStrings.tr('pulse_permission_denied_sub', currentLang),
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.white70 : const Color(0xFF881337),
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          BouncyTap(
            onTap: onGrantPressed,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.redAccent,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.check_circle_outline_rounded, color: Colors.white, size: 16),
                  const SizedBox(width: 6),
                  Text(
                    NivaraStrings.tr('pulse_btn_grant_permission', currentLang),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
