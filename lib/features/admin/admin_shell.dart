import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/widgets/bouncy_tap.dart';
import '../../core/widgets/connectivity_banner.dart';
import '../profile/profile_tab.dart';
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
        body: ProfileTab(),
      ),
    ];

    final index = _index.clamp(0, tabs.length - 1);

    return Scaffold(
      extendBody: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: WithConnectivityBanner(
        child: SafeArea(
          bottom: false,
          child: IndexedStack(
            index: index,
            children: [for (final t in tabs) t.body],
          ),
        ),
      ),
      bottomNavigationBar: _buildGlassNavBar(tabs, index),
    );
  }

  Widget _buildGlassNavBar(List<_TabSpec> tabs, int index) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = Theme.of(context).colorScheme.primary;

    return SafeArea(
      child: Container(
        margin: const EdgeInsets.fromLTRB(14, 0, 14, 12),
        height: 66,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(26),
          boxShadow: [
            BoxShadow(
              color: isDark
                  ? Colors.black.withValues(alpha: 0.55)
                  : Colors.black.withValues(alpha: 0.08),
              blurRadius: isDark ? 28 : 20,
              offset: isDark ? const Offset(0, 10) : const Offset(0, 4),
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
                color: isDark
                    ? const Color(0xFF10161E).withValues(alpha: 0.88)
                    : Colors.white.withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(26),
                border: Border.all(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.12)
                      : Colors.black.withValues(alpha: 0.08),
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
                            ? primary.withValues(alpha: isDark ? 0.18 : 0.12)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(18),
                        border: isSelected
                            ? Border.all(
                                color: primary.withValues(alpha: isDark ? 0.6 : 0.4),
                                width: 1.2,
                              )
                            : null,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isSelected ? t.selectedIcon : t.icon,
                            color: isSelected
                                ? primary
                                : (isDark ? Colors.white60 : Colors.black54),
                            size: 20,
                          ),
                          if (isSelected) ...[
                            const SizedBox(width: 6),
                            Text(
                              t.label,
                              style: TextStyle(
                                color: primary,
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
