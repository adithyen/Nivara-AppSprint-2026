import '../core/utils.dart';
import 'enums.dart';

/// A candidate pairing between a LOST and a FOUND item — a row of `lf_matches`.
class LFMatch {
  final String id;
  final String lostItemId;
  final String foundItemId;
  final int matchScore;
  final MatchStatus status;
  final DateTime? confirmedAt;
  final DateTime? resolvedAt;
  final DateTime? createdAt;

  const LFMatch({
    required this.id,
    required this.lostItemId,
    required this.foundItemId,
    required this.matchScore,
    this.status = MatchStatus.pending,
    this.confirmedAt,
    this.resolvedAt,
    this.createdAt,
  });

  factory LFMatch.fromMap(Map<String, dynamic> map) => LFMatch(
        id: map['id'] as String,
        lostItemId: map['lost_item_id'] as String,
        foundItemId: map['found_item_id'] as String,
        matchScore: toInt(map['match_score']),
        status: MatchStatus.fromWire(map['status'] as String?),
        confirmedAt: toDateTimeOrNull(map['confirmed_at']),
        resolvedAt: toDateTimeOrNull(map['resolved_at']),
        createdAt: toDateTimeOrNull(map['created_at']),
      );
}
