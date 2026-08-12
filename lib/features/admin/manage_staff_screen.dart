import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../models/enums.dart';
import '../../models/user_profile.dart';
import '../auth/auth_controller.dart';
import '../worker/worker_repo.dart';

/// **Manage Staff** — the superadmin's console for turning citizens into field
/// workers or municipal officials and setting their department. Every role
/// change goes through the `set_user_role` SECURITY DEFINER RPC, which
/// re-checks `is_superadmin(auth.uid())` on the server, so a spoofed client
/// flag can't grant anyone access.
///
/// Body-only (the [Scaffold]/[AppBar] belong to the admin shell). Non-superadmins
/// see a locked notice — the shell hides the tab, this is defence in depth.
class ManageStaffScreen extends ConsumerStatefulWidget {
  const ManageStaffScreen({super.key});

  @override
  ConsumerState<ManageStaffScreen> createState() => _ManageStaffScreenState();
}

class _ManageStaffScreenState extends ConsumerState<ManageStaffScreen> {
  final _search = TextEditingController();
  List<UserProfile> _all = [];
  bool _loading = true;
  String? _error;
  _RoleFilter _filter = _RoleFilter.all;

  @override
  void initState() {
    super.initState();
    _load();
    _search.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await WorkerRepo.listAllProfiles();
      if (!mounted) return;
      setState(() {
        _all = rows;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
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
      ].join(' ').toLowerCase();
      return hay.contains(q);
    }).toList();
  }

  Future<void> _editRole(UserProfile profile) async {
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _RoleSheet(profile: profile),
    );
    if (changed == true) {
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(content: Text('${profile.displayName} updated.')),
          );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(authControllerProvider).asData?.value;
    if (me != null && !me.isSuperadmin) {
      return const _Locked();
    }

    return Column(
      children: [
        _SearchAndFilter(
          controller: _search,
          filter: _filter,
          counts: _all,
          onFilter: (f) => setState(() => _filter = f),
        ),
        Expanded(child: _body(me)),
      ],
    );
  }

  Widget _body(UserProfile? me) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null && _all.isEmpty) {
      return _Empty(
        icon: Icons.cloud_off,
        title: 'Could not load staff',
        subtitle: '$_error',
      );
    }
    final items = _visible;
    if (items.isEmpty) {
      return const _Empty(
        icon: Icons.people_outline,
        title: 'No one here',
        subtitle: 'No accounts match this view.',
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (_, i) {
          final p = items[i];
          return _StaffCard(
            profile: p,
            isSelf: p.id == me?.id,
            onEdit: () => _editRole(p),
          );
        },
      ),
    );
  }
}

/// Colour used for a role's chip + avatar tint across this screen.
Color roleColor(UserRole r) => switch (r) {
  UserRole.citizen => Colors.blueGrey,
  UserRole.worker => NivaraColors.accent,
  UserRole.admin => NivaraColors.primary,
  UserRole.superadmin => const Color(0xFF7B4BC4),
};

IconData roleIcon(UserRole r) => switch (r) {
  UserRole.citizen => Icons.person_outline,
  UserRole.worker => Icons.engineering,
  UserRole.admin => Icons.shield_outlined,
  UserRole.superadmin => Icons.workspace_premium,
};

enum _RoleFilter {
  all('All'),
  citizens('Citizens'),
  workers('Workers'),
  officials('Officials');

  const _RoleFilter(this.label);
  final String label;

  bool test(UserProfile p) => switch (this) {
    _RoleFilter.all => true,
    _RoleFilter.citizens => p.role == UserRole.citizen,
    _RoleFilter.workers => p.role == UserRole.worker,
    _RoleFilter.officials =>
      p.role == UserRole.admin || p.role == UserRole.superadmin,
  };
}

class _SearchAndFilter extends StatelessWidget {
  const _SearchAndFilter({
    required this.controller,
    required this.filter,
    required this.counts,
    required this.onFilter,
  });

  final TextEditingController controller;
  final _RoleFilter filter;
  final List<UserProfile> counts;
  final ValueChanged<_RoleFilter> onFilter;

