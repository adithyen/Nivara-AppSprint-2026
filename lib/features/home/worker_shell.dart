import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../community/community_tab.dart';
import '../profile/profile_tab.dart';
import '../pulse/pulse_tab.dart';
import 'home_tab.dart';
import '../worker/worker_dashboard.dart';

/// The **field-worker app shell** — gives workers full citizen access plus a
/// dedicated "My Tasks" tab at position 0.
///
/// Tab order: Tasks · Home · Pulse · Community · Profile
///
/// On Leave / Resign controls live in the Profile tab (Work Status card);
/// the AppBar is clean with only the task count badge.
class WorkerShell extends ConsumerStatefulWidget {
  const WorkerShell({super.key});

  @override
  ConsumerState<WorkerShell> createState() => _WorkerShellState();
}

class _WorkerShellState extends ConsumerState<WorkerShell> {
  int _index = 0;

  static const _tabs = <_TabSpec>[
    _TabSpec(
      title: 'My Tasks',
      icon: Icons.engineering_outlined,
      selectedIcon: Icons.engineering,
      label: 'Tasks',
      body: WorkerDashboard(),
    ),
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
      body: SafeArea(
        child: IndexedStack(
          index: _index,
          children: [for (final t in _tabs) t.body],
        ),
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
