import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/civic_level.dart';
import '../../core/constants.dart';
import '../../core/services/offline_queue_service.dart';
import '../../core/supabase_client.dart';
import '../../core/theme.dart';
import '../../core/widgets/civic_level_view.dart';
import '../../models/enums.dart';
import '../../models/user_profile.dart';
import '../../router.dart';
import '../auth/auth_controller.dart';
import '../worker/worker_repo.dart';

/// The **Profile** tab — account identity, a live civic-impact summary, the
/// "Work with Nivara" entry, profile editing, and sign-out.
///
/// Body-only (the [Scaffold]/[AppBar] belong to the shell). Impact counts are
/// computed live from the database (the profile counters have no maintaining
/// triggers), mirroring the Home dashboard. "Work with Nivara" is the citizen's
/// door to becoming a verified worker — the application flow lands in M4; for
/// now it explains what's coming.
class ProfileTab extends ConsumerStatefulWidget {
  const ProfileTab({super.key});

  @override
  ConsumerState<ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends ConsumerState<ProfileTab> {
  bool _loading = true;
  int _reports = 0;
  int _confirms = 0;
  int _finds = 0;

  // Worker-specific state
  bool _onLeave = false;
  bool _leaveWorking = false;

  // Offline queue badge
  int _pendingCount = 0;

  int get _civicScore => _reports * 10 + _confirms * 5 + _finds * 15;

  @override
  void initState() {
    super.initState();
    _load();
    _loadPendingCount();
    // Sync leave status for workers
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final profile = ref.read(authControllerProvider).asData?.value;
      if (profile?.isWorker == true && mounted) {
        setState(() => _onLeave = profile!.isOnLeave);
      }
    });
  }

  Future<void> _loadPendingCount() async {
    final count = await OfflineQueueService.pendingCount();
    if (mounted) setState(() => _pendingCount = count);
  }

  Future<void> _load() async {
    final uid = ref.read(authControllerProvider).asData?.value?.id;
    final reports = await _count(kTableReports, uid, {});
    final confirms = await _count(kTableConfirmations, uid, {
      'type': 'CONFIRM',
    });
    final finds = await _count(kTableLfItems, uid, {'item_type': 'FOUND'});
    if (!mounted) return;
    setState(() {
      _reports = reports;
      _confirms = confirms;
      _finds = finds;
      _loading = false;
    });
  }

  Future<int> _count(String table, String? uid, Map<String, String> eq) async {
    if (uid == null) return 0;
    try {
      var q = supabase.from(table).select('id').eq('user_id', uid);
      eq.forEach((k, v) => q = q.eq(k, v));
      final rows = await q;
      return (rows as List).length;
    } catch (_) {
      return 0;
    }
  }

  Future<void> _editProfile(UserProfile profile) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _EditProfileSheet(profile: profile),
    );
    if (saved == true) {
      await ref.read(authControllerProvider.notifier).refresh();
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(content: Text('Profile updated.')));
      }
    }
  }

  void _workWithNivara() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => const _WorkWithNivaraSheet(),
    );
  }

  Future<void> _toggleLeave() async {
    setState(() => _leaveWorking = true);
    try {
      if (_onLeave) {
        await WorkerRepo.markAvailable();
        if (mounted) setState(() => _onLeave = false);
      } else {
        await WorkerRepo.goOnLeave();
        if (mounted) setState(() => _onLeave = true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text('Could not update: $e')));
      }
    } finally {
      if (mounted) setState(() => _leaveWorking = false);
    }
  }

  Future<void> _resign() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Resign from Nivara?'),
        content: const Text(
          'You will be removed from the field workforce and your account will '
          'revert to citizen status. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: NivaraColors.danger),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Resign'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await WorkerRepo.resign();
      if (mounted) ref.read(authControllerProvider.notifier).signOut();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text('Could not resign: $e')));
      }
    }
  }

  Future<void> _signOut() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text('You\'ll need to sign in again to file reports.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(authControllerProvider.notifier).signOut();
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(authControllerProvider).asData?.value;
    final isCitizen = profile?.role == UserRole.citizen;
    final isWorker = profile?.isWorker ?? false;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
        children: [
          _IdentityCard(profile: profile),
          const SizedBox(height: 20),
          _ImpactCard(
            loading: _loading,
            score: _civicScore,
            reports: _reports,
            confirms: _confirms,
            finds: _finds,
          ),
          const SizedBox(height: 20),
          // ── Worker Status Card ────────────────────────────────────
          if (isWorker) ...[
            _WorkStatusCard(
              onLeave: _onLeave,
              working: _leaveWorking,
              profile: profile,
              onToggleLeave: _toggleLeave,
              onResign: _resign,
            ),
            const SizedBox(height: 20),
          ],
          // ── Citizen: Work with Nivara entry ───────────────────────
          if (isCitizen) ...[
            _ActionTile(
              icon: Icons.handshake_outlined,
              color: NivaraColors.accent,
              title: 'Work with Nivara',
              subtitle: 'Become a verified worker and take on civic jobs',
              onTap: _workWithNivara,
            ),
            const SizedBox(height: 12),
          ],
          // ── Activity & Sync tiles ──────────────────────────────
          _ActionTile(
            icon: Icons.history,
            color: NivaraColors.primary,
            title: 'My Activity',
            subtitle: 'Timeline of your reports, posts, and tasks',
            onTap: () => context.push(Routes.activityLog),
          ),
          const SizedBox(height: 12),
          _ActionTile(
            icon: Icons.cloud_upload_outlined,
            color: NivaraColors.accent,
            title: 'Pending Sync',
            subtitle: _pendingCount == 0
                ? 'All items synced'
                : '$_pendingCount item${_pendingCount == 1 ? '' : 's'} waiting to go online',
            badge: _pendingCount > 0 ? '$_pendingCount' : null,
            onTap: () async {
              await context.push(Routes.pendingSync);
              _loadPendingCount();
            },
          ),
          const SizedBox(height: 12),
          _ActionTile(
            icon: Icons.edit_outlined,
            color: NivaraColors.primary,
            title: 'Edit profile',
            subtitle: 'Name, contact, and area',
            onTap: profile == null ? null : () => _editProfile(profile),
          ),
          const SizedBox(height: 12),
          _ActionTile(
            icon: Icons.palette_outlined,
            color: const Color(0xFF7B4BC4),
            title: 'Appearance',
            subtitle: 'Theme mode and accent colour',
            onTap: () => context.push(Routes.settings),
          ),
          const SizedBox(height: 12),
          _ActionTile(
            icon: Icons.logout,
            color: NivaraColors.danger,
            title: 'Sign out',
            subtitle: 'End your session on this device',
            onTap: _signOut,
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Work Status Card  (shown only to workers)
// ─────────────────────────────────────────────────────────────────────────────

class _WorkStatusCard extends StatelessWidget {
  const _WorkStatusCard({
    required this.onLeave,
    required this.working,
    required this.profile,
    required this.onToggleLeave,
    required this.onResign,
  });

  final bool onLeave;
  final bool working;
  final UserProfile? profile;
  final VoidCallback onToggleLeave;
  final VoidCallback onResign;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dept = profile?.department?.label ?? 'Field';
    final workerNum = profile?.workerNumber;
    final statusColor = onLeave ? NivaraColors.accent : NivaraColors.success;
    final statusLabel = onLeave ? 'On Leave' : 'Available';
    final statusIcon = onLeave ? Icons.beach_access : Icons.check_circle_outline;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Header label ───────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            'WORK STATUS',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
              letterSpacing: 1.2,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        // ── Status card ────────────────────────────────────────────
        Container(
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
          ),
          child: Column(
            children: [
              // On leave toggle row
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(statusIcon, color: statusColor, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            statusLabel,
                            style: TextStyle(
                              color: statusColor,
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                            ),
                          ),
                          Text(
                            onLeave
                                ? 'No new tasks will be assigned to you'
                                : 'You can receive new task assignments',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    working
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2.5),
                          )
                        : Switch(
                            value: onLeave,
                            activeThumbColor: NivaraColors.accent,
                            onChanged: (_) => onToggleLeave(),
                          ),
                  ],
                ),
              ),
              Divider(height: 1, color: scheme.outlineVariant.withValues(alpha: 0.4)),
              // Department + Worker number info row
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    Icon(Icons.badge_outlined, size: 18, color: scheme.onSurfaceVariant),
                    const SizedBox(width: 8),
                    Text(
                      dept,
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (workerNum != null) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: NivaraColors.primary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          'Worker #$workerNum',
                          style: const TextStyle(
                            color: NivaraColors.primary,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // ── Danger: Resign ──────────────────────────────────────────
        OutlinedButton.icon(
          icon: const Icon(Icons.person_remove_outlined, size: 18),
          label: const Text('Resign from Nivara'),
          style: OutlinedButton.styleFrom(
            foregroundColor: NivaraColors.danger,
            side: const BorderSide(color: NivaraColors.danger, width: 1.2),
            padding: const EdgeInsets.symmetric(vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          onPressed: onResign,
        ),
      ],
    );
  }
}


class _IdentityCard extends StatelessWidget {
  const _IdentityCard({required this.profile});
  final UserProfile? profile;

  @override
  Widget build(BuildContext context) {
    final name = profile?.displayName ?? 'Citizen';
    final area = [
      if (profile?.ward != null && profile!.ward!.trim().isNotEmpty)
        profile!.ward!.trim(),
      if (profile?.city != null && profile!.city!.trim().isNotEmpty)
        profile!.city!.trim(),
    ].join(', ');

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [NivaraColors.primary, Color(0xFF124D77)],
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 30,
            backgroundColor: Colors.white.withValues(alpha: 0.2),
            child: Text(
              name.isNotEmpty ? name.characters.first.toUpperCase() : '?',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 26,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    (profile?.role ?? UserRole.citizen).label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                ),
                if (area.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(
                        Icons.place_outlined,
                        color: Colors.white70,
                        size: 15,
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          area,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white70),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Derived civic-impact score + the three activity counts feeding it. Mirrors
/// the Home hero so the number is consistent across the app.
class _ImpactCard extends StatelessWidget {
  const _ImpactCard({
    required this.loading,
    required this.score,
    required this.reports,
    required this.confirms,
    required this.finds,
  });

  final bool loading;
  final int score;
  final int reports;
  final int confirms;
  final int finds;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.workspace_premium,
                color: NivaraColors.primary,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                'Civic impact',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              Text(
                loading ? '—' : '$score pts',
                style: const TextStyle(
                  color: NivaraColors.primary,
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _Stat(
                icon: Icons.report_outlined,
                value: reports,
                label: 'Reports',
                loading: loading,
              ),
              _Divider(),
              _Stat(
                icon: Icons.thumb_up_alt_outlined,
                value: confirms,
                label: 'Confirms',
                loading: loading,
              ),
              _Divider(),
              _Stat(
                icon: Icons.volunteer_activism_outlined,
                value: finds,
                label: 'Finds',
                loading: loading,
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(height: 1),
          const SizedBox(height: 14),
          CivicLevelBar(standing: civicStandingFor(score)),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({
    required this.icon,
    required this.value,
    required this.label,
    required this.loading,
  });

  final IconData icon;
  final int value;
  final String label;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Expanded(
      child: Column(
        children: [
          Icon(icon, color: NivaraColors.primary, size: 20),
          const SizedBox(height: 6),
          Text(
            loading ? '—' : '$value',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    width: 1,
    height: 40,
    color: Theme.of(context).colorScheme.outlineVariant,
  );
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.badge,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.15),
          child: Icon(icon, color: color),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle),
        trailing: badge != null
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      badge!,
                      style: TextStyle(
                        color: color,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.chevron_right),
                ],
              )
            : const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}


/// Editable subset of the profile (display name, phone, city, ward). Role and
/// jurisdiction are never editable here — those move through admin RPCs.
class _EditProfileSheet extends ConsumerStatefulWidget {
  const _EditProfileSheet({required this.profile});
  final UserProfile profile;

  @override
  ConsumerState<_EditProfileSheet> createState() => _EditProfileSheetState();
}

class _EditProfileSheetState extends ConsumerState<_EditProfileSheet> {
  late final _nameCtrl = TextEditingController(
    text: widget.profile.displayName,
  );
  late final _phoneCtrl = TextEditingController(
    text: widget.profile.phone ?? '',
  );
  late final _cityCtrl = TextEditingController(text: widget.profile.city ?? '');
  late final _wardCtrl = TextEditingController(text: widget.profile.ward ?? '');
  bool _saving = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _cityCtrl.dispose();
    _wardCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_nameCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Name can\'t be empty.')));
      return;
    }
    setState(() => _saving = true);
    final updated = widget.profile.copyWith(
      displayName: _nameCtrl.text.trim(),
      phone: _phoneCtrl.text.trim(),
      city: _cityCtrl.text.trim(),
      ward: _wardCtrl.text.trim(),
    );
    try {
      await supabase
          .from(kTableProfiles)
          .update(updated.toUpdateMap())
          .eq('id', widget.profile.id);
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not save: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    final email = supabase.auth.currentUser?.email ?? '';
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 4, 20, 20 + bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Edit profile',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 16),
          if (email.isNotEmpty) ...[
            TextField(
              enabled: false,
              controller: TextEditingController(text: email),
              decoration: const InputDecoration(
                labelText: 'Email (account login)',
                prefixIcon: Icon(Icons.mail_outline),
              ),
            ),
            const SizedBox(height: 12),
          ],
          TextField(
            controller: _nameCtrl,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Display name',
              prefixIcon: Icon(Icons.person_outline),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _phoneCtrl,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              labelText: 'Phone (optional)',
              prefixIcon: Icon(Icons.call_outlined),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _cityCtrl,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'City',
                    prefixIcon: Icon(Icons.location_city_outlined),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _wardCtrl,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Ward'),
                ),
              ),
            ],
          ),
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
              label: Text(_saving ? 'Saving…' : 'Save'),
            ),
          ),
        ],
      ),
    );
  }
}

