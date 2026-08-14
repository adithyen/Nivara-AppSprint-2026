import '../core/utils.dart';

/// A row of `worker_progress_notes`. Workers send these to update the admin
/// on the progress of an in-flight task, with or without a photo.
class WorkerProgressNote {
  final String id;
  final String reportId;
  final String workerId;
  final String? note;
  final String? photoUrl;
  final DateTime createdAt;

  const WorkerProgressNote({
    required this.id,
    required this.reportId,
    required this.workerId,
    this.note,
    this.photoUrl,
    required this.createdAt,
  });

  factory WorkerProgressNote.fromMap(Map<String, dynamic> map) =>
      WorkerProgressNote(
        id: map['id'] as String,
        reportId: map['report_id'] as String,
        workerId: map['worker_id'] as String,
        note: map['note'] as String?,
        photoUrl: map['photo_url'] as String?,
        createdAt: toDateTimeOrNull(map['created_at']) ?? DateTime.now(),
      );
}
