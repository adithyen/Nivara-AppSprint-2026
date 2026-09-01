import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../core/supabase_client.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../core/widgets/bouncy_tap.dart';
import '../../models/enums.dart';
import '../../models/lf_claim.dart';
import '../../models/lf_item.dart';
import '../auth/auth_controller.dart';
import 'item_card.dart';
import 'lf_claims_repo.dart';
import 'lf_contact.dart';
import 'lf_handover_dialog.dart';

/// Full view of one Lost & Found item — reached by tapping a match result or a
/// hub card. Shows the counterpart's photos (tap to zoom, to verify ownership)
/// and a one-tap contact action via [launchLFContact].
///
/// It also carries the direct handover flow: a viewer who finds or recognizes the item
/// can send a claim / handover intent directly without filing a duplicate listing,
/// and both parties can execute mutual verification via dynamic QR code passes
/// or 6-digit proximity PIN handshakes.
class LFItemDetailScreen extends ConsumerStatefulWidget {
  const LFItemDetailScreen({
    super.key,
    required this.item,
    this.distanceMeters,
    this.isMatch = false,
  });

  final LFItem item;
  final double? distanceMeters;

  /// True when opened from the match list (adds an "is this yours?" banner).
  final bool isMatch;

  @override
  ConsumerState<LFItemDetailScreen> createState() => _LFItemDetailScreenState();
}

class _LFItemDetailScreenState extends ConsumerState<LFItemDetailScreen> {
  late LFItem _item = widget.item;
  List<LFClaim> _claims = const [];
  List<LFItem> _linkable = const []; // my active opposite-type listings
  bool _busy = false;

  String? get _uid => ref.read(authControllerProvider).asData?.value?.id;
  bool get _isOwner => _uid != null && _uid == _item.userId;
  bool get _isActive => _item.status == 'ACTIVE';

