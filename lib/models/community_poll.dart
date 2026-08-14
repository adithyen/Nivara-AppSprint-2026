import '../core/utils.dart';

/// One choice on a POLL community post — a row of `community_poll_options`.
/// [voteCount] is a denormalised tally maintained by the `community_vote` RPC.
class CommunityPollOption {
  final String id;
  final String postId;
  final String label;
  final int position;
  final int voteCount;

  const CommunityPollOption({
    required this.id,
    required this.postId,
    required this.label,
    this.position = 0,
    this.voteCount = 0,
  });

  factory CommunityPollOption.fromMap(Map<String, dynamic> map) =>
      CommunityPollOption(
        id: map['id'] as String,
        postId: map['post_id'] as String,
        label: (map['label'] as String?) ?? '',
        position: toInt(map['position']),
        voteCount: toInt(map['vote_count']),
      );

  CommunityPollOption copyWith({
    String? id,
    String? postId,
    String? label,
    int? position,
    int? voteCount,
  }) =>
      CommunityPollOption(
        id: id ?? this.id,
        postId: postId ?? this.postId,
        label: label ?? this.label,
        position: position ?? this.position,
        voteCount: voteCount ?? this.voteCount,
      );

  /// Insert payload for an option created alongside its poll. [id] and
  /// [voteCount] are server-managed, so they're omitted.
  Map<String, dynamic> toInsertMap() => {
    'post_id': postId,
    'label': label,
    'position': position,
  };
}
