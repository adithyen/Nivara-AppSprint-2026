import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/civic_level.dart';
import '../../core/constants.dart';
import '../../core/localization/app_localizations.dart';
import '../../core/services/offline_queue_service.dart';
import '../../core/supabase_client.dart';
import '../../core/theme.dart';
import '../../core/widgets/bouncy_tap.dart';
import '../../core/widgets/civic_level_view.dart';
import '../../models/enums.dart';
import '../../models/user_profile.dart';
import '../../router.dart';
import '../auth/auth_controller.dart';
import '../settings/language_controller.dart';
import '../worker/worker_repo.dart';

/// 2026-Level Flagship Profile Dashboard.
class ProfileTab extends ConsumerStatefulWidget {
  const ProfileTab({super.key});

  @override
  ConsumerState<ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends ConsumerState<ProfileTab> {
  bool _loading = true;
  int _reports = 0;
  int _confirms = 0;
  int _finds = 0;

  bool _onLeave = false;
  bool _leaveWorking = false;
  int _pendingCount = 0;

  int get _civicScore => _reports * 10 + _confirms * 5 + _finds * 15;

  @override
  void initState() {
    super.initState();
    _load();
    _loadPendingCount();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final profile = ref.read(authControllerProvider).asData?.value;
      if (profile?.isWorker == true && mounted) {
        setState(() => _onLeave = profile!.isOnLeave);
      }
    });
  }

  Future<void> _loadPendingCount() async {
    final count = await OfflineQueueService.pendingCount();
    if (mounted) setState(() => _pendingCount = count);
  }

  Future<void> _load() async {
    final uid = ref.read(authControllerProvider).asData?.value?.id;
    final reports = await _count(kTableReports, uid, {});
    final confirms = await _count(kTableConfirmations, uid, {
      'type': 'CONFIRM',
    });
    final finds = await _count(kTableLfItems, uid, {'item_type': 'FOUND'});
    if (!mounted) return;
    setState(() {
      _reports = reports;
      _confirms = confirms;
      _finds = finds;
      _loading = false;
    });
  }

  Future<int> _count(String table, String? uid, Map<String, String> eq) async {
    if (uid == null) return 0;
    try {
      var q = supabase.from(table).select('id').eq('user_id', uid);
      eq.forEach((k, v) => q = q.eq(k, v));
      final rows = await q;
      return (rows as List).length;
    } catch (_) {
      return 0;
    }
  }

  Future<void> _editProfile(UserProfile profile) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _EditProfileSheet(profile: profile),
    );
    if (saved == true) {
      await ref.read(authControllerProvider.notifier).refresh();
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(content: Text('Profile updated successfully.')));
      }
    }
  }

  void _workWithNivara(UserProfile? profile) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _WorkWithNivaraSheet(profile: profile),
    );
  }

  Future<void> _toggleLeave() async {
    setState(() => _leaveWorking = true);
    try {
      if (_onLeave) {
        await WorkerRepo.markAvailable();
        if (mounted) setState(() => _onLeave = false);
      } else {
        await WorkerRepo.goOnLeave();
        if (mounted) setState(() => _onLeave = true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text('Could not update: $e')));
      }
    } finally {
      if (mounted) setState(() => _leaveWorking = false);
    }
  }

  Future<void> _resign() async {
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _ResignConfirmationDialog(),
    );
    if (ok != true || !mounted) return;
    try {
      await WorkerRepo.resign();
      if (mounted) ref.read(authControllerProvider.notifier).signOut();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text('Could not resign: $e')));
      }
    }
  }

  Future<void> _signOut() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text('You will need to sign in again to file and manage reports.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: NivaraColors.danger),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sign out', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(authControllerProvider.notifier).signOut();
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(authControllerProvider).asData?.value;
    final isCitizen = profile?.role == UserRole.citizen;
    final isWorker = profile?.isWorker ?? false;
    final isAdmin = profile?.role == UserRole.admin || profile?.role == UserRole.superadmin;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = Theme.of(context).colorScheme.primary;
    final currentLang = ref.watch(languageControllerProvider);

    return RefreshIndicator(
      color: primary,
      backgroundColor: isDark ? const Color(0xFF10161E) : Colors.white,
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 110),
        children: [
          _IdentityCard(profile: profile),
          const SizedBox(height: 20),

          // Role-Specific Metrics (No points for Admin!)
          if (isWorker) ...[
            _WorkStatusCard(
              onLeave: _onLeave,
              working: _leaveWorking,
              profile: profile,
              onToggleLeave: _toggleLeave,
              onResign: _resign,
            ),
            const SizedBox(height: 20),
            _WorkerServiceCard(
              loading: _loading,
              resolvedCount: _confirms,
              profile: profile,
            ),
            const SizedBox(height: 20),
          ] else ...[
            _CitizenImpactCard(
              loading: _loading,
              score: _civicScore,
              reports: _reports,
              confirms: _confirms,
              finds: _finds,
            ),
            const SizedBox(height: 20),
          ],

          if (isCitizen) ...[
            _ActionTile(
              icon: Icons.handshake_rounded,
              color: NivaraColors.accent,
              title: NivaraStrings.tr('work_with_nivara', currentLang),
              subtitle: NivaraStrings.tr('work_with_nivara_sub', currentLang),
              onTap: () => _workWithNivara(profile),
            ),
            const SizedBox(height: 12),
          ],

          _ActionTile(
            icon: Icons.palette_outlined,
            color: const Color(0xFF7B4BC4),
            title: NivaraStrings.tr('settings_appearance', currentLang),
            subtitle: NivaraStrings.tr('sub_appearance', currentLang),
            onTap: () => context.push(Routes.settings),
          ),
          const SizedBox(height: 12),

          _ActionTile(
            icon: Icons.accessibility_new_rounded,
            color: const Color(0xFF00E676),
            title: NivaraStrings.tr('settings_accessibility', currentLang),
            subtitle: NivaraStrings.tr('sub_accessibility', currentLang),
            onTap: () => context.push(Routes.accessibility),
          ),
          const SizedBox(height: 12),

          _ActionTile(
            icon: Icons.translate_rounded,
            color: const Color(0xFF00B0FF),
            title: NivaraStrings.tr('settings_language', currentLang),
            subtitle: NivaraStrings.tr('sub_language', currentLang),
            onTap: () => context.push(Routes.language),
          ),
          const SizedBox(height: 12),

          _ActionTile(
            icon: Icons.history_rounded,
            color: NivaraColors.primary,
            title: NivaraStrings.tr('activity_timeline', currentLang),
            subtitle: NivaraStrings.tr('sub_timeline', currentLang),
            onTap: () => context.push(Routes.activityLog),
          ),
          const SizedBox(height: 12),

          _ActionTile(
            icon: Icons.cloud_upload_outlined,
            color: NivaraColors.accent,
            title: NivaraStrings.tr('pending_sync', currentLang),
            subtitle: _pendingCount == 0
                ? NivaraStrings.tr('sub_pending_sync', currentLang)
                : '$_pendingCount item${_pendingCount == 1 ? '' : 's'} waiting to sync',
            badge: _pendingCount > 0 ? '$_pendingCount' : null,
            onTap: () async {
              await context.push(Routes.pendingSync);
              _loadPendingCount();
            },
          ),
          const SizedBox(height: 12),

          _ActionTile(
            icon: Icons.edit_rounded,
            color: NivaraColors.primaryBlue,
            title: NivaraStrings.tr('edit_profile', currentLang),
            subtitle: 'Display name, contact, and ward location',
            onTap: profile == null ? null : () => _editProfile(profile),
          ),
          const SizedBox(height: 12),

          _ActionTile(
            icon: Icons.feedback_outlined,
            color: const Color(0xFFFF9100),
            title: NivaraStrings.tr('report_issue_dev', currentLang),
            subtitle: 'Bug reports, feature suggestions, and developer email',
            onTap: () => context.push(Routes.feedback),
          ),
          const SizedBox(height: 12),

          _ActionTile(
            icon: Icons.logout_rounded,
            color: NivaraColors.danger,
            title: NivaraStrings.tr('sign_out', currentLang),
            subtitle: 'End your session on this device',
            onTap: _signOut,
          ),
        ],
      ),
    );
  }
}

