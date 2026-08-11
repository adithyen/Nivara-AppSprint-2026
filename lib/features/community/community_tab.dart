import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants.dart';
import '../../core/services/location_service.dart';
import '../../core/supabase_client.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../models/community_poll.dart';
import '../../models/community_post.dart';
import '../../models/enums.dart';
import '../../router.dart';
import '../lostfound/lf_contact.dart';

/// The **Community** tab — a neighbourhood board of posts from nearby users.
///
/// Body-only (the [Scaffold]/[AppBar] belong to the shell). Loads OPEN posts
/// via the `community_posts_near` PostGIS RPC — city-wide posts plus located
/// posts whose visibility radius covers the viewer — then hydrates poll options
/// and the viewer's own votes so tallies render live. A composer prompt sits at
/// the top with the four templates (Post · Poll · Job · Announcement); authors
/// get an edit/close/delete menu on their own posts.
class CommunityTab extends ConsumerStatefulWidget {
  const CommunityTab({super.key});

  @override
  ConsumerState<CommunityTab> createState() => _CommunityTabState();
}

class _CommunityTabState extends ConsumerState<CommunityTab> {
  final _location = const LocationService();

  bool _loading = true;
  Position? _pos;
  List<CommunityPost> _posts = const [];
  Map<String, List<CommunityPollOption>> _pollOptions = const {};
  Map<String, String> _myVotes = const {}; // postId → optionId

