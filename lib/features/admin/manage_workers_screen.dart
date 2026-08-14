import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../models/user_profile.dart';
import '../../models/worker_application.dart';
import '../worker/worker_repo.dart';

/// **Manage Workers** — the admin console for viewing, adding and removing
/// field workers. Shows worker status (available / on leave) and a
/// worker-applications inbox for citizens who requested to join.
///
/// Body-only (the [Scaffold]/[AppBar] belong to the admin shell).
class ManageWorkersScreen extends ConsumerStatefulWidget {
  const ManageWorkersScreen({super.key});

  @override
  ConsumerState<ManageWorkersScreen> createState() =>
      _ManageWorkersScreenState();
}

class _ManageWorkersScreenState extends ConsumerState<ManageWorkersScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab =
      TabController(length: 2, vsync: this);

  List<UserProfile> _workers = [];
  List<WorkerApplication> _applications = [];
  bool _loadingWorkers = true;
  bool _loadingApps = true;
  String? _workerError;
  String? _appError;

  @override
  void initState() {
    super.initState();
    _loadWorkers();
    _loadApplications();
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  Future<void> _loadWorkers() async {
    setState(() {
      _loadingWorkers = true;
      _workerError = null;
    });
    try {
      final list = await WorkerRepo.listWorkers();
      if (mounted) setState(() => _workers = list);
    } catch (e) {
      if (mounted) setState(() => _workerError = '$e');
    } finally {
      if (mounted) setState(() => _loadingWorkers = false);
    }
  }

  Future<void> _loadApplications() async {
    setState(() {
      _loadingApps = true;
      _appError = null;
    });
    try {
      final list = await WorkerRepo.listApplications();
      if (mounted) setState(() => _applications = list);
    } catch (e) {
      if (mounted) setState(() => _appError = '$e');
    } finally {
      if (mounted) setState(() => _loadingApps = false);
    }
  }

  Future<void> _removeWorker(UserProfile worker) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Remove worker?'),
        content: Text(
          '${worker.displayName} will be removed from the workforce and '
          'reverted to citizen status.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: NivaraColors.danger),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await WorkerRepo.removeWorker(worker.id);
      _snack('${worker.displayName} removed.');
      await _loadWorkers();
    } catch (e) {
      _snack('Could not remove: $e');
    }
  }

  Future<void> _reviewApplication(
    WorkerApplication app,
    String status,
  ) async {
    try {
      await WorkerRepo.reviewApplication(
        applicationId: app.id,
        status: status,
      );
      _snack(
        status == 'APPROVED' ? 'Application approved.' : 'Application rejected.',
      );
      await _loadApplications();
    } catch (e) {
      _snack('Could not update: $e');
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {

    // Summary counts
    final total = _workers.length;
    final onLeave = _workers.where((w) => w.isOnLeave).length;
    final available = total - onLeave;
    final pendingApps =
        _applications.where((a) => a.isPending).length;

    return Column(
      children: [
        // Summary cards
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(
            children: [
              _SummaryCard(
                label: 'Total',
                value: '$total',
                color: NivaraColors.primary,
                icon: Icons.engineering,
              ),
              const SizedBox(width: 10),
              _SummaryCard(
                label: 'Available',
                value: '$available',
                color: NivaraColors.success,
                icon: Icons.check_circle_outline,
              ),
              const SizedBox(width: 10),
              _SummaryCard(
                label: 'On Leave',
                value: '$onLeave',
                color: NivaraColors.accent,
                icon: Icons.beach_access_outlined,
              ),
              const SizedBox(width: 10),
              _SummaryCard(
                label: 'Applications',
                value: '$pendingApps',
                color: NivaraColors.danger,
                icon: Icons.inbox_outlined,
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        // Tab bar
        TabBar(
          controller: _tab,
          tabs: const [
            Tab(text: 'Workers'),
            Tab(text: 'Applications'),
          ],
        ),
        // Tab views
        Expanded(
          child: TabBarView(
            controller: _tab,
            children: [
              _WorkerList(
                workers: _workers,
                loading: _loadingWorkers,
                error: _workerError,
                onRefresh: _loadWorkers,
                onRemove: _removeWorker,
              ),
              _ApplicationList(
                applications: _applications,
                loading: _loadingApps,
                error: _appError,
                onRefresh: _loadApplications,
                onReview: _reviewApplication,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
  });

  final String label;
  final String value;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w800,
                fontSize: 18,
              ),
            ),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w600,
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WorkerList extends StatelessWidget {
  const _WorkerList({
    required this.workers,
    required this.loading,
    required this.error,
    required this.onRefresh,
    required this.onRemove,
  });

  final List<UserProfile> workers;
  final bool loading;
  final String? error;
  final VoidCallback onRefresh;
  final ValueChanged<UserProfile> onRemove;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (loading) return const Center(child: CircularProgressIndicator());
    if (error != null && workers.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off, size: 48, color: scheme.outline),
              const SizedBox(height: 12),
              Text('Could not load workers'),
              const SizedBox(height: 6),
              Text(
                '$error',
                style: TextStyle(color: scheme.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: onRefresh,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }
    if (workers.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.engineering, size: 48, color: scheme.outline),
              const SizedBox(height: 12),
              const Text('No workers yet'),
              const SizedBox(height: 6),
              Text(
                'Run supabase/seed_workers_by_category.sql to create 95 workers.',
                textAlign: TextAlign.center,
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      );
    }
    // Group by department
    final grouped = <String, List<UserProfile>>{};
    for (final w in workers) {
      final dept = w.department?.label ?? 'General';
      (grouped[dept] ??= []).add(w);
    }
    final depts = grouped.keys.toList()..sort();

    return RefreshIndicator(
      onRefresh: () async => onRefresh(),
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
        itemCount: depts.length,
        itemBuilder: (_, i) {
          final dept = depts[i];
          final deptWorkers = grouped[dept]!;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  dept,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: NivaraColors.primary,
                  ),
                ),
              ),
              for (final w in deptWorkers)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _WorkerCard(
                    worker: w,
                    onRemove: () => onRemove(w),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _WorkerCard extends StatelessWidget {
  const _WorkerCard({required this.worker, required this.onRemove});
  final UserProfile worker;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final onLeave = worker.isOnLeave;
    final statusColor = onLeave ? NivaraColors.accent : NivaraColors.success;
    final statusLabel = onLeave ? 'On Leave' : 'Available';

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: NivaraColors.primary.withValues(alpha: 0.15),
              child: Text(
                '${worker.workerNumber ?? ''}',
                style: TextStyle(
                  color: NivaraColors.primary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    worker.displayName,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          statusLabel,
                          style: TextStyle(
                            color: statusColor,
                            fontWeight: FontWeight.w600,
                            fontSize: 10,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Remove worker',
              icon: Icon(Icons.person_remove_outlined, color: NivaraColors.danger),
              onPressed: onRemove,
            ),
          ],
        ),
      ),
    );
  }
}

class _ApplicationList extends StatelessWidget {
  const _ApplicationList({
    required this.applications,
    required this.loading,
    required this.error,
    required this.onRefresh,
    required this.onReview,
  });

  final List<WorkerApplication> applications;
  final bool loading;
  final String? error;
  final VoidCallback onRefresh;
  final void Function(WorkerApplication, String) onReview;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (loading) return const Center(child: CircularProgressIndicator());
    if (applications.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.inbox_outlined, size: 48, color: scheme.outline),
              const SizedBox(height: 12),
              const Text('No applications'),
              const SizedBox(height: 6),
              Text(
                'Citizen applications to join the workforce appear here.',
                textAlign: TextAlign.center,
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: () async => onRefresh(),
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
        itemCount: applications.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (_, i) {
          final app = applications[i];
          return _ApplicationCard(
            application: app,
            onApprove: app.isPending
                ? () => onReview(app, 'APPROVED')
                : null,
            onReject: app.isPending
                ? () => onReview(app, 'REJECTED')
                : null,
          );
        },
      ),
    );
  }
}

class _ApplicationCard extends StatelessWidget {
  const _ApplicationCard({
    required this.application,
    this.onApprove,
    this.onReject,
  });

  final WorkerApplication application;
  final VoidCallback? onApprove;
  final VoidCallback? onReject;

  Color _statusColor() {
    if (application.isPending) return NivaraColors.accent;
    if (application.isApproved) return NivaraColors.success;
    return Colors.blueGrey;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: NivaraColors.primary.withValues(alpha: 0.15),
                  child: const Icon(
                    Icons.person,
                    color: NivaraColors.primary,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Applicant',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: _statusColor().withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    application.status,
                    style: TextStyle(
                      color: _statusColor(),
                      fontWeight: FontWeight.w700,
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
            if (application.message?.trim().isNotEmpty == true) ...[
              const SizedBox(height: 10),
              Text(
                application.message!.trim(),
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            ],
            if (application.isPending) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onReject,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: NivaraColors.danger,
                        side: BorderSide(
                          color: NivaraColors.danger.withValues(alpha: 0.5),
                        ),
                      ),
                      icon: const Icon(Icons.close),
                      label: const Text('Reject'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: onApprove,
                      style: FilledButton.styleFrom(
                        backgroundColor: NivaraColors.success,
                      ),
                      icon: const Icon(Icons.check),
                      label: const Text('Approve'),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