/// Application form for citizens who want to join the Nivara field workforce.
/// Submits via the `submit_worker_application` RPC; the admin sees it in the
/// Workers tab and can approve or reject.
class _WorkWithNivaraSheet extends StatefulWidget {
  const _WorkWithNivaraSheet();

  @override
  State<_WorkWithNivaraSheet> createState() => _WorkWithNivaraSheetState();
}

class _WorkWithNivaraSheetState extends State<_WorkWithNivaraSheet> {
  final _message = TextEditingController();
  bool _submitting = false;
  bool _submitted = false;
  String? _error;

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await WorkerRepo.submitApplication(message: _message.text.trim());
      if (mounted) setState(() => _submitted = true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _submitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(24, 4, 24, 28 + bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor: NivaraColors.accent.withValues(alpha: 0.15),
                child: const Icon(
                  Icons.handshake_outlined,
                  color: NivaraColors.accent,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'Work with Nivara',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_submitted) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: NivaraColors.success.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle, color: NivaraColors.success),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Application submitted!',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: NivaraColors.success,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'A municipal official will review your request and get in touch.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Done'),
              ),
            ),
          ] else ...[
            const Text(
              'Verified workers take on assigned civic jobs in their area — '
              'fixing potholes, clearing drains, restoring street lights — and '
              'track each job to resolution right inside Nivara.',
            ),
            const SizedBox(height: 12),
            const _Bullet('Get civic work assigned by municipal officials'),
            const _Bullet('Navigate to each job and post progress updates'),
            const _Bullet('Build a public track record of resolved issues'),
            const SizedBox(height: 16),
            TextField(
              controller: _message,
              maxLines: 3,
              maxLength: 400,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Why do you want to join? (optional)',
                hintText: 'Share your motivation, skills or experience...',
                alignLabelWithHint: true,
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _submitting ? null : _submit,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                  backgroundColor: NivaraColors.accent,
                ),
                icon: _submitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.send),
                label: Text(_submitting ? 'Submitting…' : 'Submit Application'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: Icon(
              Icons.check_circle,
              size: 18,
              color: NivaraColors.success,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}
