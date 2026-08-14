import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/services/offline_queue_service.dart';
import '../../core/theme.dart';
import '../../models/enums.dart';
import '../../models/user_profile.dart';
import '../../router.dart';
import '../auth/auth_controller.dart';
import 'admin_community_tab.dart';
import 'admin_insights.dart';
import 'admin_queue.dart';
import 'manage_team_screen.dart';

/// The municipal (admin) app shell: a bottom-nav host over
/// **Queue · Insights · Staff · Profile**.
///
/// Mirrors the citizen [HomeShell]: each tab is a *body-only* widget, this shell
/// owns the single [Scaffold], the per-tab [AppBar] title, and the Material 3
/// [NavigationBar], and tabs stay alive across switches via an [IndexedStack].
///
/// The **Staff** tab (role management) appears only for superadmins — the tab
/// set is rebuilt from the signed-in profile, and the server's `set_user_role`
/// RPC enforces the same rule authoritatively. Role access to the whole shell is
/// gated by the router guard (citizens/workers can't reach `/admin`) and by RLS.
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
        title: 'Report queue',
        icon: Icons.inbox_outlined,
        selectedIcon: Icons.inbox,
        label: 'Queue',
        body: AdminQueue(),
      ),
      const _TabSpec(
        title: 'Insights',
        icon: Icons.insights_outlined,
        selectedIcon: Icons.insights,
        label: 'Insights',
        body: AdminInsights(),
      ),
      const _TabSpec(
        title: 'Community',
        icon: Icons.groups_outlined,
        selectedIcon: Icons.groups,
        label: 'Community',
        body: AdminCommunityTab(),
      ),
      // Single Team tab replaces the old Workers + Staff tabs
      const _TabSpec(
        title: 'Team',
        icon: Icons.badge_outlined,
        selectedIcon: Icons.badge,
        label: 'Team',
        body: ManageTeamScreen(),
      ),
      const _TabSpec(
        title: 'Profile',
        icon: Icons.account_circle_outlined,
        selectedIcon: Icons.account_circle,
        label: 'Profile',
        body: _AdminProfileTab(),
      ),
    ];

    // The Staff tab appears/disappears with role; keep the index in range.
    final index = _index.clamp(0, tabs.length - 1);

    return Scaffold(
      appBar: AppBar(title: Text(tabs[index].title)),
      body: SafeArea(
        child: IndexedStack(
          index: index,
          children: [for (final t in tabs) t.body],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: [
          for (final t in tabs)
            NavigationDestination(
              icon: Icon(t.icon),
              selectedIcon: Icon(t.selectedIcon),
              label: t.label,
            ),
        ],
      ),
    );
  }
}

/// Static description of one shell tab. [body] is a body-only widget (no
/// Scaffold/AppBar of its own).
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

/// The admin **Profile** tab — officer identity (name, role, department,
/// jurisdiction), appearance settings, and sign-out. Body-only.
class _AdminProfileTab extends ConsumerWidget {
  const _AdminProfileTab();

  Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text('You\'ll need to sign in again to manage reports.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sign out'),
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
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
      children: [
        _OfficerCard(profile: profile),
        const SizedBox(height: 20),
        _ActionTile(
          icon: Icons.history,
          color: NivaraColors.primary,
          title: 'My Activity',
          subtitle: 'Timeline of your assignments, actions, and posts',
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
              title: 'Pending Sync',
              subtitle: count == 0
                  ? 'All actions synced'
                  : '$count item${count == 1 ? '' : 's'} waiting to go online',
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
          icon: Icons.logout,
          color: NivaraColors.danger,
          title: 'Sign out',
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
    final name = profile?.displayName ?? 'Officer';
    final role = (profile?.role ?? UserRole.admin).label;
    final dept = profile?.department?.label;
    final area = [
      if (profile?.jurisdictionWard?.trim().isNotEmpty == true)
        profile!.jurisdictionWard!.trim(),
      if (profile?.jurisdictionCity?.trim().isNotEmpty == true)
        profile!.jurisdictionCity!.trim(),
    ].join(', ');

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
      child: Row(
        children: [
          CircleAvatar(
            radius: 30,
            backgroundColor: Colors.white.withValues(alpha: 0.2),
            child: const Icon(Icons.shield, color: Colors.white, size: 30),
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
                    fontSize: 20,
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
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    dept == null ? role : '$role · $dept',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                ),
                if (area.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(
                        Icons.place_outlined,
                        color: Colors.white70,
                        size: 15,
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          area,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white70),
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
        trailing: badge != null
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      badge!,
                      style: TextStyle(
                        color: color,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.chevron_right),
                ],
              )
            : const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
