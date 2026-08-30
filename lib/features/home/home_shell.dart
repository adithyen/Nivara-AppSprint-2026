import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../core/localization/app_localizations.dart';
import '../../core/widgets/bouncy_tap.dart';
import '../../core/widgets/connectivity_banner.dart';
import '../community/community_tab.dart';
import '../profile/profile_tab.dart';
import '../pulse/pulse_tab.dart';
import '../settings/accessibility_controller.dart';
import '../settings/language_controller.dart';
import 'home_tab.dart';

/// 2026-Level Flagship Citizen App Shell with dynamic localization and high-contrast styling.
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final currentLang = ref.watch(languageControllerProvider);
    final a11y = ref.watch(accessibilityControllerProvider);

    final tabs = <_TabSpec>[
      _TabSpec(
        title: kAppName,
        icon: Icons.home_outlined,
        selectedIcon: Icons.home_rounded,
        label: NivaraStrings.tr('nav_home', currentLang),
        body: const HomeTab(),
      ),
      _TabSpec(
        title: 'City Pulse',
        icon: Icons.graphic_eq_outlined,
        selectedIcon: Icons.graphic_eq_rounded,
        label: NivaraStrings.tr('nav_pulse', currentLang),
        body: const PulseTab(),
      ),
      _TabSpec(
        title: 'Civic Community',
        icon: Icons.forum_outlined,
        selectedIcon: Icons.forum_rounded,
        label: NivaraStrings.tr('nav_community', currentLang),
        body: const CommunityTab(),
      ),
      _TabSpec(
        title: 'Citizen Profile',
        icon: Icons.person_outline_rounded,
        selectedIcon: Icons.person_rounded,
        label: NivaraStrings.tr('nav_profile', currentLang),
        body: const ProfileTab(),
      ),
    ];

    return Scaffold(
      extendBody: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: WithConnectivityBanner(
        child: SafeArea(
          bottom: false,
          child: IndexedStack(
            index: _index,
            children: [for (final t in tabs) t.body],
          ),
        ),
      ),
      bottomNavigationBar: _buildGlassNavBar(tabs, a11y),
    );
  }

  Widget _buildGlassNavBar(List<_TabSpec> tabs, AccessibilityState a11y) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = Theme.of(context).colorScheme.primary;

    return SafeArea(
      child: Container(
        margin: const EdgeInsets.fromLTRB(18, 0, 18, 12),
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
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: a11y.highContrast
                    ? (isDark ? Colors.black : Colors.white)
                    : (isDark
                        ? const Color(0xFF10161E).withValues(alpha: 0.88)
                        : Colors.white.withValues(alpha: 0.92)),
                borderRadius: BorderRadius.circular(26),
                border: Border.all(
                  color: a11y.highContrast
                      ? primary
                      : (isDark
                          ? Colors.white.withValues(alpha: 0.12)
                          : Colors.black.withValues(alpha: 0.08)),
                  width: a11y.highContrast ? 2.5 : 1.2,
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: List.generate(tabs.length, (i) {
                  final t = tabs[i];
                  final isSelected = _index == i;
                  return BouncyTap(
                    scaleFactor: 0.92,
                    onTap: () {
                      if (_index != i) {
                        if (a11y.hapticsEnabled) HapticFeedback.mediumImpact();
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
                            ? primary.withValues(alpha: isDark ? 0.18 : 0.12)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(18),
                        border: isSelected
                            ? Border.all(
                                color: primary.withValues(alpha: isDark ? 0.6 : 0.4),
                                width: a11y.highContrast ? 2.0 : 1.2,
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
                            size: 22,
                          ),
                          if (isSelected) ...[
                            const SizedBox(width: 8),
                            Text(
                              t.label,
                              style: TextStyle(
                                color: primary,
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
