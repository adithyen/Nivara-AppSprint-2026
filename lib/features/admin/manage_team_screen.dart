import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../models/enums.dart';
import '../../models/user_profile.dart';
import '../../models/worker_application.dart';
import '../auth/auth_controller.dart';
import '../worker/worker_repo.dart';
import 'manage_staff_screen.dart' show roleColor, roleIcon;

/// **Manage Team** — a unified console for every official and field worker.
///
/// Replaces the old "Workers" and "Staff" tabs with a single searchable list
/// that lets the superadmin manage roles AND lets every admin manage workers.
/// Tapping any row opens a rich employee detail sheet.
///
/// - Superadmin: sees everyone (citizens included if searched), can change roles
/// - Admin: sees workers + admins, can toggle leave / remove workers
class ManageTeamScreen extends ConsumerStatefulWidget {
  const ManageTeamScreen({super.key});

  @override
  ConsumerState<ManageTeamScreen> createState() => _ManageTeamScreenState();
}

class _ManageTeamScreenState extends ConsumerState<ManageTeamScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  // Team tab state
  final _search = TextEditingController();
  List<UserProfile> _all = [];
  bool _loading = true;
  String? _error;
  _TeamFilter _filter = _TeamFilter.workers;

  // Applications tab state
  List<WorkerApplication> _apps = [];
  bool _appsLoading = true;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _load();
    _search.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _tabs.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _appsLoading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        WorkerRepo.listAllProfiles(),
        WorkerRepo.listApplications(),
      ]);
      if (!mounted) return;
      setState(() {
        _all = results[0] as List<UserProfile>;
        _apps = results[1] as List<WorkerApplication>;
        _loading = false;
        _appsLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
        _appsLoading = false;
      });
    }
  }

  List<UserProfile> get _visible {
    final q = _search.text.trim().toLowerCase();
    return _all.where((p) {
      if (!_filter.test(p)) return false;
      if (q.isEmpty) return true;
      final hay = [
        p.displayName,
        p.role.label,
        p.department?.label ?? '',
        p.city ?? '',
        p.ward ?? '',
        if (p.workerNumber != null) 'worker ${p.workerNumber}',
      ].join(' ').toLowerCase();
      return hay.contains(q);
    }).toList()
      ..sort((a, b) {
        // Workers sorted by dept then number; admins alphabetically
        if (a.isWorker && b.isWorker) {
          final deptCmp = (a.department?.label ?? '').compareTo(
            b.department?.label ?? '',
          );
          if (deptCmp != 0) return deptCmp;
          return (a.workerNumber ?? 0).compareTo(b.workerNumber ?? 0);
        }
        return a.displayName.compareTo(b.displayName);
      });
  }

  int get _pendingApps => _apps.where((a) => a.isPending).length;

  void _openProfile(UserProfile person) {
    final me = ref.read(authControllerProvider).asData?.value;
    showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _EmployeeSheet(
        person: person,
        isSelf: person.id == me?.id,
        isSuperadmin: me?.isSuperadmin ?? false,
        onChanged: () async {
          Navigator.pop(context, true);
          await _load();
        },
      ),
    );
  }

  void _openApplication(WorkerApplication app) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ApplicationSheet(
        app: app,
        onReviewed: _load,
      ),
    );
  }

  // ── Summary stats ──────────────────────────────────────────────────
  int get _workerCount => _all.where((p) => p.isWorker).length;
  int get _availableCount =>
      _all.where((p) => p.isWorker && !p.isOnLeave).length;
  int get _onLeaveCount => _all.where((p) => p.isWorker && p.isOnLeave).length;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final pendingApps = _pendingApps;

    return Column(
      children: [
        // ── Tab bar ────────────────────────────────────────────────
        TabBar(
          controller: _tabs,
          tabs: [
            const Tab(text: 'Team'),
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Applications'),
                  if (pendingApps > 0) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: NivaraColors.danger,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '$pendingApps',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: [_buildTeamTab(scheme), _buildAppsTab(scheme)],
          ),
        ),
      ],
    );
  }

  // ────────────────────── Team tab ──────────────────────────────────
  Widget _buildTeamTab(ColorScheme scheme) {
    return Column(
      children: [
        // Summary row
        _SummaryRow(
          workers: _workerCount,
          available: _availableCount,
          onLeave: _onLeaveCount,
          loading: _loading,
        ),
        // Search + filter
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _search,
                  decoration: InputDecoration(
                    hintText: 'Search by name, department…',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    filled: true,
                    fillColor: scheme.surfaceContainerLow,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        // Filter chips
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
          child: Row(
            children: [
              for (final f in _TeamFilter.values)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: Text(f.label),
                    selected: _filter == f,
                    onSelected: (_) => setState(() => _filter = f),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null && _all.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.cloud_off, size: 48, color: scheme.outline),
                        const SizedBox(height: 12),
                        Text(_error!,
                            textAlign: TextAlign.center,
                            style: TextStyle(color: scheme.onSurfaceVariant)),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: _load,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 110),
                    itemCount: _visible.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (_, i) {
                      final p = _visible[i];
                      return _TeamMemberTile(
                        person: p,
                        onTap: () => _openProfile(p),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }

  // ────────────────────── Applications tab ──────────────────────────
  Widget _buildAppsTab(ColorScheme scheme) {
    if (_appsLoading) return const Center(child: CircularProgressIndicator());
    if (_apps.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inbox_outlined, size: 56, color: scheme.outline),
            const SizedBox(height: 12),
            const Text('No applications yet'),
            const SizedBox(height: 6),
            Text(
              'Citizens who tap "Work with Nivara" will appear here.',
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 110),
        itemCount: _apps.length,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (_, i) {
          final app = _apps[i];
          return _AppTile(
            app: app,
            onTap: () => _openApplication(app),
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Summary row widget
// ─────────────────────────────────────────────────────────────────────────────

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.workers,
    required this.available,
    required this.onLeave,
    required this.loading,
  });
  final int workers;
  final int available;
  final int onLeave;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: LinearProgressIndicator(),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      child: Row(
        children: [
          _StatChip(label: 'Workers', value: '$workers', color: NivaraColors.primary),
          const SizedBox(width: 8),
          _StatChip(label: 'Available', value: '$available', color: NivaraColors.success),
          const SizedBox(width: 8),
          _StatChip(label: 'On Leave', value: '$onLeave', color: NivaraColors.accent),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({
    required this.label,
    required this.value,
    required this.color,
  });
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
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
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Team member list tile
// ─────────────────────────────────────────────────────────────────────────────

class _TeamMemberTile extends StatelessWidget {
  const _TeamMemberTile({required this.person, required this.onTap});
  final UserProfile person;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final rc = roleColor(person.role);
    final isWorker = person.isWorker;
    final onLeave = person.isOnLeave;

    return Material(
      color: scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              // Avatar
              CircleAvatar(
                radius: 22,
                backgroundColor: rc.withValues(alpha: 0.15),
                child: Icon(roleIcon(person.role), color: rc, size: 20),
              ),
              const SizedBox(width: 12),
              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      person.displayName,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: rc.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            person.role.label,
                            style: TextStyle(
                              color: rc,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (person.department != null) ...[
                          const SizedBox(width: 6),
                          Text(
                            person.department!.label,
                            style: TextStyle(
                              color: scheme.onSurfaceVariant,
                              fontSize: 12,
                            ),
                          ),
                        ],
                        if (isWorker && person.workerNumber != null) ...[
                          const SizedBox(width: 6),
                          Text(
                            '#${person.workerNumber}',
                            style: TextStyle(
                              color: scheme.onSurfaceVariant,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              // Status badge (workers only)
              if (isWorker)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: onLeave
                        ? NivaraColors.accent.withValues(alpha: 0.12)
                        : NivaraColors.success.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    onLeave ? 'Leave' : 'Active',
                    style: TextStyle(
                      color: onLeave ? NivaraColors.accent : NivaraColors.success,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              const SizedBox(width: 4),
              Icon(Icons.chevron_right, color: scheme.outline, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Employee detail bottom sheet
// ─────────────────────────────────────────────────────────────────────────────

class _EmployeeSheet extends ConsumerStatefulWidget {
  const _EmployeeSheet({
    required this.person,
    required this.isSelf,
    required this.isSuperadmin,
    required this.onChanged,
  });
  final UserProfile person;
  final bool isSelf;
  final bool isSuperadmin;
  final VoidCallback onChanged;

  @override
  ConsumerState<_EmployeeSheet> createState() => _EmployeeSheetState();
}

class _EmployeeSheetState extends ConsumerState<_EmployeeSheet> {
  bool _busy = false;
  late bool _onLeave;
  UserRole? _selectedRole;
  AdminDepartment? _selectedDept;

  @override
  void initState() {
    super.initState();
    _onLeave = widget.person.isOnLeave;
    _selectedRole = widget.person.role;
    _selectedDept = widget.person.department;
  }

  Future<void> _save() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await WorkerRepo.setUserRole(
        userId: widget.person.id,
        role: _selectedRole!,
        department: _selectedDept,
      );
      if (mounted) widget.onChanged();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text('Error: $e')));
        setState(() => _busy = false);
      }
    }
  }
  Future<void> _removeWorker() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Remove worker?'),
        content: Text(
          '${widget.person.displayName} will be demoted to citizen status.',
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
    setState(() => _busy = true);
    try {
      await WorkerRepo.removeWorker(widget.person.id);
      if (mounted) widget.onChanged();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text('Error: $e')));
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final p = widget.person;
    final rc = roleColor(p.role);
    final isWorker = p.isWorker;
    final canChangeRole = widget.isSuperadmin && !widget.isSelf;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.65,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      builder: (_, ctrl) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: ListView(
          controller: ctrl,
          children: [
            // ── Header ──────────────────────────────────────────────
            Row(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: rc.withValues(alpha: 0.15),
                  child: Icon(roleIcon(p.role), color: rc, size: 26),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        p.displayName,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        [
                          p.role.label,
                          if (p.department != null) p.department!.label,
                          if (p.workerNumber != null) 'Worker #${p.workerNumber}',
                        ].join(' · '),
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // ── Worker leave status ──────────────────────────────────
            if (isWorker) ...[
              _SectionHeader('Availability'),
              const SizedBox(height: 8),
              Card(
                margin: EdgeInsets.zero,
                child: SwitchListTile(
                  value: _onLeave,
                  activeThumbColor: NivaraColors.accent,
                  title: const Text('On Leave'),
                  subtitle: Text(
                    _onLeave
                        ? 'Worker won\'t be assigned new tasks'
                        : 'Worker is active and can be assigned tasks',
                  ),
                  secondary: Icon(
                    _onLeave ? Icons.beach_access : Icons.check_circle_outline,
                    color: _onLeave ? NivaraColors.accent : NivaraColors.success,
                  ),
                  onChanged: _busy
                      ? null
                      : (_) async {
                          setState(() => _busy = true);
                          final messenger = ScaffoldMessenger.of(context);
                          try {
                            await WorkerRepo.setUserRole(
                              userId: p.id,
                              role: p.role,
                              department: p.department,
                            );
                            if (mounted) setState(() => _onLeave = !_onLeave);
                          } catch (e) {
                            if (mounted) {
                              messenger.showSnackBar(
                                SnackBar(content: Text('Error: $e')),
                              );
                            }
                          } finally {
                            if (mounted) setState(() => _busy = false);
                          }
                        },
                ),
              ),
              const SizedBox(height: 16),
            ],

            // ── Role management (superadmin only) ────────────────────
            if (canChangeRole) ...[
              _SectionHeader('Role'),
              const SizedBox(height: 8),
              Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                        for (final role in [
                          UserRole.citizen,
                          UserRole.worker,
                          UserRole.admin,
                          UserRole.superadmin,
                        ])
                          InkWell(
                            onTap: () => setState(() => _selectedRole = role),
                            borderRadius: BorderRadius.circular(8),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 10,
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    roleIcon(role),
                                    color: roleColor(role),
                                    size: 20,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(child: Text(role.label)),
                                  Icon(
                                    _selectedRole == role
                                        ? Icons.radio_button_checked
                                        : Icons.radio_button_unchecked,
                                    color: _selectedRole == role
                                        ? NivaraColors.primary
                                        : Theme.of(context).colorScheme.outline,
                                  ),
                                ],
                              ),
                            ),
                          ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // Department picker
              if (_selectedRole == UserRole.worker ||
                  _selectedRole == UserRole.admin) ...[
                _SectionHeader('Department'),
                const SizedBox(height: 8),
                Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                    child: DropdownButtonFormField<AdminDepartment>(
                      initialValue: _selectedDept,
                      decoration: const InputDecoration(border: InputBorder.none),
                      hint: const Text('Select department'),
                      items: [
                        for (final d in AdminDepartment.values)
                          DropdownMenuItem(
                            value: d,
                            child: Text(d.label),
                          ),
                      ],
                      onChanged: (d) => setState(() => _selectedDept = d),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              FilledButton.icon(
                onPressed: _busy ? null : _save,
                icon: _busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.save_outlined, size: 18),
                label: const Text('Save Changes'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // ── Danger zone ─────────────────────────────────────────
            if (isWorker && !widget.isSelf) ...[
              _SectionHeader('Danger Zone'),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                icon: const Icon(Icons.person_remove_outlined, size: 18),
                label: const Text('Remove from workforce'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: NivaraColors.danger,
                  side: const BorderSide(color: NivaraColors.danger),
                  minimumSize: const Size.fromHeight(48),
                ),
                onPressed: _busy ? null : _removeWorker,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Application tile + sheet
// ─────────────────────────────────────────────────────────────────────────────

class _AppTile extends StatelessWidget {
  const _AppTile({required this.app, required this.onTap});
  final WorkerApplication app;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isPending = app.isPending;
    final statusColor = isPending
        ? NivaraColors.accent
        : app.status == 'APPROVED'
            ? NivaraColors.success
            : NivaraColors.danger;

    return Material(
      color: scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: isPending ? onTap : null,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: statusColor.withValues(alpha: 0.12),
                child: Icon(
                  Icons.handshake_outlined,
                  color: statusColor,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      app.userId,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    if (app.message != null && app.message!.isNotEmpty)
                      Text(
                        app.message!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: scheme.onSurfaceVariant,
                          fontSize: 13,
                        ),
                      ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  app.status,
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (isPending) ...[
                const SizedBox(width: 4),
                Icon(Icons.chevron_right, color: scheme.outline, size: 18),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ApplicationSheet extends ConsumerStatefulWidget {
  const _ApplicationSheet({required this.app, required this.onReviewed});
  final WorkerApplication app;
  final VoidCallback onReviewed;

  @override
  ConsumerState<_ApplicationSheet> createState() => _ApplicationSheetState();
}

class _ApplicationSheetState extends ConsumerState<_ApplicationSheet> {
  bool _busy = false;

  Future<void> _review(String status) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await WorkerRepo.reviewApplication(
        applicationId: widget.app.id,
        status: status,
      );
      if (mounted) {
        Navigator.pop(context);
        widget.onReviewed();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        24 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Worker Application',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'User ID: ${app.userId}',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 13,
            ),
          ),
          if (app.message != null && app.message!.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(app.message!),
            ),
          ],
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.close, size: 18),
                  label: const Text('Reject'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: NivaraColors.danger,
                    side: const BorderSide(color: NivaraColors.danger),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: _busy ? null : () => _review('REJECTED'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  icon: const Icon(Icons.check, size: 18),
                  label: const Text('Approve'),
                  style: FilledButton.styleFrom(
                    backgroundColor: NivaraColors.success,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: _busy ? null : () => _review('APPROVED'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

enum _TeamFilter {
  workers('Workers'),
  officials('Officials'),
  all('All');

  const _TeamFilter(this.label);
  final String label;

  bool test(UserProfile p) => switch (this) {
    _TeamFilter.workers => p.isWorker,
    _TeamFilter.officials => p.isAdmin,
    _TeamFilter.all => true,
  };
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        letterSpacing: 1.2,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}
