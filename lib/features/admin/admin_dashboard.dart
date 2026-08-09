import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_controller.dart';
import 'admin_queue.dart';

/// Municipal (admin) home. Hosts the live report queue and carries the signed-in
/// officer's identity + department in the bar. Role access is enforced by the
/// router guard (citizens can't reach `/admin`) and, authoritatively, by RLS +
/// the `admin_set_report_status` RPC on the server.
class AdminDashboard extends ConsumerWidget {
  const AdminDashboard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(authControllerProvider).asData?.value;
    final dept = profile?.department?.label;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Nivara Admin'),
            Text(
              dept == null
                  ? 'Municipal authority'
                  : '$dept · ${profile?.displayName ?? 'Officer'}',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w400,
                color: Colors.white70,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout),
            onPressed: () =>
                ref.read(authControllerProvider.notifier).signOut(),
          ),
        ],
      ),
      body: const SafeArea(child: AdminQueue()),
    );
  }
}
