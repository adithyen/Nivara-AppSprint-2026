import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/civic_level.dart';
import '../../core/constants.dart';
import '../../core/supabase_client.dart';
import '../../core/theme.dart';
import '../../core/widgets/bouncy_tap.dart';
import '../../core/widgets/civic_level_view.dart';
import '../../core/widgets/staggered_entrance.dart';
import '../../models/enums.dart';
import '../../models/report.dart';
import '../../router.dart';
import '../auth/auth_controller.dart';

/// 2026-Level Flagship Citizen Home Dashboard.
class HomeTab extends ConsumerStatefulWidget {
  const HomeTab({super.key});

  @override
  ConsumerState<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends ConsumerState<HomeTab> {
  bool _loading = true;
  int _myReports = 0;
  int _myConfirms = 0;
  int _myFinds = 0;
  List<Report> _recent = const [];

  int get _civicScore => _myReports * 10 + _myConfirms * 5 + _myFinds * 15;

  int get _openCount => _recent
      .where(
        (r) =>
            r.status == ReportStatus.submitted ||
            r.status == ReportStatus.acknowledged,
      )
      .length;
  int get _inProgressCount =>
      _recent.where((r) => r.status == ReportStatus.inProgress).length;
  int get _resolvedCount =>
      _recent.where((r) => r.status == ReportStatus.resolved).length;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final uid = ref.read(authControllerProvider).asData?.value?.id;

    final reportsFut = _countMyRows(kTableReports, uid);
    final confirmsFut = _countMyConfirms(uid);
    final findsFut = _countMyFinds(uid);
    final recentFut = _fetchRecent();

    final myReports = await reportsFut;
    final myConfirms = await confirmsFut;
    final myFinds = await findsFut;
    final recent = await recentFut;

    if (!mounted) return;
    setState(() {
      _myReports = myReports;
      _myConfirms = myConfirms;
      _myFinds = myFinds;
      _recent = recent;
      _loading = false;
    });
  }

  Future<int> _countMyRows(String table, String? uid) async {
    if (uid == null) return 0;
    try {
      final rows = await supabase.from(table).select('id').eq('user_id', uid);
      return (rows as List).length;
    } catch (_) {
      return 0;
    }
  }

  Future<int> _countMyConfirms(String? uid) async {
    if (uid == null) return 0;
    try {
      final rows = await supabase
          .from(kTableConfirmations)
          .select('id')
          .eq('user_id', uid)
          .eq('type', 'CONFIRM');
      return (rows as List).length;
    } catch (_) {
      return 0;
    }
  }

  Future<int> _countMyFinds(String? uid) async {
    if (uid == null) return 0;
    try {
      final rows = await supabase
          .from(kTableLfItems)
          .select('id')
          .eq('user_id', uid)
          .eq('item_type', 'FOUND');
      return (rows as List).length;
    } catch (_) {
      return 0;
    }
  }

