import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants.dart';
import '../../core/services/location_service.dart';
import '../../core/supabase_client.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../core/widgets/bouncy_tap.dart';
import '../../models/community_poll.dart';
import '../../models/community_post.dart';
import '../../models/enums.dart';
import '../../router.dart';
import '../lostfound/lf_contact.dart';

Color communityTypeColor(CommunityPostType t) => switch (t) {
  CommunityPostType.general => NivaraColors.primary,
  CommunityPostType.poll => const Color(0xFF00E5FF),
  CommunityPostType.job => NivaraColors.accent,
  CommunityPostType.announcement => NivaraColors.danger,
};

IconData communityTypeIcon(CommunityPostType t) => switch (t) {
  CommunityPostType.general => Icons.chat_bubble_outline_rounded,
  CommunityPostType.poll => Icons.poll_outlined,
  CommunityPostType.job => Icons.work_outline_rounded,
  CommunityPostType.announcement => Icons.campaign_rounded,
};

/// 2026-Level Flagship Civic Community Tab.
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
  Map<String, String> _myVotes = const {};

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
      map.putIfAbsent(opt.postId, () => []).add(opt);
    }
    return map;
  }

  Future<Map<String, String>> _fetchMyVotes(List<String> pollIds) async {
    final uid = currentUserId;
    if (uid == null) return {};
    try {
      final rows = await supabase
          .from(kTableCommunityPollVotes)
          .select('post_id, option_id')
          .eq('user_id', uid)
          .inFilter('post_id', pollIds);
      final map = <String, String>{};
      for (final r in rows as List) {
        map[r['post_id'] as String] = r['option_id'] as String;
      }
      return map;
    } catch (_) {
      return {};
    }
  }

  Future<void> _vote(CommunityPost post, CommunityPollOption option) async {
    final uid = currentUserId;
    if (uid == null) {
      _snack('Sign in to vote in polls.');
      return;
    }
    if (_myVotes.containsKey(post.id)) {
      _snack('You have already voted in this poll.');
      return;
    }
    try {
      await supabase.from(kTableCommunityPollVotes).insert({
        'post_id': post.id,
        'option_id': option.id,
        'user_id': uid,
      });
      setState(() {
        final current = Map<String, String>.from(_myVotes);
        current[post.id] = option.id;
        _myVotes = current;

        final opts = _pollOptions[post.id];
        if (opts != null) {
          final updated = opts
              .map(
                (o) => o.id == option.id
                    ? o.copyWith(voteCount: o.voteCount + 1)
                    : o,
              )
              .toList();
          final allOpts =
              Map<String, List<CommunityPollOption>>.from(_pollOptions);
          allOpts[post.id] = updated;
          _pollOptions = allOpts;
        }
      });
      _snack('Vote recorded.');
    } catch (e) {
      _snack('Could not vote: $e');
    }
  }

  Future<void> _delete(CommunityPost post) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF131A24),
        title: const Text('Delete post?'),
        content: const Text('This will permanently delete this post and its poll data.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: NivaraColors.danger),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await supabase.from(kTableCommunityPosts).delete().eq('id', post.id);
      _load();
    } catch (e) {
      _snack('Could not delete: $e');
    }
  }

  Future<void> _closeJob(CommunityPost post) async {
    try {
      await supabase
          .from(kTableCommunityPosts)
          .update({'status': 'CLOSED'})
          .eq('id', post.id);
      _load();
      _snack('Job marked closed.');
    } catch (e) {
      _snack('Could not update: $e');
    }
  }

  void _compose(CommunityPostType template) async {
    final changed = await context.push<bool>(
      Routes.communityCompose,
      extra: (template: template, lat: _lat, lng: _lng),
    );
    if (changed == true) _load();
  }

  void _edit(CommunityPost post) async {
    final changed = await context.push<bool>(
      Routes.communityCompose,
      extra: (post: post, lat: _lat, lng: _lng),
    );
    if (changed == true) _load();
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final myUid = currentUserId;

    return RefreshIndicator(
      color: NivaraColors.primary,
      backgroundColor: const Color(0xFF10161E),
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 100),
        children: [
          _ComposerPrompt(onPick: _compose),
          const SizedBox(height: 20),
          Row(
            children: [
              const Text(
                'Neighborhood Feed',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Spacer(),
              if (!_loading && _posts.isNotEmpty)
                Text(
                  '${_posts.length} posts',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontSize: 12,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 36),
              child: Center(
                child: CircularProgressIndicator(color: NivaraColors.primary),
              ),
            )
          else if (_posts.isEmpty)
            const _EmptyFeed()
          else
            ..._posts.map((p) {
              final isMine = myUid != null && p.authorId == myUid;
              final dist = (p.lat != null && p.lng != null)
                  ? haversineMeters(_lat, _lng, p.lat!, p.lng!)
                  : null;
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _PostCard(
                  post: p,
                  isMine: isMine,
                  distanceMeters: dist,
                  options: _pollOptions[p.id] ?? const [],
                  myVote: _myVotes[p.id],
                  onVote: (opt) => _vote(p, opt),
                  onEdit: () => _edit(p),
                  onClose: () => _closeJob(p),
                  onDelete: () => _delete(p),
                ),
              );
            }),
        ],
      ),
    );
  }
}

