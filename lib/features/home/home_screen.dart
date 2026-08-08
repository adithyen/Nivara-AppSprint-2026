import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../router.dart';
import '../auth/auth_controller.dart';

/// Citizen landing screen (stub). The real dashboard — SensorWatch toggle,
/// CivicMap, report/lost-found entry points, civic score — lands here next.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(authControllerProvider).asData?.value;

    return Scaffold(
      appBar: AppBar(
        title: const Text(kAppName),
        actions: [
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout),
            onPressed: () =>
                ref.read(authControllerProvider.notifier).signOut(),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'Welcome, ${profile?.displayName ?? 'Citizen'}',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 4),
          Text(
            kAppTagline,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: Theme.of(context).colorScheme.outline),
          ),
          const SizedBox(height: 20),
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
          const _ModuleCard(
            icon: Icons.travel_explore,
            color: NivaraColors.danger,
            title: 'Lost & Found',
            subtitle: 'Report lost or found items, auto-matched nearby',
            enabled: false,
          ),
        ],
      ),
    );
  }
}

/// A tappable module entry on the citizen home. `enabled: false` renders a
/// dimmed "coming soon" card for modules not built yet.
class _ModuleCard extends StatelessWidget {
  const _ModuleCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    this.onTap,
    this.enabled = true,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: Card(
        margin: EdgeInsets.zero,
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          leading: CircleAvatar(
            backgroundColor: color.withValues(alpha: 0.15),
            child: Icon(icon, color: color),
          ),
          title: Text(title,
              style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(subtitle),
          trailing: enabled
              ? const Icon(Icons.chevron_right)
              : const Chip(
                  label: Text('Soon'),
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                ),
          onTap: enabled ? onTap : null,
        ),
      ),
    );
  }
}
