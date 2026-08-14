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
import '../worker/worker_repo.dart';

/// The **Admin Community** tab — same neighbourhood board as the citizen side,
/// but officials additionally see a **Delete** button on every post so they
/// can remove inappropriate content. They can also compose posts just like
/// citizens.
///
/// Body-only (the [Scaffold]/[AppBar] belong to the admin shell).
class AdminCommunityTab extends ConsumerStatefulWidget {
  const AdminCommunityTab({super.key});

  @override
  ConsumerState<AdminCommunityTab> createState() => _AdminCommunityTabState();
}

class _AdminCommunityTabState extends ConsumerState<AdminCommunityTab> {
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
      /* best-effort load */
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
        .order('sort_order');
    final map = <String, List<CommunityPollOption>>{};
    for (final r in rows as List) {
      final opt = CommunityPollOption.fromMap(r as Map<String, dynamic>);
      (map[opt.postId] ??= []).add(opt);
    }
    return map;
  }

  Future<Map<String, String>> _fetchMyVotes(List<String> pollIds) async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) return {};
    final rows = await supabase
        .from(kTableCommunityPollVotes)
        .select('post_id, option_id')
        .eq('user_id', uid)
        .inFilter('post_id', pollIds);
    return {
      for (final r in rows as List)
        (r as Map<String, dynamic>)['post_id'] as String:
            r['option_id'] as String,
    };
  }

  Future<void> _compose(CommunityPostType type) async {
    final created = await context.push<bool>(
      Routes.communityCompose,
      extra: (type: type, existing: null),
    );
    if (created == true) await _load();
  }

  Future<void> _adminDelete(CommunityPost post) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete post?'),
        content: Text(
          'Remove "${post.title.length > 60 ? '${post.title.substring(0, 60)}\u2026' : post.title}" from the community board? This cannot be undone.',
        ),
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
    if (ok != true || !mounted) return;
    try {
      await WorkerRepo.deleteCommunityPost(post.id);
      if (mounted) {
        setState(() => _posts.removeWhere((p) => p.id == post.id));
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(content: Text('Post removed.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text('Could not delete: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        // Compose prompt — same as user community
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Post to community',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      for (final t in CommunityPostType.values)
                        ActionChip(
                          label: Text(t.label),
                          onPressed: () => _compose(t),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        // Posts list
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _posts.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.groups_outlined, size: 56, color: scheme.outline),
                        const SizedBox(height: 12),
                        Text(
                          'No community posts',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Be the first to post something to the neighbourhood board.',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                    itemCount: _posts.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (_, i) {
                      final post = _posts[i];
                      return _AdminPostCard(
                        post: post,
                        options: _pollOptions[post.id],
                        myVoteOptionId: _myVotes[post.id],
                        onDelete: () => _adminDelete(post),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }
}

/// A community post card with an admin Delete button overlaid.
class _AdminPostCard extends StatelessWidget {
  const _AdminPostCard({
    required this.post,
    this.options,
    this.myVoteOptionId,
    required this.onDelete,
  });

  final CommunityPost post;
  final List<CommunityPollOption>? options;
  final String? myVoteOptionId;
  final VoidCallback onDelete;

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
            // Header row
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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        post.authorName,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        timeAgo(post.createdAt),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                // Admin delete button
                IconButton(
                  tooltip: 'Delete post',
                  icon: Icon(
                    Icons.delete_outline,
                    color: NivaraColors.danger,
                  ),
                  onPressed: onDelete,
                ),
              ],
            ),
            const SizedBox(height: 10),
            // Post type badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: NivaraColors.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                post.type.label,
                style: TextStyle(
                  color: NivaraColors.primary,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 8),
            // Title + Body
            Text(
              post.title,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            if (post.body?.trim().isNotEmpty == true) ...[  
              const SizedBox(height: 4),
              Text(post.body!),
            ],
            // Poll options
            if (post.isPoll && options != null && options!.isNotEmpty) ...[
              const SizedBox(height: 10),
              for (final opt in options!)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      Icon(
                        myVoteOptionId == opt.id
                            ? Icons.radio_button_checked
                            : Icons.radio_button_unchecked,
                        size: 16,
                        color: myVoteOptionId == opt.id
                            ? NivaraColors.primary
                            : scheme.outline,
                      ),
                      const SizedBox(width: 8),
                      Expanded(child: Text(opt.label)),
                      Text(
                        '${opt.voteCount}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
