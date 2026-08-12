import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/civic_level.dart';
import '../../core/constants.dart';
import '../../core/supabase_client.dart';
import '../../core/theme.dart';
import '../../core/widgets/civic_level_view.dart';
import '../../models/enums.dart';
import '../../models/report.dart';
import '../../router.dart';
import '../auth/auth_controller.dart';

/// The **Home** tab of the citizen shell — the landing dashboard.
///
/// Body only: the surrounding [Scaffold]/[AppBar]/bottom-nav belong to
/// [HomeShell]. Stats are computed **live** from the database (the profile
/// counters have no maintaining triggers, so they'd read 0). We count the
/// signed-in user's reports, confirmations and finds, derive a civic-impact
/// score client-side, and show a community-pulse strip over the 50 latest
/// reports. The full recent-report feed lives on the Pulse tab (kept out of
/// Home to avoid duplication). Pull-to-refresh re-runs everything.
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

  /// Derived, not stored: a transparent function of the user's own activity.
  /// Labelled as "estimated" in the UI so it's never mistaken for a DB value.
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

    // Kick everything off in parallel, then await — each guarded so one failure
    // doesn't blank the whole dashboard.
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

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
        children: [
          Text(
            'Welcome, ${profile?.displayName ?? 'Citizen'}',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 4),
          Text(
            kAppTagline,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.outline,
            ),
          ),
          const SizedBox(height: 20),
          _ImpactCard(
            loading: _loading,
            score: _civicScore,
            reports: _myReports,
            confirms: _myConfirms,
            finds: _myFinds,
          ),
          const SizedBox(height: 20),
          _SectionHeader('Community pulse'),
          const SizedBox(height: 10),
          _PulseCard(
            loading: _loading,
            open: _openCount,
            inProgress: _inProgressCount,
            resolved: _resolvedCount,
            sample: _recent.length,
          ),
          const SizedBox(height: 20),
          _SectionHeader('Modules'),
          const SizedBox(height: 10),
          _ModuleCard(
            icon: Icons.radar,
            color: NivaraColors.primary,
            title: 'SensorWatch',
            subtitle: 'Passive pothole detection with tamper-proof evidence',
            onTap: () => context.push(Routes.sensorWatch),
          ),
          const SizedBox(height: 12),
          _ModuleCard(
            icon: Icons.report,
            color: NivaraColors.accent,
            title: 'CivicReport',
            subtitle: 'File a complaint across 19 civic categories',
            onTap: () => context.push(Routes.report),
          ),
          const SizedBox(height: 12),
          _ModuleCard(
            icon: Icons.map,
            color: NivaraColors.success,
            title: 'CivicMap',
            subtitle: 'Live map of reports and Lost & Found pins',
            onTap: () => context.push(Routes.map),
          ),
          const SizedBox(height: 12),
          _ModuleCard(
            icon: Icons.travel_explore,
            color: NivaraColors.danger,
            title: 'Lost & Found',
            subtitle: 'Report lost or found items, auto-matched nearby',
            onTap: () => context.push(Routes.lostFound),
          ),
        ],
      ),
    );
  }
}

/// Hero card: derived civic-impact score + the three activity counts feeding it.
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
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [NivaraColors.primary, Color(0xFF124D77)],
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.workspace_premium,
                color: Colors.white,
                size: 22,
              ),
              const SizedBox(width: 8),
              Text(
                'Civic impact',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              loading
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: SizedBox(
                        width: 28,
                        height: 28,
                        child: CircularProgressIndicator(
                          strokeWidth: 3,
                          color: Colors.white,
                        ),
                      ),
                    )
                  : Text(
                      '$score',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 44,
                        fontWeight: FontWeight.w900,
                        height: 1,
                      ),
                    ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  'points',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          CivicLevelBar(standing: civicStandingFor(score), onDark: true),
          const SizedBox(height: 16),
          Row(
            children: [
              _ImpactStat(
                icon: Icons.report_outlined,
                value: reports,
                label: 'Reports',
                loading: loading,
              ),
              _ImpactDivider(),
              _ImpactStat(
                icon: Icons.thumb_up_alt_outlined,
                value: confirms,
                label: 'Confirms',
                loading: loading,
              ),
              _ImpactDivider(),
              _ImpactStat(
                icon: Icons.volunteer_activism_outlined,
                value: finds,
                label: 'Finds',
                loading: loading,
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
  });

  final IconData icon;
  final int value;
  final String label;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, color: Colors.white.withValues(alpha: 0.9), size: 20),
          const SizedBox(height: 6),
          Text(
            loading ? '—' : '$value',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.8),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _ImpactDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    width: 1,
    height: 40,
    color: Colors.white.withValues(alpha: 0.2),
  );
}

/// Open / In-progress / Resolved tallies across the 50 latest reports.
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
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Row(
            children: [
              _PulseStat(
                value: loading ? null : open,
                label: 'Open',
                color: NivaraColors.accent,
              ),
              _PulseStat(
                value: loading ? null : inProgress,
                label: 'In progress',
                color: NivaraColors.primary,
              ),
              _PulseStat(
                value: loading ? null : resolved,
                label: 'Resolved',
                color: NivaraColors.success,
              ),
            ],
          ),
          if (!loading && sample > 0) ...[
            const SizedBox(height: 10),
            Text(
              'Across the $sample most recent reports',
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 11.5),
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
  });

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
              fontSize: 26,
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

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);
  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: Theme.of(
        context,
      ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
    );
  }
}

/// A tappable module entry on the citizen home.
class _ModuleCard extends StatelessWidget {
  const _ModuleCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    this.onTap,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.15),
          child: Icon(icon, color: color),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
