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
import '../../core/widgets/nivara_image.dart';
import '../../models/community_poll.dart';
import '../../models/community_post.dart';
import '../../models/enums.dart';
import '../../router.dart';
import '../community/community_tab.dart' show communityTypeColor, communityTypeIcon;
import '../lostfound/lf_contact.dart';
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
  Map<String, Set<String>> _myVotes = const {}; // postId → Set of optionIds

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
    var votes = <String, Set<String>>{};

    try {
      final rows = await supabase
          .from(kTableCommunityPosts)
          .select()
          .order('created_at', ascending: false)
          .limit(200);
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
        .order('position');
    final map = <String, List<CommunityPollOption>>{};
    for (final r in rows as List) {
      final opt = CommunityPollOption.fromMap(r as Map<String, dynamic>);
      (map[opt.postId] ??= []).add(opt);
    }
    return map;
  }

  Future<Map<String, Set<String>>> _fetchMyVotes(List<String> pollIds) async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) return {};
    try {
      final rows = await supabase
          .from(kTableCommunityPollVotes)
          .select('post_id, option_id')
          .eq('user_id', uid)
          .inFilter('post_id', pollIds);
      final map = <String, Set<String>>{};
      for (final r in rows as List) {
        final pid = r['post_id'] as String;
        final oid = r['option_id'] as String;
        map.putIfAbsent(pid, () => <String>{}).add(oid);
      }
      return map;
    } catch (_) {
      return {};
    }
  }

  Future<void> _compose(CommunityPostType template) async {
    final changed = await context.push<bool>(
      Routes.communityCompose,
      extra: (template: template, lat: _lat, lng: _lng),
    );
    if (changed == true) await _load();
  }

  Future<void> _vote(CommunityPost post, CommunityPollOption option) async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Sign in to vote in polls.')));
      return;
    }

    final postVotes = _myVotes[post.id] ?? <String>{};
    final alreadyVotedThis = postVotes.contains(option.id);
    final allowsMultiple = post.allowsMultipleVotes;

    try {
      await supabase.rpc('community_vote', params: {
        'p_post_id': post.id,
        'p_option_id': option.id,
      });

      setState(() {
        final current = Map<String, Set<String>>.from(_myVotes);
        final updatedSet = Set<String>.from(current[post.id] ?? <String>{});

        if (alreadyVotedThis) {
          updatedSet.remove(option.id);
        } else {
          if (!allowsMultiple) {
            updatedSet.clear();
          }
          updatedSet.add(option.id);
        }

        if (updatedSet.isEmpty) {
          current.remove(post.id);
        } else {
          current[post.id] = updatedSet;
        }
        _myVotes = current;
      });

      final freshOpts = await _fetchPollOptions([post.id]);
      if (mounted && freshOpts.containsKey(post.id)) {
        setState(() {
          final allOpts = Map<String, List<CommunityPollOption>>.from(_pollOptions);
          allOpts[post.id] = freshOpts[post.id]!;
          _pollOptions = allOpts;
        });
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text(alreadyVotedThis
              ? 'Vote removed.'
              : (allowsMultiple ? 'Vote recorded.' : 'Vote recorded / updated.')),
        ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('Could not update vote: $e')));
    }
  }

  void _showFullImage(BuildContext context, String url) {
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(12),
        child: Stack(
          alignment: Alignment.center,
          children: [
            InteractiveViewer(
              minScale: 0.5,
              maxScale: 4.0,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: NivaraImage(
                  source: url,
                  fit: BoxFit.contain,
                ),
              ),
            ),
            Positioned(
              top: 10,
              right: 10,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 28),
                onPressed: () => Navigator.of(ctx).pop(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openPostDetail(CommunityPost post) {
    final dist = (post.lat != null && post.lng != null)
        ? haversineMeters(_lat, _lng, post.lat!, post.lng!)
        : null;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF10161E)
          : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          return _AdminPostDetailSheet(
            post: post,
            distanceMeters: dist,
            options: _pollOptions[post.id] ?? const [],
            myVotes: _myVotes[post.id] ?? const {},
            onVote: (opt) async {
              await _vote(post, opt);
              setSheetState(() {});
            },
            onDelete: () async {
              Navigator.pop(ctx);
              await _adminDelete(post);
            },
            onImageTap: (url) => _showFullImage(context, url),
          );
        },
      ),
    );
  }

  Future<void> _adminDelete(CommunityPost post) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF131A24) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text(
          'Delete post?',
          style: TextStyle(
            color: isDark ? Colors.white : const Color(0xFF0F172A),
            fontWeight: FontWeight.w800,
            fontSize: 18,
          ),
        ),
        content: Text(
          'Remove "${post.title.length > 60 ? '${post.title.substring(0, 60)}…' : post.title}" from the civic feed? This cannot be undone.',
          style: TextStyle(
            color: isDark ? Colors.white70 : const Color(0xFF475569),
            fontSize: 14,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: Text(
              'Cancel',
              style: TextStyle(
                color: isDark ? Colors.white60 : const Color(0xFF64748B),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: NivaraColors.danger,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
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
                  myVotes: _myVotes[p.id] ?? const {},
                  onVote: (opt) => _vote(p, opt),
                  onDelete: () => _adminDelete(p),
                  onTap: () => _openPostDetail(p),
                  onImageTap: (url) => _showFullImage(context, url),
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
    required this.distanceMeters,
    required this.options,
    required this.myVotes,
    required this.onVote,
    required this.onDelete,
    required this.onTap,
    required this.onImageTap,
  });

  final CommunityPost post;
  final double? distanceMeters;
  final List<CommunityPollOption> options;
  final Set<String> myVotes;
  final ValueChanged<CommunityPollOption> onVote;
  final VoidCallback onDelete;
  final VoidCallback onTap;
  final ValueChanged<String> onImageTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = communityTypeColor(post.type);

    final primaryText = isDark ? Colors.white : const Color(0xFF0F172A);
    final secondaryText = isDark ? Colors.white.withValues(alpha: 0.6) : const Color(0xFF64748B);
    final photo = (post.photoUrls?.isNotEmpty ?? false) ? post.photoUrls!.first : null;

    return BouncyTap(
      onTap: onTap,
      scaleFactor: 0.98,
      child: Container(
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
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: isDark ? Colors.white.withValues(alpha: 0.85) : const Color(0xFF334155),
                  fontSize: 13.5,
                  height: 1.4,
                ),
              ),
            ],

            // Photo if present (tappable to zoom)
            if (photo != null) ...[
              const SizedBox(height: 12),
              BouncyTap(
                onTap: () => onImageTap(photo),
                child: NivaraImage(
                  source: photo,
                  height: 190,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ],

            // Poll Section (interactive)
            if (post.isPoll && options.isNotEmpty) ...[
              const SizedBox(height: 12),
              _PollWidget(
                options: options,
                myVotes: myVotes,
                allowsMultiple: post.allowsMultipleVotes,
                onVote: onVote,
              ),
            ],

            const SizedBox(height: 12),

            // Contact Pill & Distance Footer
            Row(
              children: [
                if (post.contactValue != null &&
                    post.contactValue!.isNotEmpty &&
                    post.contactMethod != null)
                  _ContactPill(
                    method: LFContactMethod.fromWire(post.contactMethod),
                    value: post.contactValue!,
                  ),
                const Spacer(),
                Text(
                  'Tap to inspect',
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? Colors.white38 : const Color(0xFF94A3B8),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 2),
                Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 10,
                  color: isDark ? Colors.white38 : const Color(0xFF94A3B8),
                ),
              ],
            ),

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
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Interactive Poll Widget
// ─────────────────────────────────────────────────────────────────────────────

class _PollWidget extends StatelessWidget {
  const _PollWidget({
    required this.options,
    required this.myVotes,
    required this.allowsMultiple,
    required this.onVote,
  });

  final List<CommunityPollOption> options;
  final Set<String> myVotes;
  final bool allowsMultiple;
  final ValueChanged<CommunityPollOption> onVote;

  @override
  Widget build(BuildContext context) {
    final total = options.fold<int>(0, (sum, o) => sum + o.voteCount);
    final hasVoted = myVotes.isNotEmpty;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = Theme.of(context).colorScheme.primary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              allowsMultiple ? Icons.checklist_rounded : Icons.how_to_vote_rounded,
              size: 14,
              color: primary,
            ),
            const SizedBox(width: 5),
            Text(
              allowsMultiple
                  ? 'Multiple choices allowed • Tap to vote/unvote'
                  : (hasVoted ? 'Tap any option to switch your vote' : 'Single choice • Tap to vote'),
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: primary.withValues(alpha: 0.9),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ...options.map((opt) {
          final isChosen = myVotes.contains(opt.id);
          final pct = total == 0 ? 0.0 : (opt.voteCount / total);

          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: BouncyTap(
              onTap: () => onVote(opt),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: isChosen
                      ? primary.withValues(alpha: isDark ? 0.18 : 0.08)
                      : (isDark ? const Color(0xFF131A24) : const Color(0xFFF1F5F9)),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isChosen
                        ? primary
                        : (isDark ? Colors.white.withValues(alpha: 0.08) : const Color(0xFFE2E8F0)),
                    width: isChosen ? 1.5 : 1.0,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          allowsMultiple
                              ? (isChosen ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded)
                              : (isChosen ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded),
                          size: 17,
                          color: isChosen ? primary : (isDark ? Colors.white38 : Colors.black38),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            opt.label,
                            style: TextStyle(
                              color: isChosen ? primary : (isDark ? Colors.white : const Color(0xFF111827)),
                              fontWeight: isChosen ? FontWeight.w800 : FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        if (hasVoted) ...[
                          const SizedBox(width: 6),
                          Text(
                            '${(pct * 100).round()}% (${opt.voteCount})',
                            style: TextStyle(
                              color: isChosen ? primary : (isDark ? Colors.white60 : const Color(0xFF6B7280)),
                              fontWeight: FontWeight.w800,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (hasVoted) ...[
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(
                          value: pct,
                          minHeight: 5,
                          backgroundColor: isDark
                              ? Colors.white.withValues(alpha: 0.06)
                              : const Color(0xFFE2E8F0),
                          color: isChosen ? primary : primary.withValues(alpha: 0.4),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        }),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Contact Action Pill
// ─────────────────────────────────────────────────────────────────────────────

class _ContactPill extends StatelessWidget {
  const _ContactPill({required this.method, required this.value});
  final LFContactMethod method;
  final String value;

  @override
  Widget build(BuildContext context) {
    final color = lfContactColor(method);
    final icon = lfContactIcon(method);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return BouncyTap(
      onTap: () => launchLFContact(method, value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: isDark ? 0.18 : 0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.5)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 6),
            Text(
              method.label,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Admin Post Detail Modal Sheet
// ─────────────────────────────────────────────────────────────────────────────

class _AdminPostDetailSheet extends StatelessWidget {
  const _AdminPostDetailSheet({
    required this.post,
    required this.options,
    required this.myVotes,
    required this.distanceMeters,
    required this.onVote,
    required this.onDelete,
    required this.onImageTap,
  });

  final CommunityPost post;
  final List<CommunityPollOption> options;
  final Set<String> myVotes;
  final double? distanceMeters;
  final ValueChanged<CommunityPollOption> onVote;
  final VoidCallback onDelete;
  final ValueChanged<String> onImageTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = communityTypeColor(post.type);
    final primary = Theme.of(context).colorScheme.primary;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Author & Type Header
            Row(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: color.withValues(alpha: isDark ? 0.22 : 0.15),
                  child: Text(
                    post.authorName.isNotEmpty ? post.authorName[0].toUpperCase() : '?',
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        post.authorName,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: isDark ? Colors.white : const Color(0xFF0F172A),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Text(
                            timeAgo(post.createdAt),
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark ? Colors.white60 : const Color(0xFF64748B),
                            ),
                          ),
                          if (distanceMeters != null) ...[
                            Text(
                              ' · ${formatDistance(distanceMeters!)} away',
                              style: TextStyle(
                                fontSize: 12,
                                color: isDark ? Colors.white60 : const Color(0xFF64748B),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: isDark ? 0.18 : 0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: color.withValues(alpha: 0.4)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(communityTypeIcon(post.type), color: color, size: 14),
                      const SizedBox(width: 4),
                      Text(
                        post.type.label,
                        style: TextStyle(
                          color: color,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),

            // Title
            Text(
              post.title,
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w900,
                color: isDark ? Colors.white : const Color(0xFF0F172A),
                height: 1.3,
              ),
            ),
            const SizedBox(height: 10),

            // Body
            if (post.body != null && post.body!.trim().isNotEmpty) ...[
              Text(
                post.body!.trim(),
                style: TextStyle(
                  fontSize: 14.5,
                  height: 1.5,
                  color: isDark ? Colors.white.withValues(alpha: 0.9) : const Color(0xFF334155),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Photos Gallery
            if (post.photoUrls?.isNotEmpty ?? false) ...[
              const Text(
                'ATTACHED PHOTOS (TAP TO ZOOM)',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.0,
                  color: Color(0xFF94A3B8),
                ),
              ),
              const SizedBox(height: 8),
              ...post.photoUrls!.map((url) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: BouncyTap(
                      onTap: () => onImageTap(url),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: NivaraImage(
                          source: url,
                          height: 220,
                          width: double.infinity,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                  )),
              const SizedBox(height: 12),
            ],

            // Poll Section
            if (post.isPoll && options.isNotEmpty) ...[
              const Text(
                'MUNICIPAL POLL INTERACTION',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.0,
                  color: Color(0xFF94A3B8),
                ),
              ),
              const SizedBox(height: 8),
              _PollWidget(
                options: options,
                myVotes: myVotes,
                allowsMultiple: post.allowsMultipleVotes,
                onVote: onVote,
              ),
              const SizedBox(height: 16),
            ],

            // Contact section
            if (post.contactValue != null &&
                post.contactValue!.isNotEmpty &&
                post.contactMethod != null) ...[
              const Text(
                'CONTACT CITIZEN',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.0,
                  color: Color(0xFF94A3B8),
                ),
              ),
              const SizedBox(height: 8),
              _ContactPill(
                method: LFContactMethod.fromWire(post.contactMethod),
                value: post.contactValue!,
              ),
              const SizedBox(height: 16),
            ],

            // Location coordinates
            if (post.lat != null && post.lng != null) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF141C26) : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(Icons.location_on_outlined, size: 16, color: primary),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Location: ${post.lat!.toStringAsFixed(5)}, ${post.lng!.toStringAsFixed(5)}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white70 : const Color(0xFF475569),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ],

            // Official Moderation Console
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: NivaraColors.danger.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: NivaraColors.danger.withValues(alpha: 0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.shield_outlined, color: NivaraColors.danger, size: 18),
                      SizedBox(width: 8),
                      Text(
                        'Municipal Moderation Action',
                        style: TextStyle(
                          color: NivaraColors.danger,
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'As an administrator, you can remove offensive, irrelevant, or spam posts from the public civic forum.',
                    style: TextStyle(
                      color: isDark ? Colors.white70 : const Color(0xFF475569),
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 12),
                  BouncyTap(
                    onTap: onDelete,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: NivaraColors.danger,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Center(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.delete_forever_rounded, color: Colors.white, size: 18),
                            SizedBox(width: 6),
                            Text(
                              'Delete This Post Permanently',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
