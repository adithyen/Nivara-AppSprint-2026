import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/civic_level.dart';
import '../../core/constants.dart';
import '../../core/services/offline_queue_service.dart';
import '../../core/supabase_client.dart';
import '../../core/theme.dart';
import '../../core/widgets/bouncy_tap.dart';
import '../../core/widgets/civic_level_view.dart';
import '../../core/widgets/glass_card.dart';
import '../../models/enums.dart';
import '../../models/user_profile.dart';
import '../../router.dart';
import '../auth/auth_controller.dart';
import '../worker/worker_repo.dart';

/// 2026-Level Flagship Profile Dashboard.
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

  bool _onLeave = false;
  bool _leaveWorking = false;
  int _pendingCount = 0;

  int get _civicScore => _reports * 10 + _confirms * 5 + _finds * 15;

  @override
  void initState() {
    super.initState();
    _load();
    _loadPendingCount();
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
      backgroundColor: const Color(0xFF10161E),
      showDragHandle: true,
      builder: (_) => _EditProfileSheet(profile: profile),
    );
    if (saved == true) {
      await ref.read(authControllerProvider.notifier).refresh();
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(content: Text('Profile updated successfully.')));
      }
    }
  }

  void _workWithNivara() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF10161E),
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
        backgroundColor: const Color(0xFF131A24),
        title: const Text('Resign from Field Team?'),
        content: const Text(
          'You will be removed from the field workforce and your account will '
          'revert to citizen status.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: NivaraColors.danger),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Resign', style: TextStyle(color: Colors.white)),
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
        backgroundColor: const Color(0xFF131A24),
        title: const Text('Sign out?'),
        content: const Text('You will need to sign in again to file and manage reports.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: NivaraColors.danger),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sign out', style: TextStyle(color: Colors.white)),
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
      color: NivaraColors.primary,
      backgroundColor: const Color(0xFF10161E),
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 110),
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

          if (isCitizen) ...[
            _ActionTile(
              icon: Icons.handshake_rounded,
              color: NivaraColors.accent,
              title: 'Work with Nivara',
              subtitle: 'Become a verified field worker in your ward',
              onTap: _workWithNivara,
            ),
            const SizedBox(height: 12),
          ],

          _ActionTile(
            icon: Icons.history_rounded,
            color: NivaraColors.primary,
            title: 'My Activity Timeline',
            subtitle: 'Timeline of your reports, posts, and tasks',
            onTap: () => context.push(Routes.activityLog),
          ),
          const SizedBox(height: 12),

          _ActionTile(
            icon: Icons.cloud_upload_outlined,
            color: NivaraColors.accent,
            title: 'Pending Sync Queue',
            subtitle: _pendingCount == 0
                ? 'All actions synced to cloud'
                : '$_pendingCount item${_pendingCount == 1 ? '' : 's'} waiting to sync',
            badge: _pendingCount > 0 ? '$_pendingCount' : null,
            onTap: () async {
              await context.push(Routes.pendingSync);
              _loadPendingCount();
            },
          ),
          const SizedBox(height: 12),

          _ActionTile(
            icon: Icons.edit_rounded,
            color: NivaraColors.primaryBlue,
            title: 'Edit Profile',
            subtitle: 'Display name, contact, and ward location',
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
            icon: Icons.logout_rounded,
            color: NivaraColors.danger,
            title: 'Sign Out',
            subtitle: 'End your session on this device',
            onTap: _signOut,
          ),
        ],
      ),
    );
  }
}

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
    final dept = profile?.department?.label ?? 'Field Team';
    final workerNum = profile?.workerNumber;
    final statusColor = onLeave ? NivaraColors.accent : NivaraColors.success;
    final statusLabel = onLeave ? 'On Leave' : 'Available for Work';
    final statusIcon = onLeave ? Icons.beach_access_rounded : Icons.check_circle_rounded;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            'FIELD SHIFT STATUS',
            style: TextStyle(
              color: Colors.white60,
              letterSpacing: 1.2,
              fontWeight: FontWeight.w800,
              fontSize: 11,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFF10161E),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: statusColor.withValues(alpha: 0.35)),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.16),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(statusIcon, color: statusColor, size: 22),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            statusLabel,
                            style: TextStyle(
                              color: statusColor,
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            onLeave
                                ? 'No new tasks will be dispatched to you'
                                : 'Active & ready for task dispatch',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.55),
                              fontSize: 11.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    working
                        ? const SizedBox(
                            width: 22,
                            height: 22,
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
              Divider(height: 1, color: Colors.white.withValues(alpha: 0.08)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    const Icon(Icons.badge_outlined, size: 18, color: Colors.white60),
                    const SizedBox(width: 8),
                    Text(
                      dept,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    if (workerNum != null) ...[
                      const SizedBox(width: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: NivaraColors.primary.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: NivaraColors.primary.withValues(alpha: 0.4),
                          ),
                        ),
                        child: Text(
                          'Worker #$workerNum',
                          style: const TextStyle(
                            color: NivaraColors.primary,
                            fontSize: 11.5,
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
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          icon: const Icon(Icons.person_remove_rounded, size: 18),
          label: const Text('Resign from Field Team'),
          style: OutlinedButton.styleFrom(
            foregroundColor: NivaraColors.danger,
            side: const BorderSide(color: NivaraColors.danger, width: 1.2),
            padding: const EdgeInsets.symmetric(vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF122336), Color(0xFF0C141F)],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: NivaraColors.primary.withValues(alpha: 0.35),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF00E676), Color(0xFF00B0FF)],
              ),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF00E676).withValues(alpha: 0.35),
                  blurRadius: 18,
                ),
              ],
            ),
            alignment: Alignment.center,
            child: Text(
              name.isNotEmpty ? name.characters.first.toUpperCase() : '?',
              style: const TextStyle(
                color: Colors.black,
                fontSize: 26,
                fontWeight: FontWeight.w900,
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
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: NivaraColors.primary.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: NivaraColors.primary.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Text(
                    (profile?.role ?? UserRole.citizen).label,
                    style: const TextStyle(
                      color: NivaraColors.primary,
                      fontWeight: FontWeight.w700,
                      fontSize: 11.5,
                    ),
                  ),
                ),
                if (area.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(
                        Icons.place_outlined,
                        color: Colors.white60,
                        size: 14,
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          area,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white60, fontSize: 11.5),
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
    return GlassCard(
      padding: const EdgeInsets.all(18),
      borderRadius: 22,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.workspace_premium_rounded,
                color: NivaraColors.primary,
                size: 20,
              ),
              const SizedBox(width: 8),
              const Text(
                'Civic Standing',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
              const Spacer(),
              Text(
                loading ? '—' : '$score XP',
                style: const TextStyle(
                  color: NivaraColors.primary,
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _Stat(
                icon: Icons.report_gmailerrorred_rounded,
                value: reports,
                label: 'Reports',
                loading: loading,
              ),
              _Divider(),
              _Stat(
                icon: Icons.thumb_up_alt_rounded,
                value: confirms,
                label: 'Confirms',
                loading: loading,
              ),
              _Divider(),
              _Stat(
                icon: Icons.volunteer_activism_rounded,
                value: finds,
                label: 'Finds',
                loading: loading,
              ),
            ],
          ),
          const SizedBox(height: 16),
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
    return Expanded(
      child: Column(
        children: [
          Icon(icon, color: NivaraColors.primary, size: 20),
          const SizedBox(height: 6),
          Text(
            loading ? '—' : '$value',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 19,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.65),
              fontSize: 11.5,
            ),
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
    height: 36,
    color: Colors.white.withValues(alpha: 0.1),
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
    return BouncyTap(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF10161E),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.55),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            if (badge != null) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: color.withValues(alpha: 0.6)),
                ),
                child: Text(
                  badge!,
                  style: TextStyle(
                    color: color,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 6),
            ],
            const Icon(Icons.chevron_right_rounded, color: Colors.white38),
          ],
        ),
      ),
    );
  }
}

