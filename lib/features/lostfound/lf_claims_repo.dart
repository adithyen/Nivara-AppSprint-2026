import '../../core/constants.dart';
import '../../core/supabase_client.dart';
import '../../models/lf_claim.dart';
import '../../models/lf_item.dart';

/// Thin wrapper over the Lost & Found claim flow. Writes go through the
/// SECURITY DEFINER RPCs (`lf_create_claim` / `lf_complete_claim` /
/// `lf_reject_claim`) added in migration 0005 — cross-user resolution can't be
/// done with a direct table write. Self-close is the one exception: it's an
/// owner updating their own row, which `lf_update_own` already permits.
class LFClaimsRepo {
  const LFClaimsRepo._();

  /// A claimant claims someone else's ACTIVE listing. [claimantItemId] links
  /// the claimant's own opposite listing so completing the claim resolves both.
  /// Returns the claim id.
  static Future<String> createClaim({
    required String itemId,
    String? claimantItemId,
    String? message,
  }) async {
    final id = await supabase.rpc(
      'lf_create_claim',
      params: {
        'p_item_id': itemId,
        'p_claimant_item_id': claimantItemId,
        'p_message': message,
      },
    );
    return id as String;
  }

  /// The listing owner accepts a claim — resolves both listings and rejects
  /// any sibling pending claims.
  static Future<void> completeClaim(String claimId) async {
    await supabase.rpc('lf_complete_claim', params: {'p_claim_id': claimId});
  }

  /// Owner rejects / claimant withdraws a pending claim. Both listings stay
  /// active.
  static Future<void> rejectClaim(String claimId) async {
    await supabase.rpc('lf_reject_claim', params: {'p_claim_id': claimId});
  }

  /// Owner closes their own listing after recovering the item themselves.
  static Future<void> selfClose(String itemId) async {
    await supabase
        .from(kTableLfItems)
        .update({'status': 'RESOLVED'})
        .eq('id', itemId);
  }

  /// The current user's own listings (any status), newest first.
  static Future<List<LFItem>> myItems(String uid) async {
    final rows = await supabase
        .from(kTableLfItems)
        .select()
        .eq('user_id', uid)
        .order('created_at', ascending: false);
    return (rows as List)
        .map((e) => LFItem.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  /// Pending claims other people have filed on the current user's listings.
  static Future<List<LFClaim>> claimsOnMyItems(String uid) async {
    final rows = await supabase
        .from(kTableLfClaims)
        .select()
        .eq('owner_id', uid)
        .eq('status', 'PENDING')
        .order('created_at', ascending: false);
    return (rows as List)
        .map((e) => LFClaim.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  /// Claims the current user has filed on other people's listings.
  static Future<List<LFClaim>> myClaims(String uid) async {
    final rows = await supabase
        .from(kTableLfClaims)
        .select()
        .eq('claimant_id', uid)
        .order('created_at', ascending: false);
    return (rows as List)
        .map((e) => LFClaim.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  /// All claims (any status) on a single listing — used by the detail screen so
  /// the owner sees who has claimed it.
  static Future<List<LFClaim>> claimsForItem(String itemId) async {
    final rows = await supabase
        .from(kTableLfClaims)
        .select()
        .eq('item_id', itemId)
        .order('created_at', ascending: false);
    return (rows as List)
        .map((e) => LFClaim.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  /// Fetch several listings by id in one query — resolves the item behind each
  /// claim without an N+1 fan-out. Returns a map keyed by id.
  static Future<Map<String, LFItem>> itemsByIds(Iterable<String> ids) async {
    final list = ids.toSet().toList();
    if (list.isEmpty) return {};
    final rows = await supabase
        .from(kTableLfItems)
        .select()
        .inFilter('id', list);
    final map = <String, LFItem>{};
    for (final r in rows as List) {
      final item = LFItem.fromMap(r as Map<String, dynamic>);
      map[item.id] = item;
    }
    return map;
  }

  /// Display names for a set of user ids, for labelling claims. Missing/failed
  /// lookups are simply absent from the map.
  static Future<Map<String, String>> displayNames(Iterable<String> ids) async {
    final list = ids.toSet().toList();
    if (list.isEmpty) return {};
    try {
      final rows = await supabase
          .from(kTableProfiles)
          .select('id, display_name')
          .inFilter('id', list);
      final map = <String, String>{};
      for (final r in rows as List) {
        final m = r as Map<String, dynamic>;
        final name = (m['display_name'] as String?)?.trim();
        if (name != null && name.isNotEmpty) map[m['id'] as String] = name;
      }
      return map;
    } catch (_) {
      return {};
    }
  }
}
