import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../core/widgets/bouncy_tap.dart';
import '../../core/widgets/connectivity_banner.dart';
import '../community/community_tab.dart';
import '../profile/profile_tab.dart';
import '../pulse/pulse_tab.dart';
import '../worker/worker_dashboard.dart';
import 'home_tab.dart';

/// 2026-Level Field Worker Shell featuring floating glass navbar and rapid task access.
class WorkerShell extends ConsumerStatefulWidget {
  const WorkerShell({super.key});

  @override
  ConsumerState<WorkerShell> createState() => _WorkerShellState();
}

class _WorkerShellState extends ConsumerState<WorkerShell> {
  int _index = 0;

  static const _tabs = <_TabSpec>[
    _TabSpec(
      title: 'Field Tasks',
      icon: Icons.engineering_outlined,
      selectedIcon: Icons.engineering_rounded,
      label: 'Tasks',
      body: WorkerDashboard(),
    ),
    _TabSpec(
      title: kAppName,
      icon: Icons.home_outlined,
      selectedIcon: Icons.home_rounded,
      label: 'Home',
      body: HomeTab(),
    ),
    _TabSpec(
      title: 'City Pulse',
      icon: Icons.graphic_eq_outlined,
      selectedIcon: Icons.graphic_eq_rounded,
      label: 'Pulse',
      body: PulseTab(),
    ),
    _TabSpec(
      title: 'Community',
      icon: Icons.forum_outlined,
      selectedIcon: Icons.forum_rounded,
      label: 'Community',
      body: CommunityTab(),
    ),
    _TabSpec(
      title: 'Staff Profile',
      icon: Icons.person_outline_rounded,
      selectedIcon: Icons.person_rounded,
      label: 'Profile',
      body: ProfileTab(),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: WithConnectivityBanner(
        child: SafeArea(
          bottom: false,
          child: IndexedStack(
            index: _index,
            children: [for (final t in _tabs) t.body],
          ),
        ),
      ),
      bottomNavigationBar: _buildGlassNavBar(),
    );
  }

  Widget _buildGlassNavBar() {
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
                children: List.generate(_tabs.length, (i) {
                  final t = _tabs[i];
                  final isSelected = _index == i;
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
