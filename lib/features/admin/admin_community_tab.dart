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
import '../community/community_tab.dart' show communityTypeColor, communityTypeIcon;
import '../worker/worker_repo.dart';

/// **Admin Community** tab — state-of-the-art municipal civic feed matching the citizen UI,
/// equipped with official moderation tools (remove inappropriate content, broadcast announcements).
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

  Future<void> _compose(CommunityPostType template) async {
    final changed = await context.push<bool>(
      Routes.communityCompose,
      extra: (template: template, lat: _lat, lng: _lng),
    );
    if (changed == true) await _load();
  }

  Future<void> _adminDelete(CommunityPost post) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete post?'),
        content: Text(
          'Remove "${post.title.length > 60 ? '${post.title.substring(0, 60)}…' : post.title}" from the civic feed? This cannot be undone.',
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
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
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
          ..showSnackBar(const SnackBar(content: Text('Post removed from feed.')));
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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return RefreshIndicator(
      color: NivaraColors.primary,
      backgroundColor: isDark ? const Color(0xFF10161E) : Colors.white,
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 110),
        children: [
          _AdminComposerPrompt(onPick: _compose),
          const SizedBox(height: 20),
          Row(
            children: [
              Text(
                'Civic Community Feed',
                style: TextStyle(
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Spacer(),
              if (!_loading && _posts.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                  decoration: BoxDecoration(
                    color: NivaraColors.primary.withValues(alpha: isDark ? 0.15 : 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${_posts.length} posts',
                    style: const TextStyle(
                      color: NivaraColors.primary,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 36),
              child: Center(
                child: CircularProgressIndicator(color: NivaraColors.primary),
              ),
            )
          else if (_posts.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.groups_outlined,
                      size: 56,
                      color: isDark ? Colors.white38 : const Color(0xFF94A3B8),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'No community posts yet',
                      style: TextStyle(
                        color: isDark ? Colors.white : const Color(0xFF0F172A),
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Citizen discussions, polls, and announcements will appear here.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: isDark ? Colors.white60 : const Color(0xFF64748B),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            ..._posts.map((p) {
              final dist = (p.lat != null && p.lng != null)
                  ? haversineMeters(_lat, _lng, p.lat!, p.lng!)
                  : null;
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _AdminPostCard(
                  post: p,
                  distanceMeters: dist,
                  options: _pollOptions[p.id] ?? const [],
                  myVoteOptionId: _myVotes[p.id],
                  onDelete: () => _adminDelete(p),
                ),
              );
            }),
        ],
      ),
    );
  }
}

class _AdminComposerPrompt extends StatelessWidget {
  const _AdminComposerPrompt({required this.onPick});
  final ValueChanged<CommunityPostType> onPick;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF10161E) : Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: isDark ? Colors.white.withValues(alpha: 0.1) : const Color(0xFFE2E8F0),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.15 : 0.03),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
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
                child: const Icon(Icons.campaign_rounded, color: NivaraColors.accent, size: 20),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Official Broadcast & Post',
                    style: TextStyle(
                      color: isDark ? Colors.white : const Color(0xFF0F172A),
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                  Text(
                    'Publish alerts, polls, or announcements to citizens.',
                    style: TextStyle(
                      color: isDark ? Colors.white.withValues(alpha: 0.55) : const Color(0xFF64748B),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _AdminTemplateButton(
                type: CommunityPostType.announcement,
                onTap: () => onPick(CommunityPostType.announcement),
              ),
              const SizedBox(width: 8),
              _AdminTemplateButton(
                type: CommunityPostType.poll,
                onTap: () => onPick(CommunityPostType.poll),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _AdminTemplateButton(
                type: CommunityPostType.general,
                onTap: () => onPick(CommunityPostType.general),
              ),
              const SizedBox(width: 8),
              _AdminTemplateButton(
                type: CommunityPostType.job,
                onTap: () => onPick(CommunityPostType.job),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AdminTemplateButton extends StatelessWidget {
  const _AdminTemplateButton({required this.type, required this.onTap});
  final CommunityPostType type;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = communityTypeColor(type);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Expanded(
      child: BouncyTap(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: color.withValues(alpha: isDark ? 0.12 : 0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withValues(alpha: isDark ? 0.35 : 0.3)),
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

/// A flagship community post card with an official admin moderation toolbar.
class _AdminPostCard extends StatelessWidget {
  const _AdminPostCard({
    required this.post,
    this.distanceMeters,
    required this.options,
    this.myVoteOptionId,
    required this.onDelete,
  });

  final CommunityPost post;
  final double? distanceMeters;
  final List<CommunityPollOption> options;
  final String? myVoteOptionId;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = communityTypeColor(post.type);
    final totalVotes = options.fold<int>(0, (sum, o) => sum + o.voteCount);

    final primaryText = isDark ? Colors.white : const Color(0xFF0F172A);
    final secondaryText = isDark ? Colors.white.withValues(alpha: 0.6) : const Color(0xFF64748B);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF10161E) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? Colors.white.withValues(alpha: 0.08) : const Color(0xFFE2E8F0),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.03),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Author Header + Type Badge + Moderation Action
          Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: color.withValues(alpha: isDark ? 0.2 : 0.12),
                child: Text(
                  post.authorName.isNotEmpty ? post.authorName[0].toUpperCase() : '?',
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      post.authorName,
                      style: TextStyle(
                        color: primaryText,
                        fontWeight: FontWeight.w700,
                        fontSize: 13.5,
                      ),
                    ),
                    Row(
                      children: [
                        Text(
                          timeAgo(post.createdAt),
                          style: TextStyle(color: secondaryText, fontSize: 11),
                        ),
                        if (distanceMeters != null) ...[
                          Text(' · ', style: TextStyle(color: secondaryText, fontSize: 11)),
                          Text(
                            formatDistance(distanceMeters!),
                            style: TextStyle(color: secondaryText, fontSize: 11),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              // Type Badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: isDark ? 0.15 : 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: color.withValues(alpha: isDark ? 0.4 : 0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(communityTypeIcon(post.type), color: color, size: 12),
                    const SizedBox(width: 4),
                    Text(
                      post.type.label,
                      style: TextStyle(
                        color: color,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Title
          Text(
            post.title,
            style: TextStyle(
              color: primaryText,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),

          // Body
          if (post.body != null && post.body!.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              post.body!.trim(),
              style: TextStyle(
                color: isDark ? Colors.white.withValues(alpha: 0.85) : const Color(0xFF334155),
                fontSize: 13.5,
                height: 1.4,
              ),
            ),
          ],

          // Poll Section (if poll)
          if (post.isPoll && options.isNotEmpty) ...[
            const SizedBox(height: 12),
            ...options.map((opt) {
              final pct = totalVotes > 0 ? (opt.voteCount / totalVotes * 100).round() : 0;
              final isMyVote = myVoteOptionId == opt.id;

              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF141C26) : const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isMyVote
                          ? color
                          : (isDark ? Colors.white.withValues(alpha: 0.08) : const Color(0xFFE2E8F0)),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              opt.label,
                              style: TextStyle(
                                color: primaryText,
                                fontWeight: isMyVote ? FontWeight.w700 : FontWeight.w500,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          Text(
                            '${opt.voteCount} ($pct%)',
                            style: TextStyle(
                              color: isMyVote ? color : secondaryText,
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: totalVotes > 0 ? opt.voteCount / totalVotes : 0,
                          minHeight: 5,
                          backgroundColor: isDark ? Colors.white10 : const Color(0xFFE2E8F0),
                          valueColor: AlwaysStoppedAnimation(color),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ],

          const SizedBox(height: 12),

          // Admin Moderation Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: isDark ? Colors.white.withValues(alpha: 0.03) : const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.admin_panel_settings_outlined,
                  size: 16,
                  color: isDark ? Colors.white60 : const Color(0xFF64748B),
                ),
                const SizedBox(width: 6),
                Text(
                  'Official Moderation',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white60 : const Color(0xFF64748B),
                  ),
                ),
                const Spacer(),
                BouncyTap(
                  onTap: onDelete,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: NivaraColors.danger.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: NivaraColors.danger.withValues(alpha: 0.4)),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.delete_outline_rounded, size: 14, color: NivaraColors.danger),
                        SizedBox(width: 4),
                        Text(
                          'Delete Post',
                          style: TextStyle(
                            color: NivaraColors.danger,
                            fontWeight: FontWeight.w700,
                            fontSize: 11.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
