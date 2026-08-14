import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/services/offline_queue_service.dart';
import '../../core/theme.dart';
import '../../core/widgets/bouncy_tap.dart';
import '../../core/widgets/connectivity_banner.dart';
import '../../models/enums.dart';
import '../../models/user_profile.dart';
import '../../router.dart';
import '../auth/auth_controller.dart';
import 'admin_community_tab.dart';
import 'admin_insights.dart';
import 'admin_queue.dart';
import 'manage_team_screen.dart';

/// 2026-Level Municipal Command Center Shell with floating glass navbar.
class AdminShell extends ConsumerStatefulWidget {
  const AdminShell({super.key});

  @override
  ConsumerState<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends ConsumerState<AdminShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final tabs = <_TabSpec>[
      const _TabSpec(
        title: 'Dispatch Queue',
        icon: Icons.inbox_outlined,
        selectedIcon: Icons.inbox_rounded,
        label: 'Queue',
        body: AdminQueue(),
      ),
      const _TabSpec(
        title: 'City Insights',
        icon: Icons.insights_outlined,
        selectedIcon: Icons.insights_rounded,
        label: 'Insights',
        body: AdminInsights(),
      ),
      const _TabSpec(
        title: 'Municipal Forum',
        icon: Icons.groups_outlined,
        selectedIcon: Icons.groups_rounded,
        label: 'Community',
        body: AdminCommunityTab(),
      ),
      const _TabSpec(
        title: 'Staff & Field Team',
        icon: Icons.badge_outlined,
        selectedIcon: Icons.badge_rounded,
        label: 'Team',
        body: ManageTeamScreen(),
      ),
      const _TabSpec(
        title: 'Admin Profile',
        icon: Icons.shield_outlined,
        selectedIcon: Icons.shield_rounded,
        label: 'Profile',
        body: _AdminProfileTab(),
      ),
    ];

    final index = _index.clamp(0, tabs.length - 1);

    return Scaffold(
      extendBody: true,
      backgroundColor: NivaraColors.canvasDark,
      body: WithConnectivityBanner(
        child: IndexedStack(
          index: index,
          children: [for (final t in tabs) t.body],
        ),
      ),
      bottomNavigationBar: _buildGlassNavBar(tabs, index),
    );
  }

  Widget _buildGlassNavBar(List<_TabSpec> tabs, int index) {
    return SafeArea(
      child: Container(
        margin: const EdgeInsets.fromLTRB(14, 0, 14, 12),
        height: 66,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(26),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.55),
              blurRadius: 28,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(26),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF10161E).withValues(alpha: 0.88),
                borderRadius: BorderRadius.circular(26),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.12),
                  width: 1.2,
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: List.generate(tabs.length, (i) {
                  final t = tabs[i];
                  final isSelected = index == i;
                  return BouncyTap(
                    scaleFactor: 0.92,
                    onTap: () {
                      if (_index != i) {
                        HapticFeedback.lightImpact();
                        setState(() => _index = i);
                      }
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 240),
                      curve: Curves.easeOutCubic,
                      padding: EdgeInsets.symmetric(
                        horizontal: isSelected ? 12 : 8,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? NivaraColors.accent.withValues(alpha: 0.18)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(18),
                        border: isSelected
                            ? Border.all(
                                color: NivaraColors.accent.withValues(alpha: 0.7),
                                width: 1.2,
                              )
                            : null,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isSelected ? t.selectedIcon : t.icon,
                            color: isSelected ? NivaraColors.accent : Colors.white60,
                            size: 20,
                          ),
                          if (isSelected) ...[
                            const SizedBox(width: 6),
                            Text(
                              t.label,
                              style: const TextStyle(
                                color: NivaraColors.accent,
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.2,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                }),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TabSpec {
  const _TabSpec({
    required this.title,
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.body,
  });

  final String title;
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final Widget body;
}

class _AdminProfileTab extends ConsumerWidget {
  const _AdminProfileTab();

  Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF131A24),
        title: const Text('Sign out of Command Center?'),
        content: const Text('You will need to sign in again to dispatch reports.'),
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
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(authControllerProvider).asData?.value;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
      children: [
        _OfficerCard(profile: profile),
        const SizedBox(height: 20),
        _ActionTile(
          icon: Icons.history_rounded,
          color: NivaraColors.primary,
          title: 'Admin Activity & Audit',
          subtitle: 'Timeline of your assignments, approvals, and posts',
          onTap: () => context.push(Routes.activityLog),
        ),
        const SizedBox(height: 12),
        FutureBuilder<int>(
          future: OfflineQueueService.pendingCount(),
          builder: (context, snapshot) {
            final count = snapshot.data ?? 0;
            return _ActionTile(
              icon: Icons.cloud_upload_outlined,
              color: NivaraColors.accent,
              title: 'Pending Sync Queue',
              subtitle: count == 0
                  ? 'All actions synced to cloud'
                  : '$count item${count == 1 ? '' : 's'} waiting to sync',
              badge: count > 0 ? '$count' : null,
              onTap: () => context.push(Routes.pendingSync),
            );
          },
        ),
        const SizedBox(height: 12),
        _ActionTile(
          icon: Icons.palette_outlined,
          color: const Color(0xFF7B4BC4),
          title: 'Appearance',
          subtitle: 'Theme mode and accent colour',
          onTap: () => context.push(Routes.settings),
        ),
        const SizedBox(height: 12),
        _ActionTile(
          icon: Icons.logout_rounded,
          color: NivaraColors.danger,
          title: 'Sign Out',
          subtitle: 'End your session on this device',
          onTap: () => _signOut(context, ref),
        ),
      ],
    );
  }
}

class _OfficerCard extends StatelessWidget {
  const _OfficerCard({required this.profile});
  final UserProfile? profile;

  @override
  Widget build(BuildContext context) {
    final name = profile?.displayName ?? 'Municipal Officer';
    final role = (profile?.role ?? UserRole.admin).label;
    final dept = profile?.department?.label;
    final area = [
      if (profile?.jurisdictionWard?.trim().isNotEmpty == true)
        profile!.jurisdictionWard!.trim(),
      if (profile?.jurisdictionCity?.trim().isNotEmpty == true)
        profile!.jurisdictionCity!.trim(),
    ].join(', ');

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1E2A38), Color(0xFF10161E)],
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: NivaraColors.accent.withValues(alpha: 0.35),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [NivaraColors.accent, Color(0xFFFF9100)],
              ),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: NivaraColors.accent.withValues(alpha: 0.4),
                  blurRadius: 14,
                ),
              ],
            ),
            child: const Icon(Icons.shield_rounded, color: Colors.black, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: NivaraColors.accent.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: NivaraColors.accent.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Text(
                    dept == null ? role : '$role · $dept',
                    style: const TextStyle(
                      color: NivaraColors.accent,
                      fontWeight: FontWeight.w700,
                      fontSize: 11.5,
                    ),
                  ),
                ),
                if (area.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(
                        Icons.place_outlined,
                        color: Colors.white60,
                        size: 14,
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          area,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white60, fontSize: 11.5),
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
    return BouncyTap(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF131A24),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
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
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.55),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            if (badge != null) ...[
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 9,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: color.withValues(alpha: 0.6)),
                ),
                child: Text(
                  badge!,
                  style: TextStyle(
                    color: color,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 6),
            ],
            const Icon(Icons.chevron_right_rounded, color: Colors.white38),
          ],
        ),
      ),
    );
  }
}
