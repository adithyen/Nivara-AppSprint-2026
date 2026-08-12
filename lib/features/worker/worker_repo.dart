import '../../core/constants.dart';
import '../../core/supabase_client.dart';
import '../../models/enums.dart';
import '../../models/report.dart';
import '../../models/user_profile.dart';

/// Data access for the municipal staff side: listing field workers, resolving
/// assignee names, a worker's own task list, and the two assignment RPCs.
///
/// Assignment and worker status changes go through SECURITY DEFINER RPCs
/// (`admin_assign_report`, `worker_set_report_status`) — the server enforces
/// that only an official can assign and only the assigned worker can advance.
class WorkerRepo {
  const WorkerRepo._();

  /// All field workers, department first then name. Officials pick from this
  /// list when assigning. RLS lets admins read every profile.
  static Future<List<UserProfile>> listWorkers() async {
    final rows = await supabase
        .from(kTableProfiles)
        .select()
        .eq('role', UserRole.worker.wire)
        .order('department')
        .order('display_name');
    return rows.map<UserProfile>((r) => UserProfile.fromMap(r)).toList();
  }

  /// Display names for a set of user ids (e.g. to label an assignee).
  static Future<Map<String, String>> displayNamesByIds(
    Iterable<String> ids,
  ) async {
    final list = ids.toSet().toList();
    if (list.isEmpty) return {};
    final rows = await supabase
        .from(kTableProfiles)
        .select('id, display_name')
        .inFilter('id', list);
    return {
      for (final r in rows)
        r['id'] as String: (r['display_name'] as String?) ?? 'Worker',
    };
  }

  /// The tasks assigned to a worker, newest first. The dashboard also
  /// subscribes for live updates; this is the initial pull.
  static Future<List<Report>> myTasks(String uid) async {
    final rows = await supabase
        .from(kTableReports)
        .select()
        .eq('assigned_to', uid)
        .order('created_at', ascending: false);
    return rows.map<Report>((r) => Report.fromMap(r)).toList();
  }

  /// Official hands a report to a worker. Returns the updated report.
  static Future<Report> assignReport({
    required String reportId,
    required String workerId,
    String? note,
  }) async {
    final res = await supabase.rpc(
      'admin_assign_report',
      params: {
        'p_report_id': reportId,
        'p_worker_id': workerId,
        if (note != null && note.trim().isNotEmpty) 'p_note': note.trim(),
      },
    );
    final row = res is List ? res.first : res;
    return Report.fromMap(row as Map<String, dynamic>);
  }

  /// Assigned worker advances their task (IN_PROGRESS or RESOLVED), optionally
  /// attaching a resolution note and a proof photo URL. Returns the updated row.
  static Future<Report> workerSetStatus({
    required String reportId,
    required ReportStatus status,
    String? note,
    String? photoUrl,
  }) async {
    final res = await supabase.rpc(
      'worker_set_report_status',
      params: {
        'p_report_id': reportId,
        'p_new_status': status.wire,
        if (note != null && note.trim().isNotEmpty) 'p_note': note.trim(),
        'p_photo_url': ?photoUrl,
      },
    );
    final row = res is List ? res.first : res;
    return Report.fromMap(row as Map<String, dynamic>);
  }
}
