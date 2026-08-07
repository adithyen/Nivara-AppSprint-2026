import '../core/utils.dart';

/// A community vote on a report — a row of `confirmations`. A [type] of
/// 'CONFIRM' seconds the report; 'RESOLVED' vouches that it's been fixed.
/// The DB recomputes the report's counts via trigger on insert.
class Confirmation {
  final String id;
  final String reportId;
  final String userId;

  /// 'CONFIRM' | 'RESOLVED'.
  final String type;
  final DateTime? createdAt;

  const Confirmation({
    required this.id,
    required this.reportId,
    required this.userId,
    this.type = 'CONFIRM',
    this.createdAt,
  });

  static const String typeConfirm = 'CONFIRM';
  static const String typeResolved = 'RESOLVED';

  factory Confirmation.fromMap(Map<String, dynamic> map) => Confirmation(
        id: map['id'] as String,
        reportId: map['report_id'] as String,
        userId: map['user_id'] as String,
        type: (map['type'] as String?) ?? typeConfirm,
        createdAt: toDateTimeOrNull(map['created_at']),
      );

  /// Columns the app writes on insert. `location` is optional and set by
  /// callers that have a GPS fix at vote time.
  Map<String, dynamic> toInsertMap() => {
        'report_id': reportId,
        'user_id': userId,
        'type': type,
      };
}