  double get _lat => _pos?.latitude ?? kDefaultLat;
  double get _lng => _pos?.longitude ?? kDefaultLng;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final perm = await _location.ensurePermission();
    Position? pos;
    if (_location.isGranted(perm)) pos = await _location.current();
    if (mounted) setState(() => _pos = pos);
    await _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _loading = true);

    List<CommunityPost> posts = const [];
    var options = <String, List<CommunityPollOption>>{};
    var votes = <String, String>{};

    try {
      final rows = await supabase.rpc(
        'community_posts_near',
        params: {'p_lat': _lat, 'p_lng': _lng, 'p_limit': 200},
      );
      posts = (rows as List)
          .map((e) => CommunityPost.fromMap(e as Map<String, dynamic>))
          .toList();

      final pollIds = posts.where((p) => p.isPoll).map((p) => p.id).toList();
      if (pollIds.isNotEmpty) {
        options = await _fetchPollOptions(pollIds);
        votes = await _fetchMyVotes(pollIds);
      }
    } catch (_) {
      posts = const [];
    }

    if (!mounted) return;
    setState(() {
      _posts = posts;
      _pollOptions = options;
      _myVotes = votes;
      _loading = false;
    });
  }

  Future<Map<String, List<CommunityPollOption>>> _fetchPollOptions(
    List<String> pollIds,
  ) async {
    final rows = await supabase
        .from(kTableCommunityPollOptions)
        .select()
        .inFilter('post_id', pollIds)
        .order('position');
    final map = <String, List<CommunityPollOption>>{};
    for (final r in rows as List) {
      final opt = CommunityPollOption.fromMap(r as Map<String, dynamic>);
      (map[opt.postId] ??= []).add(opt);
    }
    return map;
  }

  Future<Map<String, String>> _fetchMyVotes(List<String> pollIds) async {
    final uid = currentUserId;
    if (uid == null) return {};
    final rows = await supabase
        .from(kTableCommunityPollVotes)
        .select('post_id, option_id')
        .eq('user_id', uid)
        .inFilter('post_id', pollIds);
    return {
      for (final r in rows as List)
        r['post_id'] as String: r['option_id'] as String,
    };
  }

  Future<void> _compose(CommunityPostType type, {CommunityPost? existing}) async {
    final created = await context.push<bool>(
      Routes.communityCompose,
      extra: (type: type, existing: existing),
    );
    if (created == true) await _load();
  }

  Future<void> _vote(CommunityPost post, CommunityPollOption option) async {
    // Optimistic: reflect the vote immediately, then reconcile from the server.
    final prev = _myVotes[post.id];
    if (prev == option.id) return;
    try {
      await supabase.rpc(
        'community_vote',
        params: {'p_post_id': post.id, 'p_option_id': option.id},
      );
    } catch (_) {
      if (mounted) _snack('Could not record your vote.');
      return;
    }
    await _load();
  }

  Future<void> _close(CommunityPost post) async {
    try {
      await supabase
          .from(kTableCommunityPosts)
          .update({'status': CommunityPostStatus.closed.wire})
          .eq('id', post.id);
      await _load();
      if (mounted) _snack('Post closed.');
    } catch (_) {
      if (mounted) _snack('Could not close the post.');
    }
  }

  Future<void> _delete(CommunityPost post) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete post?'),
        content: const Text('This permanently removes your post.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: NivaraColors.danger,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await supabase.from(kTableCommunityPosts).delete().eq('id', post.id);
      await _load();
      if (mounted) _snack('Post deleted.');
    } catch (_) {
      if (mounted) _snack('Could not delete the post.');
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final uid = currentUserId;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        children: [
          _ComposerPrompt(onSelect: (t) => _compose(t)),
          const SizedBox(height: 18),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_posts.isEmpty)
            const _EmptyCommunity()
          else
            ..._posts.map(
              (p) => Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: _PostCard(
                  post: p,
                  isMine: p.authorId == uid,
                  distanceMeters: p.hasLocation
                      ? haversineMeters(_lat, _lng, p.lat!, p.lng!)
                      : null,
                  options: _pollOptions[p.id] ?? const [],
                  myVote: _myVotes[p.id],
                  onVote: (o) => _vote(p, o),
                  onEdit: () => _compose(p.type, existing: p),
                  onClose: () => _close(p),
                  onDelete: () => _delete(p),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Type styling ────────────────────────────────────────────────────────────
IconData communityTypeIcon(CommunityPostType t) => switch (t) {
  CommunityPostType.general => Icons.forum_outlined,
  CommunityPostType.poll => Icons.bar_chart,
  CommunityPostType.job => Icons.work_outline,
  CommunityPostType.announcement => Icons.campaign_outlined,
};

Color communityTypeColor(CommunityPostType t) => switch (t) {
  CommunityPostType.general => NivaraColors.primary,
  CommunityPostType.poll => NivaraColors.accent,
  CommunityPostType.job => NivaraColors.success,
  CommunityPostType.announcement => NivaraColors.danger,
};

/// The "start a post" strip at the top of the feed — one button per template.
class _ComposerPrompt extends StatelessWidget {
  const _ComposerPrompt({required this.onSelect});
  final ValueChanged<CommunityPostType> onSelect;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Share with your neighbourhood',
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final t in CommunityPostType.values)
                _TemplateButton(
                  type: t,
                  onTap: () => onSelect(t),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TemplateButton extends StatelessWidget {
  const _TemplateButton({required this.type, required this.onTap});
  final CommunityPostType type;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = communityTypeColor(type);
    return SizedBox(
      width: (MediaQuery.sizeOf(context).width - 32 - 28 - 10) / 2,
      child: Material(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(
              children: [
                Icon(communityTypeIcon(type), color: color, size: 20),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    type.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
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

/// One post in the feed. Renders the type badge, author, body, optional photo,
/// inline poll (with live tallies + the viewer's choice), location + distance,
/// and a one-tap contact. The author sees an overflow menu.
class _PostCard extends StatelessWidget {
  const _PostCard({
    required this.post,
    required this.isMine,
    required this.distanceMeters,
    required this.options,
    required this.myVote,
    required this.onVote,
    required this.onEdit,
    required this.onClose,
    required this.onDelete,
  });

  final CommunityPost post;
  final bool isMine;
  final double? distanceMeters;
  final List<CommunityPollOption> options;
  final String? myVote;
  final ValueChanged<CommunityPollOption> onVote;
  final VoidCallback onEdit;
  final VoidCallback onClose;
  final VoidCallback onDelete;

  bool get _editable =>
      post.type == CommunityPostType.general ||
      post.type == CommunityPostType.job ||
      post.type == CommunityPostType.announcement;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = communityTypeColor(post.type);
    final photo = (post.photoUrls?.isNotEmpty ?? false)
        ? post.photoUrls!.first
        : null;

    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 6, 0),
            child: Row(
              children: [
                Icon(communityTypeIcon(post.type), size: 16, color: color),
                const SizedBox(width: 6),
                Text(
                  post.type.label,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
                const Spacer(),
                Text(
                  timeAgo(post.createdAt),
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
                if (isMine)
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert, size: 20),
                    onSelected: (v) {
                      switch (v) {
                        case 'edit':
                          onEdit();
                        case 'close':
                          onClose();
                        case 'delete':
                          onDelete();
                      }
                    },
                    itemBuilder: (_) => [
                      if (_editable)
                        const PopupMenuItem(
                          value: 'edit',
                          child: ListTile(
                            leading: Icon(Icons.edit_outlined),
                            title: Text('Edit'),
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                      if (post.type == CommunityPostType.job)
                        const PopupMenuItem(
                          value: 'close',
                          child: ListTile(
                            leading: Icon(Icons.check_circle_outline),
                            title: Text('Mark closed'),
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                      const PopupMenuItem(
                        value: 'delete',
                        child: ListTile(
                          leading: Icon(
                            Icons.delete_outline,
                            color: NivaraColors.danger,
                          ),
                          title: Text('Delete'),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ],
                  )
                else
                  const SizedBox(width: 8),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(14, isMine ? 0 : 4, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 12,
                      backgroundColor: color.withValues(alpha: 0.18),
                      child: Text(
                        post.authorName.isNotEmpty
                            ? post.authorName.characters.first.toUpperCase()
                            : '?',
                        style: TextStyle(
                          color: color,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      post.authorName,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  post.title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (post.body != null && post.body!.trim().isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(post.body!.trim()),
                ],
                if (photo != null) ...[
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.network(
                      photo,
                      width: double.infinity,
                      height: 180,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const SizedBox.shrink(),
                    ),
                  ),
                ],
                if (post.isPoll && options.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _PollBody(
                    options: options,
                    myVote: myVote,
                    color: color,
                    onVote: onVote,
                  ),
                ],
                if (distanceMeters != null || post.locationLabel != null) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Icon(
                        Icons.place_outlined,
                        size: 15,
                        color: scheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          [
                            if (post.locationLabel != null &&
                                post.locationLabel!.trim().isNotEmpty)
                              post.locationLabel!.trim(),
                            if (distanceMeters != null)
                              '${formatDistance(distanceMeters!)} away',
                          ].join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: scheme.onSurfaceVariant,
                            fontSize: 12.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                if (post.hasContact) ...[
                  const SizedBox(height: 12),
                  _ContactButton(post: post),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Inline poll: each option is a tappable bar showing its share of the vote.
class _PollBody extends StatelessWidget {
  const _PollBody({
    required this.options,
    required this.myVote,
    required this.color,
    required this.onVote,
  });

  final List<CommunityPollOption> options;
  final String? myVote;
  final Color color;
  final ValueChanged<CommunityPollOption> onVote;

  @override
  Widget build(BuildContext context) {
    final total = options.fold<int>(0, (s, o) => s + o.voteCount);
    final voted = myVote != null;
    return Column(
      children: [
        for (final o in options)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _PollOptionBar(
              option: o,
              total: total,
              selected: myVote == o.id,
              revealed: voted,
              color: color,
              onTap: () => onVote(o),
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            '$total ${total == 1 ? 'vote' : 'votes'}'
            '${voted ? '' : ' · tap to vote'}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}

class _PollOptionBar extends StatelessWidget {
  const _PollOptionBar({
    required this.option,
    required this.total,
    required this.selected,
    required this.revealed,
    required this.color,
    required this.onTap,
  });

  final CommunityPollOption option;
  final int total;
  final bool selected;
  final bool revealed;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final pct = total == 0 ? 0.0 : option.voteCount / total;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Stack(
        children: [
          Container(
            height: 40,
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: selected ? color : scheme.outlineVariant,
                width: selected ? 2 : 1,
              ),
            ),
          ),
          if (revealed)
            Positioned.fill(
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: pct.clamp(0.0, 1.0),
                child: Container(
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: selected ? 0.28 : 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  if (selected)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: Icon(Icons.check_circle, size: 16, color: color),
                    ),
                  Expanded(
                    child: Text(
                      option.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: selected
                            ? FontWeight.w700
                            : FontWeight.w500,
                      ),
                    ),
                  ),
                  if (revealed) ...[
                    const SizedBox(width: 8),
                    Text(
                      '${(pct * 100).round()}%',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ContactButton extends StatelessWidget {
  const _ContactButton({required this.post});
  final CommunityPost post;

  @override
  Widget build(BuildContext context) {
    final m = post.contactMethodEnum;
    if (m == null) return const SizedBox.shrink();
    final color = lfContactColor(m);
    return OutlinedButton.icon(
      onPressed: () async {
        final ok = await launchLFContact(m, post.contactValue!);
        if (!ok && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not open ${m.label}.')),
          );
        }
      },
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        side: BorderSide(color: color.withValues(alpha: 0.5)),
      ),
      icon: Icon(lfContactIcon(m), size: 18),
      label: Text(
        '${lfContactActionLabel(m)} · ${lfContactDisplay(m, post.contactValue!)}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

class _EmptyCommunity extends StatelessWidget {
  const _EmptyCommunity();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Icon(Icons.groups_outlined, size: 40, color: scheme.outline),
          const SizedBox(height: 10),
          Text(
            'No posts nearby yet',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Start the conversation — post, run a poll, or list a job.',
            textAlign: TextAlign.center,
            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12.5),
          ),
        ],
      ),
    );
  }
}