  /// My pending claim on this listing, if I've already sent one.
  LFClaim? get _myClaim {
    final uid = _uid;
    if (uid == null) return null;
    for (final c in _claims) {
      if (c.claimantId == uid) return c;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _refreshFull();
    _loadClaimContext();
  }

  Future<void> _refreshFull() async {
    try {
      final row = await supabase
          .from(kTableLfItems)
          .select()
          .eq('id', widget.item.id)
          .maybeSingle();
      if (row != null && mounted) {
        setState(() => _item = LFItem.fromMap(row));
      }
    } catch (_) {
      /* keep the passed item — it's enough to show something useful */
    }
  }

  /// Load claims visible to me (RLS returns my own claim as a viewer, or every
  /// claim as the owner) plus — for a viewer — my linkable opposite listings.
  Future<void> _loadClaimContext() async {
    final uid = _uid;
    if (uid == null) return;
    try {
      final claims = await LFClaimsRepo.claimsForItem(_item.id);
      List<LFItem> linkable = const [];
      if (_item.userId != uid) {
        final mine = await LFClaimsRepo.myItems(uid);
        final opposite = _item.isLost ? LFItemType.found : LFItemType.lost;
        linkable = mine
            .where((i) => i.itemType == opposite && i.status == 'ACTIVE')
            .toList();
      }
      if (!mounted) return;
      setState(() {
        _claims = claims;
        _linkable = linkable;
      });
    } catch (_) {
      /* claims are non-critical for viewing */
    }
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
      await _refreshFull();
      await _loadClaimContext();
    } catch (e) {
      _snack('$e'.replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sendClaim() async {
    final result =
        await showModalBottomSheet<({String? message, String? linkedId})>(
          context: context,
          isScrollControlled: true,
          showDragHandle: true,
          builder: (_) => _ClaimSheet(item: _item, linkable: _linkable),
        );
    if (result == null) return;
    await _run(
      () => LFClaimsRepo.createClaim(
        itemId: _item.id,
        claimantItemId: result.linkedId,
        message: result.message,
      ),
      _item.isLost
          ? 'Handover intent sent to the owner! You can now verify in person.'
          : 'Claim sent. The finder will confirm the handover.',
    );
  }

  Future<void> _openHandoverDialog(LFClaim claim) async {
    final resolved = await LFHandoverDialog.show(
      context,
      claim: claim,
      item: _item,
      isOwner: _isOwner,
    );
    if (resolved == true && mounted) {
      _snack('Item Handover Verified & Completed!');
      await _refreshFull();
      await _loadClaimContext();
    }
  }

  Future<void> _completeClaim(LFClaim claim) async {
    if (!await _confirm(
      'Directly complete this claim?',
      'This marks both listings resolved and removes them from the Lost & Found feed. '
          'Tip: Use "Verify Handover (QR / PIN)" when meeting in person for mutual verification.',
      'Complete',
    )) {
      return;
    }
    await _run(
      () => LFClaimsRepo.completeClaim(claim.id),
      'Claim completed — both listings resolved.',
    );
  }

  Future<void> _rejectClaim(LFClaim claim, {required bool asOwner}) async {
    await _run(
      () => LFClaimsRepo.rejectClaim(claim.id),
      asOwner ? 'Claim declined.' : 'Claim withdrawn.',
    );
  }

  Future<void> _selfClose() async {
    if (!await _confirm(
      'Mark as resolved?',
      'This removes your listing from Lost & Found. Do this once you have the item back.',
      'Mark resolved',
    )) {
      return;
    }
    await _run(() => LFClaimsRepo.selfClose(_item.id), 'Listing resolved.');
  }

  Future<void> _contact() async {
    final m = _item.contactMethodEnum;
    final value = _item.contactValue;
    if (value == null || value.trim().isEmpty) return;
    final ok = await launchLFContact(m, value);
    if (!ok && mounted) {
      _snack(
        'Could not open ${m.label}. Contact: ${lfContactDisplay(m, value)}',
      );
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final r = _item;
    final accent = r.isLost ? NivaraColors.danger : NivaraColors.success;
    final title = r.title.trim().isNotEmpty ? r.title.trim() : r.category.label;
    return Scaffold(
      appBar: AppBar(title: Text(r.isLost ? 'Lost item' : 'Found item')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        children: [
          if (widget.isMatch) _MatchBanner(isLost: r.isLost, accent: accent),
          Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: accent.withValues(alpha: 0.15),
                child: Icon(lfCategoryIcon(r.category), color: accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    _TypePill(isLost: r.isLost, accent: accent),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _PhotoGallery(urls: r.photoUrls ?? const []),
          _buildClaimSection(accent),
          const SizedBox(height: 16),
          _ContactCard(item: r, onContact: _contact, onCopy: _copyContact),
          if (r.description.trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            _Section(title: 'Description', child: Text(r.description.trim())),
          ],
          const SizedBox(height: 12),
          _Section(
            title: 'Details',
            child: Column(
              children: [
                _MetaRow('Type', r.isLost ? 'Lost' : 'Found'),
                _MetaRow('Category', r.category.label),
                _MetaRow(
                  r.isLost ? 'Lost on' : 'Found on',
                  formatDate(r.eventDate),
                ),
                if (widget.distanceMeters != null)
                  _MetaRow('Distance', formatDistance(widget.distanceMeters!)),
                if (r.locationLabel != null && r.locationLabel!.isNotEmpty)
                  _MetaRow('Area', r.locationLabel!),
                if (r.rewardAmount != null && r.rewardAmount! > 0)
                  _MetaRow('Reward', '₹${r.rewardAmount}'),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _Section(
            title: 'Location',
            child: Text(
              '${r.lat.toStringAsFixed(5)}, ${r.lng.toStringAsFixed(5)}',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _copyContact() async {
    final value = _item.contactValue;
    if (value == null || value.trim().isEmpty) return;
    final display = lfContactDisplay(_item.contactMethodEnum, value);
    await Clipboard.setData(ClipboardData(text: display));
    if (mounted) _snack('Copied $display');
  }

  /// The claim / close controls, sensitive to who's looking and the item state.
  Widget _buildClaimSection(Color accent) {
    // Already closed — show a plain status banner, no actions.
    if (!_isActive) {
      final resolved = _item.status == 'RESOLVED';
      final color = resolved
          ? NivaraColors.success
          : Theme.of(context).colorScheme.outline;
      return Padding(
        padding: const EdgeInsets.only(top: 16),
        child: _Banner(
          color: color,
          icon: resolved ? Icons.check_circle_rounded : Icons.info_outline,
          text: resolved
              ? 'This item has been safely transferred and resolved.'
              : 'This listing is ${_item.status.toLowerCase()}.',
        ),
      );
    }

    if (_isOwner) return _ownerSection();
    return _viewerSection();
  }

  Widget _ownerSection() {
    final pending = _claims.where((c) => c.isPending).toList();
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (pending.isEmpty)
            const _Banner(
              color: NivaraColors.primary,
              icon: Icons.person_pin_circle_outlined,
              text:
                  'This is your listing. When someone finds or claims it, you can verify '
                  'the physical handover here via Dynamic QR Code or 6-Digit PIN.',
            )
          else ...[
            Text(
              'Handover Requests & Claims',
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            for (final c in pending) ...[
              _OwnerClaimTile(
                claim: c,
                busy: _busy,
                onVerifyHandover: () => _openHandoverDialog(c),
                onComplete: () => _completeClaim(c),
                onDecline: () => _rejectClaim(c, asOwner: true),
              ),
              const SizedBox(height: 8),
            ],
          ],
          const SizedBox(height: 6),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _busy ? null : _selfClose,
              icon: const Icon(Icons.task_alt, size: 18),
              label: const Text('Mark resolved (Recovered directly)'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _viewerSection() {
    final uid = _uid;
    final mine = _myClaim;

    // ── Completed claim — show resolved banner instead of action button ──────
    final completedClaim = uid != null
        ? _claims.firstWhere(
            (c) => c.claimantId == uid && c.isCompleted,
            orElse: () => _claims.firstWhere(
              (c) => c.ownerId == uid && c.isCompleted,
              orElse: () => _claims.firstWhere(
                (c) => c.isCompleted,
                orElse: () => const LFClaim(
                  id: '', itemId: '', ownerId: '', claimantId: '',
                ),
              ),
            ),
          )
        : null;

    final hasCompleted = completedClaim != null &&
        completedClaim.id.isNotEmpty &&
        completedClaim.isCompleted;

    if (hasCompleted) {
      return Padding(
        padding: const EdgeInsets.only(top: 16),
        child: const _Banner(
          color: NivaraColors.success,
          icon: Icons.check_circle_rounded,
          text: '✅ Handover completed! This item has been safely transferred and resolved.',
        ),
      );
    }

    // ── Active pending claim — show handover pass button ─────────────────────
    if (mine != null && mine.isPending) {
      return Padding(
        padding: const EdgeInsets.only(top: 16),
        child: Column(
          children: [
            const _Banner(
              color: Color(0xFF00E676),
              icon: Icons.handshake_rounded,
              text:
                  'Handover request active! When you meet the counterpart, open the '
                  'Handover Pass to display your QR code or let them tap to receive your PIN.',
            ),
            const SizedBox(height: 10),
            BouncyTap(
              onTap: () => _openHandoverDialog(mine),
              child: Container(
                height: 48,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF00E676), Color(0xFF00B0FF)],
                  ),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF00E676).withValues(alpha: 0.3),
                      blurRadius: 12,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.qr_code_scanner_rounded, color: Colors.black, size: 20),
                    SizedBox(width: 8),
                    Text(
                      'Open Handover Pass (QR / PIN)',
                      style: TextStyle(
                        color: Colors.black,
                        fontWeight: FontWeight.w900,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: _busy
                    ? null
                    : () => _rejectClaim(mine, asOwner: false),
                child: const Text('Withdraw request'),
              ),
            ),
          ],
        ),
      );
    }

    // ── No claim yet — show primary action button ─────────────────────────────
    final isLost = _item.isLost;
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: BouncyTap(
        onTap: _busy ? null : _sendClaim,
        child: Container(
          height: 50,
          decoration: BoxDecoration(
            gradient: isLost
                ? const LinearGradient(
                    colors: [Color(0xFF00E676), Color(0xFF00B0FF)],
                  )
                : const LinearGradient(
                    colors: [Color(0xFF00B0FF), Color(0xFF7B4BC4)],
                  ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: (isLost ? const Color(0xFF00E676) : const Color(0xFF00B0FF))
                    .withValues(alpha: 0.35),
                blurRadius: 14,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                isLost ? Icons.volunteer_activism_rounded : Icons.verified_rounded,
                color: Colors.black,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                isLost ? 'I Found This Item (Start Handover)' : 'This Is Mine (Claim Item)',
                style: const TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.w900,
                  fontSize: 14.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A simple full-width coloured info banner used across the claim section.
class _Banner extends StatelessWidget {
  const _Banner({required this.color, required this.icon, required this.text});
  final Color color;
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}

/// One pending claim, shown to the listing owner with verify and decline actions.
class _OwnerClaimTile extends StatelessWidget {
  const _OwnerClaimTile({
    required this.claim,
    required this.busy,
    required this.onVerifyHandover,
    required this.onComplete,
    required this.onDecline,
  });

  final LFClaim claim;
  final bool busy;
  final VoidCallback onVerifyHandover;
  final VoidCallback onComplete;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: NivaraColors.accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: NivaraColors.accent.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.handshake_rounded,
                color: NivaraColors.accent,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Handover Claim Received',
                  style: TextStyle(
                    color: scheme.onSurface,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
          if (claim.message != null && claim.message!.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              '“${claim.message!.trim()}”',
              style: const TextStyle(fontStyle: FontStyle.italic, fontSize: 13),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: BouncyTap(
                  onTap: busy ? null : onVerifyHandover,
                  child: Container(
                    height: 42,
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
    );
  }
}

class _MatchBanner extends StatelessWidget {
  const _MatchBanner({required this.isLost, required this.accent});
  final bool isLost;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.compare_arrows, color: accent),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              isLost
                  ? 'Someone reported losing this. Check the photos — if it matches what you found, start the handover below.'
                  : 'Someone found this nearby. Check the photos to confirm it is yours, then claim it below.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

class _TypePill extends StatelessWidget {
  const _TypePill({required this.isLost, required this.accent});
  final bool isLost;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        isLost ? 'LOST' : 'FOUND',
        style: TextStyle(
          color: accent,
          fontWeight: FontWeight.w700,
          fontSize: 11.5,
        ),
      ),
    );
  }
}

/// Horizontal strip of photos; tapping one opens a fullscreen, zoomable viewer.
class _PhotoGallery extends StatelessWidget {
  const _PhotoGallery({required this.urls});
  final List<String> urls;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (urls.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(Icons.image_not_supported_outlined, color: scheme.outline),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'No photos attached to this report.',
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            ),
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Photos',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w700,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '· tap to zoom',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: scheme.outline),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 150,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: urls.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (_, i) => GestureDetector(
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  fullscreenDialog: true,
                  builder: (_) => _PhotoViewer(urls: urls, initialIndex: i),
                ),
              ),
              child: Hero(
                tag: 'lf_photo_$i${urls[i]}',
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: _NetImage(url: urls[i], width: 150, height: 150),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _NetImage extends StatelessWidget {
  const _NetImage({required this.url, this.width, this.height});
  final String url;
  final double? width;
  final double? height;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Image.network(
      url,
      width: width,
      height: height,
      fit: BoxFit.cover,
      loadingBuilder: (c, child, progress) => progress == null
          ? child
          : Container(
              width: width,
              height: height,
              color: scheme.surfaceContainerHighest,
              child: const Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
      errorBuilder: (c, _, _) => Container(
        width: width,
        height: height,
        color: scheme.surfaceContainerHighest,
        child: Icon(Icons.broken_image, color: scheme.outline),
      ),
    );
  }
}

/// Fullscreen, pinch-to-zoom photo viewer with paging across all [urls].
class _PhotoViewer extends StatefulWidget {
  const _PhotoViewer({required this.urls, required this.initialIndex});
  final List<String> urls;
  final int initialIndex;

  @override
  State<_PhotoViewer> createState() => _PhotoViewerState();
}

class _PhotoViewerState extends State<_PhotoViewer> {
  late final PageController _controller = PageController(
    initialPage: widget.initialIndex,
  );
  late int _index = widget.initialIndex;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          '${_index + 1} / ${widget.urls.length}',
          style: const TextStyle(fontSize: 15),
        ),
      ),
      body: PageView.builder(
        controller: _controller,
        itemCount: widget.urls.length,
        onPageChanged: (i) => setState(() => _index = i),
        itemBuilder: (_, i) => Center(
          child: Hero(
            tag: 'lf_photo_$i${widget.urls[i]}',
            child: InteractiveViewer(
              minScale: 1,
              maxScale: 5,
              child: Image.network(
                widget.urls[i],
                fit: BoxFit.contain,
                errorBuilder: (c, _, _) => const Icon(
                  Icons.broken_image,
                  color: Colors.white54,
                  size: 64,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One-tap contact card.
class _ContactCard extends StatelessWidget {
  const _ContactCard({
    required this.item,
    required this.onContact,
    required this.onCopy,
  });

  final LFItem item;
  final VoidCallback onContact;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (!item.hasContact) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(Icons.person_off_outlined, color: scheme.outline),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'The poster did not share a contact method.',
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            ),
          ],
        ),
      );
    }

    final m = item.contactMethodEnum;
    final color = lfContactColor(m);
    final display = lfContactDisplay(m, item.contactValue!);
    return Container(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onContact,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: color.withValues(alpha: 0.18),
                  child: Icon(lfContactIcon(m), color: color),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        m.label,
                        style: TextStyle(
                          color: color,
                          fontWeight: FontWeight.w700,
                          fontSize: 12.5,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        display,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Tap to ${lfContactActionLabel(m).toLowerCase()}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Copy',
                  onPressed: onCopy,
                  icon: Icon(Icons.copy, color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});
  final String title;
  final Widget child;

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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

class _MetaRow extends StatelessWidget {
  const _MetaRow(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(
              label,
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

/// The claim / handover composer: an optional note to the owner and — if the claimant has
/// matching listings of their own — an option to link one so completing the
/// claim resolves both.
class _ClaimSheet extends StatefulWidget {
  const _ClaimSheet({required this.item, required this.linkable});
  final LFItem item;
  final List<LFItem> linkable;

  @override
  State<_ClaimSheet> createState() => _ClaimSheetState();
}

class _ClaimSheetState extends State<_ClaimSheet> {
  final _msgCtrl = TextEditingController();
  String? _linkedId;

  @override
  void dispose() {
    _msgCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    final oppositeWord = widget.item.isLost ? 'found' : 'lost';
    final isLost = widget.item.isLost;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 4, 20, 20 + bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isLost ? 'I Found This Item (Start Handover)' : 'This Item Is Mine (Claim)',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            isLost
                ? 'Notify the owner that you found their item. You will be able to verify '
                  'the transfer in person using a dynamic QR code or 6-digit PIN.'
                : 'Notify the finder that you own this item. Add a note describing identifying details.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _msgCtrl,
            maxLines: 3,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: isLost ? 'Handover note (optional)' : 'Identifying details (optional)',
              hintText: isLost
                  ? 'e.g. Safe with me at Metro Station Info Desk'
                  : 'e.g. It has a blue tag on the zipper',
              alignLabelWithHint: true,
            ),
          ),
          if (widget.linkable.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              'Link your existing $oppositeWord listing (optional)',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 2),
            Text(
              'If you already posted this earlier, linking it resolves both when verified.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            _LinkOption(
              selected: _linkedId == null,
              title: 'Don\'t link anything',
              onTap: () => setState(() => _linkedId = null),
            ),
            for (final i in widget.linkable)
              _LinkOption(
                selected: _linkedId == i.id,
                title: i.title.trim().isNotEmpty
                    ? i.title.trim()
                    : i.category.label,
                subtitle: i.category.label,
                onTap: () => setState(() => _linkedId = i.id),
              ),
          ],
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton.icon(
              onPressed: () => Navigator.pop(context, (
                message: _msgCtrl.text.trim().isEmpty
                    ? null
                    : _msgCtrl.text.trim(),
                linkedId: _linkedId,
              )),
              icon: const Icon(Icons.send_rounded),
              label: Text(isLost ? 'Send Handover Intent' : 'Send Claim'),
            ),
          ),
        ],
      ),
    );
  }
}

class _LinkOption extends StatelessWidget {
  const _LinkOption({
    required this.selected,
    required this.title,
    this.subtitle,
    required this.onTap,
  });

  final bool selected;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: selected
            ? NivaraColors.primary.withValues(alpha: 0.10)
            : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Icon(
                  selected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  color: selected ? NivaraColors.primary : scheme.outline,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      if (subtitle != null)
                        Text(
                          subtitle!,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