  Future<List<Report>> _fetchRecent() async {
    try {
      final rows = await supabase
          .from(kTableReports)
          .select()
          .order('created_at', ascending: false)
          .limit(50);
      return (rows as List)
          .map((e) => Report.fromMap(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(authControllerProvider).asData?.value;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;

    return RefreshIndicator(
      color: scheme.primary,
      backgroundColor: isDark ? const Color(0xFF10161E) : Colors.white,
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 110),
        children: [
          // Greeting header
          StaggeredEntrance(
            index: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Welcome, ${profile?.displayName ?? 'Citizen'}',
                      style: TextStyle(
                        color: scheme.onSurface,
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      kAppTagline,
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF131A24)
                        : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.1)
                          : const Color(0xFFE2E8F0),
                    ),
                  ),
                  child: Icon(
                    Icons.shield_outlined,
                    color: scheme.primary,
                    size: 22,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Hero Civic Impact Glass Card
          StaggeredEntrance(
            index: 1,
            child: _ImpactCard(
              loading: _loading,
              score: _civicScore,
              reports: _myReports,
              confirms: _myConfirms,
              finds: _myFinds,
            ),
          ),

          const SizedBox(height: 22),

          // Community Pulse Strip
          StaggeredEntrance(
            index: 2,
            child: _PulseCard(
              loading: _loading,
              open: _openCount,
              inProgress: _inProgressCount,
              resolved: _resolvedCount,
              sample: _recent.length,
            ),
          ),

          const SizedBox(height: 26),

          // Section Title
          const StaggeredEntrance(
            index: 3,
            child: _SectionHeader('Civic Modules'),
          ),

          const SizedBox(height: 12),

          // 2x2 Feature Modules Grid
          StaggeredEntrance(
            index: 4,
            child: GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 14,
              mainAxisSpacing: 14,
              childAspectRatio: 1.15,
              children: [
                _FeatureModuleTile(
                  icon: Icons.sensors_rounded,
                  color: NivaraColors.primary,
                  title: 'SensorWatch',
                  subtitle: 'Passive road jolt telemetry',
                  onTap: () => context.push(Routes.sensorWatch),
                ),
                _FeatureModuleTile(
                  icon: Icons.campaign_rounded,
                  color: NivaraColors.accent,
                  title: 'CivicReport',
                  subtitle: 'Report 19 issue categories',
                  onTap: () => context.push(Routes.report),
                ),
                _FeatureModuleTile(
                  icon: Icons.map_rounded,
                  color: NivaraColors.primaryBlue,
                  title: 'CivicMap',
                  subtitle: 'Real-time Ola live map',
                  onTap: () => context.push(Routes.map),
                ),
                _FeatureModuleTile(
                  icon: Icons.travel_explore_rounded,
                  color: NivaraColors.danger,
                  title: 'Lost & Found',
                  subtitle: 'Radar item matching',
                  onTap: () => context.push(Routes.lostFound),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ImpactCard extends StatelessWidget {
  const _ImpactCard({
    required this.loading,
    required this.score,
    required this.reports,
    required this.confirms,
    required this.finds,
  });

  final bool loading;
  final int score;
  final int reports;
  final int confirms;
  final int finds;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = Theme.of(context).colorScheme.primary;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? const [Color(0xFF101B2B), Color(0xFF0D141E)]
              : const [Colors.white, Color(0xFFF6F9FD)],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: primary.withValues(alpha: isDark ? 0.35 : 0.4),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? primary.withValues(alpha: 0.12)
                : Colors.black.withValues(alpha: 0.06),
            blurRadius: isDark ? 28 : 16,
            offset: isDark ? const Offset(0, 8) : const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: primary.withValues(alpha: isDark ? 0.16 : 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.workspace_premium_rounded,
                  color: primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'Civic Standing & Impact',
                style: TextStyle(
                  color: isDark ? Colors.white : const Color(0xFF111827),
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              loading
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: primary,
                        ),
                      ),
                    )
                  : Text(
                      '$score',
                      style: TextStyle(
                        color: isDark ? Colors.white : const Color(0xFF111827),
                        fontSize: 42,
                        fontWeight: FontWeight.w900,
                        height: 1,
                        letterSpacing: -1,
                      ),
                    ),
              const SizedBox(width: 8),
              Text(
                'XP Points',
                style: TextStyle(
                  color: primary,
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          CivicLevelBar(standing: civicStandingFor(score), onDark: isDark),
          const SizedBox(height: 18),
          Row(
            children: [
              _ImpactStat(
                icon: Icons.report_gmailerrorred_rounded,
                value: reports,
                label: 'Reports',
                loading: loading,
                color: NivaraColors.accent,
                isDark: isDark,
              ),
              _ImpactDivider(isDark: isDark),
              _ImpactStat(
                icon: Icons.thumb_up_alt_rounded,
                value: confirms,
                label: 'Confirms',
                loading: loading,
                color: primary,
                isDark: isDark,
              ),
              _ImpactDivider(isDark: isDark),
              _ImpactStat(
                icon: Icons.volunteer_activism_rounded,
                value: finds,
                label: 'Finds',
                loading: loading,
                color: NivaraColors.primaryBlue,
                isDark: isDark,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ImpactStat extends StatelessWidget {
  const _ImpactStat({
    required this.icon,
    required this.value,
    required this.label,
    required this.loading,
    required this.color,
    required this.isDark,
  });

  final IconData icon;
  final int value;
  final String label;
  final bool loading;
  final Color color;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 6),
          Text(
            loading ? '—' : '$value',
            style: TextStyle(
              color: isDark ? Colors.white : const Color(0xFF111827),
              fontSize: 19,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.65)
                  : const Color(0xFF6B7280),
              fontSize: 11.5,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _ImpactDivider extends StatelessWidget {
  const _ImpactDivider({required this.isDark});
  final bool isDark;

  @override
  Widget build(BuildContext context) => Container(
    width: 1,
    height: 36,
    color: isDark
        ? Colors.white.withValues(alpha: 0.12)
        : const Color(0xFFE2E8F0),
  );
}

class _PulseCard extends StatelessWidget {
  const _PulseCard({
    required this.loading,
    required this.open,
    required this.inProgress,
    required this.resolved,
    required this.sample,
  });

  final bool loading;
  final int open;
  final int inProgress;
  final int resolved;
  final int sample;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF10161E) : Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: isDark ? Colors.white10 : const Color(0xFFE2E8F0),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              _PulseStat(
                value: loading ? null : open,
                label: 'Active',
                color: NivaraColors.accent,
                isDark: isDark,
              ),
              _PulseStat(
                value: loading ? null : inProgress,
                label: 'In Action',
                color: NivaraColors.primaryBlue,
                isDark: isDark,
              ),
              _PulseStat(
                value: loading ? null : resolved,
                label: 'Resolved',
                color: NivaraColors.success,
                isDark: isDark,
              ),
            ],
          ),
          if (!loading && sample > 0) ...[
            const SizedBox(height: 12),
            Text(
              'Live telemetry over $sample city reports',
              style: TextStyle(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.5)
                    : const Color(0xFF6B7280),
                fontSize: 11.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PulseStat extends StatelessWidget {
  const _PulseStat({
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
              fontSize: 24,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.65)
                  : const Color(0xFF6B7280),
              fontSize: 12,
              fontWeight: FontWeight.w600,
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
  Widget build(BuildContext context) {
    return Text(
      title,
      style: TextStyle(
        color: Theme.of(context).colorScheme.onSurface,
        fontSize: 17,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.2,
      ),
    );
  }
}

class _FeatureModuleTile extends StatelessWidget {
  const _FeatureModuleTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
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
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: color.withValues(alpha: isDark ? 0.35 : 0.4),
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: isDark
                  ? color.withValues(alpha: 0.08)
                  : Colors.black.withValues(alpha: 0.05),
              blurRadius: isDark ? 16 : 10,
              offset: isDark ? const Offset(0, 4) : const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.16),
                    shape: BoxShape.circle,
                    border: Border.all(color: color.withValues(alpha: 0.3)),
                  ),
                  child: Icon(icon, color: color, size: 20),
                ),
                Icon(
                  Icons.arrow_outward_rounded,
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.3)
                      : Colors.black.withValues(alpha: 0.25),
                  size: 16,
                ),
              ],
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isDark ? Colors.white : const Color(0xFF111827),
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.6)
                        : const Color(0xFF6B7280),
                    fontSize: 11.5,
                    height: 1.2,
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