  int _count(_RoleFilter f) => counts.where(f.test).length;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
          child: TextField(
            controller: controller,
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Search name, area, role…',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: controller.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: controller.clear,
                    ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
          child: Row(
            children: [
              for (final f in _RoleFilter.values)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text('${f.label} · ${_count(f)}'),
                    selected: f == filter,
                    onSelected: (_) => onFilter(f),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StaffCard extends StatelessWidget {
  const _StaffCard({
    required this.profile,
    required this.isSelf,
    required this.onEdit,
  });

  final UserProfile profile;
  final bool isSelf;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final c = roleColor(profile.role);
    final area = [
      if (profile.department != null) profile.department!.label,
      if (profile.city?.trim().isNotEmpty == true) profile.city!.trim(),
      if (profile.ward?.trim().isNotEmpty == true) profile.ward!.trim(),
    ].join(' · ');

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: c.withValues(alpha: 0.15),
              child: Icon(roleIcon(profile.role), color: c),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          profile.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      if (isSelf) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: scheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'You',
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      _RolePill(role: profile.role),
                      if (area.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            area,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (isSelf)
              // Guard: a superadmin can't change their own role here — that's how
              // you'd accidentally lock yourself out of the console.
              Tooltip(
                message: "You can't change your own role",
                child: Icon(Icons.lock_outline, color: scheme.outline),
              )
            else
              OutlinedButton(onPressed: onEdit, child: const Text('Change')),
          ],
        ),
      ),
    );
  }
}

class _RolePill extends StatelessWidget {
  const _RolePill({required this.role});
  final UserRole role;

  @override
  Widget build(BuildContext context) {
    final c = roleColor(role);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        role.label,
        style: TextStyle(color: c, fontWeight: FontWeight.w700, fontSize: 11.5),
      ),
    );
  }
}

/// The role-change editor. Pick a role; officials and workers also pick a
/// department. City/ward carry the person's jurisdiction. Saving calls
/// [WorkerRepo.setUserRole]; the server enforces the superadmin check.
class _RoleSheet extends StatefulWidget {
  const _RoleSheet({required this.profile});
  final UserProfile profile;

  @override
  State<_RoleSheet> createState() => _RoleSheetState();
}

class _RoleSheetState extends State<_RoleSheet> {
  late UserRole _role = widget.profile.role;
  late AdminDepartment? _dept = widget.profile.department;
  late final _cityCtrl = TextEditingController(
    text: widget.profile.jurisdictionCity ?? widget.profile.city ?? '',
  );
  late final _wardCtrl = TextEditingController(
    text: widget.profile.jurisdictionWard ?? widget.profile.ward ?? '',
  );
  bool _saving = false;
  String? _error;

  bool get _needsDept => _role == UserRole.worker || _role == UserRole.admin;

  @override
  void dispose() {
    _cityCtrl.dispose();
    _wardCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_needsDept && _dept == null) {
      setState(() => _error = 'Pick a department for this role.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await WorkerRepo.setUserRole(
        userId: widget.profile.id,
        role: _role,
        department: _needsDept ? _dept : null,
        city: _cityCtrl.text.trim().isEmpty ? null : _cityCtrl.text.trim(),
        ward: _wardCtrl.text.trim().isEmpty ? null : _wardCtrl.text.trim(),
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    // Superadmin is intentionally not an assignable role from this UI — bootstrap
    // the first (and any further) superadmin in the SQL editor.
    const assignable = [UserRole.citizen, UserRole.worker, UserRole.admin];
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 4, 20, 20 + bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Role — ${widget.profile.displayName}',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              'Change what this person can do in Nivara.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final r in assignable)
                  ChoiceChip(
                    avatar: Icon(
                      roleIcon(r),
                      size: 18,
                      color: _role == r ? Colors.white : roleColor(r),
                    ),
                    label: Text(r.label),
                    selected: _role == r,
                    selectedColor: roleColor(r),
                    labelStyle: TextStyle(
                      color: _role == r ? Colors.white : null,
                      fontWeight: FontWeight.w600,
                    ),
                    onSelected: (_) => setState(() {
                      _role = r;
                      _error = null;
                    }),
                  ),
              ],
            ),
            if (_needsDept) ...[
              const SizedBox(height: 18),
              Text(
                'Department',
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final d in AdminDepartment.values)
                    ChoiceChip(
                      label: Text(d.label),
                      selected: _dept == d,
                      onSelected: (_) => setState(() {
                        _dept = d;
                        _error = null;
                      }),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _cityCtrl,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'City (optional)',
                      isDense: true,
                      prefixIcon: Icon(Icons.location_city_outlined),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _wardCtrl,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Ward (optional)',
                      isDense: true,
                    ),
                  ),
                ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.save),
                label: Text(_saving ? 'Saving…' : 'Save role'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Locked extends StatelessWidget {
  const _Locked();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_outline, size: 56, color: scheme.outline),
            const SizedBox(height: 12),
            Text(
              'Superadmin only',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
              'Only a super admin can manage staff roles.',
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({
    required this.icon,
    required this.title,
    required this.subtitle,
  });
  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.all(32),
      children: [
        const SizedBox(height: 60),
        Icon(icon, size: 56, color: scheme.outline),
        const SizedBox(height: 12),
        Text(
          title,
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}