class _EditProfileSheet extends ConsumerStatefulWidget {
  const _EditProfileSheet({required this.profile});
  final UserProfile profile;

  @override
  ConsumerState<_EditProfileSheet> createState() => _EditProfileSheetState();
}

class _EditProfileSheetState extends ConsumerState<_EditProfileSheet> {
  late final _nameCtrl = TextEditingController(text: widget.profile.displayName);
  late final _phoneCtrl = TextEditingController(text: widget.profile.phone ?? '');
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Name cannot be empty.')),
      );
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    final email = supabase.auth.currentUser?.email ?? '';
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 4, 20, 24 + bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Edit Profile',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 16),
          if (email.isNotEmpty) ...[
            TextField(
              enabled: false,
              controller: TextEditingController(text: email),
              decoration: const InputDecoration(
                labelText: 'Account Email',
                prefixIcon: Icon(Icons.mail_outline, color: Colors.white60),
              ),
            ),
            const SizedBox(height: 12),
          ],
          TextField(
            controller: _nameCtrl,
            textCapitalization: TextCapitalization.words,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              labelText: 'Display Name',
              prefixIcon: Icon(Icons.person_outline_rounded, color: Colors.white60),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _phoneCtrl,
            keyboardType: TextInputType.phone,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              labelText: 'Phone Number',
              prefixIcon: Icon(Icons.call_outlined, color: Colors.white60),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _cityCtrl,
                  textCapitalization: TextCapitalization.words,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'City',
                    prefixIcon: Icon(Icons.location_city_rounded, color: Colors.white60),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _wardCtrl,
                  textCapitalization: TextCapitalization.words,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(labelText: 'Ward / Locality'),
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
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                    )
                  : const Icon(Icons.save_rounded, color: Colors.black),
              label: Text(
                _saving ? 'Saving…' : 'Save Changes',
                style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

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
      padding: EdgeInsets.fromLTRB(20, 4, 20, 24 + bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: NivaraColors.accent.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.handshake_rounded, color: NivaraColors.accent),
              ),
              const SizedBox(width: 12),
              const Text(
                'Work with Nivara',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (_submitted) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: NivaraColors.success.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: NivaraColors.success.withValues(alpha: 0.4)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.check_circle_rounded, color: NivaraColors.success),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Application submitted! Municipal officials will review your request.',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: NivaraColors.success,
                      ),
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
                child: const Text('Done', style: TextStyle(color: Colors.black, fontWeight: FontWeight.w800)),
              ),
            ),
          ] else ...[
            const Text(
              'Verified field workers resolve assigned civic reports in their area '
              'and log verified resolution proof.',
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _message,
              maxLines: 3,
              maxLength: 400,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Motivation & Skills (optional)',
                hintText: 'Share your background, skills, or available equipment…',
                alignLabelWithHint: true,
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: const TextStyle(color: NivaraColors.danger)),
            ],
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _submitting ? null : _submit,
                style: FilledButton.styleFrom(backgroundColor: NivaraColors.accent),
                icon: _submitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                      )
                    : const Icon(Icons.send_rounded, color: Colors.black),
                label: Text(
                  _submitting ? 'Submitting…' : 'Submit Application',
                  style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
