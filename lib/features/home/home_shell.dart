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
import 'home_tab.dart';

/// 2026-Level Flagship Citizen App Shell with floating glass bottom navigation bar.
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int _index = 0;

  static const _tabs = <_TabSpec>[
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
      title: 'Civic Community',
      icon: Icons.forum_outlined,
      selectedIcon: Icons.forum_rounded,
      label: 'Community',
      body: CommunityTab(),
    ),
    _TabSpec(
      title: 'Citizen Profile',
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
      backgroundColor: NivaraColors.canvasDark,
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
    return SafeArea(
      child: Container(
        margin: const EdgeInsets.fromLTRB(18, 0, 18, 12),
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
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
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
                        horizontal: isSelected ? 16 : 10,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? NivaraColors.primary.withValues(alpha: 0.18)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(18),
                        border: isSelected
                            ? Border.all(
                                color: NivaraColors.primary.withValues(alpha: 0.6),
                                width: 1.2,
                              )
                            : null,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isSelected ? t.selectedIcon : t.icon,
                            color: isSelected ? NivaraColors.primary : Colors.white60,
                            size: 22,
                          ),
                          if (isSelected) ...[
                            const SizedBox(width: 8),
                            Text(
                              t.label,
                              style: const TextStyle(
                                color: NivaraColors.primary,
                                fontSize: 12.5,
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
