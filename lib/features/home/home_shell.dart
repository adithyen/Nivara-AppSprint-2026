import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../community/community_tab.dart';
import '../profile/profile_tab.dart';
import '../pulse/pulse_tab.dart';
import 'home_tab.dart';

/// The citizen app shell: a four-tab bottom-nav host
/// (**Home · Pulse · Community · Profile**).
///
/// Each tab is a *body-only* widget; this shell owns the single [Scaffold],
/// the per-tab [AppBar] title, and the Material 3 [NavigationBar]. Tabs are
/// kept alive across switches with an [IndexedStack] so scroll position and
/// in-flight loads survive a tab change.
///
/// The tab set is built once in [initState]; M2 will append a fifth "Work" tab
/// here when the signed-in profile is a worker.
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
      selectedIcon: Icons.home,
      label: 'Home',
      body: HomeTab(),
    ),
    _TabSpec(
      title: 'Around you',
      icon: Icons.monitor_heart_outlined,
      selectedIcon: Icons.monitor_heart,
      label: 'Pulse',
      body: PulseTab(),
    ),
    _TabSpec(
      title: 'Community',
      icon: Icons.groups_outlined,
      selectedIcon: Icons.groups,
      label: 'Community',
      body: CommunityTab(),
    ),
    _TabSpec(
      title: 'Profile',
      icon: Icons.person_outline,
      selectedIcon: Icons.person,
      label: 'Profile',
      body: ProfileTab(),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_tabs[_index].title)),
      body: IndexedStack(
        index: _index,
        children: [for (final t in _tabs) t.body],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: [
          for (final t in _tabs)
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
