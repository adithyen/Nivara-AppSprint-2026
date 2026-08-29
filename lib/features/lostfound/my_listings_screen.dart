import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../core/widgets/bouncy_tap.dart';
import '../../models/enums.dart';
import '../../models/lf_claim.dart';
import '../../models/lf_item.dart';
import '../../router.dart';
import '../auth/auth_controller.dart';
import 'item_card.dart';
import 'lf_claims_repo.dart';
import 'lf_handover_dialog.dart';

/// "My Lost & Found" — the one place a user closes the loop on their own posts.
///
/// Three sections, in order of what needs the user's attention:
///   1. **Claims to review** — someone says one of your listings is theirs.
///      Complete the handover (resolves both listings) via QR/PIN verification or decline.
///   2. **My listings** — everything you've posted. Active ones can be closed
///      directly ("I got it back myself"); each shows how many people have claimed it.
///   3. **Claims you've sent** — listings you've claimed as yours, with live
///      status; pending ones can be withdrawn or verified via QR/PIN.
class MyListingsScreen extends ConsumerStatefulWidget {
  const MyListingsScreen({super.key});

  @override
  ConsumerState<MyListingsScreen> createState() => _MyListingsScreenState();
}

class _MyListingsScreenState extends ConsumerState<MyListingsScreen> {
  bool _loading = true;
  bool _busy = false;
  String? _error;

