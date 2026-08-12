import '../core/utils.dart';
import 'enums.dart';

/// A row of `lf_claims` — one person's claim on another person's Lost & Found
/// listing. Writes go exclusively through the `lf_create_claim` /
/// `lf_complete_claim` / `lf_reject_claim` RPCs; the app only ever reads this.
class LFClaim {
  final String id;

  /// The listing being claimed (owned by [ownerId]).
  final String itemId;
  final String ownerId;
  final String claimantId;

  /// The claimant's own opposite listing, linked so completing the claim
  /// resolves it too. Null when the claimant had no matching listing.
  final String? claimantItemId;

  final String? message;
  final LFClaimStatus status;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const LFClaim({
    required this.id,
    required this.itemId,
    required this.ownerId,
    required this.claimantId,
    this.claimantItemId,
    this.message,
    this.status = LFClaimStatus.pending,
    this.createdAt,
    this.updatedAt,
  });

  bool get isPending => status == LFClaimStatus.pending;
  bool get isCompleted => status == LFClaimStatus.completed;

  factory LFClaim.fromMap(Map<String, dynamic> map) => LFClaim(
    id: map['id'] as String,
    itemId: map['item_id'] as String,
    ownerId: map['owner_id'] as String,
    claimantId: map['claimant_id'] as String,
    claimantItemId: map['claimant_item_id'] as String?,
    message: map['message'] as String?,
    status: LFClaimStatus.fromWire(map['status'] as String?),
    createdAt: toDateTimeOrNull(map['created_at']),
    updatedAt: toDateTimeOrNull(map['updated_at']),
  );
}
