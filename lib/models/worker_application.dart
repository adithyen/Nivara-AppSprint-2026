import '../core/utils.dart';

/// A row of `worker_applications`. A citizen submits one when they want to
/// join the Nivara field workforce. Admins approve or reject from the
/// worker management console.
class WorkerApplication {
  final String id;
  final String userId;
  final String? message;
  final String status; // 'PENDING' | 'APPROVED' | 'REJECTED'
  final String? reviewedBy;
  final DateTime? reviewedAt;
  final DateTime createdAt;

  const WorkerApplication({
    required this.id,
    required this.userId,
    this.message,
    required this.status,
    this.reviewedBy,
    this.reviewedAt,
    required this.createdAt,
  });

  bool get isPending => status == 'PENDING';
  bool get isApproved => status == 'APPROVED';
  bool get isRejected => status == 'REJECTED';
  String get applicantId => userId;
  String get applicantName => 'Applicant';

  factory WorkerApplication.fromMap(Map<String, dynamic> map) =>
      WorkerApplication(
        id: map['id'] as String,
        userId: map['user_id'] as String,
        message: map['message'] as String?,
        status: (map['status'] as String?) ?? 'PENDING',
        reviewedBy: map['reviewed_by'] as String?,
        reviewedAt: toDateTimeOrNull(map['reviewed_at']),
        createdAt: toDateTimeOrNull(map['created_at']) ?? DateTime.now(),
      );
}