class _WorkStatusCard extends StatelessWidget {
  const _WorkStatusCard({
    required this.onLeave,
    required this.working,
    required this.profile,
    required this.onToggleLeave,
    required this.onResign,
  });

  final bool onLeave;
  final bool working;
  final UserProfile? profile;
  final VoidCallback onToggleLeave;
  final VoidCallback onResign;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = Theme.of(context).colorScheme.primary;
    final dept = profile?.department?.label ?? 'Field Team';
    final workerNum = profile?.workerNumber;
    final statusColor = onLeave ? NivaraColors.accent : NivaraColors.success;
    final statusLabel = onLeave ? 'On Leave' : 'Available for Work';
    final statusIcon = onLeave ? Icons.beach_access_rounded : Icons.check_circle_rounded;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            'FIELD SHIFT STATUS',
            style: TextStyle(
              color: isDark ? Colors.white60 : const Color(0xFF6B7280),
              letterSpacing: 1.2,
              fontWeight: FontWeight.w800,
              fontSize: 11,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF10161E) : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: statusColor.withValues(alpha: isDark ? 0.35 : 0.4),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
                blurRadius: 12,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: isDark ? 0.16 : 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(statusIcon, color: statusColor, size: 22),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            statusLabel,
                            style: TextStyle(
                              color: statusColor,
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            onLeave
                                ? 'No new tasks will be dispatched to you'
                                : 'Active & ready for task dispatch',
                            style: TextStyle(
                              color: isDark ? Colors.white54 : const Color(0xFF6B7280),
                              fontSize: 11.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    working
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2.5),
                          )
                        : Switch(
                            value: onLeave,
                            activeThumbColor: NivaraColors.accent,
                            onChanged: (_) => onToggleLeave(),
                          ),
                  ],
                ),
              ),
              Divider(
                height: 1,
                color: isDark
                    ? Colors.white.withValues(alpha: 0.08)
                    : const Color(0xFFE2E8F0),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    Icon(
                      Icons.badge_outlined,
                      size: 18,
                      color: isDark ? Colors.white60 : const Color(0xFF6B7280),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      dept,
                      style: TextStyle(
                        color: isDark ? Colors.white70 : const Color(0xFF374151),
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    if (workerNum != null) ...[
                      const SizedBox(width: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: primary.withValues(alpha: isDark ? 0.15 : 0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: primary.withValues(alpha: 0.4),
                          ),
                        ),
                        child: Text(
                          'Worker #$workerNum',
                          style: TextStyle(
                            color: primary,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          icon: const Icon(Icons.person_remove_rounded, size: 18),
          label: const Text('Resign from Field Team'),
          style: OutlinedButton.styleFrom(
            foregroundColor: NivaraColors.danger,
            side: const BorderSide(color: NivaraColors.danger, width: 1.2),
            padding: const EdgeInsets.symmetric(vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
          onPressed: onResign,
        ),
      ],
    );
  }
}

class _IdentityCard extends ConsumerWidget {
  const _IdentityCard({required this.profile});
  final UserProfile? profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentLang = ref.watch(languageControllerProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = Theme.of(context).colorScheme.primary;
    final name = profile?.displayName ?? NivaraStrings.roleName(UserRole.citizen, currentLang);
    final area = [
      if (profile?.ward != null && profile!.ward!.trim().isNotEmpty)
        profile!.ward!.trim(),
      if (profile?.city != null && profile!.city!.trim().isNotEmpty)
        profile!.city!.trim(),
    ].join(', ');

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? const [Color(0xFF122336), Color(0xFF0C141F)]
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
                ? Colors.black.withValues(alpha: 0.4)
                : Colors.black.withValues(alpha: 0.06),
            blurRadius: isDark ? 20 : 16,
            offset: isDark ? const Offset(0, 6) : const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [primary, NivaraColors.primaryBlue],
              ),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: primary.withValues(alpha: 0.35),
                  blurRadius: 18,
                ),
              ],
            ),
            alignment: Alignment.center,
            child: Text(
              name.isNotEmpty ? name.characters.first.toUpperCase() : '?',
              style: TextStyle(
                color: ThemeData.estimateBrightnessForColor(primary) == Brightness.dark
                    ? Colors.white
                    : Colors.black,
                fontSize: 26,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: TextStyle(
                    color: isDark ? Colors.white : const Color(0xFF111827),
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: primary.withValues(alpha: isDark ? 0.16 : 0.12),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: primary.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Text(
                    NivaraStrings.roleName(profile?.role ?? UserRole.citizen, currentLang),
                    style: TextStyle(
                      color: primary,
                      fontWeight: FontWeight.w700,
                      fontSize: 11.5,
                    ),
                  ),
                ),
                if (area.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(
                        Icons.place_outlined,
                        color: isDark ? Colors.white60 : const Color(0xFF6B7280),
                        size: 14,
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          area,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: isDark ? Colors.white60 : const Color(0xFF6B7280),
                            fontSize: 11.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CitizenImpactCard extends ConsumerWidget {
  const _CitizenImpactCard({
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
  Widget build(BuildContext context, WidgetRef ref) {
    final currentLang = ref.watch(languageControllerProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = Theme.of(context).colorScheme.primary;

    return Container(
      padding: const EdgeInsets.all(18),
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.workspace_premium_rounded,
                color: primary,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                NivaraStrings.tr('civic_standing', currentLang),
                style: TextStyle(
                  color: isDark ? Colors.white : const Color(0xFF111827),
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
              const Spacer(),
              Text(
                loading ? '—' : '$score XP',
                style: TextStyle(
                  color: primary,
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _Stat(
                icon: Icons.report_gmailerrorred_rounded,
                value: reports,
                label: NivaraStrings.tr('stat_reports', currentLang),
                loading: loading,
                isDark: isDark,
                color: NivaraColors.accent,
              ),
              _Divider(isDark: isDark),
              _Stat(
                icon: Icons.thumb_up_alt_rounded,
                value: confirms,
                label: NivaraStrings.tr('stat_confirms', currentLang),
                loading: loading,
                isDark: isDark,
                color: primary,
              ),
              _Divider(isDark: isDark),
              _Stat(
                icon: Icons.volunteer_activism_rounded,
                value: finds,
                label: NivaraStrings.tr('stat_finds', currentLang),
                loading: loading,
                isDark: isDark,
                color: NivaraColors.primaryBlue,
              ),
            ],
          ),
          const SizedBox(height: 16),
          CivicLevelBar(
            standing: civicStandingFor(score),
            onDark: isDark,
            currentLang: currentLang,
          ),
        ],
      ),
    );
  }
}



class _WorkerServiceCard extends StatelessWidget {
  const _WorkerServiceCard({
    required this.loading,
    required this.resolvedCount,
    required this.profile,
  });

  final bool loading;
  final int resolvedCount;
  final UserProfile? profile;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dept = profile?.department?.label ?? 'Roads & Works';

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF10161E) : Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: const Color(0xFF00B0FF).withValues(alpha: isDark ? 0.35 : 0.4),
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF00B0FF).withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.engineering_rounded,
                  color: Color(0xFF00B0FF),
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Field Service & Resolution Proofs',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
                    Text(
                      'Active Duty Track Record',
                      style: TextStyle(fontSize: 11.5, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _DutyPill(
                  label: 'Department',
                  value: dept,
                  icon: Icons.badge_outlined,
                  color: const Color(0xFF00B0FF),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _DutyPill(
                  label: 'Verified Proofs',
                  value: '$resolvedCount Completed',
                  icon: Icons.verified_rounded,
                  color: const Color(0xFF00E676),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DutyPill extends StatelessWidget {
  const _DutyPill({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.12 : 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: isDark ? 0.25 : 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  color: isDark ? Colors.white60 : const Color(0xFF64748B),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({
    required this.icon,
    required this.value,
    required this.label,
    required this.loading,
    required this.isDark,
    required this.color,
  });

  final IconData icon;
  final int value;
  final String label;
  final bool loading;
  final bool isDark;
  final Color color;

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
              color: isDark ? Colors.white60 : const Color(0xFF6B7280),
              fontSize: 11.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider({required this.isDark});
  final bool isDark;

  @override
  Widget build(BuildContext context) => Container(
    width: 1,
    height: 36,
    color: isDark
        ? Colors.white.withValues(alpha: 0.1)
        : const Color(0xFFE2E8F0),
  );
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.badge,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final String? badge;

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
            color: isDark ? Colors.white10 : const Color(0xFFE2E8F0),
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
                color: color.withValues(alpha: isDark ? 0.15 : 0.1),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: isDark ? Colors.white : const Color(0xFF111827),
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: isDark ? Colors.white54 : const Color(0xFF6B7280),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            if (badge != null) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: color.withValues(alpha: 0.6)),
                ),
                child: Text(
                  badge!,
                  style: TextStyle(
                    color: color,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 6),
            ],
            Icon(
              Icons.chevron_right_rounded,
              color: isDark ? Colors.white38 : Colors.black38,
            ),
          ],
        ),
      ),
    );
  }
}

class _EditProfileSheet extends ConsumerStatefulWidget {
  const _EditProfileSheet({required this.profile});
  final UserProfile profile;

  @override
  ConsumerState<_EditProfileSheet> createState() => _EditProfileSheetState();
}

class _EditProfileSheetState extends ConsumerState<_EditProfileSheet> {
  late final _nameCtrl = TextEditingController(text: widget.profile.displayName);
  late final _phoneCtrl = TextEditingController(text: widget.profile.phone ?? '');
  late final _cityCtrl = TextEditingController(text: widget.profile.city ?? '');
  late final _wardCtrl = TextEditingController(text: widget.profile.ward ?? '');
  bool _saving = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _cityCtrl.dispose();
    _wardCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_nameCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Name cannot be empty.')),
      );
      return;
    }
    setState(() => _saving = true);
    final updated = widget.profile.copyWith(
      displayName: _nameCtrl.text.trim(),
      phone: _phoneCtrl.text.trim(),
      city: _cityCtrl.text.trim(),
      ward: _wardCtrl.text.trim(),
    );
    try {
      await supabase
          .from(kTableProfiles)
          .update(updated.toUpdateMap())
          .eq('id', widget.profile.id);
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    final email = supabase.auth.currentUser?.email ?? '';
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 4, 20, 24 + bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Edit Profile',
            style: TextStyle(
              color: scheme.onSurface,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 16),
          if (email.isNotEmpty) ...[
            TextField(
              enabled: false,
              controller: TextEditingController(text: email),
              style: TextStyle(color: scheme.onSurfaceVariant),
              decoration: InputDecoration(
                labelText: 'Account Email',
                prefixIcon: Icon(Icons.mail_outline, color: scheme.onSurfaceVariant),
              ),
            ),
            const SizedBox(height: 12),
          ],
          TextField(
            controller: _nameCtrl,
            textCapitalization: TextCapitalization.words,
            style: TextStyle(color: scheme.onSurface),
            decoration: InputDecoration(
              labelText: 'Display Name',
              prefixIcon: Icon(Icons.person_outline_rounded, color: scheme.onSurfaceVariant),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _phoneCtrl,
            keyboardType: TextInputType.phone,
            style: TextStyle(color: scheme.onSurface),
            decoration: InputDecoration(
              labelText: 'Phone Number',
              prefixIcon: Icon(Icons.call_outlined, color: scheme.onSurfaceVariant),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _cityCtrl,
                  textCapitalization: TextCapitalization.words,
                  style: TextStyle(color: scheme.onSurface),
                  decoration: InputDecoration(
                    labelText: 'City',
                    prefixIcon: Icon(Icons.location_city_rounded, color: scheme.onSurfaceVariant),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _wardCtrl,
                  textCapitalization: TextCapitalization.words,
                  style: TextStyle(color: scheme.onSurface),
                  decoration: const InputDecoration(labelText: 'Ward / Locality'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: ThemeData.estimateBrightnessForColor(scheme.primary) == Brightness.dark
                            ? Colors.white
                            : Colors.black,
                      ),
                    )
                  : Icon(
                      Icons.save_rounded,
                      color: ThemeData.estimateBrightnessForColor(scheme.primary) == Brightness.dark
                          ? Colors.white
                          : Colors.black,
                    ),
              label: Text(
                _saving ? 'Saving…' : 'Save Changes',
                style: TextStyle(
                  color: ThemeData.estimateBrightnessForColor(scheme.primary) == Brightness.dark
                      ? Colors.white
                      : Colors.black,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WorkWithNivaraSheet extends ConsumerStatefulWidget {
  const _WorkWithNivaraSheet({this.profile});
  final UserProfile? profile;

  @override
  ConsumerState<_WorkWithNivaraSheet> createState() => _WorkWithNivaraSheetState();
}

class _WorkWithNivaraSheetState extends ConsumerState<_WorkWithNivaraSheet> {
  late final _nameCtrl = TextEditingController(text: widget.profile?.displayName ?? '');
  late final _phoneCtrl = TextEditingController(text: widget.profile?.phone ?? '');
  late final _wardCtrl = TextEditingController(text: widget.profile?.ward ?? '');
  final _motivationCtrl = TextEditingController();

  final Set<String> _selectedCategories = {'roads_potholes'};
  String _availability = 'Full-Time (Daily Shifts)';
  bool _hasVehicle = false;
  bool _hasTools = false;
  bool _hasSmartphone = true;

  bool _submitting = false;
  bool _submitted = false;
  String? _error;

  static const _kCategories = [
    ('roads_potholes', 'Roads & Potholes', Icons.edit_road_rounded, NivaraColors.accent),
    ('garbage_waste', 'Sanitation & Waste', Icons.delete_outline_rounded, NivaraColors.primary),
    ('street_lighting', 'Streetlights & Electrical', Icons.lightbulb_outline_rounded, NivaraColors.accent),
    ('water_drainage', 'Water & Drainage', Icons.water_drop_outlined, NivaraColors.primaryBlue),
    ('parks_trees', 'Parks & Environment', Icons.park_outlined, Color(0xFF00E676)),
    ('animal_control', 'Animal Control', Icons.pets_outlined, Color(0xFFFF9100)),
    ('general', 'General Maintenance', Icons.build_outlined, Color(0xFF7C4DFF)),
  ];

  static const _kAvailabilities = [
    'Full-Time (Daily Shifts)',
    'Part-Time (Flexible)',
    'Emergency Quick Responder',
  ];

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _wardCtrl.dispose();
    _motivationCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _nameCtrl.text.trim();
    final phone = _phoneCtrl.text.trim();
    final ward = _wardCtrl.text.trim();

    if (name.isEmpty) {
      setState(() => _error = 'Please provide your full applicant name.');
      return;
    }
    if (phone.isEmpty) {
      setState(() => _error = 'Please provide a contact phone number.');
      return;
    }
    if (_selectedCategories.isEmpty) {
      setState(() => _error = 'Please select at least one field of interest.');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      final payload = jsonEncode({
        'applicant_name': name,
        'phone': phone,
        'ward': ward,
        'categories': _selectedCategories.toList(),
        'availability': _availability,
        'has_vehicle': _hasVehicle,
        'has_tools': _hasTools,
        'has_smartphone': _hasSmartphone,
        'motivation': _motivationCtrl.text.trim(),
      });

      await WorkerRepo.submitApplication(message: payload);

      // If user provided name/phone/ward that differ, update profile in background
      if (widget.profile != null) {
        try {
          final p = widget.profile!;
          if (p.displayName != name || p.phone != phone || (ward.isNotEmpty && p.ward != ward)) {
            await supabase.from(kTableProfiles).update({
              'display_name': name,
              'phone': phone,
              if (ward.isNotEmpty) 'ward': ward,
            }).eq('id', p.id);
          }
        } catch (_) {}
      }

      if (mounted) setState(() => _submitted = true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _submitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentLang = ref.watch(languageControllerProvider);
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.88,
      ),
      child: ListView(
        shrinkWrap: true,
        padding: EdgeInsets.fromLTRB(20, 4, 20, 24 + bottom),
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: NivaraColors.accent.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.handshake_rounded, color: NivaraColors.accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      NivaraStrings.tr('work_with_nivara', currentLang),
                      style: TextStyle(
                        color: scheme.onSurface,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      NivaraStrings.tr('workforce_application', currentLang),
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_submitted) ...[
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: NivaraColors.success.withValues(alpha: isDark ? 0.14 : 0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: NivaraColors.success.withValues(alpha: 0.4)),
              ),
              child: Column(
                children: [
                  const Icon(Icons.check_circle_rounded, color: NivaraColors.success, size: 48),
                  const SizedBox(height: 12),
                  Text(
                    NivaraStrings.tr('app_submitted_success', currentLang),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: NivaraColors.success,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    NivaraStrings.tr('app_dispatched_msg', currentLang),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: scheme.onSurfaceVariant,
                      fontSize: 12.5,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Done'),
              ),
            ),
          ] else ...[
            Text(
              'Join verified civic field teams to resolve municipal infrastructure issues, log photo resolution proof, and receive worker stipends.',
              style: TextStyle(
                color: scheme.onSurfaceVariant,
                fontSize: 12.5,
                height: 1.3,
              ),
            ),
            const SizedBox(height: 18),

            // 1. Personal & Contact Details
            Text(
              '1. APPLICANT DETAILS',
              style: TextStyle(
                color: scheme.primary,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.1,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _nameCtrl,
              textCapitalization: TextCapitalization.words,
              style: TextStyle(color: scheme.onSurface),
              decoration: InputDecoration(
                labelText: '${NivaraStrings.tr('full_legal_name', currentLang)} *',
                prefixIcon: Icon(Icons.person_outline, color: scheme.onSurfaceVariant),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _phoneCtrl,
                    keyboardType: TextInputType.phone,
                    style: TextStyle(color: scheme.onSurface),
                    decoration: InputDecoration(
                      labelText: '${NivaraStrings.tr('phone_contact', currentLang)} *',
                      prefixIcon: Icon(Icons.phone_outlined, color: scheme.onSurfaceVariant),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _wardCtrl,
                    textCapitalization: TextCapitalization.words,
                    style: TextStyle(color: scheme.onSurface),
                    decoration: InputDecoration(
                      labelText: NivaraStrings.tr('ward_neighborhood', currentLang),
                      prefixIcon: Icon(Icons.location_city_outlined, color: scheme.onSurfaceVariant),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // 2. Interested Categories
            Text(
              '2. INTERESTED DEPARTMENTS & SKILLS *',
              style: TextStyle(
                color: scheme.primary,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.1,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _kCategories.map((cat) {
                final isSelected = _selectedCategories.contains(cat.$1);
                return FilterChip(
                  avatar: Icon(cat.$3, size: 16, color: isSelected ? Colors.black : cat.$4),
                  label: Text(cat.$2),
                  selected: isSelected,
                  selectedColor: scheme.primary,
                  checkmarkColor: Colors.black,
                  labelStyle: TextStyle(
                    color: isSelected ? Colors.black : scheme.onSurface,
                    fontWeight: isSelected ? FontWeight.w800 : FontWeight.w500,
                    fontSize: 12,
                  ),
                  backgroundColor: isDark ? const Color(0xFF131A24) : const Color(0xFFF1F5F9),
                  side: BorderSide(
                    color: isSelected
                        ? scheme.primary
                        : (isDark ? Colors.white12 : const Color(0xFFE2E8F0)),
                  ),
                  onSelected: (val) {
                    setState(() {
                      if (val) {
                        _selectedCategories.add(cat.$1);
                      } else {
                        _selectedCategories.remove(cat.$1);
                      }
                    });
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 20),

            // 3. Shift Availability
            Text(
              '3. SHIFT & AVAILABILITY',
              style: TextStyle(
                color: scheme.primary,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.1,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF131A24) : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isDark ? Colors.white10 : const Color(0xFFE2E8F0),
                ),
              ),
              child: Column(
                children: _kAvailabilities.map((avail) {
                  final isSelected = _availability == avail;
                  return InkWell(
                    onTap: () => setState(() => _availability = avail),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      child: Row(
                        children: [
                          Icon(
                            isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
                            color: isSelected ? scheme.primary : scheme.onSurfaceVariant,
                            size: 18,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              avail,
                              style: TextStyle(
                                color: scheme.onSurface,
                                fontSize: 13,
                                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 20),

            // 4. Equipment & Readiness
            Text(
              '4. EQUIPMENT & READINESS',
              style: TextStyle(
                color: scheme.primary,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.1,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF131A24) : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isDark ? Colors.white10 : const Color(0xFFE2E8F0),
                ),
              ),
              child: Column(
                children: [
                  CheckboxListTile(
                    value: _hasVehicle,
                    activeColor: scheme.primary,
                    checkColor: Colors.black,
                    title: const Text('Two-Wheeler / Vehicle Transport Available', style: TextStyle(fontSize: 12.5)),
                    secondary: const Icon(Icons.two_wheeler_rounded, size: 20),
                    onChanged: (v) => setState(() => _hasVehicle = v ?? false),
                    controlAffinity: ListTileControlAffinity.trailing,
                    dense: true,
                  ),
                  Divider(height: 1, color: isDark ? Colors.white10 : const Color(0xFFE2E8F0)),
                  CheckboxListTile(
                    value: _hasTools,
                    activeColor: scheme.primary,
                    checkColor: Colors.black,
                    title: const Text('Own Basic Hand Tools / Repair Equipment', style: TextStyle(fontSize: 12.5)),
                    secondary: const Icon(Icons.handyman_rounded, size: 20),
                    onChanged: (v) => setState(() => _hasTools = v ?? false),
                    controlAffinity: ListTileControlAffinity.trailing,
                    dense: true,
                  ),
                  Divider(height: 1, color: isDark ? Colors.white10 : const Color(0xFFE2E8F0)),
                  CheckboxListTile(
                    value: _hasSmartphone,
                    activeColor: scheme.primary,
                    checkColor: Colors.black,
                    title: const Text('Smartphone with GPS & Camera (for Proof Photos)', style: TextStyle(fontSize: 12.5)),
                    secondary: const Icon(Icons.smartphone_rounded, size: 20),
                    onChanged: (v) => setState(() => _hasSmartphone = v ?? false),
                    controlAffinity: ListTileControlAffinity.trailing,
                    dense: true,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // 5. Note / Motivation
            Text(
              '5. MOTIVATION & PAST EXPERIENCE',
              style: TextStyle(
                color: scheme.primary,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.1,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _motivationCtrl,
              maxLines: 3,
              maxLength: 400,
              style: TextStyle(color: scheme.onSurface),
              decoration: const InputDecoration(
                labelText: 'Brief Experience / Background (optional)',
                hintText: 'Share trade background, past civic work, or certifications…',
                alignLabelWithHint: true,
              ),
            ),

            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: const TextStyle(color: NivaraColors.danger, fontWeight: FontWeight.w600),
              ),
            ],

            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _submitting ? null : _submit,
                icon: _submitting
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: ThemeData.estimateBrightnessForColor(scheme.primary) == Brightness.dark
                              ? Colors.white
                              : Colors.black,
                        ),
                      )
                    : Icon(
                        Icons.send_rounded,
                        color: ThemeData.estimateBrightnessForColor(scheme.primary) == Brightness.dark
                            ? Colors.white
                            : Colors.black,
                      ),
                label: Text(
                  _submitting
                      ? 'Submitting Application…'
                      : NivaraStrings.tr('submit_application', currentLang),
                  style: TextStyle(
                    color: ThemeData.estimateBrightnessForColor(scheme.primary) == Brightness.dark
                        ? Colors.white
                        : Colors.black,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Two-step Resignation Confirmation: Requires typing 'CONFIRM' then sliding to execute.
class _ResignConfirmationDialog extends StatefulWidget {
  const _ResignConfirmationDialog();

  @override
  State<_ResignConfirmationDialog> createState() => _ResignConfirmationDialogState();
}

class _ResignConfirmationDialogState extends State<_ResignConfirmationDialog>
    with SingleTickerProviderStateMixin {
  final _confirmCtrl = TextEditingController();
  bool _unlocked = false;
  double _dragPosition = 0.0;
  bool _confirmed = false;

  late final AnimationController _resetAnim;
  Animation<double>? _resetProgress;

  @override
  void initState() {
    super.initState();
    _resetAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _confirmCtrl.addListener(_onTextChanged);
  }

  void _onTextChanged() {
    final matches = _confirmCtrl.text.trim() == 'CONFIRM';
    if (matches != _unlocked) {
      setState(() {
        _unlocked = matches;
        if (!_unlocked) _dragPosition = 0.0;
      });
    }
  }

  @override
  void dispose() {
    _confirmCtrl.removeListener(_onTextChanged);
    _confirmCtrl.dispose();
    _resetAnim.dispose();
    super.dispose();
  }

  void _onDragUpdate(DragUpdateDetails details, double trackWidth, double thumbSize) {
    if (!_unlocked || _confirmed) return;
    final maxDrag = trackWidth - thumbSize;
    if (maxDrag <= 0) return;

    setState(() {
      _dragPosition = (_dragPosition + details.delta.dx).clamp(0.0, maxDrag);
    });

    if (_dragPosition >= maxDrag * 0.90 && !_confirmed) {
      _confirmed = true;
      Navigator.pop(context, true);
    }
  }

  void _onDragEnd(DragEndDetails details, double trackWidth, double thumbSize) {
    if (!_unlocked || _confirmed) return;
    final maxDrag = trackWidth - thumbSize;
    if (_dragPosition < maxDrag * 0.90) {
      _resetProgress = Tween<double>(begin: _dragPosition, end: 0.0).animate(
        CurvedAnimation(parent: _resetAnim, curve: Curves.easeOutCubic),
      )..addListener(() {
          setState(() {
            _dragPosition = _resetProgress!.value;
          });
        });
      _resetAnim.forward(from: 0.0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryText = isDark ? Colors.white : const Color(0xFF0F172A);
    final secondaryText = isDark ? Colors.white.withValues(alpha: 0.6) : const Color(0xFF64748B);

    return Dialog(
      backgroundColor: isDark ? const Color(0xFF10161E) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(
          color: isDark ? Colors.white.withValues(alpha: 0.1) : const Color(0xFFE2E8F0),
        ),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Danger Icon Header
            Center(
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: NivaraColors.danger.withValues(alpha: isDark ? 0.16 : 0.12),
                  border: Border.all(
                    color: NivaraColors.danger.withValues(alpha: 0.4),
                  ),
                ),
                child: const Icon(
                  Icons.warning_amber_rounded,
                  color: NivaraColors.danger,
                  size: 32,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Resign from Field Team?',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: primaryText,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'You will be removed from the field workforce and your account will revert to citizen status.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: secondaryText,
                fontSize: 13,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 20),

            // Step 1: Input text box
            Text(
              "Type 'CONFIRM' to unlock slider:",
              style: TextStyle(
                color: secondaryText,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _confirmCtrl,
              textCapitalization: TextCapitalization.characters,
              style: TextStyle(
                color: primaryText,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.5,
              ),
              decoration: InputDecoration(
                hintText: 'CONFIRM',
                hintStyle: TextStyle(
                  color: isDark ? Colors.white30 : const Color(0xFF94A3B8),
                  letterSpacing: 1.5,
                ),
                filled: true,
                fillColor: isDark ? const Color(0xFF161F2B) : const Color(0xFFF1F5F9),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(
                    color: _unlocked
                        ? NivaraColors.danger
                        : (isDark ? Colors.white10 : const Color(0xFFE2E8F0)),
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(
                    color: _unlocked
                        ? NivaraColors.danger
                        : (isDark ? Colors.white10 : const Color(0xFFE2E8F0)),
                    width: _unlocked ? 1.8 : 1.0,
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(
                    color: NivaraColors.danger,
                    width: 2.0,
                  ),
                ),
                prefixIcon: Icon(
                  _unlocked ? Icons.lock_open_rounded : Icons.lock_outline_rounded,
                  color: _unlocked ? NivaraColors.danger : (isDark ? Colors.white38 : const Color(0xFF94A3B8)),
                ),
              ),
            ),
            const SizedBox(height: 18),

            // Step 2: Slide to Confirm Slider
            LayoutBuilder(
              builder: (context, constraints) {
                const trackHeight = 54.0;
                const thumbSize = 46.0;
                final trackWidth = constraints.maxWidth;

                return Container(
                  height: trackHeight,
                  decoration: BoxDecoration(
                    color: _unlocked
                        ? NivaraColors.danger.withValues(alpha: isDark ? 0.15 : 0.12)
                        : (isDark ? Colors.white.withValues(alpha: 0.04) : const Color(0xFFF1F5F9)),
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(
                      color: _unlocked
                          ? NivaraColors.danger.withValues(alpha: 0.5)
                          : (isDark ? Colors.white10 : const Color(0xFFE2E8F0)),
                    ),
                  ),
                  child: Stack(
                    alignment: Alignment.centerLeft,
                    children: [
                      // Slider Prompt / Instruction
                      Center(
                        child: Text(
                          _unlocked
                              ? 'Slide to confirm resignation ➔'
                              : 'Type CONFIRM above to unlock',
                          style: TextStyle(
                            color: _unlocked
                                ? NivaraColors.danger
                                : (isDark ? Colors.white38 : const Color(0xFF94A3B8)),
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      // Slide Thumb
                      Positioned(
                        left: 4.0 + (_unlocked ? _dragPosition : 0.0),
                        child: GestureDetector(
                          onHorizontalDragUpdate: (d) => _onDragUpdate(d, trackWidth, thumbSize + 8.0),
                          onHorizontalDragEnd: (d) => _onDragEnd(d, trackWidth, thumbSize + 8.0),
                          child: Container(
                            width: thumbSize,
                            height: thumbSize,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _unlocked ? NivaraColors.danger : (isDark ? const Color(0xFF1E2836) : const Color(0xFFCBD5E1)),
                              boxShadow: _unlocked
                                  ? [
                                      BoxShadow(
                                        color: NivaraColors.danger.withValues(alpha: 0.4),
                                        blurRadius: 10,
                                        spreadRadius: 1,
                                      ),
                                    ]
                                  : null,
                            ),
                            child: Icon(
                              _unlocked
                                  ? Icons.double_arrow_rounded
                                  : Icons.lock_rounded,
                              color: _unlocked ? Colors.white : (isDark ? Colors.white38 : const Color(0xFF64748B)),
                              size: 22,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 16),

            // Cancel Button
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(
                'Cancel',
                style: TextStyle(
                  color: secondaryText,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