  List<LFItem> _myItems = const [];
  List<LFClaim> _incoming = const []; // pending claims on my listings
  List<LFClaim> _sent = const []; // claims I filed on others' listings
  Map<String, LFItem> _itemsById = const {};
  Map<String, String> _names = const {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final uid = ref.read(authControllerProvider).asData?.value?.id;
    if (uid == null) {
      setState(() {
        _loading = false;
        _error = 'You need to be signed in.';
      });
      return;
    }
    try {
      final myItems = await LFClaimsRepo.myItems(uid);
      final incoming = await LFClaimsRepo.claimsOnMyItems(uid);
      final sent = await LFClaimsRepo.myClaims(uid);

      // Resolve every listing referenced by a claim (mine + counterparts).
      final byId = {for (final i in myItems) i.id: i};
      final needed = <String>{};
      for (final c in [...incoming, ...sent]) {
        needed.add(c.itemId);
        if (c.claimantItemId != null) needed.add(c.claimantItemId!);
      }
      needed.removeWhere(byId.containsKey);
      if (needed.isNotEmpty) {
        byId.addAll(await LFClaimsRepo.itemsByIds(needed));
      }

      final names = await LFClaimsRepo.displayNames(
        incoming.map((c) => c.claimantId),
      );

      if (!mounted) return;
      setState(() {
        _myItems = myItems;
        _incoming = incoming;
        _sent = sent;
        _itemsById = byId;
        _names = names;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<bool> _confirm(String title, String body, String confirmLabel) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _run(Future<void> Function() action, String success) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      _snack(success);
      await _load();
    } catch (e) {
      _snack('$e'.replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verifyHandover(LFClaim claim, LFItem? item) async {
    if (item == null) return;
    final uid = ref.read(authControllerProvider).asData?.value?.id;
    final isOwner = uid != null && uid == item.userId;
    final resolved = await LFHandoverDialog.show(
      context,
      claim: claim,
      item: item,
      isOwner: isOwner,
    );
    if (resolved == true && mounted) {
      _snack('Item Handover Verified & Completed!');
      _load();
    }
  }

  Future<void> _selfClose(LFItem item) async {
    final title = _label(item);
    if (!await _confirm(
      'Mark as resolved?',
      'This removes "$title" from Lost & Found. Do this once you have the item back.',
      'Mark resolved',
    )) {
      return;
    }
    await _run(() => LFClaimsRepo.selfClose(item.id), 'Listing resolved.');
  }

  Future<void> _completeClaim(LFClaim claim) async {
    if (!await _confirm(
      'Directly complete this claim?',
      'This marks both listings resolved and removes them from the Lost & Found feed.',
      'Complete',
    )) {
      return;
    }
    await _run(
      () => LFClaimsRepo.completeClaim(claim.id),
      'Claim completed — listings resolved.',
    );
  }

  Future<void> _rejectClaim(LFClaim claim, {required bool asOwner}) async {
    final verb = asOwner ? 'Decline' : 'Withdraw';
    if (!await _confirm(
      '$verb claim?',
      asOwner
          ? 'The claimant will be told their claim was declined. Your listing stays active.'
          : 'Your claim will be withdrawn. The listing stays active for others.',
      verb,
    )) {
      return;
    }
    await _run(
      () => LFClaimsRepo.rejectClaim(claim.id),
      asOwner ? 'Claim declined.' : 'Claim withdrawn.',
    );
  }

  String _label(LFItem item) =>
      item.title.trim().isNotEmpty ? item.title.trim() : item.category.label;

  int _pendingClaimsFor(String itemId) =>
      _incoming.where((c) => c.itemId == itemId && c.isPending).length;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My Lost & Found')),
      body: RefreshIndicator(onRefresh: _load, child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return ListView(
        children: [
          const SizedBox(height: 120),
          Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(_error!, textAlign: TextAlign.center),
            ),
          ),
        ],
      );
    }

    final hasNothing = _myItems.isEmpty && _incoming.isEmpty && _sent.isEmpty;
    if (hasNothing) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 120),
          Icon(
            Icons.inbox_outlined,
            size: 56,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: 12),
          Center(
            child: Text(
              'You haven\'t posted anything yet.',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          const SizedBox(height: 6),
          Center(
            child: Text(
              'Report a lost or found item from the hub.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      );
    }

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      children: [
        if (_incoming.isNotEmpty) ...[
          _SectionTitle('Claims to review', count: _incoming.length),
          const SizedBox(height: 8),
          for (final c in _incoming) ...[
            _IncomingClaimCard(
              claim: c,
              item: _itemsById[c.itemId],
              linked: c.claimantItemId == null
                  ? null
                  : _itemsById[c.claimantItemId!],
              claimantName: _names[c.claimantId],
              busy: _busy,
              onVerifyHandover: () => _verifyHandover(c, _itemsById[c.itemId]),
              onComplete: () => _completeClaim(c),
              onDecline: () => _rejectClaim(c, asOwner: true),
            ),
            const SizedBox(height: 10),
          ],
          const SizedBox(height: 12),
        ],
        _SectionTitle('My listings', count: _myItems.length),
        const SizedBox(height: 8),
        if (_myItems.isEmpty)
          const _MutedNote('You have no active listings.')
        else
          for (final item in _myItems) ...[
            _MyItemCard(
              item: item,
              pendingClaims: _pendingClaimsFor(item.id),
              busy: _busy,
              onOpen: () =>
                  context.push(Routes.lostFoundDetail, extra: item).then((_) {
                    if (mounted) _load();
                  }),
              onClose: item.status == 'ACTIVE' ? () => _selfClose(item) : null,
            ),
            const SizedBox(height: 10),
          ],
        if (_sent.isNotEmpty) ...[
          const SizedBox(height: 12),
          _SectionTitle('Claims you\'ve sent', count: _sent.length),
          const SizedBox(height: 8),
          for (final c in _sent) ...[
            _SentClaimCard(
              claim: c,
              item: _itemsById[c.itemId],
              busy: _busy,
              onVerifyHandover: () => _verifyHandover(c, _itemsById[c.itemId]),
              onWithdraw: c.isPending
                  ? () => _rejectClaim(c, asOwner: false)
                  : null,
            ),
            const SizedBox(height: 10),
          ],
        ],
      ],
    );
  }
}

// ── Section scaffolding ──────────────────────────────────────────────────────

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title, {this.count});
  final String title;
  final int? count;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        if (count != null && count! > 0) ...[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
            decoration: BoxDecoration(
              color: NivaraColors.primary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '$count',
              style: const TextStyle(
                color: NivaraColors.primary,
                fontWeight: FontWeight.w800,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _MutedNote extends StatelessWidget {
  const _MutedNote(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(text, style: TextStyle(color: scheme.onSurfaceVariant)),
    );
  }
}

// ── Incoming claim (I'm the owner) ───────────────────────────────────────────

class _IncomingClaimCard extends StatelessWidget {
  const _IncomingClaimCard({
    required this.claim,
    required this.item,
    required this.linked,
    required this.claimantName,
    required this.busy,
    required this.onVerifyHandover,
    required this.onComplete,
    required this.onDecline,
  });

  final LFClaim claim;
  final LFItem? item;
  final LFItem? linked;
  final String? claimantName;
  final bool busy;
  final VoidCallback onVerifyHandover;
  final VoidCallback onComplete;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final title = item == null
        ? 'your listing'
        : (item!.title.trim().isNotEmpty
              ? item!.title.trim()
              : item!.category.label);
    final who = (claimantName?.trim().isNotEmpty ?? false)
        ? claimantName!.trim()
        : 'Someone';

    return Card(
      margin: EdgeInsets.zero,
      color: NivaraColors.accent.withValues(alpha: 0.06),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: NivaraColors.accent.withValues(alpha: 0.35)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: NivaraColors.accent.withValues(alpha: 0.18),
                  child: const Icon(
                    Icons.handshake_rounded,
                    color: NivaraColors.accent,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: who,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const TextSpan(text: ' claims '),
                            TextSpan(
                              text: title,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (claim.createdAt != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          formatDate(claim.createdAt!),
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            if (claim.message != null && claim.message!.trim().isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: scheme.surface,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text('“${claim.message!.trim()}”'),
              ),
            ],
            if (linked != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.link, size: 15, color: scheme.onSurfaceVariant),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Linked their ${linked!.isLost ? 'lost' : 'found'} '
                      'listing: ${linked!.title.trim().isNotEmpty ? linked!.title.trim() : linked!.category.label}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: BouncyTap(
                    onTap: busy ? null : onVerifyHandover,
                    child: Container(
                      height: 40,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF00E676), Color(0xFF00B0FF)],
                        ),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF00E676).withValues(alpha: 0.25),
                            blurRadius: 8,
                          ),
                        ],
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.qr_code_rounded, color: Colors.black, size: 18),
                          SizedBox(width: 6),
                          Text(
                            'Verify (QR/PIN)',
                            style: TextStyle(
                              color: Colors.black,
                              fontWeight: FontWeight.w900,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: busy ? null : onDecline,
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Decline'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── My own listing ───────────────────────────────────────────────────────────

class _MyItemCard extends StatelessWidget {
  const _MyItemCard({
    required this.item,
    required this.pendingClaims,
    required this.busy,
    required this.onOpen,
    required this.onClose,
  });

  final LFItem item;
  final int pendingClaims;
  final bool busy;
  final VoidCallback onOpen;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isLost = item.isLost;
    final accent = isLost ? NivaraColors.danger : NivaraColors.success;
    final title = item.title.trim().isNotEmpty
        ? item.title.trim()
        : item.category.label;

    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    backgroundColor: accent.withValues(alpha: 0.15),
                    child: Icon(lfCategoryIcon(item.category), color: accent),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            _Pill(
                              text: isLost ? 'LOST' : 'FOUND',
                              color: accent,
                            ),
                            const SizedBox(width: 6),
                            _StatusPill(status: item.status),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right),
                ],
              ),
              if (pendingClaims > 0) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(
                      Icons.handshake_rounded,
                      size: 15,
                      color: NivaraColors.accent,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '$pendingClaims ${pendingClaims == 1 ? 'person has' : 'people have'} claimed this',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: NivaraColors.accent,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
              if (onClose != null) ...[
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: busy ? null : onClose,
                    icon: const Icon(Icons.task_alt, size: 18),
                    label: const Text('Mark resolved (I got it)'),
                  ),
                ),
              ] else if (item.status == 'RESOLVED') ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(
                      Icons.check_circle,
                      size: 15,
                      color: NivaraColors.success,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Resolved',
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ── Claim I sent ─────────────────────────────────────────────────────────────

class _SentClaimCard extends StatelessWidget {
  const _SentClaimCard({
    required this.claim,
    required this.item,
    required this.busy,
    this.onVerifyHandover,
    required this.onWithdraw,
  });

  final LFClaim claim;
  final LFItem? item;
  final bool busy;
  final VoidCallback? onVerifyHandover;
  final VoidCallback? onWithdraw;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final title = item == null
        ? 'a listing'
        : (item!.title.trim().isNotEmpty
              ? item!.title.trim()
              : item!.category.label);
    final (color, icon) = switch (claim.status) {
      LFClaimStatus.pending => (NivaraColors.accent, Icons.hourglass_top),
      LFClaimStatus.completed => (NivaraColors.success, Icons.check_circle),
      LFClaimStatus.rejected => (NivaraColors.danger, Icons.cancel),
      LFClaimStatus.cancelled => (scheme.outline, Icons.remove_circle_outline),
    };

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: color.withValues(alpha: 0.15),
                  child: Icon(icon, color: color),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'You claimed $title',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        claim.status.label,
                        style: TextStyle(color: color, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
                if (onWithdraw != null)
                  TextButton(
                    onPressed: busy ? null : onWithdraw,
                    child: const Text('Withdraw'),
                  ),
              ],
            ),
            if (claim.isPending && onVerifyHandover != null) ...[
              const SizedBox(height: 10),
              BouncyTap(
                onTap: busy ? null : onVerifyHandover,
                child: Container(
                  height: 38,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF00E676), Color(0xFF00B0FF)],
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.qr_code_scanner_rounded, color: Colors.black, size: 16),
                      SizedBox(width: 6),
                      Text(
                        'Open Handover Pass (QR / PIN)',
                        style: TextStyle(
                          color: Colors.black,
                          fontWeight: FontWeight.w900,
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.text, required this.color});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: 10.5,
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (label, color) = switch (status) {
      'ACTIVE' => ('Active', NivaraColors.primary),
      'MATCHED' => ('Matched', NivaraColors.primary),
      'RESOLVED' => ('Resolved', NivaraColors.success),
      'EXPIRED' => ('Expired', scheme.outline),
      _ => (status, scheme.outline),
    };
    return _Pill(text: label.toUpperCase(), color: color);
  }
}
