import 'dart:async';

import '../../core/constants.dart';
import '../../core/supabase_client.dart';
import '../../models/lf_claim.dart';
import '../../models/lf_item.dart';

/// Wrapper over the Lost & Found claim flow and Handover Verification.
/// Writes go through SECURITY DEFINER RPCs (`lf_create_claim` / `lf_complete_claim` /
/// `lf_reject_claim` / `lf_generate_handover_pass` / `lf_verify_handover`).
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

  /// Generates a dynamic 6-digit OTP and cryptographic handover token for the claim.
  static Future<Map<String, dynamic>> generateHandoverPass(String claimId) async {
    final res = await supabase.rpc(
      'lf_generate_handover_pass',
      params: {'p_claim_id': claimId},
    );
    return Map<String, dynamic>.from(res as Map);
  }

  /// Verifies the physical handover via QR token or 6-digit PIN handshake.
  static Future<Map<String, dynamic>> verifyHandover({
    required String claimId,
    String? token,
    String? otp,
  }) async {
    final res = await supabase.rpc(
      'lf_verify_handover',
      params: {
        'p_claim_id': claimId,
        'p_token': token,
        'p_otp': otp,
      },
    );
    return Map<String, dynamic>.from(res as Map);
  }

  /// The listing owner directly accepts a claim — resolves both listings and rejects
  /// any sibling pending claims.
  static Future<void> completeClaim(String claimId) async {
    await supabase.rpc('lf_complete_claim', params: {'p_claim_id': claimId});
  }

  /// Owner rejects / claimant withdraws a pending claim. Both listings stay active.
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

  /// Fetch a single claim by id.
  static Future<LFClaim?> getClaim(String claimId) async {
    final row = await supabase
        .from(kTableLfClaims)
        .select()
        .eq('id', claimId)
        .maybeSingle();
    if (row == null) return null;
    return LFClaim.fromMap(row);
  }

  /// Stream a claim in real-time to listen for completion events.
  static Stream<LFClaim?> streamClaim(String claimId) {
    return supabase
        .from(kTableLfClaims)
        .stream(primaryKey: ['id'])
        .eq('id', claimId)
        .map((rows) => rows.isNotEmpty ? LFClaim.fromMap(rows.first) : null);
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

  /// Fetch several listings by id in one query.
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

  /// Display names for a set of user ids.
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