class _ComposerPrompt extends StatelessWidget {
  const _ComposerPrompt({required this.onPick});
  final ValueChanged<CommunityPostType> onPick;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF10161E),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Share with your community',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Post questions, start polls, offer jobs, or broadcast alerts.',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.55),
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _TemplateButton(
                type: CommunityPostType.general,
                onTap: () => onPick(CommunityPostType.general),
              ),
              const SizedBox(width: 8),
              _TemplateButton(
                type: CommunityPostType.poll,
                onTap: () => onPick(CommunityPostType.poll),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _TemplateButton(
                type: CommunityPostType.job,
                onTap: () => onPick(CommunityPostType.job),
              ),
              const SizedBox(width: 8),
              _TemplateButton(
                type: CommunityPostType.announcement,
                onTap: () => onPick(CommunityPostType.announcement),
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
    return Expanded(
      child: BouncyTap(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withValues(alpha: 0.35)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(communityTypeIcon(type), color: color, size: 18),
              const SizedBox(width: 6),
              Text(
                type.label,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w800,
                  fontSize: 12.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

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
    final color = communityTypeColor(post.type);
    final photo = (post.photoUrls?.isNotEmpty ?? false)
        ? post.photoUrls!.first
        : null;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF10161E),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: color.withValues(alpha: 0.25),
          width: 1.2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
            child: Row(
              children: [
                Icon(communityTypeIcon(post.type), size: 16, color: color),
                const SizedBox(width: 6),
                Text(
                  post.type.label,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w800,
                    fontSize: 11.5,
                  ),
                ),
                const Spacer(),
                Text(
                  timeAgo(post.createdAt),
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.45),
                    fontSize: 11.5,
                  ),
                ),
                if (isMine)
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert_rounded, size: 18, color: Colors.white60),
                    color: const Color(0xFF131A24),
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
                          child: Text('Edit Post', style: TextStyle(color: Colors.white)),
                        ),
                      if (post.type == CommunityPostType.job)
                        const PopupMenuItem(
                          value: 'close',
                          child: Text('Mark Closed', style: TextStyle(color: Colors.white)),
                        ),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Text('Delete', style: TextStyle(color: NivaraColors.danger)),
                      ),
                    ],
                  )
                else
                  const SizedBox(width: 8),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(16, isMine ? 0 : 6, 16, 16),
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
                          fontWeight: FontWeight.w800,
                          fontSize: 11,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      post.authorName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  post.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 15.5,
                  ),
                ),
                if (post.body != null && post.body!.trim().isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    post.body!.trim(),
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                      fontSize: 13.5,
                      height: 1.35,
                    ),
                  ),
                ],
                if (photo != null) ...[
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Image.network(
                      photo,
                      height: 180,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
                    ),
                  ),
                ],
                if (post.isPoll && options.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  _PollWidget(
                    options: options,
                    myVote: myVote,
                    onVote: onVote,
                  ),
                ],
                const SizedBox(height: 12),
                Row(
                  children: [
                    if (distanceMeters != null) ...[
                      const Icon(Icons.near_me_rounded, size: 13, color: NivaraColors.primary),
                      const SizedBox(width: 4),
                      Text(
                        formatDistance(distanceMeters!),
                        style: const TextStyle(
                          color: NivaraColors.primary,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                    const Spacer(),
                    if (post.contactValue != null &&
                        post.contactValue!.isNotEmpty &&
                        post.contactMethod != null)
                      _ContactPill(
                        method: LFContactMethod.fromWire(post.contactMethod),
                        value: post.contactValue!,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PollWidget extends StatelessWidget {
  const _PollWidget({
    required this.options,
    required this.myVote,
    required this.onVote,
  });

  final List<CommunityPollOption> options;
  final String? myVote;
  final ValueChanged<CommunityPollOption> onVote;

  @override
  Widget build(BuildContext context) {
    final total = options.fold<int>(0, (sum, o) => sum + o.voteCount);
    final hasVoted = myVote != null;

    return Column(
      children: options.map((opt) {
        final isChosen = myVote == opt.id;
        final pct = total == 0 ? 0.0 : (opt.voteCount / total);

        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: BouncyTap(
            onTap: hasVoted ? null : () => onVote(opt),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF131A24),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isChosen
                      ? NivaraColors.primary
                      : Colors.white.withValues(alpha: 0.08),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        opt.label,
                        style: TextStyle(
                          color: isChosen ? NivaraColors.primary : Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                      if (hasVoted)
                        Text(
                          '${(pct * 100).round()}%',
                          style: TextStyle(
                            color: isChosen ? NivaraColors.primary : Colors.white60,
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),
                  if (hasVoted) ...[
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: pct,
                        minHeight: 6,
                        backgroundColor: Colors.white.withValues(alpha: 0.06),
                        color: isChosen ? NivaraColors.primary : Colors.white38,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _ContactPill extends StatelessWidget {
  const _ContactPill({required this.method, required this.value});
  final LFContactMethod method;
  final String value;

  @override
  Widget build(BuildContext context) {
    return BouncyTap(
      onTap: () => launchLFContact(method, value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: NivaraColors.primary.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: NivaraColors.primary.withValues(alpha: 0.5)),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.chat_bubble_outline_rounded, size: 12, color: NivaraColors.primary),
            SizedBox(width: 4),
            Text(
              'Contact',
              style: TextStyle(
                color: NivaraColors.primary,
                fontWeight: FontWeight.w800,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyFeed extends StatelessWidget {
  const _EmptyFeed();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.05),
              ),
              child: const Icon(Icons.forum_rounded, size: 48, color: Colors.white38),
            ),
            const SizedBox(height: 14),
            const Text(
              'No Community Posts Yet',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Be the first to post a question, start a poll, or announce a civic update.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.55),
                fontSize: 12.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
